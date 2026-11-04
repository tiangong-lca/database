#!/usr/bin/env python3
"""Actual study909 PostgREST/JWT/RLS/manifest proof with signed local fixture claims.

Requires the owned committed concurrency fixture. No GoTrue/OAuth consent, Edge,
native artifact, Storage-byte or cryptographic signature qualification is claimed.
Keys exist only in process memory; logs contain fixed statuses/codes and assertions.
"""
import argparse
import base64
import hashlib
import hmac
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import urllib.error
import urllib.request
sys.path.insert(0,str(Path(__file__).resolve().parents[3]/'scripts'))
from study_advanced_test_support import ROOT, STUDY, claim, json_lines, quote, request, sql, sql_json, verify_owned


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--workdir',type=Path,required=True)
    p.add_argument('--race-receipt',type=Path,required=True)
    p.add_argument('--report',type=Path,required=True)
    args=p.parse_args()
    verify_owned(args.workdir)
    assert not args.report.exists()
    race=json.loads(args.race_receipt.read_text())
    assert race['project']=='study909' and race['ownedSessionsReleased'] is True
    migration=ROOT/'supabase/migrations/20261104150000_study_advanced_analysis_v1.sql'
    assert race['migrationSha256']==hashlib.sha256(migration.read_bytes()).hexdigest()
    # Exact synthetic source row was withdrawn by the race. Restore only that
    # test state for transport; original JSON/owner/version must remain exact.
    origin='89400000-0000-4000-8000-000000000101'
    before=json.loads(sql("select jsonb_build_object('state',state_code,'owner',user_id,'version',version,'sha256',encode(extensions.digest(json_ordered::text,'sha256'),'hex')) from public.lifecyclemodels where id="+quote(origin)+';'))
    assert before['state'] in (0,20) and before['owner']=='89400000-0000-4000-8000-000000000001' and before['version']=='01.00.000'
    sql("begin;select set_config('app.review_controlled_write','on',true);update public.lifecyclemodels set state_code=0 where id="+quote(origin)+';commit;')
    after=json.loads(sql("select jsonb_build_object('state',state_code,'owner',user_id,'version',version,'sha256',encode(extensions.digest(json_ordered::text,'sha256'),'hex')) from public.lifecyclemodels where id="+quote(origin)+';'))
    assert after=={**before,'state':0}
    cli=os.environ['SUPABASE_CLI']
    env=json.loads(subprocess.check_output([cli,'status','--workdir',str(args.workdir),'--output','json'],text=True,stderr=subprocess.DEVNULL))
    assert env['API_URL']=='http://127.0.0.1:56821' and '127.0.0.1:56822/' in env['DB_URL']
    info=json.loads(subprocess.check_output(['docker','inspect','supabase_rest_study909'],text=True))[0]
    assert info['Config']['Labels']['com.supabase.cli.project']=='study909'
    restenv=dict(x.split('=',1) for x in info['Config']['Env'] if '=' in x)
    keys=[k for k in json.loads(restenv['PGRST_JWT_SECRET'])['keys'] if k.get('kty')=='oct']
    assert len(keys)==1
    jwk=keys[0]
    key=base64.urlsafe_b64decode(jwk['k']+'='*(-len(jwk['k'])%4))
    now=int(sql('select extract(epoch from clock_timestamp())::bigint;'))
    assertions=[]
    client='90900000-0000-4000-8000-000000000102'
    readonly='90900000-0000-4000-8000-000000000103'
    sql("insert into private.oauth_client_registry(client_id,client_kind,enabled) values('"+client+"','manual',true),('"+readonly+"','manual',true) on conflict(client_id) do update set enabled=true,disabled_at=null;"
        "insert into private.oauth_client_capability_grants(client_id,capability_id) select '"+client+"',k from(values('STUDY-READ-01'),('STUDY-WRITE-01'),('DB-CORE-READ-01'))v(k) on conflict do nothing;"
        "insert into private.oauth_client_capability_grants(client_id,capability_id) select '"+readonly+"',k from(values('STUDY-READ-01'),('DB-CORE-READ-01'))v(k) on conflict do nothing;")
    def token(actor=1,client=None,role='authenticated'):
        enc=lambda b:base64.urlsafe_b64encode(b).decode().rstrip('=')
        header={'alg':'HS256','typ':'JWT'}
        if jwk.get('kid'):header['kid']=jwk['kid']
        claims={'role':role,'aud':'authenticated','iat':now,'exp':now+600}
        if actor is not None:claims['sub']='89400000-0000-4000-8000-'+str(actor).zfill(12)
        if client:claims['client_id']=client
        h=enc(json.dumps(header,separators=(',',':')).encode());b=enc(json.dumps(claims,separators=(',',':')).encode())
        return h+'.'+b+'.'+enc(hmac.new(key,(h+'.'+b).encode(),hashlib.sha256).digest())
    def http(path,body=None,actor=1,client=None,role='authenticated',profile='api'):
        headers={'apikey':env['ANON_KEY'],'Authorization':'Bearer '+token(actor,client,role),'Content-Type':'application/json','Content-Profile':profile,'Accept-Profile':profile}
        req=urllib.request.Request(env['API_URL']+'/rest/v1/'+path,headers=headers,data=None if body is None else json.dumps(body).encode(),method='GET' if body is None else 'POST')
        try:
            with urllib.request.build_opener(urllib.request.ProxyHandler({}),NoRedirect).open(req,timeout=15) as result:status,raw=result.status,result.read()
        except urllib.error.HTTPError as error:status,raw=error.code,error.read()
        try:return status,json.loads(raw)
        except ValueError:return status,{}
    def rpc(op,fields=None,key='http',write=False,review=False,version=5,**kw):
        req=request(op,fields,key);req['schemaVersion']='lca.study-api.v'+str(version)
        if write:req['idempotencyKey']=key
        facade=('cmd' if write else 'qry')+('_study_advanced_review_v1' if review and version==5 else '_study_review_v1' if review else '_study_advanced_v1' if version==5 else '_study_reporting_v1')
        return http('rpc/'+facade,{'p_request':req},**kw)
    def check(name,response,ok=True,code=None,status=200):
        actual,body=response
        passed=actual==status and(body.get('ok') is True if ok else body.get('code')==code)
        proof={'name':name,'httpStatus':actual,'code':body.get('code'),'passed':passed};assertions.append(proof)
        assert passed,'transport assertion failed: '+json.dumps(proof)
        return body
    cap=check('V5-owner-capability',rpc('capability.read'))['data']
    assert cap['contractVersion']=='5.0.0' and set(cap['analysisProfiles'])=={'lca.study-sensitivity-oat.v1','lca.study-uncertainty-bounded.v1'}
    cap=check('V3-capability-not-redefined',rpc('capability.read',version=3))['data']
    assert cap['contractVersion']=='3.0.0' and cap['analysisProfiles']==['lca.study-analysis-explicit-v1']
    cap=check('V4-capability-not-redefined',rpc('capability.read',review=True,version=4))['data']
    assert cap['contractVersion']=='4.0.0'
    cap=check('V5-review-capability',rpc('capability.read',review=True))['data']
    assert cap['contractVersion']=='5.0.0' and 'member.set' not in cap['operations']
    configuration=json.loads(sql("select config from private.study_advanced_analyses order by id limit 1;"))
    digest=hashlib.sha256(b'study.analysis-config.v2\0'+json.dumps(configuration,sort_keys=True,separators=(',',':')).encode()).hexdigest()
    fields={'studyId':STUDY,'profileId':'lca.study-sensitivity-oat.v1','config':configuration,'configHash':digest}
    check('read-only-client-write-pre-request-denied',rpc('analysis.request',fields,'http-readonly',True,client=readonly),False,'42501',403)
    check('foreign-actor-admission-denied',rpc('analysis.request',fields,'http-foreign',True,actor=3),False,'FORBIDDEN')
    admitted=check('OAuth-advanced-admission',rpc('analysis.request',fields,'http-advanced',True,client=client))['data']['value']
    assert check('same-intent-process-recovery',rpc('analysis.request',fields,'http-advanced',True,client=client))['data']['value']==admitted
    aid=admitted['analysisId'];job=admitted['execution']['jobId']
    check('legacy-direct-advanced-read-denied',rpc('analysis.read',{'analysisId':aid},version=3),False,'FORBIDDEN')
    check('legacy-direct-advanced-task-denied',rpc('task.read',{'studyId':STUDY,'resource':{'type':'analysis','id':aid}},version=3),False,'FORBIDDEN')
    check('V5-core-reviewer-no-raw-analysis',rpc('analysis.read',{'analysisId':aid},actor=2,client=client),False,'FORBIDDEN')
    check('V5-owner-direct-read',rpc('analysis.read',{'analysisId':aid},client=client))
    case=rpc('analysis.read',{'analysisId':aid},actor=None,role='anon');assert case[0] in(401,403,404);assertions.append({'name':'anonymous-advanced-ACL-denied','httpStatus':case[0],'passed':True})
    case=http('study_advanced_analyses?select=id',profile='private');assert case[0]==406;assertions.append({'name':'advanced-private-schema-unexposed','httpStatus':case[0],'passed':True})
    for name,arguments in [
        ('svc_study_analysis_advanced_read_input_v1',{'p_analysis_id':aid,'p_job_id':job,'p_lease_token':aid}),
        ('svc_study_analysis_advanced_complete_v1',{'p_analysis_id':aid,'p_job_id':job,'p_lease_token':aid,'p_completion':{},'p_idempotency_key':'actor-forbidden'}),
        ('svc_study_analysis_parameters_resolve_v1',{'p_intent_id':aid}),
        ('svc_study_review_advanced_intent_resolve_v1',{'p_intent_id':aid}),
    ]:
        case=http('rpc/'+name,arguments);assert case[0] in(401,403,404);assertions.append({'name':name+'-actor-ACL-denied','httpStatus':case[0],'passed':True})
    # A canonical claim is SQL fixture authority; callbacks still cross real HTTP.
    claimed=json_lines(sql('begin;'+claim(service=True)+"select private.worker_claim_jobs('solver','study909-http',100,900);commit;"))[0]
    assert claimed['ok']
    lease=sql('select lease_token from private.worker_jobs where id='+quote(job)+';')
    service={'actor':None,'role':'service_role'}
    params={'p_analysis_id':aid,'p_job_id':job,'p_lease_token':lease}
    context=check('actual-service-input-facade',http('rpc/svc_study_analysis_advanced_read_input_v1',params,**service))['data']
    assert context['schemaVersion']=='lca.study-analysis-input.v2' and context['analysis']['analysisId']==aid and context['baseline']['run']['runId']==configuration['baselineRunId']
    check('old-service-input-family-refused',http('rpc/svc_study_analysis_read_input_v1',params,**service),False,'REFERENCE_MISMATCH')
    check('foreign-lease-no-private-source',http('rpc/svc_study_analysis_advanced_read_input_v1',{**params,'p_lease_token':'90900000-0000-4000-8000-000000000399'},**service),False,'FORBIDDEN')
    catalog=check('parameter-catalog-opaque-intent',rpc('analysis.parameters.read',{'studyId':STUDY,'baselineRunId':configuration['baselineRunId']},client=client))['data']
    resolved=check('parameter-catalog-service-binding',http('rpc/svc_study_analysis_parameters_resolve_v1',{'p_intent_id':catalog['intentId']},**service))['data']
    assert resolved['actorId']=='89400000-0000-4000-8000-000000000001' and resolved['clientId']==client and resolved['baseline']['run']['runId']==configuration['baselineRunId']
    artifact='90900000-0000-4000-8000-000000000301'
    completion={'profileId':'lca.study-sensitivity-oat.v1','configHash':digest,'factsRef':{'type':'analysisFacts','id':artifact,'contentHash':'f'*64,'digestScope':'artifact_bytes_sha256','byteSize':2,'mediaType':'application/json','schemaVersion':'lca.study-analysis-facts.v2'},'storageBucket':'study-artifacts','storageObjectPath':f'study/{STUDY}/{artifact}/facts.json'}
    complete_params={**params,'p_completion':completion,'p_idempotency_key':'http-advanced-complete'}
    completed=check('HTTP-fenced-completion',http('rpc/svc_study_analysis_advanced_complete_v1',complete_params,**service))
    assert check('HTTP-terminal-callback-recovery',http('rpc/svc_study_analysis_advanced_complete_v1',complete_params,**service))==completed
    check('HTTP-task-status-completed',rpc('task.read',{'studyId':STUDY,'resource':{'type':'analysis','id':aid}},client=client))
    artifact_intent=check('HTTP-advanced-facts-intent',rpc('artifact.read',{'studyId':STUDY,'artifactRef':completion['factsRef']},client=client))['data']['intentId']
    check('HTTP-legacy-facts-disclosure-refused',rpc('artifact.read',{'studyId':STUDY,'artifactRef':completion['factsRef']},version=3,client=client),False,'DISCLOSURE_DENIED')
    check('HTTP-current-facts-capability-resolution',http('rpc/svc_study_artifact_read_resolve_v1',{'p_intent_id':artifact_intent},**service))
    page=check('HTTP-V5-family-before-pagination',rpc('study.resources.list',{'studyId':STUDY,'kind':'analysis','limit':1,'cursor':None},client=client))['data']
    assert len(page['items'])==1 and page['nextCursor'] is not None and page['items'][0]['value']['profileId']!='lca.study-analysis-explicit-v1'
    check('HTTP-cursor-family-transplant-refused',rpc('study.resources.list',{'studyId':STUDY,'kind':'analysis','limit':1,'cursor':page['nextCursor']},version=3,client=client),False,'INVALID_REQUEST')
    legacy=check('HTTP-V3-family-before-pagination',rpc('study.resources.list',{'studyId':STUDY,'kind':'analysis','limit':1,'cursor':None},version=3,client=client))['data']
    assert legacy['items'][0]['value']['profileId']=='lca.study-analysis-explicit-v1'
    rid=sql("select id from private.study_report_revisions where template_id='lca.study-report.v2' and status='frozen' and content_hash=repeat('b',64) order by id limit 1;")
    binding={'reportRevisionId':rid,'expectedContentHash':'b'*64}
    check('HTTP-V5-raw-report',rpc('report.read',{'reportRevisionId':rid},client=client))
    check('HTTP-V3-raw-report-refused',rpc('report.read',{'reportRevisionId':rid},version=3,client=client),False,'FORBIDDEN')
    check('HTTP-V4-review-report-refused',rpc('report.current',binding,review=True,version=4,client=client),False,'FORBIDDEN')
    state=check('HTTP-V5-review-state',rpc('report.current',binding,review=True,client=client))['data']['value']
    check('HTTP-V5-reviewer-summary-authority',rpc('report.current',binding,review=True,actor=2,client=client))
    check('HTTP-V5-study-actions-excluded',rpc('resource.actions',{'resource':{'type':'study','id':STUDY}},review=True),False,'INVALID_REQUEST')
    actions=check('HTTP-V5-report-actions',rpc('resource.actions',{'resource':{'type':'reportRevision','id':rid}},review=True))['data']
    assert actions['corePermissions']=={'read':False,'write':False} and 'report.view' in actions['actions']
    export_id=sql('select id from private.study_review_exports where report_id='+quote(rid)+' order by id limit 1;')
    share=check('HTTP-V5-named-share',rpc('share.create',{**binding,'exportId':export_id,'recipientId':'89400000-0000-4000-8000-000000000003','disclosurePolicyId':'lca.study-report-summary-share.v1','expiresAt':json.loads(sql("select to_jsonb(clock_timestamp()+interval '1 hour');"))},'http-share',True,True))['data']['value']
    check('HTTP-V4-share-family-refused',rpc('share.read',{'shareId':share['shareId']},review=True,version=4,actor=3),False,'FORBIDDEN')
    check('HTTP-V5-share-recipient-metadata',rpc('share.read',{'shareId':share['shareId']},review=True,actor=3))
    view_intent=check('HTTP-V5-recipient-view-intent',rpc('share.view',{'shareId':share['shareId']},review=True,actor=3))['data']['intentId']
    view=check('HTTP-V5-narrow-recipient-projection',http('rpc/svc_study_review_advanced_intent_resolve_v1',{'p_intent_id':view_intent},**service))['data']
    assert view['producerContext'] is None and view['artifact']['artifactRef']['type']=='reportProjection'
    check('HTTP-V4-service-intent-family-refused',http('rpc/svc_study_review_intent_resolve_v1',{'p_intent_id':view_intent},**service),False,'CAPABILITY_UNAVAILABLE')
    check('HTTP-V5-nonrecipient-share-denied',rpc('share.read',{'shareId':share['shareId']},review=True,actor=4),False,'FORBIDDEN')
    check('HTTP-V5-owner-share-revoke',rpc('share.revoke',{'shareId':share['shareId'],'reason':'Owned HTTP fixture completed'},'http-share-revoke',True,True))
    check('HTTP-V5-revocation-during-resolution',http('rpc/svc_study_review_advanced_intent_resolve_v1',{'p_intent_id':view_intent},**service),False,'DISCLOSURE_DENIED')
    # Revoking original client after successful completion may deny replay but
    # must never detach its committed facts artifact.
    sql("update private.oauth_client_registry set enabled=false,disabled_at=clock_timestamp() where client_id="+quote(client)+';')
    check('HTTP-original-client-revoked-after-completion',http('rpc/svc_study_analysis_advanced_complete_v1',complete_params,**service),False,'FORBIDDEN')
    check('HTTP-original-client-revoked-before-intent-resolve',http('rpc/svc_study_artifact_read_resolve_v1',{'p_intent_id':artifact_intent},**service),False,'FORBIDDEN')
    assert sql('select count(*) from private.study_artifacts where id='+quote(artifact)+';')=='1'
    check('HTTP-revoked-client-pre-request-denied',rpc('analysis.read',{'analysisId':aid},client=client),False,'42501',403)
    reconcile=check('HTTP-scoped-committed-reconciliation',http('rpc/svc_study_task_reconcile_v1',{'p_resource_type':'analysis','p_resource_id':aid,'p_job_id':job,'p_lease_token':lease,'p_idempotency_key':'http-advanced-complete','p_artifact_id':artifact},**service))
    assert reconcile['data']['state']=='committed'
    sql("update private.oauth_client_registry set enabled=true,disabled_at=null where client_id="+quote(client)+';')
    args.report.write_text(json.dumps({'schemaVersion':'lca.study-advanced-transport-receipt.v1','project':'study909','assertions':assertions,'assertionCount':len(assertions),'sourceFixtureRestoration':{'before':before,'after':after,'bytesOwnerVersionUnchanged':True},'migrationSha256':race['migrationSha256'],'clockSkewSeconds':int(time.time())-now,'classification':'actual PostgREST signed local fixture claims; no GoTrue/consent, Edge, native, Storage-byte or cryptographic signature proof','disposition':'synthetic fixture/client rows retained for exact owned reset'},indent=2)+'\n')
    print(f'Advanced actual PostgREST: {len(assertions)} checks passed; no credentials or raw responses logged.')


if __name__=='__main__':
    main()
