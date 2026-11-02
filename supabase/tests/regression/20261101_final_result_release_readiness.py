#!/usr/bin/env python3
"""Observed begin/proof/seal arbitration on the exact owner-reset synthetic DB."""
import copy
import importlib.util
import json
from pathlib import Path
import re
import subprocess

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('identity', HERE / '20261101_final_result_identity_concurrency.py')
db = importlib.util.module_from_spec(spec)
spec.loader.exec_module(db)


def sql(value):
    return "'" + json.dumps(value, separators=(',', ':')).replace("'", "''") + "'::jsonb"


def expand(path):
    return re.sub(r'^\\ir (.+)$', lambda m: expand((path.parent / m[1]).resolve()), path.read_text(), flags=re.M)


def commands(header, proofs):
    identity = header['verificationId']
    return (
        'select api.svc_final_result_readiness_begin_v2(' + sql(header) + ');',
        f"select api.svc_final_result_readiness_artifacts_v2('{identity}'," + sql(proofs) + ');',
        f"select api.svc_final_result_readiness_seal_v2('{identity}');",
    )


def race(number, isolation, kind, fixture):
    header = copy.deepcopy(fixture['header'])
    header['verificationId'] = f'87951000-0000-4000-8000-{number:012d}'
    proofs = fixture['proofs']
    begin, stage, seal = commands(header, proofs)
    if kind == 'begin_conflict':
        changed = dict(header, readerSha256='e' * 64)
        first_sql, second_sql = begin, commands(changed, proofs)[0]
    else:
        db.query('set role service_role;' + begin + (stage if kind == 'seal_retry' else ''))
        first_sql = second_sql = seal if kind == 'seal_retry' else stage
    names = f'readiness879_a_{number}', f'readiness879_b_{number}'
    first, second = db.client(names[0]), db.client(names[1])
    try:
        first.stdin.write('begin;set local role service_role;' + first_sql + '\n')
        first.stdin.flush()
        db.wait_for(f"select exists(select 1 from pg_stat_activity where application_name='{names[0]}' and state='idle in transaction');")
        second.stdin.write(f'begin isolation level {isolation};select count(*) from private.final_result_release_verifications;set local role service_role;' + second_sql + '\ncommit;\n\\q\n')
        second.stdin.flush()
        db.wait_for(f"select exists(select 1 from pg_stat_activity b join pg_stat_activity a on a.pid=any(pg_blocking_pids(b.pid)) where a.application_name='{names[0]}' and b.application_name='{names[1]}');")
        first.stdin.write('commit;\n\\q\n')
        first.stdin.flush()
        _, error_a = first.communicate(timeout=20)
        _, error_b = second.communicate(timeout=20)
        assert first.returncode == 0, error_a
        if isolation == 'read committed' and kind != 'begin_conflict':
            assert second.returncode == 0, error_b
        elif second.returncode:
            # A conflicting header can be rejected against a fresh snapshot
            # (23505) or the stale context (22023); neither can commit evidence.
            assert any(f'ERROR:  {code}:' in error_b for code in ('23505', '40001', '22023')), error_b
        else:
            assert kind != 'begin_conflict', 'conflicting verification identity committed'
        recovered = json.loads(db.query('set role service_role;' + begin + stage + seal).splitlines()[-1])['data']
        assert recovered['artifactCount'] == 2 and recovered['probeCount'] == 2
        assert recovered['publicationAuthorized'] is False
        assert db.query(f"select count(*) from private.final_result_release_artifact_proofs where verification_id='{header['verificationId']}';") == '2'
        print(f'ok - {isolation}: {kind}; exact retry recovered one immutable receipt', flush=True)
    finally:
        for process in (first, second):
            if process.poll() is None:
                process.kill()
                process.communicate(timeout=5)


def main():
    metadata = json.loads(subprocess.check_output(['docker', 'inspect', db.CONTAINER]))[0]
    assert metadata['Name'] == '/' + db.CONTAINER
    assert metadata['Config']['Labels'].get('com.supabase.cli.project') == 'hdf5-final-879'
    assert db.query('select count(*) from private.final_result_release_verifications;') == '0', 'owner reset required'
    assert db.query('select count(*) from private.final_result_query_runtime_revisions;') == '0', 'owner reset required'
    source = expand(HERE.parent / 'fixtures/final-result-readiness-setup.sql')
    output = db.query('begin;' + source + "\nselect jsonb_build_object('header',header,'proofs',proofs) from readiness_fixture;commit;")
    fixture = json.loads(output.splitlines()[-1])
    number = 879900
    for isolation in ('read committed', 'repeatable read', 'serializable'):
        for kind in ('begin_conflict', 'proof_retry', 'seal_retry'):
            race(number, isolation, kind, fixture)
            number += 1
    assert db.query('select count(*) from private.lca_release_publications;') == '0'
    assert db.query('select count(*) from private.final_result_release_readiness;') == '9'
    print('9 actual readiness races passed; immutable synthetic evidence retained for owner reset')


if __name__ == '__main__':
    main()
