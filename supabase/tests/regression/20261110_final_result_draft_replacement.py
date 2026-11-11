#!/usr/bin/env python3
"""Observed races on an explicitly owned local synthetic database, never hosted."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time

ACTOR = '87930000-0000-4000-8000-000000000001'
ACTOR_SQL = f"set local role authenticated; select set_config('request.jwt.claim.sub','{ACTOR}',true);"
BASE = []


def query(sql):
    r = subprocess.run(BASE, input=sql, text=True, capture_output=True, timeout=25)
    assert r.returncode == 0, r.stderr
    return r.stdout.strip()


def sql(v):
    return "'" + str(v).replace("'", "''") + "'"


def raw(plan):
    return json.dumps(plan, sort_keys=True, separators=(',', ':'))


def digest(plan):
    return hashlib.sha256(raw(plan).encode()).hexdigest()


def request(plan, predecessor=None):
    args = sql(raw(plan)) + ',' + sql('draft961:' + plan['releaseRunId'])
    if predecessor:
        args += ',' + sql(predecessor['releaseRunId']) + ',' + sql(digest(predecessor))
    return 'select api.cmd_final_result_release_' + ('replace' if predecessor else 'prepare') + '_v2(' + args + ');'


def call(command):
    out = query('begin;' + ACTOR_SQL + command + 'commit;')
    return json.loads(next(line for line in reversed(out.splitlines()) if line.startswith('{')))


def client(name):
    p = subprocess.Popen(BASE, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    p.stdin.write(f"set application_name='{name}'; set statement_timeout='20s'; set lock_timeout='15s';\n")
    p.stdin.flush()
    return p


def wait(sql_query):
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        if query(sql_query) == 't':
            return
        time.sleep(0.03)
    raise AssertionError('exact backend barrier was not observed')


def expand(p):
    return re.sub(r'^\\ir\s+(.+)$', lambda m: expand(p.parent / m.group(1)), p.read_text(), flags=re.M)


def race(number, isolation, kind, candidate_hash):
    def plan(which):
        return dict(schemaVersion='tiangong.final-result-publish-plan.v2',
                    releaseRunId=f'96100000-0000-4000-8000-{number * 10 + which:012d}',
                    releaseVersion=f'2099.11.{number}', candidateSha256=candidate_hash, targetHash='d' * 64,
                    selectionCount=2, selectionHash='cada21d09411290414089d96661ee0bfd20a8909a930e21bb85a305d545259bc',
                    expectedCurrentPublicationId=None, rollbackOfPublicationId=None, reason='synthetic draft race')
    old, a, b = plan(0), plan(1), plan(2)
    if kind != 'prepare':
        assert call(request(old))['ok']
    first_sql = request(a, old if kind != 'prepare' else None)
    second_sql = request(b, old if kind in ('replace', 'rollback', 'approved_state', 'role_revoked') else None)
    if kind == 'approved_state':
        # Pre-existing approved-state fixture, not an approval RPC or user release.
        first_sql = f"update private.lca_release_runs set status='ready_for_approval' where id='{old['releaseRunId']}'; update private.lca_release_runs set status='approved' where id='{old['releaseRunId']}';"
    if kind == 'role_revoked':
        first_sql = f"delete from private.roles where user_id='{ACTOR}' and team_id='00000000-0000-0000-0000-000000000000' and role='data_product_manager';"
    names = f'draft961_a_{number}', f'draft961_b_{number}'
    first, second = client(names[0]), client(names[1])
    try:
        first.stdin.write('begin;' + ('' if kind in ('approved_state', 'role_revoked') else ACTOR_SQL) + first_sql + '\n')
        first.stdin.flush()
        wait(f"select exists(select 1 from pg_stat_activity where application_name='{names[0]}' and state='idle in transaction');")
        second.stdin.write(f'begin isolation level {isolation}; select count(*) from private.lca_release_runs;' + ACTOR_SQL + second_sql + '\ncommit;\n\\q\n')
        second.stdin.flush()
        wait(f"select exists(select 1 from pg_stat_activity b join pg_stat_activity a on a.pid=any(pg_blocking_pids(b.pid)) where a.application_name='{names[0]}' and b.application_name='{names[1]}');")
        first.stdin.write(('rollback;' if kind == 'rollback' else 'commit;') + '\n\\q\n')
        first.stdin.flush()
        _, err_a = first.communicate(timeout=25)
        out_b, err_b = second.communicate(timeout=25)
        assert first.returncode == 0, err_a
        recovered = False
        if second.returncode:
            assert isolation != 'read committed' and '40001' in err_b, err_b
            result = call(second_sql)
            recovered = True
        else:
            result = json.loads(next(line for line in reversed(out_b.splitlines()) if line.startswith('{')))
        expected = {'prepare': 'final_result_release_version_conflict', 'ordinary_vs_replace': 'final_result_release_version_conflict', 'replace': 'final_result_draft_replacement_conflict', 'approved_state': 'final_result_draft_not_replaceable', 'role_revoked': 'not_data_product_manager'}
        if kind == 'rollback':
            assert result['ok'], result
        else:
            assert result['code'] == expected[kind], result
        state = json.loads(query("select jsonb_build_object('active',count(*) filter(where replaced_by_run_id is null),'total',count(*),'oldTarget',max(replaced_by_run_id::text) filter(where id=" + sql(old['releaseRunId']) + "),'oldStatus',max(status) filter(where id=" + sql(old['releaseRunId']) + ")) from private.lca_release_runs where release_version=" + sql(old['releaseVersion']) + ';'))
        assert state['active'] == 1, state
        if kind == 'prepare':
            assert state['total'] == 1
        elif kind == 'approved_state':
            assert state['total'] == 1 and state['oldStatus'] == 'approved' and state['oldTarget'] is None
        elif kind == 'role_revoked':
            assert state['total'] == 1 and state['oldStatus'] == 'prepared' and state['oldTarget'] is None
            query(f"insert into private.roles(user_id,team_id,role) values('{ACTOR}','00000000-0000-0000-0000-000000000000','data_product_manager');")
        else:
            winner = b if kind == 'rollback' else a
            assert state['total'] == 2 and state['oldStatus'] == 'abandoned' and state['oldTarget'] == winner['releaseRunId'], state
            assert call(request(winner, old))['ok'], 'exact lost-ACK replay must recover original winner'
        print(f'ok - {isolation}: {kind}; observed blocking and independent stored-state proof', flush=True)
        return dict(isolation=isolation, kind=kind, observedBlocking=True, snapshotRecovery=recovered, activeRunCount=state['active'], totalRunCount=state['total'])
    finally:
        for p in (first, second):
            if p.poll() is None:
                p.kill()
                p.communicate(timeout=5)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--container', required=True)
    parser.add_argument('--project', required=True)
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    assert not args.report.exists(), 'never overwrite a qualification receipt'
    allowed = args.project == 'draft961' or (os.environ.get('GITHUB_ACTIONS') == 'true' and args.project == 'database-engine')
    assert allowed, 'only owned draft961 or this workflow disposable CI database is allowed'
    meta = json.loads(subprocess.check_output(['docker', 'inspect', args.container], text=True))[0]
    assert meta['Config']['Labels'].get('com.supabase.cli.project') == args.project and meta['Name'] == '/' + args.container
    global BASE
    BASE = ['docker', 'exec', '-i', args.container, 'psql', '-X', '-qAt', '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=verbose']
    assert query(f"select not exists(select 1 from auth.users where id='{ACTOR}');") == 't', 'owner reset required'
    fixture = Path(__file__).resolve().parents[1] / 'fixtures/final-result-release-setup.sql'
    setup = query('begin;' + expand(fixture) + "select a#>>'{receipt,candidateSha256}' from original_args;commit;")
    candidate_hash = setup.splitlines()[-1]
    assert re.fullmatch('[0-9a-f]{64}', candidate_hash)
    rows = []
    number = 961100
    for isolation in ('read committed', 'repeatable read', 'serializable'):
        for kind in ('prepare', 'replace', 'ordinary_vs_replace', 'rollback', 'approved_state', 'role_revoked'):
            rows.append(race(number, isolation, kind, candidate_hash))
            number += 1
    assert query('select count(*) from private.lca_release_publications;') == '0'
    assert query("select count(*) from pg_stat_activity where application_name like 'draft961_%';") == '0'
    receipt = dict(kind='final-result-draft-replacement-concurrency.v1', project=args.project, containerId=meta['Id'], races=rows, publicationCount=0, disposition='committed synthetic fixtures retained only for exact owner reset; client sessions released')
    with args.report.open('x') as f:
        os.chmod(args.report, 0o600)
        json.dump(receipt, f, indent=2)
    print('18 observed local races passed; no publication created')


if __name__ == '__main__':
    main()
