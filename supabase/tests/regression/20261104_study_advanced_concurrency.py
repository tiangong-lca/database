#!/usr/bin/env python3
"""Observe V5 independent-session fences in the exact owned study909 PG17 project.

No reset, clone or cleanup is performed. The owner must preserve this receipt and
reset this synthetic namespace before schema export. No native/bytes/signature proof.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import select
import subprocess
import time

ROOT = Path(__file__).resolve().parents[3]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--workdir', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    assert not args.report.exists()
    ownership = json.loads((args.workdir/'ownership.json').read_text())
    assert ownership['project'] == 'study909' and ownership['dbPort'] == 56822 and ownership['postgresMajor'] == 17
    assert Path(ownership['destination']).resolve() == args.workdir.resolve()
    spec = importlib.util.spec_from_file_location('study_races', Path(__file__).with_name('20261103_study_runtime_concurrency.py'))
    base = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(base)
    base.CONTAINER = 'supabase_db_study909'
    info = json.loads(subprocess.check_output(['docker', 'inspect', base.CONTAINER], text=True))[0]
    assert info['Config']['Labels']['com.supabase.cli.project'] == 'study909'
    assert {x['HostPort'] for x in info['HostConfig']['PortBindings']['5432/tcp']} == {'56822'}
    assert base.sql("select current_setting('server_version_num')::integer/10000;") == '17'
    assert base.sql("select count(*) from auth.users where id::text like '89400000-%';") == '0', 'owner reset required before repeat'
    def expand(path):
        return '\n'.join(expand(path.parent/line[4:].strip()) if line.startswith('\\ir ') else line for line in path.read_text().splitlines())
    seed = expand(ROOT/'supabase/tests/20261104_study_advanced_analysis.sql')
    seed = seed.replace('select * from finish();', '').rsplit('rollback;', 1)[0]
    seed += "select jsonb_build_object('raceSeed',true,'analysisRequest',pg_temp.advanced_request('race-advanced'),'reportRequest',pg_temp.advanced_report_request('race-report'));commit;"
    output = base.sql(seed)
    assert 'not ok' not in output, 'SQL seed assertion failed'
    prepared = next(x for x in base.json_lines(output) if x.get('raceSeed'))
    def invoke(statement, service=False):
        return base.json_lines(base.sql('begin;'+base.claim(service)+statement+'commit;'))[0]
    def actor(req, review=False):
        return 'select api.'+('cmd_study_advanced_review_v1' if review else 'cmd_study_advanced_v1')+'('+base.sql_json(req)+');'
    def req(operation, fields, key):
        return {'schemaVersion':'lca.study-api.v5','requestId':key,'idempotencyKey':key,'operation':operation,**fields}
    def service_race(name, first, second):
        original = base.claim
        base.claim = lambda service=False: original(True)
        try:
            return base.race(name, first, second, True)
        finally:
            base.claim = original
    receipts = []
    ar = prepared['analysisRequest']
    exact = base.race('advanced-admission-exact-key', actor(ar), actor(ar))
    assert exact['first']['ok'] and exact['first'] == exact['second'], exact
    receipts.append(exact)
    changed = json.loads(json.dumps(ar))
    changed['config']['parameters'][0]['low'] = '8'
    changed['configHash'] = hashlib.sha256(b'study.analysis-config.v2\0'+json.dumps(changed['config'],sort_keys=True,separators=(',',':')).encode()).hexdigest()
    changed['requestId'] = changed['idempotencyKey'] = 'race-advanced-conflict'
    original = {**ar,'requestId':'race-advanced-conflict','idempotencyKey':'race-advanced-conflict'}
    conflict = base.race('advanced-admission-changed-key',actor(original),actor(changed))
    assert conflict['first']['ok'] and conflict['second']['code'] == 'IDEMPOTENCY_CONFLICT', conflict
    receipts.append(conflict)
    def claim_analysis(analysis):
        claimed = invoke("select private.worker_claim_jobs('solver','study909-races',100,900);",True)
        assert claimed['ok'], claimed
        aid = analysis['analysisId']
        job = analysis['execution']['jobId']
        token = base.sql('select lease_token from private.worker_jobs where id='+base.quote(job)+';')
        assert token
        return aid,job,token
    def completion(analysis, artifact_id):
        return {'profileId':analysis['profileId'],'configHash':analysis['configHash'],'factsRef':{'type':'analysisFacts','id':artifact_id,'contentHash':'f'*64,'digestScope':'artifact_bytes_sha256','byteSize':2,'mediaType':'application/json','schemaVersion':'lca.study-analysis-facts.v2'},'storageBucket':'study-artifacts','storageObjectPath':f'study/{base.STUDY}/{artifact_id}/facts.json'}
    def callback(binding,payload,key):
        return 'select api.svc_study_analysis_advanced_complete_v1('+','.join([*(base.quote(x) for x in binding),base.sql_json(payload),base.quote(key)])+');'
    analysis = exact['first']['data']['value']
    binding = claim_analysis(analysis)
    payload = completion(analysis,'90900000-0000-4000-8000-000000000201')
    complete = service_race('advanced-completion-exact-retry',callback(binding,payload,'race-complete'),callback(binding,payload,'race-complete'))
    assert complete['first']['ok'] and complete['first'] == complete['second'], complete
    receipts.append(complete)
    def new_analysis(key):
        response = invoke(actor({**ar,'requestId':key,'idempotencyKey':key}))
        assert response['ok'],response
        return response['data']['value']
    def cancel(analysis,key):
        return actor(req('task.cancel',{'studyId':base.STUDY,'resource':{'type':'analysis','id':analysis['analysisId']},'reason':'Owned observed cancellation race'},key))
    completed_first = new_analysis('complete-first')
    completed_binding = claim_analysis(completed_first)
    completed_payload = completion(completed_first,'90900000-0000-4000-8000-000000000202')
    race = base.race('advanced-complete-before-cancel',callback(completed_binding,completed_payload,'complete-first'),cancel(completed_first,'cancel-late'),True)
    assert race['first']['ok'] and race['second']['code'] == 'REVISION_CONFLICT',race
    receipts.append(race)
    cancelled_first = new_analysis('cancel-first')
    cancelled_binding = claim_analysis(cancelled_first)
    cancelled_payload = completion(cancelled_first,'90900000-0000-4000-8000-000000000203')
    race = base.race('advanced-cancel-before-complete',cancel(cancelled_first,'cancel-first'),base.claim(True)+callback(cancelled_binding,cancelled_payload,'complete-late'))
    assert race['first']['ok'] and race['second']['code'] == 'FORBIDDEN',race
    assert base.sql("select count(*) from private.study_artifacts where id='90900000-0000-4000-8000-000000000203';") == '0'
    receipts.append(race)
    report_request = prepared['reportRequest']
    def context(intent):
        result = invoke('select api.svc_study_report_advanced_intent_resolve_v1('+base.quote(intent['data']['intentId'])+');',True)
        assert result['ok'],result
        return result['data']
    def artifact(ctx,digest):
        aid = ctx['contentArtifactId']
        return {'studyId':ctx['studyId'],'artifactRef':{'type':'reportContent','id':aid,'contentHash':digest,'digestScope':'artifact_bytes_sha256','byteSize':2,'mediaType':'application/json','schemaVersion':'lca.study-report-content.v2'},'storageBucket':'study-artifacts','storageObjectPath':f"study/{ctx['studyId']}/{aid}/content.json"}
    def validation(ctx,digest):
        return {'schemaVersion':'lca.study-report-validation.v2','profileId':'lca.study-report-claims.v2','reportRevisionId':ctx['reportRevisionId'],'contentHash':digest,'claimCount':1,'factsBindingHash':ctx['factsBindingHash']}
    def content(ctx,digest):
        return {'kind':'validatedContent','contentArtifact':artifact(ctx,digest),'factsRefs':[x['analysis']['factsRef'] for x in ctx['analyses']],'validation':validation(ctx,digest)}
    def consume(ctx,payload):
        return 'select api.svc_study_report_advanced_intent_consume_v1('+base.quote(ctx['intentId'])+','+base.sql_json(payload)+');'
    report_admit = base.race('advanced-report-admission-exact',actor(report_request),actor(report_request))
    assert report_admit['first']['ok'] and report_admit['first'] == report_admit['second'],report_admit
    receipts.append(report_admit)
    ctx = context(report_admit['first'])
    committed = service_race('advanced-report-consume-exact',consume(ctx,content(ctx,'1'*64)),consume(ctx,content(ctx,'1'*64)))
    assert committed['first']['ok'] and committed['first']==committed['second'],committed
    receipts.append(committed)
    rid = committed['first']['data']['value']['reportRevisionId']
    def save(key,generation,title,report_id=rid):
        return req('report.save',{'target':{'type':'reportRevision','id':report_id,'expectedRevision':generation},'content':{**report_request['content'],'title':title}},key)
    a_ctx = context(invoke(actor(save('advanced-save-a',1,'Writer A'))))
    b_ctx = context(invoke(actor(save('advanced-save-b',1,'Writer B'))))
    saves = service_race('advanced-report-save-save',consume(a_ctx,content(a_ctx,'2'*64)),consume(b_ctx,content(b_ctx,'3'*64)))
    assert saves['first']['ok'] and saves['second']['code']=='REVISION_CONFLICT',saves
    receipts.append(saves)
    freeze_intent = invoke(actor(req('report.freeze',{'target':{'type':'reportRevision','id':rid,'expectedRevision':2},'expectedContentHash':'2'*64},'advanced-race-freeze')))
    freeze_ctx = context(freeze_intent)
    late_ctx = context(invoke(actor(save('advanced-save-late',2,'Late writer'))))
    frozen = service_race('advanced-report-freeze-save',consume(freeze_ctx,{'kind':'validatedFreeze','contentRef':saves['first']['data']['value']['contentRef'],'validation':validation(freeze_ctx,'2'*64)}),consume(late_ctx,content(late_ctx,'4'*64)))
    assert frozen['first']['ok'] and frozen['second']['code']=='REVISION_CONFLICT',frozen
    receipts.append(frozen)
    for operation in ['report.save','report.freeze']:
        key = 'advanced-admission-'+operation.split('.')[1]
        case_create = invoke(actor({**report_request,'requestId':key,'idempotencyKey':key}))
        create_ctx = context(case_create)
        draft = invoke(consume(create_ctx,content(create_ctx,'1'*64)),True)
        case_id = draft['data']['value']['reportRevisionId']
        first_request = save(key+'-first',1,'First save',case_id)
        first_ctx = context(invoke(actor(first_request)))
        fields = {'target':{'type':'reportRevision','id':case_id,'expectedRevision':1}}
        fields.update({'content':report_request['content']} if operation=='report.save' else {'expectedContentHash':'1'*64})
        second_key = key+'-stale'
        overlap = base.race('advanced-consume-versus-'+operation+'-admission',consume(first_ctx,content(first_ctx,'2'*64)),actor(req(operation,fields,second_key)),True)
        assert overlap['first']['ok'] and overlap['second']['code']=='REVISION_CONFLICT',overlap
        assert base.sql("select count(*) from private.study_report_intents where request->>'idempotencyKey'="+base.quote(second_key)+';')=='0'
        assert invoke(actor(first_request)) == overlap['first']
        receipts.append(overlap)
    # Completing a real leased producer retains source locks until its commit.
    source_case = new_analysis('source-fence')
    source_binding = claim_analysis(source_case)
    source_payload = completion(source_case,'90900000-0000-4000-8000-000000000204')
    withdraw = "update public.lifecyclemodels set state_code=20 where id='89400000-0000-4000-8000-000000000101';select jsonb_build_object('withdrawn',true);"
    source_race = base.race('advanced-completion-before-source-withdrawal',callback(source_binding,source_payload,'source-fence'),withdraw,True)
    assert source_race['first']['ok'] and source_race['second']['withdrawn'],source_race
    assert invoke(callback(source_binding,source_payload,'source-fence'),True)['code']=='DISCLOSURE_DENIED'
    assert base.sql("select count(*) from private.study_artifacts where id='90900000-0000-4000-8000-000000000204';")=='1'
    receipts.append(source_race)
    assert base.sql("select count(*) from pg_stat_activity where application_name in ('study894-writer-a','study894-writer-b','study894-barrier');")=='0'
    args.report.write_text(json.dumps({'schemaVersion':'lca.study-advanced-concurrency-receipt.v1','project':'study909','postgresMajor':17,'races':receipts,'ownedSessionsReleased':True,'migrationSha256':hashlib.sha256((ROOT/'supabase/migrations/20261104150000_study_advanced_analysis_v1.sql').read_bytes()).hexdigest(),'classification':'synthetic SQL bindings/signatures; no numerical/Storage/cryptographic qualification','disposition':'owned study909 fixtures retained for transport and explicit owner reset'},indent=2)+'\n')
    print(f'Advanced PG17: {len(receipts)} races passed with observed advisory and actual row waits; fixture retained.')


if __name__=='__main__':
    main()
