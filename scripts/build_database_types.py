#!/usr/bin/env python3
"""Generate the checked-in TypeScript contract for exposed Data API schemas."""

from __future__ import annotations

import argparse
import subprocess
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
OUTPUT = REPO_ROOT / "supabase" / "workspace" / "database.types.ts"


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Generate TypeScript types for the public and api Data API schemas."
    )
    parser.add_argument(
        "--environment",
        choices=("local", "linked"),
        default="local",
        help="Supabase CLI database target (default: local)",
    )
    args = parser.parse_args()

    command = [
        "supabase",
        "gen",
        "types",
        "typescript",
        f"--{args.environment}",
        "--schema",
        "public",
        "--schema",
        "api",
    ]
    result = subprocess.run(
        command,
        cwd=REPO_ROOT,
        check=True,
        stdout=subprocess.PIPE,
        text=True,
    )
    OUTPUT.write_text(result.stdout.rstrip() + "\n", encoding="utf-8")
    print(f"Wrote {OUTPUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
