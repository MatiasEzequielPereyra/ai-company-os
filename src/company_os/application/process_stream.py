from __future__ import annotations

import subprocess
import time
from dataclasses import dataclass
from queue import Empty, Queue
from threading import Thread
from typing import Callable


ProgressCallback = Callable[[str], None]


@dataclass(frozen=True)
class StreamedProcessResult:
    returncode: int
    output: str


def run_streamed_process(
    command: list[str],
    *,
    timeout: int,
    env: dict[str, str] | None = None,
    cwd: str | None = None,
    on_line: ProgressCallback | None = None,
) -> StreamedProcessResult:
    process = subprocess.Popen(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
        env=env,
        cwd=cwd,
    )

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
