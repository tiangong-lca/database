#!/usr/bin/env python3
"""Materialize an independent study894 Supabase project; never start/reset it.

The tracked config and shared database-engine project remain untouched. Callers
must own the destination and retain/clean exact project resources explicitly.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil

def settings(config):
    """Read only three guarded scalar fields in the repository's known layout."""
    header = re.split(r'^\[', config, maxsplit=1, flags=re.M)[0]
    project = re.findall(r'^project_id\s*=\s*"([a-z0-9-]+)"\s*$', header, re.M)
    section = re.findall(r'^\[db\]\s*\n([\s\S]*?)(?=^\[|\Z)', config, re.M)
    assert len(project) == len(section) == 1, "ambiguous project/database configuration"
    port = re.findall(r'^port\s*=\s*(\d+)\s*$', section[0], re.M)
    major = re.findall(r'^major_version\s*=\s*(\d+)\s*$', section[0], re.M)
    assert len(port) == len(major) == 1, "ambiguous database scalar fields"
    return project[0], int(port[0]), int(major[0])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--destination", type=Path, required=True)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    destination = args.destination.resolve()
    if destination.name != "study894" or destination.exists():
        parser.error("destination must be a new task-owned directory named study894")
    source = repo / "supabase"
    config = (source / "config.toml").read_text()
    assert settings(config)[0] == "database-engine"
    config = config.replace('project_id = "database-engine"', 'project_id = "study894"', 1)
    config = re.sub(r"\n\[remotes\.[\s\S]*", "\n", config)
    for old, new in [(55321, 56421), (55322, 56422), (55320, 56420),
                     (55323, 56423), (55324, 56424), (55327, 56427), (55329, 56429)]:
        config = config.replace(str(old), str(new))
    assert settings(config) == ("study894", 56422, 17)
    assert not re.search(r'^\[remotes\.', config, re.M)
    target = destination / "supabase"
    target.mkdir(parents=True)
    for directory in ["migrations", "seeds", "templates"]:
        if (source / directory).is_dir():
            shutil.copytree(source / directory, target / directory)
    shutil.copy2(source / "seed.sql", target / "seed.sql")
    (target / "config.toml").write_text(config)
    receipt = {"schemaVersion": "lca.study-owned-project.v1", "issue": "database#894",
        "project": "study894", "destination": str(destination), "postgresMajor": 17,
        "apiPort": 56421, "dbPort": 56422,
        "migrationHashes": {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                            for p in sorted((target / "migrations").glob("*.sql"))},
        "disposition": "caller owns exact study894 resources and must preserve cleanup/retention evidence"}
    (destination / "ownership.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print("Materialized isolated study894/PG17 configuration; no database operation performed.")


if __name__ == "__main__":
    main()
