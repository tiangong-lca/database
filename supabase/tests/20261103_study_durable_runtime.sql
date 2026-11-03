begin;
create extension if not exists pgtap with schema extensions;
set local search_path=extensions,public,api,private,pg_temp;
select no_plan();
-- This suite qualifies the frozen W03 core with runtime admissions disabled.
update private.study_runtime_config set source_enabled=false,compute_enabled=false,disclosure_enabled=false where singleton;
\ir fixtures/study894_runtime_fixture.sql
create temp table study894_results(k text primary key,v jsonb);
create function pg_temp.keep(p_key text,p_value jsonb) returns jsonb language plpgsql as $$ begin
 insert into study894_results values(p_key,p_value) on conflict(k) do update set v=excluded.v; return p_value;
end $$;
create function pg_temp.val(p_key text) returns jsonb language sql as $$ select v from study894_results where k=p_key $$;

select ok(not has_table_privilege('authenticated','private.studies','SELECT'),'raw Study SELECT is closed');
select ok(not has_table_privilege('service_role','private.study_revisions','UPDATE'),'raw service update is closed');
select ok(not has_function_privilege('authenticated','api.svc_study_revision_freeze_consume_v1(uuid,text,text)','EXECUTE'),'actors cannot call trusted freeze service');
select ok(not has_function_privilege('service_role','private.study_complete(text,uuid,uuid,uuid,jsonb,text)','EXECUTE'),'service cannot bypass reviewed API helper');
select ok(not has_function_privilege('anon','api.cmd_study_v1(jsonb)','EXECUTE'),'anonymous command is closed');
select is((pg_temp.study894_cmd(1,'study.create','{"scope":{"kind":"personal"},"title":"New research"}','create-replay')->>'ok')::boolean,true,'actor creates real persistent Study');
select is((select count(*) from private.studies),3::bigint,'created row exists alongside exact synthetic fixtures');
select is((pg_temp.study894_cmd(1,'study.create','{"scope":{"kind":"personal"},"title":"New research"}','create-replay')->>'ok')::boolean,true,'lost acknowledgement recovers across different requestId');
select is((select count(*) from private.studies),3::bigint,'replay creates no replacement row');
select is(pg_temp.study894_cmd(1,'study.create','{"scope":{"kind":"personal"},"title":"Changed research"}','create-replay')->>'code','IDEMPOTENCY_CONFLICT','changed content using same key conflicts');
select is(pg_temp.study894_cmd(2,'study.create','{"scope":{"kind":"team","teamId":"89400000-0000-4000-8000-000000000100"},"title":"No team management"}')->>'code','FORBIDDEN','ordinary team member cannot create team Study');
select is(pg_temp.study894_qry(2,'study.read','{"studyId":"89400000-0000-4000-8000-000000000011"}')->>'code','FORBIDDEN','team membership alone grants no research access');
select is((pg_temp.study894_cmd(1,'member.set','{"target":{"type":"study","id":"89400000-0000-4000-8000-000000000011","expectedRevision":1},"memberId":"89400000-0000-4000-8000-000000000002","role":"viewer"}')->>'ok')::boolean,true,'owner grants narrow team viewer access');
select is((pg_temp.study894_qry(2,'study.read','{"studyId":"89400000-0000-4000-8000-000000000011"}')->>'ok')::boolean,true,'second existing member reads through explicit live grant');
select is(pg_temp.study894_cmd(2,'study.archive','{"target":{"type":"study","id":"89400000-0000-4000-8000-000000000011","expectedRevision":2}}')->>'code','FORBIDDEN','viewer cannot manage');
update private.roles set role='is_invited' where user_id='89400000-0000-4000-8000-000000000002' and team_id='89400000-0000-4000-8000-000000000100';
select is(pg_temp.study894_qry(2,'study.read','{"studyId":"89400000-0000-4000-8000-000000000011"}')->>'code','FORBIDDEN','team demotion revokes existing Study grant immediately');
select is((pg_temp.study894_cmd(1,'member.set','{"target":{"type":"study","id":"89400000-0000-4000-8000-000000000011","expectedRevision":2},"memberId":"89400000-0000-4000-8000-000000000002","role":null}')->>'ok')::boolean,true,'owner can clean a revoked member grant');
select is(pg_temp.study894_cmd(1,'member.set','{"target":{"type":"study","id":"89400000-0000-4000-8000-000000000011","expectedRevision":2},"memberId":"89400000-0000-4000-8000-000000000002","role":null}')->>'code','REVISION_CONFLICT','stale Study CAS rejects no-op or member mutation');

insert into private.oauth_client_registry(client_id,client_kind,enabled) values('study894-read-only','manual',true);
insert into private.oauth_client_capability_grants(client_id,capability_id) values('study894-read-only','STUDY-READ-01');
select is((pg_temp.study894_qry(1,'study.read','{"studyId":"89400000-0000-4000-8000-000000000010"}','study894-read-only')->>'ok')::boolean,true,'narrow OAuth read grant admits Study query');
select is(pg_temp.study894_cmd(1,'study.archive','{"target":{"type":"study","id":"89400000-0000-4000-8000-000000000010","expectedRevision":1}}',null,'study894-read-only')->>'code','FORBIDDEN','read capability cannot mutate even as owner');
update private.oauth_client_registry set enabled=false,disabled_at=clock_timestamp() where client_id='study894-read-only';
select is(pg_temp.study894_qry(1,'study.read','{"studyId":"89400000-0000-4000-8000-000000000010"}','study894-read-only')->>'code','FORBIDDEN','already issued client session is denied after registry revocation');

select pg_temp.study894_claim(null,null,true);
select is(api.svc_study_model_preparation_complete_v1('89400000-0000-4000-8000-000000000021','89400000-0000-4000-8000-000000000031','89400000-0000-4000-8000-000000000049',pg_temp.study894_complete(),'complete-base')->>'code','FORBIDDEN','stale Worker lease cannot issue a prepared model');
select is((select model_ref is null from private.study_model_preparations where id='89400000-0000-4000-8000-000000000021'),true,'failed lease leaves preparation unissued');
select is((api.svc_study_model_preparation_complete_v1('89400000-0000-4000-8000-000000000021','89400000-0000-4000-8000-000000000031','89400000-0000-4000-8000-000000000041',pg_temp.study894_complete(),'complete-base')->>'ok')::boolean,true,'actual bound current lease issues prepared model atomically');
select is((select status from private.worker_jobs where id='89400000-0000-4000-8000-000000000031'),'completed','canonical Worker task completes in same transaction');
select ok(not (select private.worker_job_payload(j,false)->'result' ?| array['storageBucket','storageObjectPath','sourceAuthorization','modelRef','inputArtifactRef'] from private.worker_jobs j where id='89400000-0000-4000-8000-000000000031'),'generic Worker result projection carries no private locator/source/model payload');
select ok((select private.worker_job_payload(j,false)->'resultRef' is null from private.worker_jobs j where id='89400000-0000-4000-8000-000000000031'),'generic noninternal Worker projection omits artifact reference');
select is((api.svc_study_model_preparation_complete_v1('89400000-0000-4000-8000-000000000021','89400000-0000-4000-8000-000000000031','89400000-0000-4000-8000-000000000041',pg_temp.study894_complete(),'complete-base')->>'ok')::boolean,true,'terminal response loss recovers exact original receipt');
select is(api.svc_study_model_preparation_complete_v1('89400000-0000-4000-8000-000000000021','89400000-0000-4000-8000-000000000031','89400000-0000-4000-8000-000000000041',pg_temp.study894_complete()||'{"inputHash":"dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"}','complete-base')->>'code','IDEMPOTENCY_CONFLICT','terminal completion key cannot change semantic identity');

