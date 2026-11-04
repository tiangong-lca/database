#!/usr/bin/env python3
"""Materialize Database #909's disposable PG17 project without operating a database."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
from prepare_study_runtime_project import settings


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--destination', type=Path, required=True)
    args = parser.parse_args()
    destination = args.destination.resolve()
    assert destination.name == 'study909' and not destination.exists()
    source = Path(__file__).resolve().parents[1] / 'supabase'
    config = (source / 'config.toml').read_text()
    assert settings(config) == ('database-engine', 55322, 17)
    config = config.replace('project_id = "database-engine"', 'project_id = "study909"', 1)
    config = re.sub(r'\n\[remotes\.[\s\S]*', '\n', config)
    for old, new in [(55321, 56821), (55322, 56822), (55320, 56820),
                     (55323, 56823), (55324, 56824), (55327, 56827), (55329, 56829)]:
        config = config.replace(str(old), str(new))
    assert settings(config) == ('study909', 56822, 17)
    target = destination / 'supabase'
    target.mkdir(parents=True)
    for directory in ['migrations', 'seeds', 'templates']:
        if (source / directory).is_dir():
            shutil.copytree(source / directory, target / directory)
    shutil.copy2(source / 'seed.sql', target / 'seed.sql')
    (target / 'config.toml').write_text(config)
    receipt = {'schemaVersion': 'lca.study-owned-project.v1', 'issue': 'database#909',
               'project': 'study909', 'destination': str(destination), 'postgresMajor': 17,
               'apiPort': 56821, 'dbPort': 56822, 'sharedProjectTouched': False,
               'migrationHashes': {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                                   for p in sorted((target / 'migrations').glob('*.sql'))},
               'disposition': 'Database #909 owns exact study909 resources; cleanup receipt required'}
    (destination / 'ownership.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print('Materialized owned study909/PG17 API56821 DB56822; no database operation performed.')


if __name__ == '__main__':
    main()
