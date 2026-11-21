#!/usr/bin/env python3
"""Generate deterministic TypeScript modules from Portal JSON Schemas."""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
SCHEMA_DIR = REPO_ROOT / "contracts" / "portal"
OUTPUT_DIR = SCHEMA_DIR / "generated"
TOOL_VERSION = "15.0.4"
GENERATED_SUFFIX = ".d.ts"
GENERATOR_PATH = Path(__file__).resolve()


def tool_identity() -> dict:
    tools = {}
    for name in ("node", "npx"):
        executable = shutil.which(name)
        if executable is None:
            raise ValueError(f"Portal generation requires {name}")
        tools[name] = {
            "path": str(Path(executable).resolve()),
            "version": subprocess.check_output([executable, "--version"], text=True).strip(),
        }
    return {"python": sys.version, "tools": tools}


def input_snapshot() -> dict:
    for directory in (SCHEMA_DIR, OUTPUT_DIR):
        if directory.is_symlink() or not directory.is_dir():
            raise ValueError(f"Portal inputs require regular directories: {directory}")
    schemas = sorted(SCHEMA_DIR.glob("*.schema.json"))
    if not schemas:
        raise ValueError("Portal schemas are missing")
    files = [GENERATOR_PATH, *schemas, *sorted(OUTPUT_DIR.glob(f"*{GENERATED_SUFFIX}"))]
    hashes = {}
    for file in files:
        if file.is_symlink() or not file.is_file():
            raise ValueError(f"Portal inputs require regular files: {file}")
        hashes[str(file.relative_to(REPO_ROOT))] = hashlib.sha256(file.read_bytes()).hexdigest()
    return {
        "schema": "portal-type-inputs.v1",
        "root": str(REPO_ROOT.resolve()),
        "generator_version": TOOL_VERSION,
        "environment": tool_identity(),
        "files": hashes,
    }


def capture_inputs(destination: Path) -> None:
    # This records inputs only. It never asserts that generation or validation passed.
    value = input_snapshot()
    with destination.open("x", encoding="utf-8") as output:
        json.dump(value, output, sort_keys=True)
        output.write("\n")
    print(f"Captured Portal input inventory ({len(value['files'])} files); generation still required")


def verify_inputs(snapshot: Path) -> None:
    if snapshot.is_symlink() or not snapshot.is_file():
        if not snapshot.exists():
            raise FileNotFoundError(snapshot)
        raise ValueError("Portal input snapshot requires a regular file")
    if json.loads(snapshot.read_text(encoding="utf-8")) != input_snapshot():
        raise ValueError("Portal generation inputs, outputs or tools changed between checks")


def check_with_snapshot(snapshot: Path | None = None) -> int:
    if snapshot is not None:
        verify_inputs(snapshot)
    with tempfile.TemporaryDirectory(prefix="portal-contract-types-") as temp_dir:
        rendered = render_all(Path(temp_dir))
    result = check_generated(rendered)
    if snapshot is not None:
        verify_inputs(snapshot)
    return result


def output_name(schema: Path) -> str:
    suffix = ".schema.json"
    if not schema.name.endswith(suffix):
        raise ValueError(f"unsupported Portal schema name: {schema.name}")
    return schema.name[: -len(suffix)] + GENERATED_SUFFIX


def compile_schema(schema: Path, output: Path) -> None:
    subprocess.run(
        [
            "npx",
            "--yes",
            "--package",
            f"json-schema-to-typescript@{TOOL_VERSION}",
            "json2ts",
            "--input",
            str(schema),
            "--output",
            str(output),
            "--cwd",
            str(SCHEMA_DIR),
            "--no-enableConstEnums",
            "--unknownAny",
            "--unreachableDefinitions",
            "--maxItems=-1",
        ],
        cwd=REPO_ROOT,
        check=True,
    )
    generated = output.read_text(encoding="utf-8").rstrip() + "\n"
    provenance = (
        f"// Source: ../{schema.name}\n"
        f"// Generator: json-schema-to-typescript@{TOOL_VERSION}\n"
    )
    output.write_text(provenance + generated, encoding="utf-8")


def render_all(destination: Path) -> dict[str, str]:
    schemas = sorted(SCHEMA_DIR.glob("*.schema.json"), key=lambda path: path.name)
    if not schemas:
        raise RuntimeError(f"no Portal JSON Schemas found under {SCHEMA_DIR}")

    rendered: dict[str, str] = {}
    for schema in schemas:
        generated = destination / output_name(schema)
        compile_schema(schema, generated)
        rendered[generated.name] = generated.read_text(encoding="utf-8")
    return rendered


def check_generated(rendered: dict[str, str]) -> int:
    actual_names = (
        {path.name for path in OUTPUT_DIR.glob(f"*{GENERATED_SUFFIX}")}
        if OUTPUT_DIR.is_dir()
        else set()
    )
    expected_names = set(rendered)
    drifted = sorted(
        name
        for name, expected in rendered.items()
        if not (OUTPUT_DIR / name).is_file()
        or (OUTPUT_DIR / name).read_text(encoding="utf-8") != expected
    )
    unexpected = sorted(actual_names - expected_names)
    if drifted or unexpected:
        if drifted:
            print("Portal generated TypeScript drift: " + ", ".join(drifted))
        if unexpected:
            print("Unexpected Portal generated TypeScript: " + ", ".join(unexpected))
        return 1
    print(
        f"Portal generated TypeScript is current ({len(expected_names)} modules, "
        f"json-schema-to-typescript@{TOOL_VERSION})"
    )
    return 0


def write_generated(rendered: dict[str, str]) -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    expected_names = set(rendered)
    for existing in OUTPUT_DIR.glob(f"*{GENERATED_SUFFIX}"):
        if existing.name not in expected_names:
            existing.unlink()
    for name, content in rendered.items():
        (OUTPUT_DIR / name).write_text(content, encoding="utf-8")
    print(
        f"Wrote {len(rendered)} Portal TypeScript modules with "
        f"json-schema-to-typescript@{TOOL_VERSION}"
    )


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Generate committed TypeScript modules from the exhaustive Portal "
            "JSON Schemas."
        )
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="fail on generated drift without modifying the checkout",
    )
    parser.add_argument("--capture-inputs", type=Path, help="record inputs only; does not run or replace --check")
    parser.add_argument("--input-snapshot", type=Path, help="with --check, also reject drift since the earlier input capture")
    args = parser.parse_args()

    if args.capture_inputs:
        if args.check or args.input_snapshot:
            parser.error("--capture-inputs is independent of --check and --input-snapshot")
        capture_inputs(args.capture_inputs)
        return 0
    if args.input_snapshot and not args.check:
        parser.error("--input-snapshot requires --check")
    if args.check:
        return check_with_snapshot(args.input_snapshot)

    with tempfile.TemporaryDirectory(prefix="portal-contract-types-") as temp_dir:
        rendered = render_all(Path(temp_dir))
    write_generated(rendered)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