select ok((pg_temp.keep('revision',pg_temp.study894_cmd(1,'revision.create',jsonb_build_object('studyId','89400000-0000-4000-8000-000000000010','parentRevisionId',null,'definition',pg_temp.study894_definition(),'modelPreparationId','89400000-0000-4000-8000-000000000021','modelRef',pg_temp.study894_model())))->>'ok')::boolean,'create revision binds exact prepared model/method selection');
select is(pg_temp.study894_cmd(1,'revision.create',jsonb_build_object('studyId','89400000-0000-4000-8000-000000000011','parentRevisionId',null,'definition',pg_temp.study894_definition(),'modelPreparationId','89400000-0000-4000-8000-000000000021','modelRef',pg_temp.study894_model()))->>'code','REFERENCE_MISMATCH','foreign Study preparation is rejected');
select is(pg_temp.study894_cmd(1,'revision.save',jsonb_build_object('target',jsonb_build_object('type','studyRevision','id',pg_temp.val('revision')->'data'->'value'->'revisionId','expectedRevision',1),'definition',pg_temp.study894_definition(),'modelPreparationId','89400000-0000-4000-8000-000000000021','modelRef',pg_temp.study894_model(),'validation','passed'))->>'code','INVALID_REQUEST','actor cannot inject trusted passed flag');
select ok((pg_temp.keep('intent',pg_temp.study894_cmd(1,'revision.freeze',jsonb_build_object('target',jsonb_build_object('type','studyRevision','id',pg_temp.val('revision')->'data'->'value'->'revisionId','expectedRevision',1),'expectedContentHash',pg_temp.val('revision')->'data'->'value'->'contentHash'),'freeze-lost-reply'))->>'ok')::boolean,'freeze returns bound intent without mutating draft');
select is((select validation from private.study_revisions limit 1),'not_checked','issued intent does not self-certify validation');
select pg_temp.study894_claim(null,null,true);
select is(api.svc_study_revision_freeze_consume_v1((pg_temp.val('intent')->'data'->>'intentId')::uuid,'failed','INVALID_REQUEST')->>'code','INVALID_REQUEST','rejected structural validation does not freeze');
select is((select revision from private.study_revisions limit 1),1::bigint,'failed validation leaves CAS unchanged');
select is((api.svc_study_revision_freeze_consume_v1((pg_temp.val('intent')->'data'->>'intentId')::uuid,'passed')->>'ok')::boolean,true,'trusted service atomically records passed and frozen');
select is((select status||':'||validation from private.study_revisions limit 1),'frozen:passed','successful freeze has both state axes');
select is((select revision from private.study_revisions limit 1),2::bigint,'freeze advances target generation once');
select is((api.svc_study_revision_freeze_consume_v1((pg_temp.val('intent')->'data'->>'intentId')::uuid,'passed')->>'ok')::boolean,true,'freeze service exact retry recovers recorded receipt');
select is((select revision from private.study_revisions limit 1),2::bigint,'freeze retry advances no generation');
-- Synthetic future observation changes only this fixture deadline, not any
-- host/VM clock. The committed frozen response must survive the intent TTL.
update private.study_validation_intents set expires_at=clock_timestamp()-interval '1 second' where id=(pg_temp.val('intent')->'data'->>'intentId')::uuid;
select ok((pg_temp.keep('freeze-recovered',pg_temp.study894_cmd(1,'revision.freeze',jsonb_build_object('target',jsonb_build_object('type','studyRevision','id',pg_temp.val('revision')->'data'->'value'->'revisionId','expectedRevision',1),'expectedContentHash',pg_temp.val('revision')->'data'->'value'->'contentHash'),'freeze-lost-reply'))->>'ok')::boolean,'actor lost-reply replay succeeds after consumed intent expiry');
select is(pg_temp.val('freeze-recovered')->'data'->>'type','studyRevision','replay returns committed resource instead of stale validation intent');
select is(pg_temp.val('freeze-recovered')->'data'->'value'->>'status','frozen','recovered receipt preserves frozen outcome');
select is((select revision from private.study_revisions limit 1),2::bigint,'after-TTL actor replay does not reapply CAS or increment generation');
select is(pg_temp.study894_cmd(1,'revision.freeze',jsonb_build_object('target',jsonb_build_object('type','studyRevision','id',pg_temp.val('revision')->'data'->'value'->'revisionId','expectedRevision',1),'expectedContentHash',repeat('f',64)),'freeze-lost-reply')->>'code','IDEMPOTENCY_CONFLICT','committed after-TTL replay still rejects changed normalized content');
insert into private.oauth_client_registry(client_id,client_kind) values('study894-freeze-recovery','manual');
insert into private.oauth_client_capability_grants(client_id,capability_id) values('study894-freeze-recovery','STUDY-WRITE-01');
select is(pg_temp.study894_cmd(1,'revision.freeze',jsonb_build_object('target',jsonb_build_object('type','studyRevision','id',pg_temp.val('revision')->'data'->'value'->'revisionId','expectedRevision',1),'expectedContentHash',pg_temp.val('revision')->'data'->'value'->'contentHash'),'freeze-lost-reply','study894-freeze-recovery')->'data'->>'type','studyRevision','another currently authorized client of the same actor recovers the committed receipt');
update private.oauth_client_registry set enabled=false,disabled_at=clock_timestamp() where client_id='study894-freeze-recovery';
select is(pg_temp.study894_cmd(1,'revision.freeze',jsonb_build_object('target',jsonb_build_object('type','studyRevision','id',pg_temp.val('revision')->'data'->'value'->'revisionId','expectedRevision',1),'expectedContentHash',pg_temp.val('revision')->'data'->'value'->'contentHash'),'freeze-lost-reply','study894-freeze-recovery')->>'code','FORBIDDEN','revoked current caller cannot recover even a committed expired intent');
select is(pg_temp.study894_cmd(1,'revision.save',jsonb_build_object('target',jsonb_build_object('type','studyRevision','id',pg_temp.val('revision')->'data'->'value'->'revisionId','expectedRevision',2),'definition',pg_temp.study894_definition(),'modelPreparationId','89400000-0000-4000-8000-000000000021','modelRef',pg_temp.study894_model()))->>'code','FROZEN_REVISION','frozen content is immutable');
select ok((pg_temp.keep('scenario',pg_temp.study894_cmd(1,'scenario.create',jsonb_build_object('studyRevisionId',pg_temp.val('revision')->'data'->'value'->'revisionId','parentScenarioRevisionId',null,'overrides','[{"path":"/instances/i/exchanges/e/amount","value":1}]'::jsonb)))->>'ok')::boolean,'frozen Study supports draft Scenario identity');
select is(pg_temp.study894_cmd(1,'scenario.freeze',jsonb_build_object('target',jsonb_build_object('type','scenarioRevision','id',pg_temp.val('scenario')->'data'->'value'->'scenarioRevisionId','expectedRevision',1),'expectedContentHash',pg_temp.val('scenario')->'data'->'value'->'contentHash','modelPreparationId','89400000-0000-4000-8000-000000000021'))->>'code','REFERENCE_MISMATCH','base-source preparation cannot substitute for exact Scenario preparation');
insert into private.worker_jobs(id,job_kind,worker_queue,requested_by,status,leased_by,lease_token,lease_expires_at,payload_schema_version,payload_json)
values('89400000-0000-4000-8000-000000000032','study.model_prepare','solver','89400000-0000-4000-8000-000000000001','running','study894-test','89400000-0000-4000-8000-000000000042',clock_timestamp()+interval '1 hour','lca.study-job.v1','{"studyId":"89400000-0000-4000-8000-000000000010","preparationId":"89400000-0000-4000-8000-000000000022"}');
insert into private.study_model_preparations(id,study_id,source,source_document,source_scenario_id,source_study_revision_id,method_refs,profile_id,calculation_contract_ref,job_id)
select '89400000-0000-4000-8000-000000000022',study_id,jsonb_build_object('type','scenarioRevision','scenarioRevisionId',id,'expectedRevision',revision,'contentHash',content_hash),'{"syntheticFixture":true}',id,study_revision_id,pg_temp.study894_definition()->'methodRefs','lca.study-explicit-v1',pg_temp.study894_complete()->'calculationContractRef','89400000-0000-4000-8000-000000000032' from private.study_scenarios;
select pg_temp.study894_claim(null,null,true);
select ok((api.svc_study_model_preparation_complete_v1('89400000-0000-4000-8000-000000000022','89400000-0000-4000-8000-000000000032','89400000-0000-4000-8000-000000000042',
 jsonb_set(pg_temp.study894_complete(),'{inputArtifactRef,id}','"89400000-0000-4000-8000-000000000062"')||jsonb_build_object('modelRef',pg_temp.study894_model()||jsonb_build_object('modelRevisionId','scenario-model-894','contentHash',repeat('e',64)),'inputHash',repeat('d',64),'storageObjectPath','study/89400000-0000-4000-8000-000000000010/89400000-0000-4000-8000-000000000062/input.json'),'scenario-producer')->>'ok')::boolean,'current actual lease issues exact Scenario preparation and semantic input identity');
