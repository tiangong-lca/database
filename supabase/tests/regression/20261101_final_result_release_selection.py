#!/usr/bin/env python3
"""Observed actor prepare/member/seal races on the exact disposable owner DB."""
import copy
import importlib.util
import json
from pathlib import Path
import subprocess

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('candidate_v2', HERE / '20261101_final_result_candidate_v2.py')
candidate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(candidate)
query, db = candidate.query, candidate.identity
ACTOR = '87931000-0000-4000-8000-000000000001'
ACTOR_SQL = f"set local role authenticated; select set_config('request.jwt.claim.sub','{ACTOR}',true);"


def setup(number):
    value = candidate.fixture(number)
    db.query('set role service_role; ' + candidate.register(value))
    result = json.loads(value['catalog'])['datasets'][1]
    row = {key: result[key] for key in ('uuid', 'version')}
    block = query.digest(row['uuid'] + '@' + row['version'] + '\n')
    plan = dict(schemaVersion='tiangong.final-result-publish-plan.v2',
                releaseRunId=f'87932000-0000-4000-8000-{number:012d}',
                releaseVersion=f'2026.11.{number}', candidateSha256=value['receipt']['candidateSha256'],
                targetHash=value['receipt']['targetHash'], selectionCount=1,
                selectionHash=query.digest('tiangong.final-result-selection.v1\n' + block + '\n'),
                expectedCurrentPublicationId=None, rollbackOfPublicationId=None, reason='synthetic concurrency')
    return plan, row


def commands(plan, row, key):
    raw = query.canonical(plan)
    args = query.sql(plan['releaseRunId']) + ',' + query.sql(query.digest(raw))
    return (
        'select api.cmd_final_result_release_prepare_v2(' + query.sql(raw) + ',' + query.sql(key) + ');',
        'select api.cmd_final_result_release_members_v2(' + args + ',' + query.sql([row]) + '::jsonb);',
        'select api.cmd_final_result_release_seal_v2(' + args + ');',
    )


def race(number, isolation, kind):
    plan, row = setup(number)
    prepare, members, seal = commands(plan, row, str(number))
    if kind == 'prepare_conflict':
        other = copy.deepcopy(plan)
        other['releaseRunId'] = f'87933000-0000-4000-8000-{number:012d}'
        other['releaseVersion'] += '1'
        first_sql, second_sql = prepare, commands(other, row, str(number))[0]
    else:
        db.query('begin;' + ACTOR_SQL + prepare + (members if kind == 'seal_retry' else '') + 'commit;')
        first_sql = second_sql = seal if kind == 'seal_retry' else members
    names = f'selection879_a_{number}', f'selection879_b_{number}'
    first, second = db.client(names[0]), db.client(names[1])
    try:
        first.stdin.write('begin;' + ACTOR_SQL + first_sql + '\n')
        first.stdin.flush()
        db.wait_for(f"select exists(select 1 from pg_stat_activity where application_name='{names[0]}' and state='idle in transaction');")
        second.stdin.write(f'begin isolation level {isolation}; select count(*) from private.lca_release_runs;' + ACTOR_SQL + second_sql + '\ncommit;\n\\q\n')
        second.stdin.flush()
        db.wait_for(f"select exists(select 1 from pg_stat_activity b join pg_stat_activity a on a.pid=any(pg_blocking_pids(b.pid)) where a.application_name='{names[0]}' and b.application_name='{names[1]}');")
        first.stdin.write('commit;\n\\q\n')
        first.stdin.flush()
        _, first_error = first.communicate(timeout=20)
        _, second_error = second.communicate(timeout=20)
        assert first.returncode == 0, first_error
        if isolation == 'read committed' and kind != 'prepare_conflict':
            assert second.returncode == 0, second_error
        elif second.returncode:
            assert any(f'ERROR:  {code}:' in second_error for code in ('23505', '40001')), second_error
        else:
            assert kind != 'prepare_conflict', 'conflicting actor idempotency committed'
        # Recover in a fresh snapshot even when the waiting transaction aborted.
        recovered = db.query('begin;' + ACTOR_SQL + prepare + members + seal + 'commit;')
        assert json.loads(recovered.splitlines()[-1])['data']['sealed'] is True
        assert db.query(f"select count(*) from private.lca_release_runs where created_by='{ACTOR}' and idempotency_key='{number}';") == '1'
        assert db.query(f"select count(*) from private.final_result_release_members where release_run_id='{plan['releaseRunId']}';") == '1'
        print(f'ok - {isolation}: {kind}, exact actor retry recovered', flush=True)
    finally:
        for process in (first, second):
            if process.poll() is None:
                process.kill()
                process.communicate(timeout=5)


def main():
    metadata = json.loads(subprocess.run(['docker', 'inspect', db.CONTAINER], capture_output=True, text=True, check=True).stdout)[0]
    assert metadata['Name'] == '/' + db.CONTAINER
    assert metadata['Config']['Labels'].get('com.supabase.cli.project') == 'hdf5-final-879'
    assert db.query(f"select not exists(select 1 from auth.users where id='{ACTOR}');") == 't', 'owner reset required'
    db.query(f"""begin; insert into auth.users(id,aud,role,email,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
      values('{ACTOR}','authenticated','authenticated','selection-race@example.invalid','{{}}','{{}}',now(),now());
      insert into private.users(id,raw_user_meta_data) values('{ACTOR}','{{}}');
      insert into private.teams(id,json,rank,is_public) values('00000000-0000-0000-0000-000000000000','{{}}',0,false) on conflict(id) do nothing;
      insert into private.roles(user_id,team_id,role) values('{ACTOR}','00000000-0000-0000-0000-000000000000','data_product_manager'); commit;""")
    number = 879700
    for isolation in ('read committed', 'repeatable read', 'serializable'):
        for kind in ('prepare_conflict', 'member_retry', 'seal_retry'):
            race(number, isolation, kind)
            number += 1
    assert db.query('select count(*) from private.lca_release_publications;') == '0'
    print('9 real actor races passed; immutable synthetic selections retained for owner reset')


if __name__ == '__main__':
    main()
