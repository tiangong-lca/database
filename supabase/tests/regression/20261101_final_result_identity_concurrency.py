#!/usr/bin/env python3
"""Two real clients prove Result/legacy arbitration on a task-owned local DB.

No fixture deletion or disabled guards: immutable claims remain until the owner
resets this disposable project. Each run refuses pre-existing fixture identities.
"""
import hashlib
import json
import subprocess
import time

CONTAINER = 'supabase_db_hdf5-final-879'
BASE = ['docker', 'exec', '-i', CONTAINER, 'psql', '-X', '-qAt', '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=verbose']


def query(sql):
    result = subprocess.run(BASE, input=sql, text=True, capture_output=True, timeout=20, check=True)
    return result.stdout.strip()


def client(name):
    proc = subprocess.Popen(BASE, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    proc.stdin.write(f"set application_name='{name}'; set statement_timeout='20s'; set lock_timeout='15s';\n")
    proc.stdin.flush()
    return proc


def wait_for(sql):
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        if query(sql) == 't':
            return
        time.sleep(0.05)
    raise AssertionError('exact client barrier did not become observable')


def request(identity, changed=False):
    envelope = {
        'canonicalContentHash': ('c' if changed else 'a') * 64,
        'hashDomain': 'tiangong.final-result-content.jcs.v1',
        'semanticDependencies': [{'key': 'flow:87900000-0000-4000-8000-000000000002@01.00.000', 'contentHash': 'b' * 64}],
    }
    digest = hashlib.sha256(json.dumps(envelope, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
    value = dict(envelope, schemaVersion='tiangong.final-result-identity-request.v1', result={'uuid': identity, 'version': '01.00.000'}, contentHash=digest, producer='synthetic-concurrency')
    return "select api.svc_result_identity_register('" + json.dumps(value, separators=(',', ':')) + "'::jsonb);"


def claim(identity):
    # The same shared unique-key primitive called by every legacy table trigger.
    return f"select private.final_result_legacy_claim('{identity}','01.00.000');"


def race(number, isolation, first_legacy, second_kind):
    identity = f'87900000-0000-4000-8000-{number:012d}'
    assert query(f"select not exists(select 1 from private.final_result_identities where result_id='{identity}');") == 't', 'fixture already exists; owner reset required'
    first_name, second_name = f'identity879_a_{number}', f'identity879_b_{number}'
    first, second = client(first_name), client(second_name)
    try:
        first.stdin.write('begin;\n' + (claim(identity) if first_legacy else request(identity)) + '\n')
        first.stdin.flush()
        # The writer holds its transaction open without sleeps. Query state is
        # observed through another connection, not inferred from elapsed time.
        wait_for(f"select exists(select 1 from pg_stat_activity where application_name='{first_name}' and state='idle in transaction');")
        second_sql = claim(identity) if second_kind == 'legacy' else request(identity, second_kind == 'conflict')
        second.stdin.write(f'begin isolation level {isolation}; select count(*) from private.final_result_identities;\n' + second_sql + '\ncommit;\n\\q\n')
        second.stdin.flush()
        wait_for(f"select exists(select 1 from pg_stat_activity b join pg_stat_activity a on a.pid=any(pg_blocking_pids(b.pid)) where a.application_name='{first_name}' and b.application_name='{second_name}');")
        # Only release after proving the second exact backend is blocked by the
        # first. No scheduler-dependent timing can make this a sequential test.
        first.stdin.write('commit;\n\\q\n')
        first.stdin.flush()
        _, first_error = first.communicate(timeout=20)
        second_out, second_error = second.communicate(timeout=20)
        assert first.returncode == 0, first_error
        if isolation == 'read committed' and second_kind == 'same':
            assert second.returncode == 0, second_error
            returned = json.loads(second_out.splitlines()[-1])
            assert returned['data']['result']['uuid'] == identity
        else:
            expected = '40001' if isolation != 'read committed' else ('55000' if first_legacy else '23505')
            assert second.returncode != 0 and f'ERROR:  {expected}:' in second_error, second_error
        expected_kind = 'legacy' if first_legacy else 'registered'
        assert query(f"select registration_kind from private.final_result_identities where result_id='{identity}';") == expected_kind
        assert query(f"select count(*) from private.final_result_identities where result_id='{identity}';") == '1'
        print(f'ok - {isolation}: {expected_kind} first, {second_kind} second', flush=True)
    finally:
        for proc in (first, second):
            if proc.poll() is None:
                proc.kill()
                proc.communicate(timeout=5)


def main():
    metadata = json.loads(subprocess.run(['docker', 'inspect', CONTAINER], capture_output=True, text=True, check=True).stdout)[0]
    assert metadata['Name'] == '/' + CONTAINER
    assert metadata['Config']['Labels'].get('com.supabase.cli.project') == 'hdf5-final-879', 'refusing non-task database'
    assert query("select to_regprocedure('private.final_result_legacy_claim(uuid,text)') is not null;") == 't'
    number = 879100
    for isolation in ('read committed', 'repeatable read', 'serializable'):
        for first_legacy, second_kind in ((False, 'same'), (False, 'conflict'), (False, 'legacy'), (True, 'register')):
            race(number, isolation, first_legacy, second_kind)
            number += 1
    print('12 real two-client races passed; immutable synthetic claims retained for owner reset')


if __name__ == '__main__':
    main()