select ok((pg_temp.study894_cmd(1,'scenario.freeze',jsonb_build_object('target',jsonb_build_object('type','scenarioRevision','id',pg_temp.val('scenario')->'data'->'value'->'scenarioRevisionId','expectedRevision',1),'expectedContentHash',pg_temp.val('scenario')->'data'->'value'->'contentHash','modelPreparationId','89400000-0000-4000-8000-000000000022'))->>'ok')::boolean,'captured draft preparation freezes without a false provenance self-cycle');
select is((select status||':'||revision from private.study_scenarios),'frozen:2','Scenario freezes once and advances its own generation');
select is(pg_temp.study894_cmd(1,'run.submit',jsonb_build_object('studyRevisionId',pg_temp.val('revision')->'data'->'value'->'revisionId','scenarioRevisionId',pg_temp.val('scenario')->'data'->'value'->'scenarioRevisionId','expectedInputHash',repeat('d',64),'profileId','lca.study-explicit-v1','calculationContractRef',pg_temp.study894_complete()->'calculationContractRef'))->>'code','CAPABILITY_UNAVAILABLE','no placeholder queue/solver admission is advertised');
select is((select count(*) from private.study_runs),0::bigint,'unavailable Run command creates no domain row');
select is(pg_temp.study894_qry(1,'artifact.read','{"studyId":"89400000-0000-4000-8000-000000000010","artifactRef":{}}')->>'code','CAPABILITY_UNAVAILABLE','artifact disclosure unavailable until qualified W06 path');

