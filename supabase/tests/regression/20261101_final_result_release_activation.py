#!/usr/bin/env python3
"""Actual lock arbitration in the task-owned DB; immutable evidence needs owner reset."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('readiness', HERE / '20261101_final_result_release_readiness.py')
fixture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixture)
db = fixture.db
ACTOR = "set role authenticated;select set_config('request.jwt.claim.sub','87930000-0000-4000-8000-000000000001',false);"
RUN = '87930000-0000-4000-8000-000000000010'


def literal(value):
    return "'" + str(value).replace("'", "''") + "'"


def request(sql):
    return json.loads(db.query(ACTOR + sql).splitlines()[-1])


def prepare(number, baseline, expiry_seconds=1800, rollback=None, selected=(10, 12)):
    plan = copy.deepcopy(baseline['plan'])
    plan['releaseRunId'] = run = f'87962000-0000-4000-8000-{number:012d}'
    plan['releaseVersion'] = f'2026.11.{number}'
    plan['expectedCurrentPublicationId'] = db.query("select id from private.lca_release_publications where is_current;") or None
    plan['rollbackOfPublicationId'] = rollback
    plan['selectionCount'] = len(selected)
    block = hashlib.sha256(''.join(f'87920000-0000-4000-8000-{i:012d}@01.00.000\n' for i in sorted(selected)).encode()).hexdigest()
    plan['selectionHash'] = hashlib.sha256(('tiangong.final-result-selection.v1\n' + block + '\n').encode()).hexdigest()
    text = json.dumps(plan, separators=(',', ':'), sort_keys=True)
    digest = hashlib.sha256(text.encode()).hexdigest()
    assert request(f"select api.cmd_final_result_release_prepare_v2({literal(text)},'prepare-{number}');")['ok']
    members = [dict(uuid=f'87920000-0000-4000-8000-{i:012d}', version='01.00.000') for i in selected]
    assert request(f"select api.cmd_final_result_release_members_v2('{run}','{digest}',{fixture.sql(members)});")['ok']
    assert request(f"select api.cmd_final_result_release_seal_v2('{run}','{digest}');")['ok']
    context = request(f"select api.qry_final_result_release_probe_page_v2('{run}','{digest}');")['data']
    header = copy.deepcopy(baseline['header'])
    header.update({key: value for key, value in context.items() if key not in ('artifacts', 'nextArtifactCursor', 'scope', 'publicationAuthorized')})
    header['verificationId'] = verify = f'87963000-0000-4000-8000-{number:012d}'
    proofs = copy.deepcopy(baseline['proofs'])
    wanted = {m['uuid'] for m in members}
    for proof in proofs:
        proof['probes'] = [p for p in proof['probes'] if p['result']['uuid'] in wanted]
        proof['selectedResultCount'] = len(proof['probes'])
    proofs = [p for p in proofs if p['probes']]
    for proof in proofs:
        for probe in proof['probes']:
            result = probe['result']
            new_context = request(f"select api.qry_final_result_release_probe_v2('{run}','{digest}','{header['runtimeRevision']}','{result['uuid']}','{result['version']}');")['data']
            probe.update(new_context)
    begin, stage, seal = fixture.commands(header, proofs)
    db.query('set role service_role;' + begin + stage + seal)
    approval_id = f'87964000-0000-4000-8000-{number:012d}'
    expiry = db.query(f"select clock_timestamp()+interval '{expiry_seconds} seconds';")
    approval_sql = f"select api.cmd_final_result_release_approve_v2('{run}','{digest}','{verify}','{approval_id}',null,{literal(expiry)},'synthetic concurrency');"
    return dict(run=run, digest=digest, verify=verify, approval_id=approval_id, approval_sql=approval_sql, expiry=expiry)


def approve(item):
    data = request(item['approval_sql'])
    assert data['ok'], data
    item['approval_hash'] = data['data']['approvalHash']
    return item


def activation(item):
    return f"select api.cmd_final_result_release_activate_v2('{item['run']}','{item['digest']}','{item['approval_id']}','{item['approval_hash']}','{item['verify']}','activate-{item['run']}',repeat('f',64));"


def race(number, isolation, first_sql, second_sql, expected='retry', wait_sql=None):
    names = f'activation879_a_{number}', f'activation879_b_{number}'
    first, second = db.client(names[0]), db.client(names[1])
    try:
        first.stdin.write('begin;' + ACTOR + first_sql + '\n')
        first.stdin.flush()
        db.wait_for(f"select exists(select 1 from pg_stat_activity where application_name='{names[0]}' and state='idle in transaction');")
        second.stdin.write(f'begin isolation level {isolation};select count(*) from private.lca_release_publications;' + ACTOR + second_sql + '\ncommit;\n\\q\n')
        second.stdin.flush()
        db.wait_for(f"select exists(select 1 from pg_stat_activity b join pg_stat_activity a on a.pid=any(pg_blocking_pids(b.pid)) where a.application_name='{names[0]}' and b.application_name='{names[1]}');")
        if wait_sql:
            db.wait_for(wait_sql)
        first.stdin.write('commit;\n\\q\n')
        first.stdin.flush()
        _, error_a = first.communicate(timeout=20)
        out_b, error_b = second.communicate(timeout=20)
        assert first.returncode == 0, error_a
        if second.returncode:
            codes = ('40001',) if expected == 'retry' else ('40001', '55000')
            assert any(f'ERROR:  {code}:' in error_b for code in codes), error_b
        else:
            result = json.loads(out_b.splitlines()[-1])
            if expected == 'retry':
                assert result['ok'] and result['data']['reused'], result
            else:
                assert result.get('code') == expected, result
        print(f'ok - {isolation}: {expected}; observed real blocking', flush=True)
    finally:
        for process in (first, second):
            if process.poll() is None:
                process.kill()
                process.communicate(timeout=5)


def main():
    metadata = json.loads(subprocess.check_output(['docker', 'inspect', db.CONTAINER]))[0]
    assert metadata['Config']['Labels'].get('com.supabase.cli.project') == 'hdf5-final-879'
    assert db.query('select count(*) from private.final_result_query_runtime_head;') == '0', 'owner reset required'
    source = fixture.expand(HERE.parent / 'fixtures/final-result-readiness-setup.sql')
    out = db.query('begin;' + source + "select jsonb_build_object('plan',pg_temp.final_release_plan()::jsonb,'header',header,'proofs',proofs) from readiness_fixture;commit;")
    baseline = json.loads(out.splitlines()[-1])
    n = 879700
    for isolation in ('read committed', 'repeatable read', 'serializable'):
        item = prepare(n, baseline)
        race(n, isolation, item['approval_sql'], item['approval_sql'])
        approve(item)  # exact readback after a possible serialization failure
        race(n+1, isolation, activation(item), activation(item))
        assert request(activation(item))['data']['reused']
        old = db.query('select id from private.lca_release_publications where is_current;')
        # Two distinct approved runs share the same expected current pointer.
        left, right = approve(prepare(n+2, baseline)), approve(prepare(n+3, baseline))
        race(n+2, isolation, activation(left), activation(right), 'expected_current_conflict')
        assert db.query(f"select status from private.lca_release_publications where id='{old}';") == 'superseded'
        assert db.query(f"select count(*) from private.lca_release_publications where release_run_id='{right['run']}';") == '0'
        assert db.query('select count(*) from private.lca_release_publications where is_current;') == '1'
        n += 10
    # The blocker is a transaction-owned table lock, no DDL or persistent change.
    item = approve(prepare(n, baseline, expiry_seconds=4))
    # Need postgres only for the blocker; ACTOR is reset explicitly before lock.
    race(n, 'read committed', 'reset role;lock table private.lca_release_publications in exclusive mode;', activation(item), 'approval_invalid',
         f"select clock_timestamp()>={literal(item['expiry'])}::timestamptz;")
    assert db.query(f"select count(*) from private.lca_release_publications where release_run_id='{item['run']}';") == '0'
    # Rolling back an earlier exact Candidate/selection creates a fresh record.
    historical = db.query("select id from private.lca_release_publications where status='superseded' order by published_at limit 1;")
    item = approve(prepare(n+1, baseline, rollback=historical))
    new = request(activation(item))
    assert new['ok'] and new['data']['publicationId'] != historical, new
    assert db.query(f"select status from private.lca_release_publications where id='{historical}';") == 'superseded'
    assert db.query(f"select rollback_of_publication_id from private.final_result_publication_bindings where publication_id='{new['data']['publicationId']}';") == historical
    current = new['data']['publicationId']
    changed = approve(prepare(n+2, baseline, rollback=historical, selected=(10,)))
    denied = request(activation(changed))
    assert denied.get('code') == 'rollback_scope_mismatch', denied
    assert db.query('select id from private.lca_release_publications where is_current;') == current
    assert db.query(f"select count(*) from private.lca_release_publications where release_run_id='{changed['run']}';") == '0'
    print('10 actual races plus exact-scope rollback and changed-scope rejection passed; owner reset required')


if __name__ == '__main__':
    main()
