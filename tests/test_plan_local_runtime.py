from __future__ import annotations

import asyncio
import threading
from types import SimpleNamespace

from rich.console import Console
from textual.app import App
from textual.widgets import Static

from company_os.application.local_runtime_service import LocalRuntimeStatus
from company_os.cli.screens.plan_control import PlanControlScreen


def rendered(widget):
    console = Console(width=120, color_system=None)
    with console.capture() as capture:
        console.print(widget.content)
    return capture.get()


class RuntimePlanScreen(PlanControlScreen):
    # Isolate the runtime surface from unrelated task/repository queries.
    def _refresh_view(self):
        self._refresh_local_runtime(self.fixture_tasks)


def test_runtime_panel_worker_keeps_navigation_responsive(tmp_path):
    async def scenario():
        started, release = threading.Event(), threading.Event()
        calls = []
        screen = RuntimePlanScreen(SimpleNamespace(project_root=tmp_path), SimpleNamespace())
        screen.fixture_tasks = [SimpleNamespace(owner="backend", status="ACTIVE", work_kind="IMPLEMENTATION")]
        def inspect(root, role, workload):
            calls.append((root, role, workload))
            started.set()
            release.wait(timeout=5)
            return LocalRuntimeStatus(available=True, profile="LOCAL_GPU_8GB", capability_score=72,
                                      model="fixture-coder:7b", reason="Fixture selection", ram_gb=32,
                                      gpu_name="Fixture GPU", vram_gb=8, num_ctx=8192, num_predict=2048)
        screen.local_runtime.inspect = inspect
        class TestApp(App):
            language = "en"
            interface_theme = "hacker"
        app = TestApp()
        async with app.run_test() as pilot:
            await app.push_screen(screen)
            for _ in range(30):
                if started.is_set():
                    break
                await asyncio.sleep(0.01)
            assert started.is_set()
            assert "Inspecting local runtime" in rendered(screen.query_one("#plan-local-runtime", Static))
            assert screen.busy is False
            # A pending hardware process must not occupy the UI thread or forbid back.
            await pilot.press("escape")
            assert app.screen is not screen
            release.set()
            await screen.workers.wait_for_complete()
        assert calls == [(tmp_path, "backend", "writable")]
    asyncio.run(scenario())


def test_runtime_panel_available_unavailable_i18n_and_refresh(tmp_path):
    async def scenario():
        calls = []
        invalidations = []
        screen = RuntimePlanScreen(SimpleNamespace(project_root=tmp_path), SimpleNamespace())
        screen.fixture_tasks = [SimpleNamespace(owner="engineering-manager", status="ACTIVE", work_kind="PLANNING")]
        available = LocalRuntimeStatus(available=True, profile="LOCAL_CPU_HIGH", capability_score=44,
                                       model="fixture-local", reason="Selected", ram_gb=32,
                                       gpu_name="", vram_gb=0, num_ctx=4096, num_predict=1024)
        def inspect(root, role, workload):
            calls.append((role, workload))
            return available if len(calls) == 1 else LocalRuntimeStatus(reason="Fixture resolver failed.")
        screen.local_runtime.inspect = inspect
        screen.local_runtime.invalidate = lambda root: invalidations.append(root)
        class TestApp(App):
            language = "en"
            interface_theme = "default"
        app = TestApp()
        async with app.run_test() as pilot:
            await app.push_screen(screen)
            await screen.workers.wait_for_complete()
            text = rendered(screen.query_one("#plan-local-runtime", Static))
            for value in ("LOCAL_CPU_HIGH", "44", "engineering-manager / analysis", "fixture-local", "4096", "1024"):
                assert value in text
            assert "Auto depends on workload and provider policy" in text
            app.language = "es"
            screen.refresh_language()
            assert "Candidato local" in rendered(screen.query_one("#plan-local-runtime", Static))
            await pilot.press("f5")
            await screen.workers.wait_for_complete()
            text = rendered(screen.query_one("#plan-local-runtime", Static))
            assert "Runtime local no disponible" in text and "Fixture resolver failed." in text
            assert "RAM (GB): -" in text and "fixture-local" not in text
            assert invalidations == [tmp_path]
            assert calls == [("engineering-manager", "analysis")] * 2
    asyncio.run(scenario())