-- Fresh mutable child for CAS/validation-intent rejection and pagination proofs.
select ok((pg_temp.keep('draft',pg_temp.study894_cmd(1,'revision.create',jsonb_build_object('studyId','89400000-0000-4000-8000-000000000010','parentRevisionId',pg_temp.val('revision')->'data'->'value'->'revisionId','definition',pg_temp.study894_definition(),'modelPreparationId','89400000-0000-4000-8000-000000000021','modelRef',pg_temp.study894_model())))->>'ok')::boolean,'new content revision links a frozen same-Study parent');
select is(pg_temp.study894_cmd(1,'revision.create',jsonb_build_object('studyId','89400000-0000-4000-8000-000000000010','parentRevisionId',pg_temp.val('draft')->'data'->'value'->'revisionId','definition',pg_temp.study894_definition(),'modelPreparationId','89400000-0000-4000-8000-000000000021','modelRef',pg_temp.study894_model()))->>'code','REFERENCE_MISMATCH','draft parent is rejected');
select is(pg_temp.study894_cmd(1,'revision.save',jsonb_build_object('target',jsonb_build_object('type','studyRevision','id',pg_temp.val('draft')->'data'->'value'->'revisionId','expectedRevision',1),'definition',pg_temp.study894_definition(),'modelPreparationId','89400000-0000-4000-8000-000000000021','modelRef',pg_temp.study894_model()||jsonb_build_object('contentHash',repeat('e',64))))->>'code','REFERENCE_MISMATCH','save cannot silently ignore mismatched selected model');
select is((select revision from private.study_revisions where id=(pg_temp.val('draft')->'data'->'value'->>'revisionId')::uuid),1::bigint,'rejected replacement preserves CAS');
select ok((pg_temp.keep('expired',pg_temp.study894_cmd(1,'revision.freeze',jsonb_build_object('target',jsonb_build_object('type','studyRevision','id',pg_temp.val('draft')->'data'->'value'->'revisionId','expectedRevision',1),'expectedContentHash',pg_temp.val('draft')->'data'->'value'->'contentHash'),'freeze-expired-unconsumed'))->>'ok')::boolean,'fresh draft issues expirable intent');
update private.study_validation_intents set expires_at=clock_timestamp()-interval '1 second' where id=(pg_temp.val('expired')->'data'->>'intentId')::uuid;
select pg_temp.study894_claim(null,null,true);
select is(api.svc_study_revision_freeze_consume_v1((pg_temp.val('expired')->'data'->>'intentId')::uuid,'passed')->>'code','CAPABILITY_UNAVAILABLE','expired intent cannot freeze');
select is((select validation from private.study_revisions where id=(pg_temp.val('draft')->'data'->'value'->>'revisionId')::uuid),'not_checked','expired intent leaves draft validation untouched');
select is(pg_temp.study894_cmd(1,'revision.freeze',jsonb_build_object('target',jsonb_build_object('type','studyRevision','id',pg_temp.val('draft')->'data'->'value'->'revisionId','expectedRevision',1),'expectedContentHash',pg_temp.val('draft')->'data'->'value'->'contentHash'),'freeze-expired-unconsumed')->>'code','CAPABILITY_UNAVAILABLE','actor replay of expired unconsumed intent is rejected by database clock');
select is((select count(*) from private.study_validation_intents where revision_id=(pg_temp.val('draft')->'data'->'value'->>'revisionId')::uuid),1::bigint,'expired pending replay creates no replacement intent');
select is((select count(*) from private.study_command_receipts where idempotency_key='freeze-expired-unconsumed'),1::bigint,'expired pending replay creates no replacement receipt');
insert into private.oauth_client_registry(client_id,client_kind,enabled) values('study894-write','manual',true);
insert into private.oauth_client_capability_grants(client_id,capability_id) values('study894-write','STUDY-WRITE-01');
select ok((pg_temp.keep('revoked',pg_temp.study894_cmd(1,'revision.freeze',jsonb_build_object('target',jsonb_build_object('type','studyRevision','id',pg_temp.val('draft')->'data'->'value'->'revisionId','expectedRevision',1),'expectedContentHash',pg_temp.val('draft')->'data'->'value'->'contentHash'),'freeze-revoked-original','study894-write'))->>'ok')::boolean,'intent captures real original OAuth client');
update private.oauth_client_registry set enabled=false,disabled_at=clock_timestamp() where client_id='study894-write';
select pg_temp.study894_claim(null,null,true);
select is(api.svc_study_revision_freeze_consume_v1((pg_temp.val('revoked')->'data'->>'intentId')::uuid,'passed')->>'code','FORBIDDEN','service rechecks original client after revocation');
update private.study_validation_intents set expires_at=clock_timestamp()-interval '1 second' where id=(pg_temp.val('revoked')->'data'->>'intentId')::uuid;
select is(pg_temp.study894_cmd(1,'revision.freeze',jsonb_build_object('target',jsonb_build_object('type','studyRevision','id',pg_temp.val('draft')->'data'->'value'->'revisionId','expectedRevision',1),'expectedContentHash',pg_temp.val('draft')->'data'->'value'->'contentHash'),'freeze-revoked-original','study894-write')->>'code','FORBIDDEN','expired unconsumed replay never bypasses revoked current caller authorization');
select ok((pg_temp.keep('stale',pg_temp.study894_cmd(1,'revision.freeze',jsonb_build_object('target',jsonb_build_object('type','studyRevision','id',pg_temp.val('draft')->'data'->'value'->'revisionId','expectedRevision',1),'expectedContentHash',pg_temp.val('draft')->'data'->'value'->'contentHash')))->>'ok')::boolean,'intent captures exact draft generation');
select ok((pg_temp.keep('saved',pg_temp.study894_cmd(1,'revision.save',jsonb_build_object('target',jsonb_build_object('type','studyRevision','id',pg_temp.val('draft')->'data'->'value'->'revisionId','expectedRevision',1),'definition',pg_temp.study894_definition()||'{"goal":"Changed draft"}','modelPreparationId','89400000-0000-4000-8000-000000000021','modelRef',pg_temp.study894_model())))->>'ok')::boolean,'save really replaces definition and advances CAS');
select is(pg_temp.val('saved')->'data'->'value'->'definition'->>'goal','Changed draft','new definition is durable readback truth');
select is((pg_temp.val('saved')->'data'->'value'->>'revision')::integer,2,'save advances target generation');
select isnt(pg_temp.val('saved')->'data'->'value'->>'contentHash',pg_temp.val('draft')->'data'->'value'->>'contentHash','research document identity changes with content');
select pg_temp.study894_claim(null,null,true);
select is(api.svc_study_revision_freeze_consume_v1((pg_temp.val('stale')->'data'->>'intentId')::uuid,'passed')->>'code','REVISION_CONFLICT','service rejects intervening save against old intent');
select is((select count(*) from private.study_revisions where status='draft' and validation='not_checked'),1::bigint,'stale validation creates no ghost frozen revision');
select is(pg_temp.study894_cmd(1,'revision.save',jsonb_build_object('target',jsonb_build_object('type','studyRevision','id',pg_temp.val('draft')->'data'->'value'->'revisionId','expectedRevision',1),'definition',pg_temp.study894_definition(),'modelPreparationId','89400000-0000-4000-8000-000000000021','modelRef',pg_temp.study894_model()))->>'code','REVISION_CONFLICT','second stale writer cannot overwrite saved content');

