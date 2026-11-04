#!/usr/bin/env python3
"""Observed method-family PG17 races on the exact owned study912 project.

Commits only the explicit synthetic namespace. Never resets or creates resources.
SQL producers/signatures are fixtures, not native or Storage-byte qualification.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[3]/'scripts'))
from study_method_test_support import ROOT, STUDY, claim, expand, quote, sql, sql_json, verify_owned

MIGRATION='20261104191012_study_method_assessment_v1.sql'


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--workdir',type=Path,required=True)
    parser.add_argument('--report',type=Path,required=True)
    parser.add_argument('--vectors-report',type=Path)
    args=parser.parse_args()
    verify_owned(args.workdir)
    assert not args.report.exists()
    assert args.vectors_report is None or not args.vectors_report.exists()
    assert sql("select count(*)from auth.users where id::text like '89400000-%';")=='0','owned synthetic namespace must be explicitly reset before repeating'
    spec=importlib.util.spec_from_file_location('method_race_engine',Path(__file__).with_name('20261103_study_runtime_concurrency.py'))
    base=importlib.util.module_from_spec(spec);spec.loader.exec_module(base);base.CONTAINER='supabase_db_study912'
    source=expand(ROOT/'supabase/tests/20261104_study_method_assessment.sql')
    source=source.replace('select * from finish();','').rsplit('rollback;',1)[0]
    source+="select jsonb_build_object('methodRaceSeed',true,'request',pg_temp.method_request('race-method'),'reportRequest',pg_temp.method_report_request('race-method-report'),'serviceDtos',jsonb_build_object('assessment',pg_temp.val('method-completed')->'data'->'value','inputContext',pg_temp.val('method-input')->'data','completion',pg_temp.method_completion(pg_temp.val('method')->'data'->'value'->>'configHash'),'evidenceBody',pg_temp.evidence_body(),'evidenceRecord',pg_temp.val('evidence')->'data'->'value'),'evidenceRequest',pg_temp.v6('method.evidence.create',jsonb_build_object('idempotencyKey','race-evidence','studyId','"+STUDY+"','content',pg_temp.evidence_body()),'race-evidence'));commit;"
    output=sql(source);assert 'not ok' not in output
    prepared=next(x for x in base.json_lines(output)if x.get('methodRaceSeed'))
    if args.vectors_report:
        args.vectors_report.write_text(json.dumps({'classification':'actualSQLSyntheticMetadataOnly','project':'study912','migrationSha256':hashlib.sha256((ROOT/'supabase/migrations'/MIGRATION).read_bytes()).hexdigest(),'serviceDtos':prepared['serviceDtos']},indent=2)+'\n')
    def invoke(statement,service=False):return base.json_lines(sql('begin;'+claim(service=service)+statement+'commit;'))[0]
    def actor(req):return 'select api.cmd_study_method_v1('+sql_json(req)+');'
    def request(key):return {**prepared['request'],'requestId':key,'idempotencyKey':key}
    def req(operation,fields,key):return {'schemaVersion':'lca.study-api.v6','requestId':key,'idempotencyKey':key,'operation':operation,**fields}
    def service_race(name,first,second):return base.race(name,claim(service=True)+first,claim(service=True)+second)
    def new_assessment(key,client=None):
        prefix='' if client is None else claim(client=client)
        result=invoke(prefix+actor(request(key)));assert result['ok'],result;return result['data']['value']
    def leased(record):
        result=invoke("select private.worker_claim_jobs('solver','study912-races',100,900);",True);assert result['ok']
        token=sql('select lease_token from private.worker_jobs where id='+quote(record['execution']['jobId'])+';');assert token
        return record['assessmentId'],record['execution']['jobId'],token
    def completion(record,aid):return {'profileId':record['profileId'],'configHash':record['configHash'],'selectedFactorRecordCount':2,'factsRef':{'type':'methodAssessmentFacts','id':aid,'contentHash':'f'*64,'digestScope':'artifact_bytes_sha256','byteSize':2,'mediaType':'application/json','schemaVersion':'lca.study-method-assessment-facts.v1'},'storageBucket':'study-artifacts','storageObjectPath':f'study/{STUDY}/{aid}/method-facts.json'}
    def callback(binding,value,key):return 'select api.svc_study_method_assessment_complete_v1('+','.join([*(quote(x)for x in binding),sql_json(value),quote(key)])+');'
    def cancel(record,key):return actor({'schemaVersion':'lca.study-api.v6','requestId':key,'idempotencyKey':key,'operation':'task.cancel','studyId':STUDY,'resource':{'type':'methodAssessment','id':record['assessmentId']},'reason':'Owned observed cancellation race'})
    receipts=[]
    first=request('race-exact');r=base.race('method-admission-exact',actor(first),actor(first));assert r['first']['ok'] and r['first']==r['second'];receipts.append(r)
    changed=json.loads(json.dumps(request('race-conflict')));changed['config']['declarations']['studyPhase']='screening';changed['configHash']=hashlib.sha256(b'study.method-assessment-config.v1\0'+json.dumps(changed['config'],sort_keys=True,separators=(',',':'),ensure_ascii=False).encode()).hexdigest()
    r=base.race('method-admission-changed-key-content',actor(request('race-conflict')),actor(changed));assert r['first']['ok']and r['second']['code']=='IDEMPOTENCY_CONFLICT';receipts.append(r)
    record=receipts[0]['first']['data']['value'];binding=leased(record);payload=completion(record,'91200000-0000-4000-8000-000000000201')
    r=service_race('method-completion-exact-retry',callback(binding,payload,'race-complete'),callback(binding,payload,'race-complete'));assert r['first']['ok']and r['first']==r['second'];receipts.append(r)
    record=new_assessment('complete-first');binding=leased(record);payload=completion(record,'91200000-0000-4000-8000-000000000202')
    r=base.race('method-complete-before-cancel',callback(binding,payload,'complete-first'),cancel(record,'cancel-late'),True);assert r['first']['ok']and r['second']['code']=='REVISION_CONFLICT';receipts.append(r)
    record=new_assessment('cancel-first');binding=leased(record);payload=completion(record,'91200000-0000-4000-8000-000000000203')
    r=base.race('method-cancel-before-complete',cancel(record,'cancel-first'),claim(service=True)+callback(binding,payload,'complete-late'));assert r['first']['ok']and r['second']['code']=='FORBIDDEN';assert sql("select count(*)from private.study_artifacts where id='91200000-0000-4000-8000-000000000203';")=='0';receipts.append(r)
    # The service commits a registered declaration before a concurrent admission shutdown.
    evidence=prepared['evidenceRequest'];intent=invoke(actor(evidence));assert intent['ok'];iid=intent['data']['intentId'];ctx=invoke('select api.svc_study_method_evidence_intent_resolve_v1('+quote(iid)+');',True)['data']
    ref={'type':'methodEvidence','id':ctx['artifactId'],'contentHash':ctx['contentHash'],'digestScope':'artifact_bytes_sha256','byteSize':ctx['byteSize'],'mediaType':'application/json','schemaVersion':'lca.study-method-evidence.v1'}
    evidence_payload={'artifact':{'artifactRef':ref,'storageBucket':'study-artifacts','storageObjectPath':f"study/{STUDY}/{ctx['artifactId']}/evidence.json"}}
    consume='select api.svc_study_method_evidence_intent_consume_v1('+quote(iid)+','+sql_json(evidence_payload)+');'
    revision=int(sql('select revision from private.study_method_config;'));off={'executionEnabled':False,'reportEnabled':False,'maxEvidenceRefs':128,'maxSelectedFactorRecords':8192,'qualificationEvidenceRef':'owned.sql.race-only'}
    configure='select api.svc_study_method_configure_v1('+str(revision)+','+sql_json(off)+');'
    r=service_race('method-evidence-consume-before-config-disable',consume,configure);assert r['first']['ok']and r['second']['ok'];assert invoke(consume,True)==r['first'];receipts.append(r)
    on={**off,'executionEnabled':True,'reportEnabled':True};assert invoke('select api.svc_study_method_configure_v1('+str(revision+1)+','+sql_json(on)+');',True)['ok']
    # Original OAuth authority is rechecked on completion retry, while historical reconcile proves attachment.
    client='91200000-0000-4000-8000-000000000102'
    sql("insert into private.oauth_client_registry(client_id,client_kind,enabled)values("+quote(client)+",'manual',true);insert into private.oauth_client_capability_grants(client_id,capability_id)select "+quote(client)+",v from(values('STUDY-READ-01'),('STUDY-WRITE-01'),('DB-CORE-READ-01'))t(v);")
    record=new_assessment('client-fence',client);binding=leased(record);payload=completion(record,'91200000-0000-4000-8000-000000000204')
    disable="update private.oauth_client_registry set enabled=false,disabled_at=clock_timestamp()where client_id="+quote(client)+";select jsonb_build_object('disabled',true);"
    r=base.race('method-completion-before-client-revoke',callback(binding,payload,'client-fence'),disable,True);assert r['first']['ok']and r['second']['disabled'];assert invoke(callback(binding,payload,'client-fence'),True)['code']=='FORBIDDEN'
    reconciled=invoke('select api.svc_study_method_assessment_reconcile_v1('+','.join([quote('methodAssessment'),*(quote(x)for x in binding),quote('client-fence'),quote(payload['factsRef']['id'])])+');',True)
    assert reconciled['ok']and reconciled['data']['state']=='committed'and reconciled['data']['resource']==r['first']['data'];assert sql('select count(*)from private.study_artifacts where id='+quote(payload['factsRef']['id'])+';')=='1';receipts.append(r)
    report_request = prepared['reportRequest']
    def context(intent):
        result = invoke('select api.svc_study_report_method_intent_resolve_v1('+base.quote(intent['data']['intentId'])+');',True)
        assert result['ok'],result
        return result['data']
    def artifact(ctx,digest):
        aid = ctx['contentArtifactId']
        return {'studyId':ctx['studyId'],'artifactRef':{'type':'reportContent','id':aid,'contentHash':digest,'digestScope':'artifact_bytes_sha256','byteSize':2,'mediaType':'application/json','schemaVersion':'lca.study-method-report-content.v1'},'storageBucket':'study-artifacts','storageObjectPath':f"study/{ctx['studyId']}/{aid}/content.json"}
    def validation(ctx,digest):
        return {'schemaVersion':'lca.study-method-report-validation.v1','profileId':'lca.study-method-report-claims.v1','reportRevisionId':ctx['reportRevisionId'],'contentHash':digest,'claimCount':1,'factsBindingHash':ctx['factsBindingHash'],'methodAssessmentId':ctx['methodAssessments'][0]['assessment']['assessmentId'],'configHash':ctx['methodAssessments'][0]['assessment']['configHash'],'requirementCount':20,'categoryCount':25,'factCount':58}
    def content(ctx,digest):
        return {'kind':'validatedContent','contentArtifact':artifact(ctx,digest),'factsRefs':[x['assessment']['factsRef'] for x in ctx['methodAssessments']],'validation':validation(ctx,digest)}
    def consume(ctx,payload):
        return 'select api.svc_study_report_method_intent_consume_v1('+base.quote(ctx['intentId'])+','+base.sql_json(payload)+');'
    report_admit = base.race('method-report-admission-exact',actor(report_request),actor(report_request))
    assert report_admit['first']['ok'] and report_admit['first'] == report_admit['second'],report_admit
    receipts.append(report_admit)
    ctx = context(report_admit['first'])
    committed = service_race('method-report-consume-exact',consume(ctx,content(ctx,'1'*64)),consume(ctx,content(ctx,'1'*64)))
    assert committed['first']['ok'] and committed['first']==committed['second'],committed
    receipts.append(committed)
    rid = committed['first']['data']['value']['reportRevisionId']
    def save(key,generation,title,report_id=rid):
        return req('report.save',{'target':{'type':'reportRevision','id':report_id,'expectedRevision':generation},'content':{**report_request['content'],'title':title}},key)
    a_ctx = context(invoke(actor(save('method-save-a',1,'Writer A'))))
    b_ctx = context(invoke(actor(save('method-save-b',1,'Writer B'))))
    saves = service_race('method-report-save-save',consume(a_ctx,content(a_ctx,'2'*64)),consume(b_ctx,content(b_ctx,'3'*64)))
    assert saves['first']['ok'] and saves['second']['code']=='REVISION_CONFLICT',saves
    receipts.append(saves)
    freeze_intent = invoke(actor(req('report.freeze',{'target':{'type':'reportRevision','id':rid,'expectedRevision':2},'expectedContentHash':'2'*64},'method-race-freeze')))
    freeze_ctx = context(freeze_intent)
    late_ctx = context(invoke(actor(save('method-save-late',2,'Late writer'))))
    frozen = service_race('method-report-freeze-save',consume(freeze_ctx,{'kind':'validatedFreeze','contentRef':saves['first']['data']['value']['contentRef'],'validation':validation(freeze_ctx,'2'*64)}),consume(late_ctx,content(late_ctx,'4'*64)))
    assert frozen['first']['ok'] and frozen['second']['code']=='REVISION_CONFLICT',frozen
    receipts.append(frozen)
    for operation in ['report.save','report.freeze']:
        key = 'method-admission-'+operation.split('.')[1]
        case_create = invoke(actor({**report_request,'requestId':key,'idempotencyKey':key}))
        create_ctx = context(case_create)
        draft = invoke(consume(create_ctx,content(create_ctx,'1'*64)),True)
        case_id = draft['data']['value']['reportRevisionId']
        first_request = save(key+'-first',1,'First save',case_id)
        first_ctx = context(invoke(actor(first_request)))
        fields = {'target':{'type':'reportRevision','id':case_id,'expectedRevision':1}}
        fields.update({'content':report_request['content']} if operation=='report.save' else {'expectedContentHash':'1'*64})
        second_key = key+'-stale'
        overlap = base.race('method-consume-versus-'+operation+'-admission',consume(first_ctx,content(first_ctx,'2'*64)),actor(req(operation,fields,second_key)),True)
        assert overlap['first']['ok'] and overlap['second']['code']=='REVISION_CONFLICT',overlap
        assert base.sql("select count(*) from private.study_report_intents where request->>'idempotencyKey'="+base.quote(second_key)+';')=='0'
        assert invoke(actor(first_request)) == overlap['first']
        receipts.append(overlap)
    # Exact source row locks retain authority until the successful terminal commit.
    record=new_assessment('source-fence');binding=leased(record);payload=completion(record,'91200000-0000-4000-8000-000000000205')
    withdraw="update public.lifecyclemodels set state_code=20 where id='89400000-0000-4000-8000-000000000101';select jsonb_build_object('withdrawn',true);"
    r=base.race('method-completion-before-source-withdrawal',callback(binding,payload,'source-fence'),withdraw,True);assert r['first']['ok']and r['second']['withdrawn'];assert invoke(callback(binding,payload,'source-fence'),True)['code']=='DISCLOSURE_DENIED';receipts.append(r)
    assert sql("select count(*)from pg_stat_activity where application_name in('study894-writer-a','study894-writer-b','study894-barrier');")=='0'
    args.report.write_text(json.dumps({'schemaVersion':'lca.study-method-concurrency-receipt.v1','project':'study912','postgresMajor':17,'races':receipts,'ownedSessionsReleased':True,'migrationSha256':hashlib.sha256((ROOT/'supabase/migrations'/MIGRATION).read_bytes()).hexdigest(),'classification':'syntheticSQLfencing_noNativeStorageByteOrScientificQualification','disposition':'ownedstudy912syntheticnamespace retained forHTTPandexplicitownedreset'},indent=2)+'\n')
    print(json.dumps({'passed':True,'observedRaces':len(receipts),'ownedSessionsReleased':True}))


if __name__=='__main__':main()
