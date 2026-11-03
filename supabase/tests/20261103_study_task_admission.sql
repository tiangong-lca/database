begin;
create extension if not exists pgtap with schema extensions;
set local search_path=extensions,public,api,private,pg_temp;
select no_plan();
update private.study_runtime_config set source_enabled=false,compute_enabled=false,disclosure_enabled=false where singleton;
-- Suppress only unrelated outbound fixture webhooks; all real source writers,
-- RLS, command authorization and canonical queue/lease routines remain active.
create or replace function util.invoke_edge_function(name text,body jsonb,timeout_milliseconds integer default 300000) returns void
language plpgsql security definer set search_path='' as $$begin return;end$$;
\ir fixtures/study895_source_rows.sql
create temp table study895_results(k text primary key,v jsonb);
create function pg_temp.keep(k text,v jsonb) returns jsonb language plpgsql as $$ begin insert into study895_results values(k,v); return v; end $$;
create function pg_temp.val(k text) returns jsonb language sql as $$ select v from study895_results where study895_results.k=$1 $$;
select pg_temp.study895_claim();
select ok((pg_temp.keep('study',api.cmd_study_v1(pg_temp.study895_request('study.create','{"scope":{"kind":"personal"},"title":"Owned Study895"}','study895-create')))->>'ok')::boolean,'core Study create still works through private delegation');
select is(api.cmd_study_v1(pg_temp.study895_request('model.source.resolve',jsonb_build_object('studyId',pg_temp.val('study')->'data'->'value'->'studyId','originRef',jsonb_build_object('type','datasetRevision','datasetType','lifecyclemodel','id','89500000-0000-4000-8000-000000000101','version','01.00.000')),'source-off'))->>'code','CAPABILITY_UNAVAILABLE','code installation does not activate the source producer');
select is((select count(*) from private.study_source_acquisitions where study_id=(pg_temp.val('study')->'data'->'value'->>'studyId')::uuid),0::bigint,'unavailable producer creates no placeholder acquisition');
update private.study_runtime_config set source_enabled=true where singleton;
savepoint oversized_owned_source;
update public.lifecyclemodels set json_ordered=jsonb_set(json_ordered::jsonb,'{ownedOversizePadding}',to_jsonb(repeat('x',4194304)))::json where id='89500000-0000-4000-8000-000000000101';
select is(api.cmd_study_v1(pg_temp.study895_request('model.source.resolve',jsonb_build_object('studyId',pg_temp.val('study')->'data'->'value'->'studyId','originRef',jsonb_build_object('type','datasetRevision','datasetType','lifecyclemodel','id','89500000-0000-4000-8000-000000000101','version','01.00.000')),'source-oversize895'))->>'code','CAPABILITY_UNAVAILABLE','an oversized actual source row is rejected before JSON projection or hashing');
select ok(not exists(select 1 from private.study_command_receipts where idempotency_key='source-oversize895'),'oversized source admission leaves no receipt or replacement authority');
rollback to savepoint oversized_owned_source;

