#!/usr/bin/env python3
"""Materialize Database #912's disposable PG17 project without operating a database."""
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
    parser.add_argument('--through-version', default=None)
    args = parser.parse_args()
    assert args.through_version is None or re.fullmatch(r'[0-9]{14}', args.through_version)
    destination = args.destination.resolve()
    assert destination.name == 'study912' and not destination.exists()
    source = Path(__file__).resolve().parents[1] / 'supabase'
    config = (source / 'config.toml').read_text()
    assert settings(config) == ('database-engine', 55322, 17)
    config = config.replace('project_id = "database-engine"', 'project_id = "study912"', 1)
    config = re.sub(r'\n\[remotes\.[\s\S]*', '\n', config)
    for old, new in [(55321, 56921), (55322, 56922), (55320, 56920),
                     (55323, 56923), (55324, 56924), (55327, 56927), (55329, 56929)]:
        config = config.replace(str(old), str(new))
    assert settings(config) == ('study912', 56922, 17)
    target = destination / 'supabase'
    target.mkdir(parents=True)
    for directory in ['migrations', 'seeds', 'templates']:
        if (source / directory).is_dir():
            shutil.copytree(source / directory, target / directory)
    shutil.copy2(source / 'seed.sql', target / 'seed.sql')
    if args.through_version:
        assert any(p.name.startswith(args.through_version+'_') for p in (target/'migrations').glob('*.sql'))
        for p in (target/'migrations').glob('*.sql'):
            if p.name.split('_')[0] > args.through_version:
                p.unlink()
    (target / 'config.toml').write_text(config)
    receipt = {'schemaVersion': 'lca.study-owned-project.v1', 'issue': 'database#912',
               'project': 'study912', 'destination': str(destination), 'postgresMajor': 17,
               'apiPort': 56921, 'dbPort': 56922, 'sharedProjectTouched': False,
               'migrationHashes': {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                                   for p in sorted((target / 'migrations').glob('*.sql'))},
               'disposition': 'Database #912 owns exact study912 resources; cleanup receipt required'}
    (destination / 'ownership.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print('Materialized owned study912/PG17 API56921 DB56922; no database operation performed.')


if __name__ == '__main__':
    main()
