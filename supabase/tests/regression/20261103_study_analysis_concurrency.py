#!/usr/bin/env python3
"""Observed two-session P2 races in a caller-owned cloned study894 database.

Requires an explicit new clone DB name and verifies project/port/PG17. It never
resets, drops or clones a database. Synthetic bindings remain for owner cleanup.
"""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import select
import time

ROOT = Path(__file__).resolve().parents[3]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--database', required=True)
    parser.add_argument('--report', type=Path, required=True)
    parser.add_argument('--owned-ci-project', type=Path)
    args = parser.parse_args()
    if args.database == 'postgres':
        assert os.environ.get('CI') == 'true' and args.owned_ci_project is not None
        ownership = json.loads((args.owned_ci_project/'ownership.json').read_text())
        assert ownership['project'] == 'study894' and ownership['dbPort'] == 56422 and ownership['postgresMajor'] == 17
        assert Path(ownership['destination']).resolve() == args.owned_ci_project.resolve()
    else:
        assert args.database.startswith('study904_') and args.database.replace('_', '').isalnum()
    assert not args.report.exists()
    spec = importlib.util.spec_from_file_location('study_races', Path(__file__).with_name('20261103_study_runtime_concurrency.py'))
    base = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(base)
    original_command = base.command
    def command(application='study894-control'):
        result = original_command(application)
        result[result.index('-d') + 1] = args.database
        return result
    base.command = command
    info = json.loads(subprocess.check_output(['docker', 'inspect', base.CONTAINER], text=True))[0]
    assert info['Config']['Labels']['com.supabase.cli.project'] == 'study894'
    assert {x['HostPort'] for x in info['HostConfig']['PortBindings']['5432/tcp']} == {'56422'}
    assert base.sql("select current_setting('server_version_num')::integer/10000;") == '17'
    assert base.sql("select count(*) from auth.users where id::text like '89400000-%';") == '0'
    fixture = ROOT / 'supabase/tests/fixtures/study904_analysis_fixture.sql'
    def expand(path):
        return '\n'.join(expand(path.parent / line[4:].strip()) if line.startswith('\\ir ') else line for line in path.read_text().splitlines())
    base.sql('begin;' + expand(fixture) + '\nupdate private.study_reporting_config set analysis_enabled=true;commit;')
    config = {'schemaVersion':'lca.study-analysis-config.v1','kind':'comparison','runIds':['90400000-0000-4000-8000-000000000012','90400000-0000-4000-8000-000000000013']}
    import hashlib
    config_hash = hashlib.sha256(b'study.analysis-config.v1\0' + json.dumps(config, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
    def request(key, configuration=None, digest=None):
        return {'schemaVersion':'lca.study-api.v3','requestId':key,'idempotencyKey':key,'operation':'analysis.request','studyId':base.STUDY,'profileId':'lca.study-analysis-explicit-v1','config':configuration or config,'configHash':digest or config_hash}
    def call(req):
        return 'select api.cmd_study_reporting_v1(' + base.sql_json(req) + ');'
    receipts = []
    same = base.race('analysis-exact-key', call(request('analysis-race-exact')), call(request('analysis-race-exact')))
    assert same['first']['ok'] and same['first'] == same['second'], same
    receipts.append(same)
    changed_config = {**config, 'runIds': list(reversed(config['runIds']))}
    changed_hash = hashlib.sha256(b'study.analysis-config.v1\0' + json.dumps(changed_config, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
    conflict = base.race('analysis-changed-key', call(request('analysis-race-changed')), call(request('analysis-race-changed',changed_config,changed_hash)))
    assert conflict['first']['ok'] and conflict['second']['code'] == 'IDEMPOTENCY_CONFLICT', conflict
    receipts.append(conflict)
    assert base.sql("select count(*) from private.study_analyses;") == '2'
    assert base.sql("select count(*) from private.worker_jobs where job_kind='study.analysis';") == '2'
    assert base.sql("select count(*) from private.study_analysis_runs;") == '4'
    origin = '89400000-0000-4000-8000-000000000101'
    withdraw_sql = "update public.lifecyclemodels set state_code=20 where id="+base.quote(origin)+";select jsonb_build_object('withdrawn',true);"
    protected = base.race('analysis-admission-before-withdrawal',call(request('analysis-race-withdraw')),withdraw_sql)
    assert protected['first']['ok'] and protected['second']['withdrawn'],protected
    receipts.append(protected)
    admitted = protected['first']['data']['value']
    job = admitted['execution']['jobId']
    claimed = base.json_lines(base.sql('begin;'+base.claim(True)+"select private.worker_claim_jobs('solver','study904-source-fence',10,900);commit;"))[0]
    assert claimed['ok'],claimed
    token = base.sql('select lease_token from private.worker_jobs where id='+base.quote(job)+';')
    callback = {'profileId':'lca.study-analysis-explicit-v1','configHash':config_hash,'comparability':{'status':'not_assessed','reasonCodes':[]},'factsRef':{'type':'analysisFacts','id':'90400000-0000-4000-8000-000000000060','contentHash':'f'*64,'digestScope':'artifact_bytes_sha256','byteSize':2,'mediaType':'application/json','schemaVersion':'lca.study-analysis-facts.v1'},'storageBucket':'study-artifacts','storageObjectPath':'study/'+base.STUDY+'/90400000-0000-4000-8000-000000000060/facts.json'}
    callback_sql = 'select api.svc_study_analysis_complete_v1('+','.join([base.quote(admitted['analysisId']),base.quote(job),base.quote(token),base.sql_json(callback),base.quote('withdrawn-complete')])+');'
    denied = base.json_lines(base.sql('begin;'+base.claim(True)+callback_sql+'commit;'))[0]
    assert denied['code']=='DISCLOSURE_DENIED',denied
    assert base.sql("select count(*) from private.study_artifacts where id='90400000-0000-4000-8000-000000000060';")=='0'
    # A writer that holds the source first causes immediate P2 NOWAIT refusal.
    base.sql("begin;select set_config('app.review_controlled_write','on',true);update public.lifecyclemodels set state_code=0 where id="+base.quote(origin)+';commit;')
    held = subprocess.Popen(command('study904-source-writer'),stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
    try:
        held.stdin.write('begin;'+withdraw_sql+"select pg_advisory_xact_lock(9042158);\n")
        held.stdin.flush()
        # The root source row is held once the writer has returned its fixed JSON.
        deadline=time.monotonic()+10
        observed=False
        while time.monotonic()<deadline:
            if select.select([held.stdout],[],[],0.1)[0]:
                line=held.stdout.readline().strip()
                if line.startswith('{'):
                    observed=True;break
        assert observed,'source writer did not acquire exact row'
        begun=time.monotonic()
        collision=base.json_lines(base.sql('begin;'+base.claim()+call(request('analysis-nowait-collision'))+'commit;'))[0]
        elapsed=time.monotonic()-begun
        assert collision['code']=='CAPABILITY_UNAVAILABLE' and elapsed<5, (collision,elapsed)
        assert base.sql("select count(*) from private.study_command_receipts where idempotency_key='analysis-nowait-collision';")=='0'
        held.stdin.write('commit;\n\\q\n');held.stdin.flush()
        held.communicate(timeout=10)
        assert held.returncode==0
    finally:
        if held.poll() is None:
            held.kill();held.communicate(timeout=5)
    after=base.json_lines(base.sql('begin;'+base.claim()+call(request('analysis-nowait-collision'))+'commit;'))[0]
    assert after['code']=='DISCLOSURE_DENIED',after
    assert base.sql("select count(*) from private.study_analyses;")=='3'
    assert base.sql("select count(*) from pg_stat_activity where application_name in ('study894-writer-a','study894-writer-b','study894-barrier','study904-source-writer');") == '0'
    source_fence={'producerBeforeWithdrawal':protected,'lateCallbackDenied':denied,'writerFirstNowaitDenied':collision,'writerFirstElapsedSeconds':elapsed,'postWithdrawalRetryDenied':after,'noFactsRegistered':True}
    args.report.write_text(json.dumps({'schemaVersion':'lca.study-analysis-concurrency-receipt.v1','project':'study894','database':args.database,'postgresMajor':17,'races':receipts,'storedAnalyses':3,'storedJobs':3,'storedOrderedInputs':6,'sourceWithdrawalFence':source_fence,'ownedSessionsReleased':True,'classification':'synthetic SQL binding proof; no numerical/runtime qualification','disposition':'owned cloned database retained for explicit cleanup'},indent=2)+'\n')
    print('P2 analysis: receipt races and both source-withdrawal orders passed; producer locks observed and late callback denied.')

if __name__ == '__main__':
    main()