def test_old_role_result_cannot_replace_current_selection(tmp_path):
    async def scenario():
        screen = RuntimePlanScreen(SimpleNamespace(project_root=tmp_path), SimpleNamespace())
        screen.fixture_tasks = []
        screen.local_runtime.inspect = lambda *_args, **_kwargs: LocalRuntimeStatus(reason="Fixture unavailable")
        app = App()
        async with app.run_test():
            await app.push_screen(screen)
            await screen.workers.wait_for_complete()
            screen._local_runtime_key = ("backend", "writable")
            screen._apply_local_runtime(("pm", "analysis"), LocalRuntimeStatus(model="stale-fixture"), screen._local_runtime_generation)
            assert screen._local_runtime_status.model != "stale-fixture"
            screen._apply_local_runtime(("backend", "writable"), LocalRuntimeStatus(model="stale-same-key"), screen._local_runtime_generation - 1)
            assert screen._local_runtime_status.model != "stale-same-key"
    asyncio.run(scenario())


def test_unexpected_diagnostic_error_does_not_abort_screen_or_expose_details(tmp_path):
    async def scenario():
        screen = RuntimePlanScreen(SimpleNamespace(project_root=tmp_path), SimpleNamespace())
        screen.fixture_tasks = []
        def fail(*_args, **_kwargs):
            raise RuntimeError("OBVIOUSLY_FAKE_SECRET_INTERNAL_ERROR")
        screen.local_runtime.inspect = fail
        app = App()
        async with app.run_test() as pilot:
            await app.push_screen(screen)
            await screen.workers.wait_for_complete()
            assert screen._local_runtime_status.available is False
            text = rendered(screen.query_one("#plan-local-runtime", Static))
            assert "Local runtime inspection failed." in text
            assert "OBVIOUSLY_FAKE_SECRET" not in text
            await pilot.press("escape")
            assert app.screen is not screen
    asyncio.run(scenario())


def test_gate_runtime_uses_independent_reviewer_and_updates_live_stages(tmp_path):
    async def scenario():
        calls = []
        screen = RuntimePlanScreen(SimpleNamespace(project_root=tmp_path), SimpleNamespace())
        screen.fixture_tasks = []
        def inspect(_root, role, workload):
            calls.append((role, workload))
            return LocalRuntimeStatus(model=f"fixture-{role}", reason="Fixture diagnostic")
        screen.local_runtime.inspect = inspect
        screen._operation_owners = {"AICO-001": "backend", "AICO-002": "qa", "AICO-003": "security"}
        class TestApp(App):
            language = "en"
        app = TestApp()
        async with app.run_test() as pilot:
            await app.push_screen(screen)
            await screen.workers.wait_for_complete()
            screen.progress.start(kind="gates", title="Gates", task_ids=["AICO-001"], initial_event="Fixture")
            screen.busy = True
            for task, gate, role in (
                ("AICO-001", "REVIEW", "engineering-manager"),
                ("AICO-001", "QA", "qa"),
                ("AICO-001", "SECURITY", "security"),
                ("AICO-002", "QA", "engineering-manager"),
                ("AICO-003", "SECURITY", "engineering-manager"),
            ):
                screen._handle_progress_line(f"__AICO_GATE__|{task}|{gate}|START")
                await screen.workers.wait_for_complete()
                assert screen._local_runtime_key == (role, "gate")
                assert f"{role} / gate" in rendered(screen.query_one("#plan-local-runtime", Static))
            screen.progress.finish(status="PASS", summary="Fixture")
            screen.busy = False
            await pilot.press("escape")
            assert app.screen is not screen
        assert ("backend", "gate") not in calls
        assert ("qa", "gate") in calls and ("security", "gate") in calls
    asyncio.run(scenario())


def test_analysis_runtime_updates_when_stream_changes_task_owner(tmp_path):
    async def scenario():
        screen = RuntimePlanScreen(SimpleNamespace(project_root=tmp_path), SimpleNamespace())
        screen.fixture_tasks = []
        screen.local_runtime.inspect = lambda *_args, **_kwargs: LocalRuntimeStatus(reason="Fixture")
        screen._operation_owners = {"AICO-001": "backend", "AICO-002": "frontend"}
        app = App()
        async with app.run_test():
            await app.push_screen(screen)
            await screen.workers.wait_for_complete()
            screen.progress.start(kind="analysis", title="Analysis", task_ids=["AICO-001", "AICO-002"], initial_event="Fixture")
            screen._handle_progress_line("Task: AICO-002")
            await screen.workers.wait_for_complete()
            assert screen._local_runtime_key == ("frontend", "analysis")
    asyncio.run(scenario())