update private.oauth_client_registry set enabled=true,disabled_at=null where client_id='study894-read-only';
select ok(not (pg_temp.study894_qry(1,'capability.read','{}','study894-read-only')->'data'->'operations' ? 'study.create'),'read-only OAuth capability projection excludes writes');
select ok((pg_temp.keep('page',pg_temp.study894_qry(1,'study.list','{"limit":1,"cursor":null}'))->'data'->>'nextCursor') is not null,'bounded query issues opaque server cursor');
select is(pg_temp.study894_qry(2,'study.list',jsonb_build_object('limit',1,'cursor',pg_temp.val('page')->'data'->'nextCursor'))->>'code','FORBIDDEN','cursor cannot move to another actor');
select is(pg_temp.study894_qry(1,'study.list',jsonb_build_object('limit',1,'cursor',pg_temp.val('page')->'data'->'nextCursor'),'study894-read-only')->>'code','FORBIDDEN','cursor cannot move to another client');
select is(pg_temp.study894_qry(1,'study.list',jsonb_build_object('limit',2,'cursor',pg_temp.val('page')->'data'->'nextCursor'))->>'code','FORBIDDEN','cursor cannot alter original selection');
select is((pg_temp.study894_qry(1,'study.list',jsonb_build_object('limit',1,'cursor',pg_temp.val('page')->'data'->'nextCursor'))->>'ok')::boolean,true,'same live actor/client/selection can continue');
update private.study_cursors set expires_at=clock_timestamp()-interval '1 second' where id=(pg_temp.val('page')->'data'->>'nextCursor')::uuid;
select is(pg_temp.study894_qry(1,'study.list',jsonb_build_object('limit',1,'cursor',pg_temp.val('page')->'data'->'nextCursor'))->>'code','FORBIDDEN','expired cursor is denied without a background writer');
select ok((pg_temp.keep('epoch-page',pg_temp.study894_qry(1,'study.list','{"limit":1,"cursor":null}'))->'data'->>'nextCursor') is not null,'second cursor captures current access epoch');
update private.studies set grant_epoch=grant_epoch+1 where id='89400000-0000-4000-8000-000000000011';
select is(pg_temp.study894_qry(1,'study.list',jsonb_build_object('limit',1,'cursor',pg_temp.val('epoch-page')->'data'->'nextCursor'))->>'code','FORBIDDEN','grant epoch changes fence earlier cursor');
\ir fixtures/study894_definition_vectors.sql
select is(private.study_definition_valid(definition),valid,'Edge structural definition parity: '||name) from study894_definition_vectors order by name;
select is(pg_temp.study894_cmd(1,'revision.create',jsonb_build_object('studyId','89400000-0000-4000-8000-000000000010','parentRevisionId',null,'definition',definition,'modelPreparationId','89400000-0000-4000-8000-000000000021','modelRef',pg_temp.study894_model()),'invalid-create-'||name)->>'code','INVALID_REQUEST','direct RPC create rejects '||name) from study894_definition_vectors where not valid order by name;
select is(pg_temp.study894_cmd(1,'revision.save',jsonb_build_object('target',jsonb_build_object('type','studyRevision','id',pg_temp.val('draft')->'data'->'value'->'revisionId','expectedRevision',2),'definition',definition,'modelPreparationId','89400000-0000-4000-8000-000000000021','modelRef',pg_temp.study894_model()),'invalid-save-'||name)->>'code','INVALID_REQUEST','direct RPC save rejects '||name) from study894_definition_vectors where not valid order by name;
select is((select count(*) from private.study_command_receipts where idempotency_key like 'invalid-%'),0::bigint,'invalid direct requests leave no command receipts');
select is((select count(*) from private.study_revisions),2::bigint,'invalid direct creates leave no domain rows');
select is((select revision from private.study_revisions where id=(pg_temp.val('draft')->'data'->'value'->>'revisionId')::uuid),2::bigint,'invalid saves preserve generation');
select is((select definition->>'goal' from private.study_revisions where id=(pg_temp.val('draft')->'data'->'value'->>'revisionId')::uuid),'Changed draft','invalid saves preserve complete content');
create temp table study894_bad_overrides(name text primary key,overrides jsonb);
insert into study894_bad_overrides values
 ('missing-both-two-other-keys','[{"other":"x","unknown":1}]'),
 ('missing-path-two-keys','[{"other":"x","value":1}]'),
 ('missing-value-two-keys','[{"path":"/instances/i/exchanges/e/amount","other":1}]'),
 ('null-path','[{"path":null,"value":1}]'),
 ('null-value','[{"path":"/instances/i/exchanges/e/amount","value":null}]'),
 ('string-value','[{"path":"/instances/i/exchanges/e/amount","value":"1"}]'),
 ('unknown-field','[{"path":"/instances/i/exchanges/e/amount","value":1,"other":1}]'),
 ('wrong-operation','[{"path":"/providers/x","value":1}]'),
 ('non-finite-float64','[{"path":"/instances/i/exchanges/e/amount","value":1e400}]');
select is(pg_temp.study894_cmd(1,'scenario.create',jsonb_build_object('studyRevisionId',pg_temp.val('revision')->'data'->'value'->'revisionId','parentScenarioRevisionId',null,'overrides',overrides),'bad-overrides-'||name)->>'code','INVALID_REQUEST','direct Scenario RPC rejects '||name) from study894_bad_overrides order by name;
select is((select count(*) from private.study_scenarios),1::bigint,'invalid overrides create no Scenario');
select is((select count(*) from private.study_command_receipts where idempotency_key like 'bad-overrides-%'),0::bigint,'invalid overrides create no receipts');
create temp table study894_bad_targets(name text primary key,target jsonb);
insert into study894_bad_targets values
 ('missing-id',jsonb_build_object('type','studyRevision','expectedRevision',2)),
 ('extra-actor',jsonb_build_object('type','studyRevision','id',pg_temp.val('draft')->'data'->'value'->'revisionId','expectedRevision',2,'actorId','forged')),
 ('string-generation',jsonb_build_object('type','studyRevision','id',pg_temp.val('draft')->'data'->'value'->'revisionId','expectedRevision','2')),
 ('fractional-generation',jsonb_build_object('type','studyRevision','id',pg_temp.val('draft')->'data'->'value'->'revisionId','expectedRevision',2.5)),
 ('oversized-generation',jsonb_build_object('type','studyRevision','id',pg_temp.val('draft')->'data'->'value'->'revisionId','expectedRevision',9007199254740992)),
 ('null-generation',jsonb_build_object('type','studyRevision','id',pg_temp.val('draft')->'data'->'value'->'revisionId','expectedRevision',null));
