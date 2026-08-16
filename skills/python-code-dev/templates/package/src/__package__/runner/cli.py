"""Command-line entrypoint for the example runner."""

import argparse
import sys
from pathlib import Path

from __PACKAGE__.configs.paths import output_root
from __PACKAGE__.core import ExampleRunner


def build_parser() -> argparse.ArgumentParser:
    """Build CLI parser.

    Returns:
        Configured argument parser.
    """
    parser = argparse.ArgumentParser(description="Run __PROJECT__ example pipeline.")
    parser.add_argument("--message", default="hello", help="Message written to artifact")
    parser.add_argument("--output-root", default=None, help="Override output root")
    return parser


def main(argv: list[str] | None = None) -> int:
    """Run the example pipeline CLI.

    Args:
        argv: Optional. Command-line args. ``None`` reads from ``sys.argv``.

    Returns:
        Process exit code. ``0`` indicates success.
    """
    args = build_parser().parse_args(argv)
    root = Path(args.output_root) if args.output_root is not None else output_root()
    result = ExampleRunner(output_root=root).run({"message": args.message})
    print(result.run_dir)
    return 0


if __name__ == "__main__":
    sys.exit(main())
