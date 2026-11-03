#!/usr/bin/env python3
"""Materialize the Database #906 disposable project without starting/resetting it."""
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
    assert destination.name == 'study906' and not destination.exists()
    source = Path(__file__).resolve().parents[1] / 'supabase'
    config = (source / 'config.toml').read_text()
    assert settings(config) == ('database-engine', 55322, 17)
    config = config.replace('project_id = "database-engine"', 'project_id = "study906"', 1)
    config = re.sub(r'\n\[remotes\.[\s\S]*', '\n', config)
    for old, new in [(55321, 56621), (55322, 56622), (55320, 56620),
                     (55323, 56623), (55324, 56624), (55327, 56627), (55329, 56629)]:
        config = config.replace(str(old), str(new))
    assert settings(config) == ('study906', 56622, 17)
    target = destination / 'supabase'
    target.mkdir(parents=True)
    for directory in ['migrations', 'seeds', 'templates']:
        if (source / directory).is_dir():
            shutil.copytree(source / directory, target / directory)
    shutil.copy2(source / 'seed.sql', target / 'seed.sql')
    (target / 'config.toml').write_text(config)
    receipt = {'schemaVersion': 'lca.study-owned-project.v1', 'issue': 'database#906',
               'project': 'study906', 'destination': str(destination), 'postgresMajor': 17,
               'apiPort': 56621, 'dbPort': 56622, 'sharedProjectTouched': False,
               'migrationHashes': {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                                   for p in sorted((target / 'migrations').glob('*.sql'))},
               'disposition': 'Database #906 owns exact study906 resources; cleanup receipt required'}
    (destination / 'ownership.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print('Materialized owned study906/PG17 API56621 DB56622; no database operation performed.')


if __name__ == '__main__':
    main()
