"""Positive baseline checks for the existing list command."""

from pathlib import Path
import subprocess
import sys
import unittest


PROJECT_ROOT = Path(__file__).resolve().parents[1]


def run_cli(*arguments: str) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(
        [sys.executable, "-B", "-m", "taskcli", *arguments],
        cwd=PROJECT_ROOT,
        capture_output=True,
        text=False,
        check=False,
    )


class BaselineCLITests(unittest.TestCase):
    def test_cli_help_succeeds(self) -> None:
        self.assertEqual(run_cli("--help").returncode, 0)

    def test_list_command_exists(self) -> None:
        self.assertEqual(run_cli("list", "--help").returncode, 0)

    def test_list_stdout(self) -> None:
        self.assertEqual(run_cli("list").stdout, b"No tasks.\n")

    def test_list_stderr(self) -> None:
        self.assertEqual(run_cli("list").stderr, b"")

    def test_list_exit_code(self) -> None:
        self.assertEqual(run_cli("list").returncode, 0)


if __name__ == "__main__":
    unittest.main()