select ok((pg_temp.keep('acquisition',api.cmd_study_v1(pg_temp.study895_request('model.source.resolve',jsonb_build_object('studyId',pg_temp.val('study')->'data'->'value'->'studyId','originRef',jsonb_build_object('type','datasetRevision','datasetType','lifecyclemodel','id','89500000-0000-4000-8000-000000000101','version','01.00.000')),'source895')))->>'ok')::boolean,'authorized exact origin admits a canonical source task');
select is(api.cmd_study_v1(pg_temp.study895_request('model.source.resolve',jsonb_build_object('studyId',pg_temp.val('study')->'data'->'value'->'studyId','originRef',jsonb_build_object('type','datasetRevision','datasetType','lifecyclemodel','id','89500000-0000-4000-8000-000000000101','version','01.00.000')),'source895')),pg_temp.val('acquisition'),'response-loss retry recovers exact acquisition and job');
select is((select count(*) from private.worker_jobs where payload_json->>'studyId'=pg_temp.val('study')->'data'->'value'->>'studyId'),1::bigint,'duplicate submission produces one canonical job');
select pg_temp.study895_claim(null,true);
select is(private.worker_enqueue_job('study.source_acquire','{}')->>'code','STUDY_SCOPED_ROUTE_REQUIRED','generic enqueue cannot create an unbound Study job');
select ok((pg_temp.keep('claim',private.worker_claim_jobs('solver','study895-sql',1,900))->>'ok')::boolean,'trusted Worker canonical claim remains available');
select is(private.worker_read_job((pg_temp.val('claim')->'data'->0->>'id')::uuid,false)->>'code','STUDY_SCOPED_ROUTE_REQUIRED','generic requester read cannot bypass Study authorization');
select is(private.worker_record_job_result((pg_temp.val('claim')->'data'->0->>'id')::uuid,(pg_temp.val('claim')->'data'->0->>'leaseToken')::uuid,'failed')->>'code','STUDY_SCOPED_ROUTE_REQUIRED','generic result/error route cannot bypass scoped completion');
select ok((pg_temp.keep('packet',api.svc_study_source_acquisition_read_input_v1((pg_temp.val('acquisition')->'data'->'value'->>'acquisitionId')::uuid,(pg_temp.val('claim')->'data'->0->>'id')::uuid,(pg_temp.val('claim')->'data'->0->>'leaseToken')::uuid))->>'ok')::boolean,'leased source read resolves actual actor-visible rows');
select is(jsonb_array_length(pg_temp.val('packet')->'data'->'sourcePacket'->'source'->'documents'),5,'exact bounded closure contains model, Process, Flow and two unit supports');
select ok(not exists(select 1 from jsonb_array_elements(pg_temp.val('packet')->'data'->'sourcePacket'->'source'->'documents')d where d->>'sha256'<>encode(extensions.digest(convert_to(d->>'json','UTF8'),'sha256'),'hex')),'per-document digest binds exact stored UTF8 text');
select is(pg_temp.val('packet')->'data'->'sourcePacket'->'source'->'methodRefs','[]'::jsonb,'source acquisition does not invent a method selection');
select is(api.svc_study_source_acquisition_read_input_v1((pg_temp.val('acquisition')->'data'->'value'->>'acquisitionId')::uuid,(pg_temp.val('claim')->'data'->0->>'id')::uuid,gen_random_uuid())->>'code','FORBIDDEN','foreign lease cannot obtain private source data');
update public.lifecyclemodels set json_ordered=jsonb_set(json_ordered::jsonb,'{taskOwnedChange}','true')::json where id='89500000-0000-4000-8000-000000000101';
select is(api.svc_study_source_acquisition_read_input_v1((pg_temp.val('acquisition')->'data'->'value'->>'acquisitionId')::uuid,(pg_temp.val('claim')->'data'->0->>'id')::uuid,(pg_temp.val('claim')->'data'->0->>'leaseToken')::uuid)->'data'->'sourcePacket',pg_temp.val('packet')->'data'->'sourcePacket','retry returns the first immutable capture rather than later draft bytes');
select lives_ok(format('select private.study_source_rights(%L::jsonb,%L::uuid,null)',pg_temp.val('packet')->'data'->'sourcePacket'->'sourceAuthorization'->'sourceScope','89500000-0000-4000-8000-000000000001'),'captured owner retains old own draft bytes while current ownership remains');
-- Published rows are immutable through the normal writer. Ownership loss is
-- tested on an actual private draft before its publication transition.
savepoint study895_owner_loss;
update public.lifecyclemodels set user_id='89500000-0000-4000-8000-000000000002' where id='89500000-0000-4000-8000-000000000101';
select throws_ok(format('select private.study_source_rights(%L::jsonb,%L::uuid,null)',pg_temp.val('packet')->'data'->'sourcePacket'->'sourceAuthorization'->'sourceScope','89500000-0000-4000-8000-000000000001'),'P0001','DISCLOSURE_DENIED','captured private owner loses history access after current ownership loss');
rollback to savepoint study895_owner_loss;
update public.lifecyclemodels set state_code=100 where id='89500000-0000-4000-8000-000000000101';
select throws_ok(format('select private.study_source_rights(%L::jsonb,%L::uuid,null)',pg_temp.val('packet')->'data'->'sourcePacket'->'sourceAuthorization'->'sourceScope','89500000-0000-4000-8000-000000000002'),'P0001','DISCLOSURE_DENIED','private X edited and published as Y never exposes captured X to another reader');
select ok((pg_temp.keep('public-packet',jsonb_build_object('scope',jsonb_build_array(private.study_source_document('process','89500000-0000-4000-8000-000000000102','01.00.000','89500000-0000-4000-8000-000000000001',null))))->'scope') is not null,'capture actual public byte observation');
-- A reviewed administrative content correction can change an approved row;
-- that exceptional authority must not retroactively grant old byte access.
select set_config('app.review_controlled_write','on',true);
update public.processes set json_ordered=jsonb_set(json_ordered::jsonb,'{taskOwnedChange}','true')::json where id='89500000-0000-4000-8000-000000000102';
select set_config('app.review_controlled_write','',true);
select throws_ok(format('select private.study_source_rights(%L::jsonb,%L::uuid,null)',pg_temp.val('public-packet')->'scope','89500000-0000-4000-8000-000000000002'),'P0001','DISCLOSURE_DENIED','public X changed to public Y does not retroactively qualify historical X for another reader');
select ok(not has_table_privilege('authenticated','private.study_artifact_read_intents','SELECT'),'artifact read intents are raw-ACL closed');
select ok(not has_function_privilege('authenticated','api.svc_study_artifact_read_resolve_v1(uuid)','EXECUTE'),'only the service resolves a locator after live authorization');
select is((select public from storage.buckets where id='study-artifacts'),false,'Study artifact bucket is private');
select ok(exists(select 1 from pg_policy where polname='study_artifacts_raw_closed' and not polpermissive),'restrictive policy closes raw storage access independently of permissive policies');
select pg_temp.study895_claim();
select is(api.cmd_study_v1(pg_temp.study895_request('run.cancel',jsonb_build_object('runId','89500000-0000-4000-8000-000000009999','reason','No such owned Run'),'missing-run-cancel895'))->>'code','FORBIDDEN','Run lookup qualifies its id column and fails closed for a missing resource');
select ok(not exists(select 1 from private.study_command_receipts where idempotency_key='missing-run-cancel895'),'unknown Run cancellation creates no receipt');
-- Scoped control uses current Study rights and fences the actual canonical lease.
select pg_temp.study895_claim();
select ok((api.qry_study_v1(pg_temp.study895_request('task.read',jsonb_build_object('studyId',pg_temp.val('study')->'data'->'value'->'studyId','resource',jsonb_build_object('type','modelSourceAcquisition','id',pg_temp.val('acquisition')->'data'->'value'->'acquisitionId'))))->>'ok')::boolean,'scoped owner reads the current canonical task state');
select pg_temp.study895_claim(2);
select is(api.qry_study_v1(pg_temp.study895_request('task.read',jsonb_build_object('studyId',pg_temp.val('study')->'data'->'value'->'studyId','resource',jsonb_build_object('type','modelSourceAcquisition','id',pg_temp.val('acquisition')->'data'->'value'->'acquisitionId'))))->>'code','FORBIDDEN','resource identity is not task-read permission');
select pg_temp.study895_claim();
select ok((pg_temp.keep('cancelled',api.cmd_study_v1(pg_temp.study895_request('task.cancel',jsonb_build_object('studyId',pg_temp.val('study')->'data'->'value'->'studyId','resource',jsonb_build_object('type','modelSourceAcquisition','id',pg_temp.val('acquisition')->'data'->'value'->'acquisitionId'),'reason','Owned SQL cancellation'),'cancel895')))->>'ok')::boolean,'scoped cancellation reaches the existing canonical arbiter');
select is(api.cmd_study_v1(pg_temp.study895_request('task.cancel',jsonb_build_object('studyId',pg_temp.val('study')->'data'->'value'->'studyId','resource',jsonb_build_object('type','modelSourceAcquisition','id',pg_temp.val('acquisition')->'data'->'value'->'acquisitionId'),'reason','Owned SQL cancellation'),'cancel895')),pg_temp.val('cancelled'),'lost cancellation acknowledgement recovers the exact receipt');
select is((select status from private.worker_jobs where id=(pg_temp.val('claim')->'data'->0->>'id')::uuid),'cancelled','cancellation terminalizes the same canonical task');
select ok((select lease_token is null and lease_expires_at is null from private.worker_jobs where id=(pg_temp.val('claim')->'data'->0->>'id')::uuid),'cancellation clears current lease authority atomically');
select pg_temp.study895_claim(null,true);
select is(api.svc_study_source_acquisition_read_input_v1((pg_temp.val('acquisition')->'data'->'value'->>'acquisitionId')::uuid,(pg_temp.val('claim')->'data'->0->>'id')::uuid,(pg_temp.val('claim')->'data'->0->>'leaseToken')::uuid)->>'code','FORBIDDEN','late leased input read cannot cross cancellation');
select is(api.svc_study_task_fail_v1('modelSourceAcquisition',(pg_temp.val('acquisition')->'data'->'value'->>'acquisitionId')::uuid,(pg_temp.val('claim')->'data'->0->>'id')::uuid,(pg_temp.val('claim')->'data'->0->>'leaseToken')::uuid,'arbitrary-secret-error','fail895')->>'code','INVALID_REQUEST','service diagnostics cannot inject arbitrary error strings');
select is(api.svc_study_task_fail_v1('modelSourceAcquisition',(pg_temp.val('acquisition')->'data'->'value'->>'acquisitionId')::uuid,(pg_temp.val('claim')->'data'->0->>'id')::uuid,(pg_temp.val('claim')->'data'->0->>'leaseToken')::uuid,'runtime_failed','fail895')->>'code','FORBIDDEN','late failure cannot replace terminal cancellation');
select is(api.svc_study_task_reconcile_v1('modelSourceAcquisition',(pg_temp.val('acquisition')->'data'->'value'->>'acquisitionId')::uuid,(pg_temp.val('claim')->'data'->0->>'id')::uuid,(pg_temp.val('claim')->'data'->0->>'leaseToken')::uuid,'no-callback895',gen_random_uuid())->'data'->>'state','unreferenced','historical claimed lease can prove a terminal unreferenced upload candidate');
select is(api.svc_study_task_reconcile_v1('modelSourceAcquisition',(pg_temp.val('acquisition')->'data'->'value'->>'acquisitionId')::uuid,(pg_temp.val('claim')->'data'->0->>'id')::uuid,gen_random_uuid(),'no-callback895',gen_random_uuid())->>'code','FORBIDDEN','unknown historical lease cannot prove artifact cleanup authority');
select * from finish();
rollback;
