#!/usr/bin/env python3
"""Actual owned-study906 PostgREST/JWT/RLS/pre-request proof.

Uses signed local fixture claims, not GoTrue/OAuth-consent or Edge byte proof.
Never logs credentials, payloads or raw errors. Requires committed race fixture.
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
from study_review_test_support import REPORT,STUDY,request,sql,verify_owned


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self,req,fp,code,msg,headers,newurl):return None


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--workdir',type=Path,required=True)
    p.add_argument('--race-receipt',type=Path,required=True)
    p.add_argument('--report',type=Path,required=True)
    args=p.parse_args()
    verify_owned(args.workdir);assert not args.report.exists()
    race=json.loads(args.race_receipt.read_text());assert race['project']=='study906'
    share=race['retainedHttpShareId']
    cli=os.environ['SUPABASE_CLI']
    env=json.loads(subprocess.check_output([cli,'status','--workdir',str(args.workdir),'--output','json'],text=True,stderr=subprocess.DEVNULL))
    assert env['API_URL']=='http://127.0.0.1:56621' and '127.0.0.1:56622/' in env['DB_URL']
    info=json.loads(subprocess.check_output(['docker','inspect','supabase_rest_study906'],text=True))[0]
    assert info['Config']['Labels']['com.supabase.cli.project']=='study906'
    restenv=dict(x.split('=',1) for x in info['Config']['Env'] if '=' in x)
    keys=[k for k in json.loads(restenv['PGRST_JWT_SECRET'])['keys'] if k.get('kty')=='oct'];assert len(keys)==1
    jwk=keys[0];key=base64.urlsafe_b64decode(jwk['k']+'='*(-len(jwk['k'])%4))
    now=int(sql('select extract(epoch from clock_timestamp())::bigint;'));assertions=[]
    client='90600000-0000-4000-8000-000000000101';other='90600000-0000-4000-8000-000000000102'
    def token(actor=1,client=None,role='authenticated'):
        enc=lambda b:base64.urlsafe_b64encode(b).decode().rstrip('=')
        h={'alg':'HS256','typ':'JWT'}
        if jwk.get('kid'):h['kid']=jwk['kid']
        c={'role':role,'aud':'authenticated','iat':now,'exp':now+600}
        if actor is not None:c['sub']='89400000-0000-4000-8000-'+str(actor).zfill(12)
        if client:c['client_id']=client
        head=enc(json.dumps(h,separators=(',',':')).encode());body=enc(json.dumps(c,separators=(',',':')).encode())
        return head+'.'+body+'.'+enc(hmac.new(key,(head+'.'+body).encode(),hashlib.sha256).digest())
    def http(path,body=None,actor=1,client=None,role='authenticated',profile='api'):
        headers={'apikey':env['ANON_KEY'],'Authorization':'Bearer '+token(actor,client,role),'Content-Type':'application/json','Content-Profile':profile,'Accept-Profile':profile}
        req=urllib.request.Request(env['API_URL']+'/rest/v1/'+path,headers=headers,data=None if body is None else json.dumps(body).encode(),method='GET' if body is None else 'POST')
        try:
            with urllib.request.build_opener(urllib.request.ProxyHandler({}),NoRedirect).open(req,timeout=15) as r:status,raw=r.status,r.read()
        except urllib.error.HTTPError as e:status,raw=e.code,e.read()
        try:return status,json.loads(raw)
        except ValueError:return status,{}
    def rpc(op,fields=None,key='http',write=False,**kw):
        req=request(op,fields,key)
        if write:req['idempotencyKey']=key
        return http('rpc/'+('cmd' if write else 'qry')+'_study_review_v1',{'p_request':req},**kw)
    def check(name,response,ok=True,code=None,status=200):
        actual,body=response
        passed=actual==status and(body.get('ok') is True if ok else body.get('code')==code)
        proof={'name':name,'httpStatus':actual,'code':body.get('code'),'passed':passed};assertions.append(proof)
        assert passed,'transport check failed: '+json.dumps(proof)
        return body
    binding={'reportRevisionId':REPORT,'expectedContentHash':'b'*64}
    check('owner-current-report',rpc('report.current',binding))
    core={'resource':{'type':'study','id':STUDY}}
    def check_core(name,expected,actor=1,client=None):
        body=check(name,rpc('resource.actions',core,actor=actor,client=client));assert body['data']['corePermissions']==expected
    check_core('owner-coarse-core-authority',{'read':True,'write':True})
    check_core('editor-coarse-core-authority',{'read':True,'write':True},actor=4)
    check_core('viewer-coarse-core-authority',{'read':True,'write':False},actor=5)
    check_core('reviewer-no-coarse-core-authority',{'read':False,'write':False},actor=2)
    check_core('recipient-no-coarse-core-authority',{'read':False,'write':False},actor=3)
    readonly='90600000-0000-4000-8000-000000000104'
    check_core('read-only-OAuth-core-authority',{'read':True,'write':False},client=readonly)
    nonstudy=check('non-Study-no-coarse-core-authority',rpc('resource.actions',{'resource':{'type':'reportRevision','id':REPORT}}));assert nonstudy['data']['corePermissions']=={'read':False,'write':False}
    try:
        sql("update private.studies set status='archived' where id='"+STUDY+"';")
        check_core('archived-owner-no-core-write',{'read':True,'write':False})
    finally:
        sql("update private.studies set status='active' where id='"+STUDY+"';")
    try:
        sql("delete from private.roles where user_id='89400000-0000-4000-8000-000000000004' and team_id='89400000-0000-4000-8000-000000000100';")
        check_core('team-revoked-no-core-authority',{'read':False,'write':False},actor=4)
    finally:
        sql("insert into private.roles(user_id,team_id,role) values('89400000-0000-4000-8000-000000000004','89400000-0000-4000-8000-000000000100','member');")
    try:
        sql("delete from private.study_members where study_id='"+STUDY+"' and actor_id='89400000-0000-4000-8000-000000000005';")
        check_core('member-revoked-no-core-authority',{'read':False,'write':False},actor=5)
    finally:
        sql("insert into private.study_members values('"+STUDY+"','89400000-0000-4000-8000-000000000005','viewer');")
    try:
        sql("update private.oauth_client_registry set enabled=false,disabled_at=clock_timestamp() where client_id='"+readonly+"';")
        check('revoked-read-client-core-request-denied',rpc('resource.actions',core,client=readonly),False,'42501',403)
    finally:
        sql("update private.oauth_client_registry set enabled=true,disabled_at=null where client_id='"+readonly+"';")
    legacy={'schemaVersion':'lca.study-api.v2','requestId':'mixed-owner-reviewer','operation':'study.list','limit':1,'cursor':None}
    firstpage=check('legacy-mixed-role-first-page',http('rpc/qry_study_v1',{'p_request':legacy},actor=2))['data'];assert firstpage['items'][0]['studyId']=='89300000-0000-4000-8000-000000000001'
    secondpage=check('legacy-mixed-role-cursor-page',http('rpc/qry_study_v1',{'p_request':{**legacy,'cursor':firstpage['nextCursor']}},actor=2))['data'];assert secondpage['items'][0]['studyId']=='89500000-0000-4000-8000-000000000001' and secondpage['nextCursor'] is None
    check('legacy-reviewer-explicit-read-still-denied',http('rpc/qry_study_v1',{'p_request':{'schemaVersion':'lca.study-api.v2','requestId':'reviewer-direct','operation':'study.read','studyId':STUDY}},actor=2),False,'FORBIDDEN')
    check('reviewer-summary-without-core-read',rpc('report.current',binding,actor=2,client=client))
    v3=http('rpc/qry_study_reporting_v1',{'p_request':{'schemaVersion':'lca.study-api.v3','requestId':'legacy','operation':'report.read','reportRevisionId':REPORT}},actor=2)
    check('reviewer-no-V3-escalation',v3,False,'FORBIDDEN')
    check('viewer-cannot-comment',rpc('comment.append',{**binding,'text':'Forbidden viewer'},'http-viewer',True,actor=5),False,'FORBIDDEN')
    first=check('reviewer-appends-comment',rpc('comment.append',{**binding,'text':'Actual PostgREST actor fixture'},'http-comment',True,actor=2))
    replay=check('comment-exact-recovery',rpc('comment.append',{**binding,'text':'Actual PostgREST actor fixture'},'http-comment',True,actor=2));assert replay==first
    check('wrong-hash-denied',rpc('report.current',{**binding,'expectedContentHash':'c'*64},actor=2),False,'REFERENCE_MISMATCH')
    r=rpc('report.current',binding,actor=None,role='anon');assert r[0] in (401,403,404);assertions.append({'name':'anonymous-ACL-denied','httpStatus':r[0],'passed':True})
    r=http('study_report_reviews?select=id',profile='private');assert r[0]==406;assertions.append({'name':'private-schema-unexposed','httpStatus':r[0],'passed':True})
    r=http('rpc/svc_study_review_intent_resolve_v1',{'p_intent_id':'90600000-0000-4000-8000-000000009999'});assert r[0] in(401,403,404);assertions.append({'name':'trusted-resolver-ACL-denied','httpStatus':r[0],'passed':True})
    check('service-consume-canonical-manifest',http('rpc/svc_study_review_intent_consume_v1',{'p_intent_id':'90600000-0000-4000-8000-000000009999','p_completion':{}},actor=None,role='service_role'),False,'CAPABILITY_UNAVAILABLE')
    check('service-config-canonical-manifest',http('rpc/svc_study_review_configure_v1',{'p_expected_revision':99999,'p_configuration':{'qualificationVersion':'lca.study-review-qualification.v1','enabled':True,'evidenceRef':'synthetic-stale-CAS'}},actor=None,role='service_role'),False,'REVISION_CONFLICT')
    predecessor=sql("select review_id from private.study_report_review_heads where report_id='"+REPORT+"' and actor_id='89400000-0000-4000-8000-000000000002';")
    expiry=json.loads(sql("select to_jsonb(clock_timestamp()+interval '5 minutes');"))
    fields={**binding,'clientId':client,'reviewClass':'internal','decision':'approve','predecessorReviewId':predecessor,'expiresAt':expiry}
    check('OAuth-cannot-self-authorize',rpc('review.delegation.issue',fields,'http-self-grant',True,actor=2,client=client),False,'FORBIDDEN')
    d=check('first-party-actor-delegation',rpc('review.delegation.issue',fields,'http-actor-grant',True,actor=2))['data']['value']['delegationId']
    review={**binding,'reviewClass':'internal','decision':'approve','comment':'Delegated actor assessment','predecessorReviewId':predecessor,'delegationId':d}
    check('wrong-client-grant-denied',rpc('review.record',review,'http-wrong-client',True,actor=2,client=other),False,'FORBIDDEN')
    approved=check('OAuth-consumes-actor-grant',rpc('review.record',review,'http-OAuth-review',True,actor=2,client=client))
    assert check('OAuth-same-key-recovers',rpc('review.record',review,'http-OAuth-review',True,actor=2,client=client))['data']['value']==approved['data']['value']
    replay=check('delegation-replay-current-consumption',rpc('review.delegation.issue',fields,'http-actor-grant',True,actor=2));assert replay['data']['value']['consumedReviewId']==approved['data']['value']['reviewId']
    shared=check('named-recipient-metadata',rpc('share.read',{'shareId':share},actor=3))['data']['value']
    ownerintent=check('owner-export-download-intent',rpc('export.download',{'exportId':shared['exportId']}))['data']['intentId']
    check('reviewer-owner-download-denied',rpc('export.download',{'exportId':shared['exportId']},actor=2),False,'FORBIDDEN')
    check('recipient-no-Study-authority',rpc('report.current',binding,actor=3),False,'FORBIDDEN')
    intent=check('recipient-projection-intent',rpc('share.view',{'shareId':share},actor=3))['data']['intentId']
    def resolve(i):return http('rpc/svc_study_review_intent_resolve_v1',{'p_intent_id':i},actor=None,role='service_role')
    c=check('owner-export-exact-bundle',resolve(ownerintent))['data'];assert c['share'] is None and c['producerContext'] is None and c['artifact']['artifactRef']==c['export']['bundleRef']
    c=check('service-narrow-projection',resolve(intent))['data'];assert c['producerContext'] is None and c['artifact']['artifactRef']['type']=='reportProjection'
    download=check('recipient-cross-context-download',rpc('share.download',{'shareId':share},actor=3,client=client))['data']['intentId']
    c=check('service-exact-bundle-only',resolve(download))['data'];assert c['producerContext'] is None and c['artifact']['artifactRef']['type']=='reportExportBundle'
    try:
        sql("update private.oauth_client_registry set enabled=false,disabled_at=clock_timestamp() where client_id='"+client+"';")
        r=rpc('report.current',binding,actor=2,client=client);check('revoked-client-pre-request',r,False,'42501',403)
        check('client-change-during-I/O',resolve(download),False,'FORBIDDEN')
    finally:
        sql("update private.oauth_client_registry set enabled=true,disabled_at=null where client_id='"+client+"';")
    try:
        sql("update public.lifecyclemodels set user_id='89400000-0000-4000-8000-000000000002' where id='89400000-0000-4000-8000-000000000101';")
        check('source-change-during-I/O',resolve(intent),False,'DISCLOSURE_DENIED')
        check('owner-download-source-change-during-I/O',resolve(ownerintent),False,'DISCLOSURE_DENIED')
    finally:
        sql("update public.lifecyclemodels set user_id='89400000-0000-4000-8000-000000000001' where id='89400000-0000-4000-8000-000000000101';")
    check('owner-HTTP-share-revoke',rpc('share.revoke',{'shareId':share,'reason':'HTTP fixture revoke'},'http-share-revoke',True))
    original=json.loads(sql("select request-'_verifiedClientId'-'operation' from private.study_command_receipts where idempotency_key='http-retained-share';"))
    replay=check('share-create-replay-current-revocation',rpc('share.create',original,'http-retained-share',True));assert replay['data']['value']['shareId']==share and replay['data']['value']['status']=='revoked'
    check('share-revoke-during-I/O',resolve(intent),False,'DISCLOSURE_DENIED')
    body=check('recipient-retained-revoked-metadata',rpc('share.read',{'shareId':share},actor=3));assert body['data']['value']['status']=='revoked'
    short={**original,'expiresAt':json.loads(sql("select to_jsonb(clock_timestamp()+interval '2 seconds');"))}
    shortshare=check('short-share-creation',rpc('share.create',short,'http-short-share',True))['data']['value']
    time.sleep(2.1)
    replay=check('share-create-replay-current-expiry',rpc('share.create',short,'http-short-share',True));assert replay['data']['value']['shareId']==shortshare['shareId'] and replay['data']['value']['status']=='expired'
    actionreport='90600000-0000-4000-8000-000000000004'
    sql("insert into private.study_report_revisions(id,study_id,author_id,revision,status,content_hash,content_artifact_id,template_id,run_ids,analysis_ids,facts_refs,validity_snapshot,validation_evidence) select '"+actionreport+"',study_id,author_id,revision,status,content_hash,content_artifact_id,template_id,run_ids,analysis_ids,facts_refs,validity_snapshot,validation_evidence from private.study_report_revisions where id='"+REPORT+"';")
    actionbinding={**binding,'reportRevisionId':actionreport}
    check('first-withdrawal-denied',rpc('review.record',{**actionbinding,'reviewClass':'internal','decision':'withdraw','comment':'No prior decision','predecessorReviewId':None,'delegationId':None},'http-first-withdraw',True,actor=2),False,'REVISION_CONFLICT')
    check('first-withdrawal-delegation-denied',rpc('review.delegation.issue',{**actionbinding,'reviewClass':'internal','decision':'withdraw','clientId':client,'predecessorReviewId':None,'expiresAt':json.loads(sql("select to_jsonb(clock_timestamp()+interval '5 minutes');"))},'http-first-withdraw-grant',True,actor=2),False,'REVISION_CONFLICT')
    assert sql("select count(*) from private.study_report_reviews where report_id='"+actionreport+"';")=='0'
    assert sql("select count(*) from private.study_review_delegations where report_id='"+actionreport+"';")=='0'
    actionstate=check('action-report-current',rpc('report.current',actionbinding))['data']['value']
    f=check('action-report-unreviewed-finalization',rpc('report.finalize',{'target':{'type':'reportRevision','id':actionreport,'expectedRevision':3},'expectedContentHash':'b'*64,'expectedReviewStateHash':actionstate['reviewStateHash'],'profileId':'lca.study-report-unreviewed.v1','acceptedReviewIds':[]},'http-action-finalization',True))['data']['value']
    def produce_export(key,exportclient=None):
        fields={**actionbinding,'finalizationId':f['finalizationId'],'expectedReviewStateHash':actionstate['reviewStateHash'],'rendererVersion':'1.0.0','viewModelVersion':'lca.study-report-view.v1'}
        iid=check(key+'-intent',rpc('export.request',fields,key,True,client=exportclient))['data']['intentId']
        context=check(key+'-context',resolve(iid))['data'];c=context['producerContext']
        manifest={'schemaVersion':'lca.study-export-manifest.v2','issuerId':'study906-test','exportId':c['exportId'],'studyId':STUDY,'reportRevisionId':actionreport,'reportContentHash':'b'*64,'actorId':context['actorId'],'clientId':context['clientId'],'grantEpoch':c['grantEpoch'],'policyId':'lca.study-report-disclosure.v1','disclosureContextHash':c['disclosureContextHash'],'generatedAt':c['generatedAt'],'validitySnapshot':c['report']['validitySnapshot'],'reviewIds':f['acceptedReviewIds'],'finalization':f,'renderer':{'version':'1.0.0','viewModelVersion':'lca.study-report-view.v1','artifactHash':'a'*64},'files':[{'path':'report.html','mediaType':'text/html','sha256':'d'*64,'byteSize':2},{'path':'projection.json','mediaType':'application/json','sha256':'e'*64,'byteSize':2}]}
        raw=json.dumps(manifest,sort_keys=True,separators=(',',':')).encode()
        def artifact(field,kind,schema,name,digest,size=2):
            aid=c[field]
            return {'studyId':STUDY,'artifactRef':{'type':kind,'id':aid,'contentHash':digest,'digestScope':'artifact_bytes_sha256','byteSize':size,'mediaType':'application/json','schemaVersion':schema},'storageBucket':'study-artifacts','storageObjectPath':f'study/{STUDY}/{aid}/{name}.json'}
        completion={'kind':'validatedReviewExport','projectionArtifact':artifact('projectionArtifactId','reportProjection','lca.study-report-view.v1','projection','e'*64),'resourcesArtifact':artifact('resourcesArtifactId','renderResources','lca.study-export-manifest.v2','resources',hashlib.sha256(raw).hexdigest(),len(raw)),'bundleArtifact':artifact('bundleArtifactId','reportExportBundle','lca.study-export-bundle.v2','bundle','f'*64),'manifest':manifest,'receipt':{'schemaVersion':'lca.study-export-receipt.v2','manifestHash':hashlib.sha256(b'lca.study-export-signature.v1\0'+raw).hexdigest(),'keyId':'study906-key','algorithm':'Ed25519','signature':'A'*86}}
        return check(key+'-consume',http('rpc/svc_study_review_intent_consume_v1',{'p_intent_id':iid,'p_completion':completion},actor=None,role='service_role'))['data']['value']
    oauth_export=produce_export('http-action-OAuth-export',client)
    actions={'resource':{'type':'reportRevision','id':actionreport}}
    a=check('original-client-current-actions',rpc('resource.actions',actions));assert 'share.create' in a['data']['actions']
    try:
        sql("update private.oauth_client_registry set enabled=false,disabled_at=clock_timestamp() where client_id='"+client+"';")
        a=check('original-client-revoked-actions',rpc('resource.actions',actions));assert 'share.create' not in a['data']['actions']
        check('revoked-export-share-command-denied',rpc('share.create',{**actionbinding,'exportId':oauth_export['exportId'],'recipientId':'89400000-0000-4000-8000-000000000003','disclosurePolicyId':'lca.study-report-summary-share.v1','expiresAt':json.loads(sql("select to_jsonb(clock_timestamp()+interval '1 hour');"))},'http-action-denied-share',True),False,'DISCLOSURE_DENIED')
        produce_export('http-action-fresh-export')
        a=check('fresh-export-restores-share-action',rpc('resource.actions',actions));assert 'share.create' in a['data']['actions']
    finally:
        sql("update private.oauth_client_registry set enabled=true,disabled_at=null where client_id='"+client+"';")
    # Same immutable report under an explicitly personal fixture scope; every
    # admission/decision is a real HTTP operation, never a direct grant insert.
    sql("update private.studies set team_id=null where id='"+STUDY+"';")
    policy=check('personal-owner-role-policy',rpc('resource.actions',{'resource':{'type':'study','id':STUDY}}));assert policy['data']['allowedMemberRoles']==['reviewer']
    def membership(role,key):
        generation=int(sql("select revision from private.studies where id='"+STUDY+"';"))
        return rpc('member.set',{'target':{'type':'study','id':STUDY,'expectedRevision':generation},'memberId':'89400000-0000-4000-8000-000000000002','role':role},key,True)
    check('personal-reviewer-remove',membership(None,'http-personal-remove'))
    check('personal-default-isolation',rpc('report.current',binding,actor=2),False,'FORBIDDEN')
    check('personal-editor-denied',membership('editor','http-personal-editor'),False,'CAPABILITY_UNAVAILABLE')
    check('personal-reviewer-admission',membership('reviewer','http-personal-reviewer'))
    check('personal-reviewer-comment',rpc('comment.append',{**binding,'text':'Personal HTTP reviewer'},'http-personal-comment',True,actor=2))
    r=http('rpc/qry_study_reporting_v1',{'p_request':{'schemaVersion':'lca.study-api.v3','requestId':'personal-legacy','operation':'report.read','reportRevisionId':REPORT}},actor=2)
    check('personal-reviewer-no-core-escalation',r,False,'FORBIDDEN')
    previous=approved['data']['value']['reviewId']
    pfields={**binding,'reviewClass':'internal','decision':'approve','comment':'Personal nonauthor actor decision','predecessorReviewId':previous,'delegationId':None}
    personal=check('personal-reviewer-approval',rpc('review.record',pfields,'http-personal-approve',True,actor=2))
    state=check('personal-current-state',rpc('report.current',binding))['data']['value']
    finfields={'target':{'type':'reportRevision','id':REPORT,'expectedRevision':3},'expectedContentHash':'b'*64,'expectedReviewStateHash':state['reviewStateHash'],'profileId':'lca.study-report-internal-review.v1','acceptedReviewIds':state['acceptedReviewIds']}
    finalized=check('personal-owner-finalizes',rpc('report.finalize',finfields,'http-personal-finalize',True))
    view=check('personal-reviewer-view-intent',rpc('report.view',binding,actor=2))['data']['intentId']
    check('personal-report-only-view-context',resolve(view))
    wfields={**pfields,'decision':'withdraw','predecessorReviewId':personal['data']['value']['reviewId']}
    check('personal-reviewer-withdraws',rpc('review.record',wfields,'http-personal-withdraw',True,actor=2))
    replay=check('finalization-replay-withdrawn-current-state',rpc('report.finalize',finfields,'http-personal-finalize',True));assert replay['data']['value']==finalized['data']['value'] and replay['data']['state']['acceptance']=='invalidated'
    state=check('withdrawn-current-state',rpc('report.current',binding))['data']['value']
    newer=check('new-explicit-unreviewed-finalization',rpc('report.finalize',{**finfields,'expectedReviewStateHash':state['reviewStateHash'],'profileId':'lca.study-report-unreviewed.v1','acceptedReviewIds':[]},'http-latest-finalization',True))
    replay=check('old-outcome-with-different-latest-state',rpc('report.finalize',finfields,'http-personal-finalize',True));assert replay['data']['value']==finalized['data']['value'] and replay['data']['state']['finalization']['finalizationId']==newer['data']['value']['finalizationId']
    oldreview=check('old-review-replay-fresh-head-state',rpc('review.record',pfields,'http-personal-approve',True,actor=2));assert oldreview['data']['value']==personal['data']['value'] and oldreview['data']['state']['currentReviewIds']!=[personal['data']['value']['reviewId']]
    check('personal-role-removal',membership(None,'http-personal-final-remove'))
    check('personal-removal-during-I/O',resolve(view),False,'FORBIDDEN')
    args.report.write_text(json.dumps({'schemaVersion':'lca.study-review-transport-receipt.v1','project':'study906','assertions':assertions,'credentialsLogged':False,
      'hostMinusVerifierClockSeconds':int(time.time())-now,'classification':'actual PostgREST/JWT/RLS/pre-request proof with synthetic fixture claims; no GoTrue/OAuth-consent, Storage bytes or deployed Edge/UI qualification',
      'disposition':'synthetic fixtures retained for explicit owned study906 reset'},indent=2)+'\n')
    print(f'Study906: {len(assertions)} actual PostgREST authorization/receipt/I/O-fence assertions passed; credentials not logged.')


if __name__=='__main__':main()
