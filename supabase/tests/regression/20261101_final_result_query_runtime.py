#!/usr/bin/env python3
"""Observed runtime admission CAS races; exact owner-reset synthetic DB only."""
import importlib.util
import json
from pathlib import Path
import subprocess

spec = importlib.util.spec_from_file_location('identity', Path(__file__).with_name('20261101_final_result_identity_concurrency.py'))
db = importlib.util.module_from_spec(spec)
spec.loader.exec_module(db)


def configure(revision, expected):
    prior = 'null' if expected is None else "'" + expected + "'"
    return f"select api.svc_result_query_runtime_configure_v2('{revision}',{prior},repeat('d',64),repeat('c',64),true,'synthetic runtime race');"


def race(number, isolation, same):
    first_id = f'87941000-0000-4000-8000-{number:012d}'
    second_id = first_id if same else f'87942000-0000-4000-8000-{number:012d}'
    expected = db.query('select revision_id from private.final_result_query_runtime_head;') or None
    assert db.query(f"select not exists(select 1 from private.final_result_query_runtime_revisions where id='{first_id}');") == 't'
    names = f'runtime879_a_{number}', f'runtime879_b_{number}'
    first, second = db.client(names[0]), db.client(names[1])
    try:
        first.stdin.write('begin;set local role service_role;' + configure(first_id, expected) + '\n')
        first.stdin.flush()
        db.wait_for(f"select exists(select 1 from pg_stat_activity where application_name='{names[0]}' and state='idle in transaction');")
        second.stdin.write(f'begin isolation level {isolation}; select count(*) from private.final_result_query_runtime_revisions;set local role service_role;' + configure(second_id, expected) + '\ncommit;\n\\q\n')
        second.stdin.flush()
        db.wait_for(f"select exists(select 1 from pg_stat_activity b join pg_stat_activity a on a.pid=any(pg_blocking_pids(b.pid)) where a.application_name='{names[0]}' and b.application_name='{names[1]}');")
        first.stdin.write('commit;\n\\q\n')
        first.stdin.flush()
        _, error_a = first.communicate(timeout=20)
        out_b, error_b = second.communicate(timeout=20)
        assert first.returncode == 0, error_a
        if isolation == 'read committed':
            assert second.returncode == 0, error_b
            response = json.loads(out_b.splitlines()[-1])
            assert response.get('data', {}).get('isCurrent') is True if same else response['code'] == 'runtime_revision_conflict'
        elif second.returncode:
            assert any(f'ERROR:  {code}:' in error_b for code in ('40001', '23505')), error_b
        else:
            response = json.loads(out_b.splitlines()[-1])
            assert response.get('data', {}).get('isCurrent') is True if same else response['code'] == 'runtime_revision_conflict'
        assert db.query('select revision_id from private.final_result_query_runtime_head;') == first_id
        recovered = json.loads(db.query('set role service_role;' + configure(first_id, expected)))
        assert recovered['data']['isCurrent'] is True
        assert recovered['data']['publicationAuthorized'] is False
        print(f'ok - {isolation}: runtime {"same revision retry" if same else "conflicting CAS"}', flush=True)
    finally:
        for process in (first, second):
            if process.poll() is None:
                process.kill()
                process.communicate(timeout=5)


def main():
    metadata = json.loads(subprocess.check_output(['docker', 'inspect', db.CONTAINER]))[0]
    assert metadata['Name'] == '/' + db.CONTAINER
    assert metadata['Config']['Labels'].get('com.supabase.cli.project') == 'hdf5-final-879'
    assert db.query('select count(*) from private.final_result_query_runtime_revisions;') == '0', 'owner reset required'
    number = 879800
    for isolation in ('read committed', 'repeatable read', 'serializable'):
        for same in (True, False):
            race(number, isolation, same)
            number += 1
    assert db.query('select count(*) from private.lca_release_publications;') == '0'
    print('6 real runtime CAS races passed; synthetic admission history retained for owner reset')


if __name__ == '__main__':
    main()
