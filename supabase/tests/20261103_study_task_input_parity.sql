begin;
create extension if not exists pgtap with schema extensions;
set local search_path=extensions,public,api,private,pg_temp;
select no_plan();
\ir fixtures/study894_runtime_fixture.sql
-- Real actor/service facades and queue; numerical metadata is a SQL fixture.
create temp table study895_parity(k text primary key,v jsonb);
create function pg_temp.keep(k text,v jsonb) returns jsonb language plpgsql as $$begin insert into study895_parity values(k,v);return v;end$$;
create function pg_temp.val(k text) returns jsonb language sql as $$select v from study895_parity where study895_parity.k=$1$$;
select pg_temp.study894_claim(null,null,true);
select ok((api.svc_study_model_preparation_complete_v1('89400000-0000-4000-8000-000000000021','89400000-0000-4000-8000-000000000031','89400000-0000-4000-8000-000000000041',pg_temp.study894_complete(),'parity-base')->>'ok')::boolean,'prepare the bound SQL fixture');
select pg_temp.keep('revision',pg_temp.study894_cmd(1,'revision.create',jsonb_build_object('studyId','89400000-0000-4000-8000-000000000010','parentRevisionId',null,'definition',pg_temp.study894_definition(),'modelPreparationId','89400000-0000-4000-8000-000000000021','modelRef',pg_temp.study894_model())));
select pg_temp.keep('intent',pg_temp.study894_cmd(1,'revision.freeze',jsonb_build_object('target',jsonb_build_object('type','studyRevision','id',pg_temp.val('revision')->'data'->'value'->'revisionId','expectedRevision',1),'expectedContentHash',pg_temp.val('revision')->'data'->'value'->'contentHash')));
select pg_temp.study894_claim(null,null,true);
select ok((api.svc_study_revision_freeze_consume_v1((pg_temp.val('intent')->'data'->>'intentId')::uuid,'passed')->>'ok')::boolean,'freeze the exact fixture revision');
select pg_temp.keep('scenario',pg_temp.study894_cmd(1,'scenario.create',jsonb_build_object('studyRevisionId',pg_temp.val('revision')->'data'->'value'->'revisionId','parentScenarioRevisionId',null,'overrides','[]'::jsonb)));
update private.study_runtime_config set compute_enabled=true,method_refs=pg_temp.study894_definition()->'methodRefs' where singleton;
create function pg_temp.prepare(p_generation jsonb) returns jsonb language sql as $$
 select pg_temp.study894_cmd(1,'model.prepare',jsonb_build_object(
 'studyId','89400000-0000-4000-8000-000000000010',
 'source',jsonb_build_object('type','scenarioRevision','scenarioRevisionId',pg_temp.val('scenario')->'data'->'value'->'scenarioRevisionId','expectedRevision',p_generation,'contentHash',pg_temp.val('scenario')->'data'->'value'->'contentHash'),
 'profileId','lca.study-explicit-v1','calculationContractRef',pg_temp.study894_complete()->'calculationContractRef'))
$$;
create temp table invalid_generations(name text,value jsonb);
insert into invalid_generations values ('string','"1"'),('boolean','true'),('null','null'),('fraction','1.5'),('zero','0'),('negative','-1'),('unsafe','9007199254740992'),('object','{}'),('array','[1]');
savepoint invalid_generation;
select is(pg_temp.prepare(value)->>'code','INVALID_REQUEST','direct actor rejects generation '||name) from invalid_generations order by name;
select is((select count(*) from private.study_model_preparations where source_scenario_id=(pg_temp.val('scenario')->'data'->'value'->>'scenarioRevisionId')::uuid),0::bigint,'invalid types create no unprojectable preparation');
rollback to savepoint invalid_generation;
select ok((pg_temp.keep('integer',pg_temp.prepare('1'))->>'ok')::boolean,'valid numeric generation is admitted');
select ok((pg_temp.keep('decimal-integer',pg_temp.prepare('1.0'))->>'ok')::boolean,'numeric integral spelling has the same generation semantics');
select is(pg_temp.val('decimal-integer')->'data'->'value'->'source'->>'expectedRevision','1','persisted integral generation is canonical for typed consumers');
select is(pg_temp.val('integer')->'data'->'value'->'source',pg_temp.val('decimal-integer')->'data'->'value'->'source','equivalent numeric generations preserve exact freeze source identity');
-- Numeric-looking UUIDs still have string type in the public contract.
savepoint invalid_source_reference;
update private.study_runtime_config set source_enabled=true where singleton;
select is(pg_temp.study894_cmd(1,'model.source.resolve',jsonb_build_object(
 'studyId','89400000-0000-4000-8000-000000000010','originRef',
 jsonb_build_object('type','datasetRevision','datasetType','lifecyclemodel',
 'id',89400000000040008000000000000101::numeric,'version','01.00.000')))->>'code',
 'INVALID_REQUEST','raw numeric origin UUID cannot persist an unprojectable source');
select is(pg_temp.study894_cmd(1,'model.prepare',jsonb_build_object(
 'studyId','89400000-0000-4000-8000-000000000010','source',
 jsonb_build_object('type','modelSourceSnapshot','snapshotId',89400000000040008000000000000050::numeric,
 'contentHash',repeat('a',64),'digestScope','artifact_bytes_sha256'),
 'profileId','lca.study-explicit-v1','calculationContractRef',pg_temp.study894_complete()->'calculationContractRef',
 'methodRefs',pg_temp.study894_definition()->'methodRefs'))->>'code',
 'INVALID_REQUEST','raw numeric snapshot UUID cannot persist an unprojectable preparation');
rollback to savepoint invalid_source_reference;
select pg_temp.study894_claim(null,null,true);
select set_config('app.study.task_context','',true);
update private.study_runtime_config set source_enabled=false,compute_enabled=false,disclosure_enabled=false where singleton;
select is(api.svc_worker_enqueue_job(p_job_kind=>kind,p_payload_json=>'{}',p_requested_by=>'89400000-0000-4000-8000-000000000001')->>'code','STUDY_SCOPED_ROUTE_REQUIRED','generic service rejects normalized Study kind '||kind)
from (values('study.source_acquire'),(' STUDY.SOURCE_ACQUIRE '),('Study.Model_Prepare'),(' study.model_prepare '),('study.run'),(' STUDY.RUN ')) v(kind);
select ok((api.svc_worker_enqueue_job(p_job_kind=>' LCA.SOLVE_ONE ',p_payload_json=>'{}',p_requested_by=>'89400000-0000-4000-8000-000000000001')->>'ok')::boolean,'ordinary canonical non-Study enqueue remains supported');
select * from finish();
rollback;
