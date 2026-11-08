#!/usr/bin/env python3
"""Render a self-contained calculation-admission proof for Supabase pg_prove.

The CLI mounts an individual test's directory, so sibling fixture/migration
includes in upgrade/ and regression/ must be expanded before container testing.
Inputs remain the checked-in SQL, including the actual forward migration.
"""
import argparse
import hashlib
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
SOURCES = {
    "upgrade": "supabase/tests/upgrade/20261108_calculation_certificate_admission.sql",
    "transactions": "supabase/tests/regression/20261108_calculation_admission_transactions.sql",
}


def expand(path, ancestors=()):
    path = path.resolve()
    if not path.is_relative_to(ROOT / "supabase") or path in ancestors:
        raise ValueError("SQL include escapes the source tree or contains a cycle")
    result = []
    for line in path.read_text().splitlines(keepends=True):
        match = re.fullmatch(r"\\ir ([^\s]+)\s*", line)
        if match:
            result.append(expand(path.parent / match[1], (*ancestors, path)))
        else:
            result.append(line)
    return "".join(result)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("proof", choices=SOURCES)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    sql = expand(ROOT / SOURCES[args.proof])
    # Exclusive creation prevents replacing another task's proof or source file.
    with args.output.open("x") as output:
        output.write(sql)
    print(f"Rendered {args.proof} proof; SHA-256 {hashlib.sha256(sql.encode()).hexdigest()}")


if __name__ == "__main__":
    main()
