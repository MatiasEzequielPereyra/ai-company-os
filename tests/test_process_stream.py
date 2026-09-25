from __future__ import annotations

import sys

from company_os.application.process_stream import (
    run_streamed_process,
)


def test_run_streamed_process_emits_lines() -> None:
    events: list[str] = []

    result = run_streamed_process(
        [
            sys.executable,
            "-c",
            (
                "import time;"
                "print('first', flush=True);"
                "time.sleep(0.05);"
                "print('second', flush=True)"
            ),
        ],
        timeout=5,
        on_line=events.append,
    )

    assert result.returncode == 0
    assert events == [
        "first",
        "second",
    ]
    assert result.output == "first\nsecond"
