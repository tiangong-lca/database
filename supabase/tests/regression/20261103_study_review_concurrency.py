#!/usr/bin/env python3
"""Observed independent-session P3 row/source fences on owned study906 only.

Never resets or drops a database. Retains synthetic fixtures for explicit owner
cleanup. SQL facts/content/signatures do not qualify real renderer/byte output.
"""
import argparse
import hashlib
import json
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[3]/'scripts'))
from study_review_test_support import ROOT,REPORT,STUDY,call,claim,expand,invoke,json_lines,quote,race,request,sql,sql_json,verify_owned


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--workdir',type=Path,required=True)
    p.add_argument('--report',type=Path,required=True)
    args=p.parse_args()
    ownership=verify_owned(args.workdir)
    assert not args.report.exists()
    assert sql("select count(*) from auth.users where id::text like '89400000-%';")=='0','fixture namespace occupied; owner must reset exact owned project'
    seed=expand(ROOT/'supabase/tests/20261103_study_review_finalization_sharing.sql').replace('select * from finish();','').rsplit('rollback;',1)[0]+'commit;'
    output=sql(seed)
    assert 'not ok' not in output,'SQL seed assertions failed'
    binding={'reportRevisionId':REPORT,'expectedContentHash':'b'*64}
    def cmd(op,fields,key):
        return call({**request(op,fields,key),'idempotencyKey':key})
    def current():
        return invoke(call(request('report.current',binding),False))['data']['value']
    def head():
        return sql("select review_id from private.study_report_review_heads where report_id="+quote(REPORT)+" and actor_id='89400000-0000-4000-8000-000000000002';")
    def review(decision,previous,delegation=None):
        return {**binding,'reviewClass':'internal','decision':decision,'comment':'Synthetic concurrent actor assessment','predecessorReviewId':previous,'delegationId':delegation}
    def finalize(st,profile='lca.study-report-internal-review.v1'):
        return {'target':{'type':'reportRevision','id':REPORT,'expectedRevision':3},'expectedContentHash':'b'*64,'profileId':profile,
                'expectedReviewStateHash':st['reviewStateHash'],'acceptedReviewIds':st['acceptedReviewIds'] if profile.endswith('internal-review.v1') else []}
    receipts=[]
    exact=cmd('review.record',review('approve',head()),'race-exact-review')
    r=race('same-key-review-recovery',exact,exact,claim(2),claim(2))
    assert r['first']['ok'] and r['first']['data']['value']==r['second']['data']['value'],r
    assert r['first']['data']['state']['reviewStateHash']==r['second']['data']['state']['reviewStateHash'],r;receipts.append(r)
    h=head()
    r=race('stale-head-fork',cmd('review.record',review('approve',h),'race-head-a'),cmd('review.record',review('reject',h),'race-head-b'),claim(2),claim(2))
    assert r['first']['ok'] and r['second']['code']=='REVISION_CONFLICT',r;receipts.append(r)
    st=current()
    r=race('finalization-before-withdrawal',cmd('report.finalize',finalize(st),'race-finalize-first'),cmd('review.record',review('withdraw',head()),'race-withdraw-second'),claim(1),claim(2))
    assert r['first']['ok'] and r['second']['ok'],r
    assert current()['acceptance']=='invalidated';receipts.append(r)
    replay=invoke(cmd('report.finalize',finalize(st),'race-finalize-first'))
    assert replay['data']['value']==r['first']['data']['value'] and replay['data']['state']['acceptance']=='invalidated',replay
    r['postWithdrawalReplay']={'immutableValuePreserved':True,'currentAcceptance':replay['data']['state']['acceptance']}
    assert invoke(cmd('review.record',review('approve',head()),'race-approve-again'),actor=2)['ok']
    stale=cmd('report.finalize',finalize(current()),'race-stale-finalize')
    r=race('withdrawal-before-finalization',cmd('review.record',review('withdraw',head()),'race-withdraw-first'),stale,claim(2),claim(1))
    assert r['first']['ok'] and r['second']['code']=='REVISION_CONFLICT',r;receipts.append(r)
    assert sql("select count(*) from private.study_command_receipts where idempotency_key='race-stale-finalize';")=='0'
    assert invoke(cmd('review.record',review('approve',head()),'race-before-demotion'),actor=2)['ok']
    rev=int(sql('select revision from private.studies where id='+quote(STUDY)+';'))
    member={'target':{'type':'study','id':STUDY,'expectedRevision':rev},'memberId':'89400000-0000-4000-8000-000000000002','role':'editor'}
    r=race('membership-demotion-before-finalization',cmd('member.set',member,'race-demote'),cmd('report.finalize',finalize(current()),'race-finalize-demoted'),claim(1),claim(1))
    assert r['first']['ok'] and r['second']['code']=='REVISION_CONFLICT',r;receipts.append(r)
    member['target']['expectedRevision']=rev+1;member['role']='reviewer'
    assert invoke(cmd('member.set',member,'race-restore-reviewer'))['ok']
    client='90600000-0000-4000-8000-000000000101'
    expiration=sql("select to_jsonb(clock_timestamp()+interval '5 minutes');")
    d=invoke(cmd('review.delegation.issue',{**binding,'reviewClass':'internal','decision':'approve','predecessorReviewId':head(),'clientId':client,'expiresAt':json.loads(expiration)},'race-issue-delegation'),actor=2)
    assert d['ok'],d
    did=d['data']['value']['delegationId']
    r=race('delegation-revoke-before-consume',cmd('review.delegation.revoke',{'delegationId':did},'race-revoke-delegation'),cmd('review.record',review('approve',head(),did),'race-consume-revoked'),claim(2),claim(2,client))
    assert r['first']['ok'] and r['second']['code']=='FORBIDDEN',r;receipts.append(r)
    st=current()
    source="update public.lifecyclemodels set user_id='89400000-0000-4000-8000-000000000002' where id='89400000-0000-4000-8000-000000000101';select jsonb_build_object('withdrawn',true);"
    r=race('source-withdrawal-before-finalization',source,cmd('report.finalize',finalize(st),'race-finalize-withdrawn'),claim(service=True),claim(1),second_wait=False)
    assert r['first']['withdrawn'] and r['second']['code']=='CAPABILITY_UNAVAILABLE',r;receipts.append(r)
    assert sql('select count(*) from private.study_report_finalizations;')!='0'
    assert invoke(cmd('report.finalize',finalize(st),'race-finalize-after-withdraw'))['code']=='DISCLOSURE_DENIED'
    sql("update public.lifecyclemodels set user_id='89400000-0000-4000-8000-000000000001' where id='89400000-0000-4000-8000-000000000101';")
    f=invoke(cmd('report.finalize',finalize(current(),'lca.study-report-unreviewed.v1'),'race-share-finalization'))
    assert f['ok'],f
    fields={**binding,'finalizationId':f['data']['value']['finalizationId'],'expectedReviewStateHash':current()['reviewStateHash'],'rendererVersion':'1.0.0','viewModelVersion':'lca.study-report-view.v1'}
    intent=invoke(cmd('export.request',fields,'race-share-export'))
    assert intent['ok'],intent
    iid=intent['data']['intentId']
    context=invoke('select api.svc_study_review_intent_resolve_v1('+quote(iid)+');',service=True)['data']
    c=context['producerContext']
    manifest={'schemaVersion':'lca.study-export-manifest.v2','issuerId':'study906-test','exportId':c['exportId'],'studyId':STUDY,'reportRevisionId':REPORT,'reportContentHash':'b'*64,
     'actorId':context['actorId'],'clientId':context['clientId'],'grantEpoch':c['grantEpoch'],'policyId':'lca.study-report-disclosure.v1','disclosureContextHash':c['disclosureContextHash'],
     'generatedAt':c['generatedAt'],'validitySnapshot':c['report']['validitySnapshot'],'reviewIds':[],'finalization':f['data']['value'],
     'renderer':{'version':'1.0.0','viewModelVersion':'lca.study-report-view.v1','artifactHash':'a'*64},'files':[{'path':'report.html','mediaType':'text/html','sha256':'d'*64,'byteSize':2},{'path':'projection.json','mediaType':'application/json','sha256':'e'*64,'byteSize':2}]}
    raw=json.dumps(manifest,sort_keys=True,separators=(',',':')).encode()
    def artifact(field,kind,schema,name,digest,size=2):
        aid=c[field]
        return {'studyId':STUDY,'artifactRef':{'type':kind,'id':aid,'contentHash':digest,'digestScope':'artifact_bytes_sha256','byteSize':size,'mediaType':'application/json','schemaVersion':schema},'storageBucket':'study-artifacts','storageObjectPath':f'study/{STUDY}/{aid}/{name}.json'}
    completion={'kind':'validatedReviewExport','projectionArtifact':artifact('projectionArtifactId','reportProjection','lca.study-report-view.v1','projection','e'*64),
     'resourcesArtifact':artifact('resourcesArtifactId','renderResources','lca.study-export-manifest.v2','resources',hashlib.sha256(raw).hexdigest(),len(raw)),
     'bundleArtifact':artifact('bundleArtifactId','reportExportBundle','lca.study-export-bundle.v2','bundle','f'*64),'manifest':manifest,
     'receipt':{'schemaVersion':'lca.study-export-receipt.v2','manifestHash':hashlib.sha256(b'lca.study-export-signature.v1\0'+raw).hexdigest(),'keyId':'study906-key','algorithm':'Ed25519','signature':'A'*86}}
    exported=invoke('select api.svc_study_review_intent_consume_v1('+quote(iid)+','+sql_json(completion)+');',service=True)
    assert exported['ok'],exported
    def share(key):
        expiry=json.loads(sql("select to_jsonb(clock_timestamp()+interval '1 hour');"))
        r=invoke(cmd('share.create',{**binding,'exportId':exported['data']['value']['exportId'],'recipientId':'89400000-0000-4000-8000-000000000003','disclosurePolicyId':'lca.study-report-summary-share.v1','expiresAt':expiry},key))
        assert r['ok'],r
        return r['data']['value']['shareId']
    shareid=share('race-share')
    r=race('share-revocation-before-recipient-intent',cmd('share.revoke',{'shareId':shareid,'reason':'Concurrent revoke'},'race-revoke-share'),call(request('share.view',{'shareId':shareid}),False),claim(1),claim(3))
    assert r['first']['ok'] and r['second']['code']=='DISCLOSURE_DENIED',r;receipts.append(r)
    http_share=share('http-retained-share')
    assert sql("select count(*) from pg_stat_activity where application_name in('study906-barrier','study906-writer-a','study906-writer-b');")=='0'
    args.report.write_text(json.dumps({'schemaVersion':'lca.study-review-concurrency-receipt.v1','project':'study906','ownership':ownership,'races':receipts,
      'retainedHttpShareId':http_share,'ownedSessionsReleased':True,'classification':'observed PG17 SQL transaction/source fences with synthetic content/signatures; no real byte/UI qualification',
      'disposition':'exact synthetic fixture namespace retained for owned HTTP proof then explicit reset'},indent=2)+'\n')
    print('Study906: 8 independent-session review/finalization/grant/share/source races passed with observed locks.')


if __name__=='__main__':main()