select is(pg_temp.study894_cmd(1,'revision.save',jsonb_build_object('target',target,'definition',pg_temp.study894_definition(),'modelPreparationId','89400000-0000-4000-8000-000000000021','modelRef',pg_temp.study894_model()),'bad-target-'||name)->>'code','INVALID_REQUEST','closed direct RPC target: '||name) from study894_bad_targets order by name;
select is((select count(*) from private.study_command_receipts where idempotency_key like 'bad-target-%'),0::bigint,'invalid nested targets produce no receipt');
select ok((pg_temp.keep('replacement',pg_temp.study894_cmd(1,'revision.save',jsonb_build_object('target',jsonb_build_object('type','studyRevision','id',pg_temp.val('draft')->'data'->'value'->'revisionId','expectedRevision',2),'definition',pg_temp.val('saved')->'data'->'value'->'definition','modelPreparationId','89400000-0000-4000-8000-000000000022','modelRef',(select model_ref from private.study_model_preparations where id='89400000-0000-4000-8000-000000000022'))))->>'ok')::boolean,'save applies another qualified exact preparation/model pair');
select is(pg_temp.val('replacement')->'data'->'value'->>'modelPreparationId','89400000-0000-4000-8000-000000000022','replacement preparation is persisted');
select is(pg_temp.val('replacement')->'data'->'value'->'modelRef'->>'modelRevisionId','scenario-model-894','replacement model reference is persisted');
select is((pg_temp.val('replacement')->'data'->'value'->>'revision')::integer,3,'qualified replacement advances its own CAS generation');
-- W06 admission is simulated only by exact private fixtures here. These are
-- real canonical rows/leases, not a claim that the actor can submit a Run yet.
insert into private.worker_jobs(id,job_kind,worker_queue,requested_by,status,leased_by,lease_token,lease_expires_at,payload_schema_version,payload_json)
select ('89400000-0000-4000-8000-'||lpad((34+i)::text,12,'0'))::uuid,'study.run','solver','89400000-0000-4000-8000-000000000001','running','study894-test',('89400000-0000-4000-8000-'||lpad((44+i)::text,12,'0'))::uuid,clock_timestamp()+interval '1 hour','lca.study-job.v1',jsonb_build_object('studyId','89400000-0000-4000-8000-000000000010','runId','89400000-0000-4000-8000-'||lpad((24+i)::text,12,'0')) from generate_series(0,1)i;
insert into private.study_runs(id,study_id,study_revision_id,scenario_id,preparation_id,input_hash,model_ref,profile_id,calculation_contract_ref,job_id)
select ('89400000-0000-4000-8000-'||lpad((24+i)::text,12,'0'))::uuid,p.study_id,c.study_revision_id,c.id,p.id,p.input_hash,p.model_ref,p.profile_id,p.calculation_contract_ref,('89400000-0000-4000-8000-'||lpad((34+i)::text,12,'0'))::uuid from private.study_scenarios c join private.study_model_preparations p on p.id=c.preparation_id cross join generate_series(0,1)i;
select ok((pg_temp.keep('run-first',pg_temp.study894_qry(1,'run.read','{"runId":"89400000-0000-4000-8000-000000000024"}'))->>'ok')::boolean,'actual persisted Run is recoverable through Study authorization');
select pg_sleep(0.01);
select is(pg_temp.study894_qry(1,'run.read','{"runId":"89400000-0000-4000-8000-000000000024"}')->'data'->'value'->'validity'->'checkedAt',pg_temp.val('run-first')->'data'->'value'->'validity'->'checkedAt','Run read preserves recorded applicability time rather than inventing a new check');
create function pg_temp.study894_run_completion(p_artifact integer default 63) returns jsonb language sql as $$
 select jsonb_build_object('inputHash',repeat('d',64),'calculationContractRef',pg_temp.study894_complete()->'calculationContractRef','resultRef',jsonb_build_object('type','runResult','id','89400000-0000-4000-8000-'||lpad(p_artifact::text,12,'0'),'contentHash',repeat('f',64),'digestScope','artifact_bytes_sha256','byteSize',2,'mediaType','application/json','schemaVersion','lca.study-run-result.v1'),'storageBucket','study-artifacts','storageObjectPath','study/89400000-0000-4000-8000-000000000010/89400000-0000-4000-8000-'||lpad(p_artifact::text,12,'0')||'/result.json')
$$;
select pg_temp.study894_claim(null,null,true);
update private.worker_jobs set lease_expires_at=clock_timestamp()-interval '1 second' where id='89400000-0000-4000-8000-000000000034';
select is(api.svc_study_run_read_input_v1('89400000-0000-4000-8000-000000000024','89400000-0000-4000-8000-000000000034','89400000-0000-4000-8000-000000000044')->>'code','FORBIDDEN','expired actual Run lease cannot retrieve frozen input');
update private.worker_jobs set lease_expires_at=clock_timestamp()+interval '1 hour' where id='89400000-0000-4000-8000-000000000034';
select is(api.svc_study_run_complete_v1('89400000-0000-4000-8000-000000000024','89400000-0000-4000-8000-000000000034','89400000-0000-4000-8000-000000000044',pg_temp.study894_run_completion()||jsonb_build_object('inputHash',repeat('a',64)),'run-finish')->>'code','REFERENCE_MISMATCH','Run completion must bind exact semantic input identity');
select ok(not exists(select 1 from private.study_artifacts where id='89400000-0000-4000-8000-000000000063'),'rejected Run completion creates no artifact metadata');
select ok((api.svc_study_run_complete_v1('89400000-0000-4000-8000-000000000024','89400000-0000-4000-8000-000000000034','89400000-0000-4000-8000-000000000044',pg_temp.study894_run_completion(),'run-finish')->>'ok')::boolean,'real current lease atomically completes Run and installs immutable result');
select is((select status from private.worker_jobs where id='89400000-0000-4000-8000-000000000034'),'completed','Run terminal state uses canonical Worker lifecycle');
select ok((api.svc_study_run_complete_v1('89400000-0000-4000-8000-000000000024','89400000-0000-4000-8000-000000000034','89400000-0000-4000-8000-000000000044',pg_temp.study894_run_completion(),'run-finish')->>'ok')::boolean,'lost Run completion acknowledgement recovers original terminal receipt');
select is(api.svc_study_run_complete_v1('89400000-0000-4000-8000-000000000025','89400000-0000-4000-8000-000000000035','89400000-0000-4000-8000-000000000045',pg_temp.study894_run_completion(64),'run-finish')->>'code','IDEMPOTENCY_CONFLICT','Run completion key cannot be reused for another exact Run/job');
update private.worker_jobs set status='cancelled',lease_token=null,lease_expires_at=null,cancelled_at=clock_timestamp() where id='89400000-0000-4000-8000-000000000035';
select is(api.svc_study_run_complete_v1('89400000-0000-4000-8000-000000000025','89400000-0000-4000-8000-000000000035','89400000-0000-4000-8000-000000000045',pg_temp.study894_run_completion(64),'run-late-result')->>'code','FORBIDDEN','cancelled canonical task fences late Run completion');
select ok((select result_artifact_id is null from private.study_runs where id='89400000-0000-4000-8000-000000000025'),'late completion leaves result unavailable rather than numerical zero');
select ok(not exists(select 1 from private.study_artifacts where id='89400000-0000-4000-8000-000000000064'),'late completion leaves no partial artifact metadata');
-- Fault injection is rolled back by throws_ok's statement subtransaction. The
-- normal façades never disable guards or permit frozen-parent mutation.
create function pg_temp.study894_inject_mixed_cycle() returns void language plpgsql as $$
declare p uuid:=gen_random_uuid(); j uuid:=gen_random_uuid(); sc uuid:=gen_random_uuid(); r1 uuid; r2 uuid; begin
  r1:=(pg_temp.val('revision')->'data'->'value'->>'revisionId')::uuid;
  r2:=(pg_temp.val('draft')->'data'->'value'->>'revisionId')::uuid;
  insert into private.worker_jobs(id,job_kind,worker_queue,requested_by,payload_schema_version,payload_json) values(j,'study.model_prepare','solver','89400000-0000-4000-8000-000000000001','lca.study-job.v1','{}');
  insert into private.study_scenarios(id,study_id,study_revision_id,content_hash,overrides) values(sc,'89400000-0000-4000-8000-000000000010',r2,repeat('a',64),'[]');
  insert into private.study_model_preparations(id,study_id,source,source_document,source_scenario_id,source_study_revision_id,method_refs,profile_id,calculation_contract_ref,job_id)
    values(p,'89400000-0000-4000-8000-000000000010',jsonb_build_object('type','scenarioRevision','scenarioRevisionId',sc,'expectedRevision',1,'contentHash',repeat('a',64)),'{}',sc,r2,pg_temp.study894_definition()->'methodRefs','lca.study-explicit-v1',pg_temp.study894_complete()->'calculationContractRef',j);
  alter table private.study_revisions disable trigger study_revision_immutable;
  update private.study_revisions set preparation_id=p where id=r1;
  perform private.study_assert_provenance('89400000-0000-4000-8000-000000000010');
  raise exception 'cycle guard did not reject';
