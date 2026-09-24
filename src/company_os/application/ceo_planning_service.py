from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path

from company_os.application.status_service import StatusService
from company_os.repository.task_repository import TaskRepository


@dataclass
class ProposedTask:
    key: str
    title: str
    owner: str
    objective: str
    dependencies: list[str] = field(
        default_factory=list
    )
    wave: int = 1


@dataclass
class CEOPlan:
    request: str
    intent: str
    strategy: str
    strategy_id: str

    engine_type: str
    project_name: str
    project_root: str

    project_facts: list[str]
    tasks: list[ProposedTask]
    warnings: list[str]

    existing_open_tasks: int
    engine_ready: bool

    @property
    def execution_waves(self) -> list[list[ProposedTask]]:
        waves: dict[int, list[ProposedTask]] = {}

        for task in self.tasks:
            waves.setdefault(
                task.wave,
                [],
            ).append(task)

        return [
            waves[key]
            for key in sorted(waves)
        ]


class CEOPlanningService:
    INTENT_TO_ENGINE_TYPE = {
        "AUDIT": "AUDIT",
        "FIX": "BUG",
        "FEATURE": "FEATURE",
        "GENERAL": "RESEARCH",
    }

    REQUIRED_ENGINE_FILES = [
        "scripts/new-work-request.ps1",
        "scripts/generate-plan.ps1",
        "scripts/materialize-plan-tasks.ps1",
        "scripts/evaluate-readiness.ps1",
        "scripts/dispatch-ready-tasks.ps1",
        "scripts/orchestrate.ps1",
    ]

    def __init__(self) -> None:
        self.status_service = StatusService()
        self.task_repository = TaskRepository()

    def build_plan(
        self,
        project: Path,
        proposal,
        option,
    ) -> CEOPlan:
        root = Path(project).expanduser().resolve()

        snapshot = self.status_service.get_status(
            root
        )

        tasks = self.task_repository.list_tasks(
            root
        )

        open_tasks = [
            task
            for task in tasks
            if task.status.value != "DONE"
        ]

        engine_ready = all(
            (root / relative).exists()
            for relative in self.REQUIRED_ENGINE_FILES
        )

        facts = self._inspect_project(
            root
        )

        warnings: list[str] = []

        if open_tasks:
            warnings.append(
                f"{len(open_tasks)} unfinished task(s) already "
                "exist. The preview does not modify them."
            )

        if not engine_ready:
            warnings.append(
                "The complete AI Company OS orchestration "
                "runtime was not detected in this project."
            )

        engine_type = (
            self.INTENT_TO_ENGINE_TYPE.get(
                proposal.intent,
                "RESEARCH",
            )
        )

        proposed_tasks = self._build_tasks(
            proposal.intent,
            option.id,
            proposal.request,
        )

        return CEOPlan(
            request=proposal.request,
            intent=proposal.intent,
            strategy=option.title,
            strategy_id=option.id,
            engine_type=engine_type,
            project_name=snapshot.project.name,
            project_root=str(root),
            project_facts=facts,
            tasks=proposed_tasks,
            warnings=warnings,
            existing_open_tasks=len(open_tasks),
            engine_ready=engine_ready,
        )

    def _inspect_project(
        self,
        root: Path,
    ) -> list[str]:
        facts: list[str] = []

        branch = self._git_branch(
            root
        )

        if branch:
            facts.append(
                f"Git branch: {branch}"
            )

        if (root / "package.json").exists():
            facts.append(
                "Node/JavaScript project detected"
            )

        if (
            (root / "tsconfig.json").exists()
            or (root / "src").exists()
            and any(
                root.glob("src/**/*.ts")
            )
        ):
            facts.append(
                "TypeScript source detected"
            )

        if (
            (root / "pyproject.toml").exists()
            or (root / "requirements.txt").exists()
        ):
            facts.append(
                "Python project detected"
            )

        if (root / "supabase").exists():
            facts.append(
                "Supabase integration detected"
            )

        if (
            (root / "vercel.json").exists()
            or (root / ".vercel").exists()
        ):
            facts.append(
                "Vercel configuration detected"
            )

        if (
            (root / ".codex").exists()
            and (root / "tasks").exists()
        ):
            facts.append(
                "AI Company OS project structure detected"
            )

        if not facts:
            facts.append(
                "No additional project characteristics detected"
            )

        return facts

    def _git_branch(
        self,
        root: Path,
    ) -> str | None:
        head = root / ".git" / "HEAD"

        if not head.exists():
            return None

        try:
            text = head.read_text(
                encoding="utf-8"
            ).strip()
        except OSError:
            return None

        prefix = "ref: refs/heads/"

        if text.startswith(prefix):
            return text[len(prefix):]

        if text:
            return "detached"

        return None

    def _build_tasks(
        self,
        intent: str,
        strategy: str,
        request: str,
    ) -> list[ProposedTask]:

        if intent == "AUDIT":
            return self._audit_plan(
                strategy,
                request,
            )

        if intent == "FIX":
            return self._fix_plan(
                strategy,
                request,
            )

        if intent == "FEATURE":
            return self._feature_plan(
                strategy,
                request,
            )

        return self._research_plan(
            strategy,
            request,
        )

    def _audit_plan(
        self,
        strategy: str,
        request: str,
    ) -> list[ProposedTask]:

        if strategy == "focused":
            return [
                ProposedTask(
                    key="PLAN-01",
                    title="Focused engineering audit",
                    owner="engineering-manager",
                    objective=request,
                    wave=1,
                )
            ]

        specialists = [
            ProposedTask(
                key="PLAN-01",
                title="Product completeness audit",
                owner="pm",
                objective=request,
                wave=1,
            ),
            ProposedTask(
                key="PLAN-02",
                title="Architecture audit",
                owner="cto",
                objective=request,
                wave=1,
            ),
            ProposedTask(
                key="PLAN-03",
                title="QA and regression audit",
                owner="qa",
                objective=request,
                wave=1,
            ),
            ProposedTask(
                key="PLAN-04",
                title="Security audit",
                owner="security",
                objective=request,
                wave=1,
            ),
        ]

        if strategy == "thorough":
            specialists.append(
                ProposedTask(
                    key="PLAN-05",
                    title="Deployment and operations audit",
                    owner="devops",
                    objective=request,
                    wave=1,
                )
            )

        dependencies = [
            task.key
            for task in specialists
        ]

        specialists.append(
            ProposedTask(
                key="PLAN-99",
                title="Consolidate audit into engineering plan",
                owner="engineering-manager",
                objective=(
                    "Convert verified findings into "
                    "prioritized executable work."
                ),
                dependencies=dependencies,
                wave=2,
            )
        )

        return specialists

    def _fix_plan(
        self,
        strategy: str,
        request: str,
    ) -> list[ProposedTask]:

        result = [
            ProposedTask(
                key="PLAN-01",
                title="Reproduce and scope defect",
                owner="engineering-manager",
                objective=request,
                wave=1,
            )
        ]

        if strategy == "thorough":
            result.append(
                ProposedTask(
                    key="PLAN-02",
                    title="Review architectural impact",
                    owner="cto",
                    objective=request,
                    dependencies=["PLAN-01"],
                    wave=2,
                )
            )

            implementation_dependencies = [
                "PLAN-01",
                "PLAN-02",
            ]

        else:
            implementation_dependencies = [
                "PLAN-01"
            ]

        result.append(
            ProposedTask(
                key="PLAN-03",
                title="Prepare corrective implementation",
                owner="engineering-manager",
                objective=request,
                dependencies=implementation_dependencies,
                wave=3 if strategy == "thorough" else 2,
            )
        )

        result.append(
            ProposedTask(
                key="PLAN-04",
                title="Verify fix and regression coverage",
                owner="qa",
                objective=request,
                dependencies=["PLAN-03"],
                wave=4 if strategy == "thorough" else 3,
            )
        )

        if strategy == "thorough":
            result.append(
                ProposedTask(
                    key="PLAN-05",
                    title="Review security impact",
                    owner="security",
                    objective=request,
                    dependencies=["PLAN-03"],
                    wave=4,
                )
            )

        return result

    def _feature_plan(
        self,
        strategy: str,
        request: str,
    ) -> list[ProposedTask]:

        if strategy == "focused":
            return [
                ProposedTask(
                    key="PLAN-01",
                    title="Define implementation scope",
                    owner="engineering-manager",
                    objective=request,
                    wave=1,
                )
            ]

        result = [
            ProposedTask(
                key="PLAN-01",
                title="Define product scope and acceptance criteria",
                owner="pm",
                objective=request,
                wave=1,
            ),
            ProposedTask(
                key="PLAN-02",
                title="Define technical architecture",
                owner="cto",
                objective=request,
                dependencies=["PLAN-01"],
                wave=2,
            ),
            ProposedTask(
                key="PLAN-03",
                title="Prepare engineering execution plan",
                owner="engineering-manager",
                objective=request,
                dependencies=[
                    "PLAN-01",
                    "PLAN-02",
                ],
                wave=3,
            ),
            ProposedTask(
                key="PLAN-04",
                title="Prepare QA validation",
                owner="qa",
                objective=request,
                dependencies=["PLAN-03"],
                wave=4,
            ),
        ]

        if strategy == "thorough":
            result.extend(
                [
                    ProposedTask(
                        key="PLAN-05",
                        title="Prepare security review",
                        owner="security",
                        objective=request,
                        dependencies=["PLAN-03"],
                        wave=4,
                    ),
                    ProposedTask(
                        key="PLAN-06",
                        title="Prepare deployment and rollback plan",
                        owner="devops",
                        objective=request,
                        dependencies=["PLAN-03"],
                        wave=4,
                    ),
                ]
            )

        return result

    def _research_plan(
        self,
        strategy: str,
        request: str,
    ) -> list[ProposedTask]:

        if strategy == "focused":
            return [
                ProposedTask(
                    key="PLAN-01",
                    title="Investigate request",
                    owner="engineering-manager",
                    objective=request,
                    wave=1,
                )
            ]

        return [
            ProposedTask(
                key="PLAN-01",
                title="Frame product decision",
                owner="pm",
                objective=request,
                wave=1,
            ),
            ProposedTask(
                key="PLAN-02",
                title="Evaluate technical options",
                owner="cto",
                objective=request,
                wave=1,
            ),
            ProposedTask(
                key="PLAN-03",
                title="Consolidate recommendation",
                owner="engineering-manager",
                objective=request,
                dependencies=[
                    "PLAN-01",
                    "PLAN-02",
                ],
                wave=2,
            ),
        ]