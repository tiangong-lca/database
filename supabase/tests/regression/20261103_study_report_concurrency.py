#!/usr/bin/env python3
"""Observed report producer intent/CAS/export races in an owned PG17 clone.

No reset, clone or cleanup is performed here. Inputs are explicitly synthetic
SQL producer evidence; no numerical artifacts or cryptographic signer proof.
"""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[3]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--database', required=True)
    parser.add_argument('--report', type=Path, required=True)
    parser.add_argument('--owned-ci-project', type=Path)
    parser.add_argument('--expect-stale-admission', action='store_true', help='Evidence-only reproduction of the reviewed vulnerable migration; never used by CI')
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
    def expand(path):
        return '\n'.join(expand(path.parent / line[4:].strip()) if line.startswith('\\ir ') else line for line in path.read_text().splitlines())
    seed = expand(ROOT / 'supabase/tests/20261103_study_report_producer.sql')
    seed = seed.replace('select * from finish();', '').rsplit('rollback;', 1)[0]
    seed += "select jsonb_build_object('raceSeed',true,'request',pg_temp.create_req('race-report-create'));commit;"
    output = base.sql(seed)
    assert 'not ok' not in output, 'seed SQL assertions failed'
    request = next(x for x in base.json_lines(output) if x.get('raceSeed'))['request']
    def call(req):
        return 'select api.cmd_study_reporting_v1(' + base.sql_json(req) + ');'
    def invoke(statement, service=False):
        return base.json_lines(base.sql('begin;' + base.claim(service) + statement + 'commit;'))[0]
    def context(intent):
        result = invoke('select api.svc_study_report_intent_resolve_v1(' + base.quote(intent['data']['intentId']) + ');', True)
        assert result['ok'], result
        return result['data']
    def artifact(ctx, field, kind, schema, name, digest, size=2):
        aid = ctx[field]
        return {'studyId': ctx['studyId'], 'artifactRef': {'type': kind,'id': aid,'contentHash':digest,'digestScope':'artifact_bytes_sha256','byteSize':size,'mediaType':'application/json','schemaVersion':schema},'storageBucket':'study-artifacts','storageObjectPath':f"study/{ctx['studyId']}/{aid}/{name}.json"}
    def validation(ctx, digest):
        return {'schemaVersion':'lca.study-report-validation.v1','profileId':'lca.study-report-claims.v1','reportRevisionId':ctx['reportRevisionId'],'contentHash':digest,'claimCount':1,'factsBindingHash':ctx['factsBindingHash']}
    def complete(ctx, digest):
        return {'kind':'validatedContent','contentArtifact':artifact(ctx,'contentArtifactId','reportContent','lca.study-report-content.v1','content',digest),'factsRefs':[x['analysis']['factsRef'] for x in ctx['analyses']],'validation':validation(ctx,digest)}
    def consume(ctx, payload):
        return 'select api.svc_study_report_intent_consume_v1(' + base.quote(ctx['intentId']) + ',' + base.sql_json(payload) + ');'
    def service_race(name, first, second):
        original_claim = base.claim
        base.claim = lambda service=False: original_claim(True)
        try:
            return base.race(name, first, second, True)
        finally:
            base.claim = original_claim
    receipts = []
    admission = base.race('report-create-exact-key', call(request), call(request))
    assert admission['first']['ok'] and admission['first'] == admission['second'], admission
    receipts.append(admission)
    ctx = context(admission['first'])
    committed = service_race('report-content-consume-retry',consume(ctx,complete(ctx,'1'*64)),consume(ctx,complete(ctx,'1'*64)))
    assert committed['first']['ok'] and committed['first'] == committed['second'], committed
    receipts.append(committed)
    rid = committed['first']['data']['value']['reportRevisionId']
    def req(operation, fields, key):
        return {'schemaVersion':'lca.study-api.v3','requestId':key,'idempotencyKey':key,'operation':operation,**fields}
    def save_intent(key, revision, title):
        return invoke(call(req('report.save',{'target':{'type':'reportRevision','id':rid,'expectedRevision':revision},'content':{**request['content'],'title':title}},key)))
    a_ctx = context(save_intent('race-report-save-a',1,'Writer A'))
    b_ctx = context(save_intent('race-report-save-b',1,'Writer B'))
    saves = service_race('report-save-save',consume(a_ctx,complete(a_ctx,'2'*64)),consume(b_ctx,complete(b_ctx,'3'*64)))
    assert saves['first']['ok'] and saves['second']['code'] == 'REVISION_CONFLICT', saves
    receipts.append(saves)
    frozen_intent = invoke(call(req('report.freeze',{'target':{'type':'reportRevision','id':rid,'expectedRevision':2},'expectedContentHash':'2'*64},'race-report-freeze')))
    freeze_ctx = context(frozen_intent)
    late_ctx = context(save_intent('race-report-late-save',2,'Too late'))
    freeze_payload = {'kind':'validatedFreeze','contentRef':saves['first']['data']['value']['contentRef'],'validation':validation(freeze_ctx,'2'*64)}
    freeze = service_race('report-freeze-save',consume(freeze_ctx,freeze_payload),consume(late_ctx,complete(late_ctx,'4'*64)))
    assert freeze['first']['ok'] and freeze['second']['code'] == 'REVISION_CONFLICT', freeze
    receipts.append(freeze)
    export_intent = invoke(call(req('export.request',{'reportRevisionId':rid,'expectedContentHash':'2'*64,'rendererVersion':'1.0.0','viewModelVersion':'lca.study-report-view.v1'},'race-report-export')))
    export_ctx = context(export_intent)
    manifest = {'schemaVersion':'lca.study-export-manifest.v1','issuerId':'study904-test','exportId':export_ctx['exportId'],'studyId':export_ctx['studyId'],'reportRevisionId':rid,'reportContentHash':'2'*64,'actorId':export_ctx['actorId'],'clientId':export_ctx['clientId'],'grantEpoch':export_ctx['grantEpoch'],'policyId':'lca.study-report-disclosure.v1','disclosureContextHash':export_ctx['disclosureContextHash'],'generatedAt':export_ctx['generatedAt'],'validitySnapshot':freeze['first']['data']['value']['validitySnapshot'],'reviewIds':[],'renderer':{'version':'1.0.0','viewModelVersion':'lca.study-report-view.v1','artifactHash':'a'*64},'files':[{'path':'report.html','mediaType':'text/html','sha256':'d'*64,'byteSize':2},{'path':'projection.json','mediaType':'application/json','sha256':'e'*64,'byteSize':2}]}
    manifest_bytes = json.dumps(manifest,sort_keys=True,separators=(',',':'),ensure_ascii=False).encode()
    payload = {'kind':'validatedExport','projectionArtifact':artifact(export_ctx,'projectionArtifactId','reportProjection','lca.study-report-view.v1','projection','e'*64),'resourcesArtifact':artifact(export_ctx,'resourcesArtifactId','renderResources','lca.study-export-manifest.v1','resources',hashlib.sha256(manifest_bytes).hexdigest(),len(manifest_bytes)),'bundleArtifact':artifact(export_ctx,'bundleArtifactId','reportExportBundle','lca.study-export-bundle.v1','bundle','f'*64),'manifest':manifest,'receipt':{'schemaVersion':'lca.study-export-receipt.v2','manifestHash':hashlib.sha256(b'lca.study-export-signature.v1\0'+manifest_bytes).hexdigest(),'keyId':'study904-key','algorithm':'Ed25519','signature':'A'*86}}
    exported = service_race('report-export-consume-retry',consume(export_ctx,payload),consume(export_ctx,payload))
    assert exported['first']['ok'] and exported['first'] == exported['second'], exported
    receipts.append(exported)
    stored = json.loads(base.sql('select jsonb_build_object(\'status\',status,\'revision\',revision,\'hash\',content_hash) from private.study_report_revisions where id='+base.quote(rid)+';'))
    assert stored == {'status':'frozen','revision':3,'hash':'2'*64}, stored
    assert base.sql("select count(*) from private.study_report_exports where report_id="+base.quote(rid)+';') == '1'
    # A command must reload its mutable report after waiting for Study authority.
    # First consume updates the row while holding that Study lock; a second
    # admission starts before commit and must reject its original stale CAS.
    admission_races = []
    for operation in ['report.save','report.freeze']:
        suffix = operation.split('.')[1]
        created = invoke(call({**request,'requestId':'admission-case-'+suffix,'idempotencyKey':'admission-case-'+suffix}))
        create_ctx = context(created)
        draft = invoke(consume(create_ctx,complete(create_ctx,'1'*64)),True)
        assert draft['ok'],draft
        case_rid = draft['data']['value']['reportRevisionId']
        first_request = req('report.save',{'target':{'type':'reportRevision','id':case_rid,'expectedRevision':1},'content':{**request['content'],'title':'First committed save'}},'consume-admit-first-'+suffix)
        first_ctx = context(invoke(call(first_request)))
        second_fields = {'target':{'type':'reportRevision','id':case_rid,'expectedRevision':1}}
        if operation == 'report.save':
            second_fields['content'] = {**request['content'],'title':'Stale admission must not overwrite'}
        else:
            second_fields['expectedContentHash'] = '1'*64
        second_key = 'consume-admit-stale-'+suffix
        second_request = req(operation,second_fields,second_key)
        overlap = base.race('consume-vs-'+suffix+'-admission',consume(first_ctx,complete(first_ctx,'2'*64)),call(second_request),True)
        assert overlap['first']['ok'],overlap
        if args.expect_stale_admission:
            assert overlap['second']['ok'],overlap
            stale_ctx = context(overlap['second'])
            assert stale_ctx['request']['target']['expectedRevision']==1 and stale_ctx['report']['revision']==2,stale_ctx
            if operation == 'report.save':
                stale_payload=complete(stale_ctx,'3'*64)
            else:
                stale_payload={'kind':'validatedFreeze','contentRef':stale_ctx['report']['contentRef'],'validation':validation(stale_ctx,'2'*64)}
            stale_consumed=invoke(consume(stale_ctx,stale_payload),True)
            assert stale_consumed['ok'] and stale_consumed['data']['value']['revision']==3,stale_consumed
            evidence={'overlap':overlap,'requestedRevision':1,'capturedRevision':2,'staleServiceConsume':stale_consumed}
        else:
            assert overlap['second']['code']=='REVISION_CONFLICT',overlap
            assert base.sql("select count(*) from private.study_report_intents where request->>'idempotencyKey'="+base.quote(second_key)+';')=='0'
            assert base.sql("select count(*) from private.study_command_receipts where idempotency_key="+base.quote(second_key)+';')=='0'
            after = json.loads(base.sql("select jsonb_build_object('revision',revision,'hash',content_hash,'status',status) from private.study_report_revisions where id="+base.quote(case_rid)+';'))
            assert after=={'revision':2,'hash':'2'*64,'status':'draft'},after
            replay=invoke(call(first_request))
            assert replay==overlap['first'],'committed exact replay must precede fresh CAS'
            evidence={'overlap':overlap,'noStaleIntent':True,'noStaleReceipt':True,'storedReport':after,'committedReplayPreserved':True}
        admission_races.append(evidence)
    # The final disclosure producer must serialize with source withdrawal.
    export2_intent = invoke(call(req('export.request',{'reportRevisionId':rid,'expectedContentHash':'2'*64,'rendererVersion':'1.0.0','viewModelVersion':'lca.study-report-view.v1'},'race-export-withdraw')))
    ctx2 = context(export2_intent)
    manifest2 = {**manifest,'exportId':ctx2['exportId'],'disclosureContextHash':ctx2['disclosureContextHash'],'generatedAt':ctx2['generatedAt']}
    bytes2 = json.dumps(manifest2,sort_keys=True,separators=(',',':'),ensure_ascii=False).encode()
    payload2 = {'kind':'validatedExport','projectionArtifact':artifact(ctx2,'projectionArtifactId','reportProjection','lca.study-report-view.v1','projection','e'*64),'resourcesArtifact':artifact(ctx2,'resourcesArtifactId','renderResources','lca.study-export-manifest.v1','resources',hashlib.sha256(bytes2).hexdigest(),len(bytes2)),'bundleArtifact':artifact(ctx2,'bundleArtifactId','reportExportBundle','lca.study-export-bundle.v1','bundle','f'*64),'manifest':manifest2,'receipt':{'schemaVersion':'lca.study-export-receipt.v2','manifestHash':hashlib.sha256(b'lca.study-export-signature.v1\0'+bytes2).hexdigest(),'keyId':'study904-key','algorithm':'Ed25519','signature':'A'*86}}
    withdrawal = "update public.lifecyclemodels set state_code=20 where id='89400000-0000-4000-8000-000000000101';select jsonb_build_object('withdrawn',true);"
    protected = base.race('report-export-before-source-withdrawal',consume(ctx2,payload2),withdrawal,True)
    assert protected['first']['ok'] and protected['second']['withdrawn'],protected
    receipts.append(protected)
    late = invoke(consume(ctx2,payload2),True)
    assert late['code']=='DISCLOSURE_DENIED',late
    read = invoke('select api.qry_study_reporting_v1('+base.sql_json({'schemaVersion':'lca.study-api.v3','requestId':'withdrawn-export-read','operation':'export.read','exportId':ctx2['exportId']})+');')
    assert read['code']=='DISCLOSURE_DENIED',read
    assert base.sql("select count(*) from private.study_report_exports where report_id="+base.quote(rid)+';')=='2'
    source_fence={'producerBeforeWithdrawal':protected,'lateConsumeDenied':late,'subsequentExportReadDenied':read,'onlyTwoExplicitExportIntentsCommitted':True}
    assert base.sql("select count(*) from pg_stat_activity where application_name in ('study894-writer-a','study894-writer-b','study894-barrier');") == '0'
    args.report.write_text(json.dumps({'schemaVersion':'lca.study-report-concurrency-receipt.v1','project':'study894','database':args.database,'postgresMajor':17,'races':receipts,'storedReport':stored,'consumeVersusAdmission':admission_races,'expectedVulnerable':args.expect_stale_admission,'reportMigrationSha256':hashlib.sha256((ROOT/'supabase/migrations/20261103110002_study_report_producer_v1.sql').read_bytes()).hexdigest(),'executedCommandDefinitionSha256':base.sql("select encode(extensions.digest(pg_get_functiondef('private.study_report_command(jsonb)'::regprocedure),'sha256'),'hex');"),'oneCommittedExportPerIntent':True,'sourceWithdrawalFence':source_fence,'ownedSessionsReleased':True,'classification':'synthetic SQL producer/metadata/signature evidence; no actual signer or byte qualification','disposition':'exact owned cloned database retained for explicit cleanup'},indent=2)+'\n')
    print('P2 reports: consume-versus-save/freeze admission '+('vulnerability reproduced' if args.expect_stale_admission else 'rejected stale CAS without intents')+'; receipt/CAS/export/source races passed.')

if __name__ == '__main__':
    main()
