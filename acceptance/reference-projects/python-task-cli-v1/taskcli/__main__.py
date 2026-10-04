"""Command line entry point for the reference task CLI."""

import argparse
import sys


def main() -> int:
    parser = argparse.ArgumentParser(prog="taskcli", description="List tasks.")
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("list", help="List tasks.")
    parser.parse_args()
    sys.stdout.buffer.write(b"No tasks.\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
