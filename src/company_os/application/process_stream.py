from __future__ import annotations

import subprocess
import time
from dataclasses import dataclass
from queue import Empty, Queue
from threading import Thread
from typing import Callable
from pathlib import Path


ProgressCallback = Callable[[str], None]


@dataclass(frozen=True)
class StreamedProcessResult:
    returncode: int
    output: str


def _observe_process_failure(command: list[str], category: str,
                             on_line: ProgressCallback | None) -> None:
    """Record launch/timeout metadata for known AICO runners, never process prose."""
    runners = {"run-active-agents.ps1": "agent-runner",
               "run-agent-task.ps1": "agent-runner",
               "run-gate-agent.ps1": "gate-runner",
               "run-writable-agent.ps1": "writable-runner"}
    try:
        script = command[command.index("-File") + 1]
        component = runners.get(Path(script).name)
        if component is None or "-ProjectPath" not in command:
            return
        project = command[command.index("-ProjectPath") + 1]
        event = {"event_type": "runtime_failure", "component": component,
                 "error_category": category}
        if "-Id" in command:
            event["task_id"] = command[command.index("-Id") + 1]
        from company_os.error_intelligence.runtime import capture_event

        observed = capture_event(project, event)
        if on_line and observed["status"] == "captured":
            on_line(f"Error Intelligence: incident={observed['incident_id']}")
        elif on_line and observed["status"] == "unavailable":
            on_line("ERROR_INTELLIGENCE_CAPTURE_UNAVAILABLE")
    except Exception:
        # Failure observation cannot replace the original execution exception.
        pass


def run_streamed_process(
    command: list[str],
    *,
    timeout: int,
    env: dict[str, str] | None = None,
    cwd: str | None = None,
    on_line: ProgressCallback | None = None,
) -> StreamedProcessResult:
    try:
        process = subprocess.Popen(
            command,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
            env=env,
            cwd=cwd,
        )
    except OSError:
        _observe_process_failure(command, "process_launch", on_line)
        raise

    queue: Queue[object] = Queue()
    empty_marker = object()

    def reader() -> None:
        try:
            stream = process.stdout

            if stream is None:
                return

            for raw_line in stream:
                queue.put(
                    raw_line.rstrip("\r\n")
                )
        finally:
            queue.put(None)

    thread = Thread(
        target=reader,
        daemon=True,
    )
    thread.start()

    started = time.monotonic()
    lines: list[str] = []
    reader_finished = False

    while True:
        elapsed = (
            time.monotonic()
            - started
        )

        if elapsed > timeout:
            process.kill()
            thread.join(timeout=1)
            _observe_process_failure(command, "timeout", on_line)

            raise subprocess.TimeoutExpired(
                command,
                timeout,
                output="\n".join(lines),
            )

        try:
            line = queue.get(
                timeout=0.1
            )
        except Empty:
            line = empty_marker

        if line is None:
            reader_finished = True

        elif line is not empty_marker:
            text_line = str(line)
            lines.append(text_line)

            if on_line is not None:
                try:
                    on_line(text_line)
                except Exception:
                    # Progress reporting must never alter
                    # the execution result.
                    pass

        if (
            process.poll() is not None
            and reader_finished
        ):
            break

    return StreamedProcessResult(
        returncode=process.wait(),
        output="\n".join(lines).strip(),
    )