end $$;
select throws_ok('select pg_temp.study894_inject_mixed_cycle()','P0001','REFERENCE_MISMATCH','mixed R1/preparation/Scenario/R2-parent provenance cycle is rejected');
select is((select count(*) from private.study_revisions),2::bigint,'faulted graph operation leaves revision population unchanged');
select is((select count(*) from private.study_scenarios),1::bigint,'faulted graph operation leaves no Scenario residue');
select ok((select tgenabled='O' from pg_trigger where tgrelid='private.study_revisions'::regclass and tgname='study_revision_immutable'),'fault injection restores actual frozen immutability trigger');
select ok((pg_temp.keep('scenario-child',pg_temp.study894_cmd(1,'scenario.create',jsonb_build_object('studyRevisionId',pg_temp.val('revision')->'data'->'value'->'revisionId','parentScenarioRevisionId',pg_temp.val('scenario')->'data'->'value'->'scenarioRevisionId','overrides','[]'::jsonb)))->>'ok')::boolean,'frozen Scenario parent admits an explicit revision chain');
select is(pg_temp.val('scenario-child')->'data'->'value'->'scenarioId',pg_temp.val('scenario')->'data'->'value'->'scenarioId','Scenario revision chain retains stable alternative identity');
select isnt(pg_temp.val('scenario-child')->'data'->'value'->'scenarioRevisionId',pg_temp.val('scenario')->'data'->'value'->'scenarioRevisionId','child receives a distinct ScenarioRevision identity');
select is(pg_temp.val('scenario-child')->'data'->'value'->'overrides','[]'::jsonb,'child explicit layer replaces rather than implicitly merging parent overrides');
select ok((pg_temp.keep('scenario-alternative',pg_temp.study894_cmd(1,'scenario.create',jsonb_build_object('studyRevisionId',pg_temp.val('revision')->'data'->'value'->'revisionId','parentScenarioRevisionId',null,'overrides',pg_temp.val('scenario')->'data'->'value'->'overrides')))->>'ok')::boolean,'null parent with copied layer creates another alternative');
select isnt(pg_temp.val('scenario-alternative')->'data'->'value'->'scenarioId',pg_temp.val('scenario')->'data'->'value'->'scenarioId','new alternative gets a new stable Scenario identity');

-- A second legitimate same-owner Study needs its own producer bindings; there
-- is no cross-Study shortcut through a shared ModelPreparation/artifact row.
insert into private.worker_jobs(id,job_kind,worker_queue,requested_by,status,payload_schema_version,payload_json)
values('89400000-0000-4000-8000-000000000036','study.source_acquire','solver','89400000-0000-4000-8000-000000000001','completed','lca.study-job.v1','{"studyId":"89400000-0000-4000-8000-000000000011","acquisitionId":"89400000-0000-4000-8000-000000000026"}'),
 ('89400000-0000-4000-8000-000000000037','study.model_prepare','solver','89400000-0000-4000-8000-000000000001','completed','lca.study-job.v1','{"studyId":"89400000-0000-4000-8000-000000000011","preparationId":"89400000-0000-4000-8000-000000000027"}');
insert into private.study_artifacts(id,study_id,ref,bucket,object_path)
select ('89400000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'89400000-0000-4000-8000-000000000011',jsonb_set(a.ref,'{id}',to_jsonb('89400000-0000-4000-8000-'||lpad(n::text,12,'0'))),'study-artifacts','study/89400000-0000-4000-8000-000000000011/89400000-0000-4000-8000-'||lpad(n::text,12,'0')||case when n=65 then '/source.zip' else '/input.json' end
from (values(65,'89400000-0000-4000-8000-000000000060'::uuid),(66,'89400000-0000-4000-8000-000000000061'::uuid)) t(n,old_id) join private.study_artifacts a on a.id=t.old_id;
insert into private.study_source_acquisitions(id,study_id,origin_ref,requested_by,job_id)
select '89400000-0000-4000-8000-000000000026','89400000-0000-4000-8000-000000000011',origin_ref,requested_by,'89400000-0000-4000-8000-000000000036' from private.study_source_acquisitions where id='89400000-0000-4000-8000-000000000020';
insert into private.study_source_snapshots(id,study_id,acquisition_id,origin_ref,artifact_id,license_ref,issuer_id,observed_at,source_authorization)
select '89400000-0000-4000-8000-000000000056','89400000-0000-4000-8000-000000000011','89400000-0000-4000-8000-000000000026',origin_ref,'89400000-0000-4000-8000-000000000065',license_ref,issuer_id,observed_at,source_authorization from private.study_source_snapshots where id='89400000-0000-4000-8000-000000000050';
update private.study_source_acquisitions set snapshot_id='89400000-0000-4000-8000-000000000056' where id='89400000-0000-4000-8000-000000000026';
insert into private.study_model_preparations(id,study_id,source,source_document,source_snapshot_id,method_refs,profile_id,calculation_contract_ref,job_id,model_ref,input_artifact_id)
select '89400000-0000-4000-8000-000000000027','89400000-0000-4000-8000-000000000011',jsonb_set(source,'{snapshotId}','"89400000-0000-4000-8000-000000000056"'),source_document,'89400000-0000-4000-8000-000000000056',method_refs,profile_id,calculation_contract_ref,'89400000-0000-4000-8000-000000000037',model_ref,'89400000-0000-4000-8000-000000000066' from private.study_model_preparations where id='89400000-0000-4000-8000-000000000021';
select ok((pg_temp.keep('foreign-revision',pg_temp.study894_cmd(1,'revision.create',jsonb_build_object('studyId','89400000-0000-4000-8000-000000000011','parentRevisionId',null,'definition',pg_temp.study894_definition(),'modelPreparationId','89400000-0000-4000-8000-000000000027','modelRef',pg_temp.study894_model())))->>'ok')::boolean,'foreign Study uses its own exact prepared bindings');
select ok((pg_temp.keep('foreign-intent',pg_temp.study894_cmd(1,'revision.freeze',jsonb_build_object('target',jsonb_build_object('type','studyRevision','id',pg_temp.val('foreign-revision')->'data'->'value'->'revisionId','expectedRevision',1),'expectedContentHash',pg_temp.val('foreign-revision')->'data'->'value'->'contentHash')))->>'ok')::boolean,'foreign Study issues its own authorized freeze intent');
select pg_temp.study894_claim(null,null,true);
select ok((api.svc_study_revision_freeze_consume_v1((pg_temp.val('foreign-intent')->'data'->>'intentId')::uuid,'passed')->>'ok')::boolean,'foreign Study definition is frozen through the same service seam');
select is(pg_temp.study894_cmd(1,'scenario.create',jsonb_build_object('studyRevisionId',pg_temp.val('foreign-revision')->'data'->'value'->'revisionId','parentScenarioRevisionId',pg_temp.val('scenario')->'data'->'value'->'scenarioRevisionId','overrides','[]'::jsonb),'cross-study-scenario-parent')->>'code','REFERENCE_MISMATCH','even the common owner cannot attach a frozen Scenario parent from another Study');
select is((select count(*) from private.study_scenarios where study_id='89400000-0000-4000-8000-000000000011'),0::bigint,'cross-Study parent rejection leaves no child row');
select ok(not exists(select 1 from private.study_command_receipts where idempotency_key='cross-study-scenario-parent'),'cross-Study parent rejection leaves no receipt');
-- Legitimate shared-parent history has two routes to each predecessor:
-- s_i -> parent s_(i-1), and s_i -> prep_i -> captured parent s_(i-1).
-- Materializing every path is exponential; the production helper must dedup
-- reachability pairs while retaining both edges and genuine cycle detection.
create function pg_temp.study894_shared_parent_history(p_layers integer) returns integer language plpgsql as $$
declare parent_id uuid:=(pg_temp.val('scenario')->'data'->'value'->>'scenarioRevisionId')::uuid;
  base_revision uuid:=(pg_temp.val('revision')->'data'->'value'->>'revisionId')::uuid;
  response jsonb; scene jsonb; prep uuid; job uuid; token uuid; artifact uuid; completion jsonb; n integer;
begin
  for n in 1..p_layers loop
    response:=pg_temp.study894_cmd(1,'scenario.create',jsonb_build_object('studyRevisionId',base_revision,'parentScenarioRevisionId',parent_id,'overrides',jsonb_build_array(jsonb_build_object('path','/instances/i/exchanges/e/amount','value',n))));
    if response->>'ok'<>'true' then raise exception 'shared history create failed'; end if;
    scene:=response->'data'->'value'; prep:=gen_random_uuid(); job:=gen_random_uuid(); token:=gen_random_uuid(); artifact:=gen_random_uuid();
    insert into private.worker_jobs(id,job_kind,worker_queue,requested_by,status,leased_by,lease_token,lease_expires_at,payload_schema_version,payload_json)
      values(job,'study.model_prepare','solver','89400000-0000-4000-8000-000000000001','running','study894-depth-test',token,clock_timestamp()+interval '1 hour','lca.study-job.v1',jsonb_build_object('studyId','89400000-0000-4000-8000-000000000010','preparationId',prep));
    insert into private.study_model_preparations(id,study_id,source,source_document,source_scenario_id,source_study_revision_id,source_parent_scenario_id,method_refs,profile_id,calculation_contract_ref,job_id)
      values(prep,'89400000-0000-4000-8000-000000000010',jsonb_build_object('type','scenarioRevision','scenarioRevisionId',scene->>'scenarioRevisionId','expectedRevision',1,'contentHash',scene->>'contentHash'),'{"syntheticFixture":true}',(scene->>'scenarioRevisionId')::uuid,base_revision,parent_id,pg_temp.study894_definition()->'methodRefs','lca.study-explicit-v1',pg_temp.study894_complete()->'calculationContractRef',job);
    completion:=jsonb_set(pg_temp.study894_complete(),'{inputArtifactRef,id}',to_jsonb(artifact::text))||jsonb_build_object('inputHash',encode(extensions.digest('depth-fixture-'||n,'sha256'),'hex'),'storageObjectPath','study/89400000-0000-4000-8000-000000000010/'||artifact::text||'/input.json');
    perform pg_temp.study894_claim(null,null,true);
    response:=api.svc_study_model_preparation_complete_v1(prep,job,token,completion,'depth-complete-'||n);
    if response->>'ok'<>'true' then raise exception 'shared history producer failed'; end if;
    response:=pg_temp.study894_cmd(1,'scenario.freeze',jsonb_build_object('target',jsonb_build_object('type','scenarioRevision','id',scene->>'scenarioRevisionId','expectedRevision',1),'expectedContentHash',scene->>'contentHash','modelPreparationId',prep));
    if response->>'ok'<>'true' then raise exception 'shared history freeze failed'; end if;
    parent_id:=(scene->>'scenarioRevisionId')::uuid;
  end loop;
  return p_layers;
end $$;
set local statement_timeout='15s';
select is(pg_temp.study894_shared_parent_history(40),40,'40-layer valid frozen Scenario history completes with deduplicated shared-parent reachability');
set local statement_timeout=0;
select is((select count(*) from private.study_scenarios where study_id='89400000-0000-4000-8000-000000000010' and status='frozen'),41::bigint,'all forty descendants and original frozen parent retain valid domain state');
select throws_ok('select pg_temp.study894_inject_mixed_cycle()','P0001','REFERENCE_MISMATCH','genuine mixed cycle is still rejected after deep legitimate shared history');
select is((select count(*) from private.study_scenarios where study_id='89400000-0000-4000-8000-000000000010'),43::bigint,'deep-history cycle rejection leaves no partial Scenario node');
select ok((select tgenabled='O' from pg_trigger where tgrelid='private.study_revisions'::regclass and tgname='study_revision_immutable'),'deep-history cycle fault rolls back trigger mutation');
select * from finish();
rollback;
