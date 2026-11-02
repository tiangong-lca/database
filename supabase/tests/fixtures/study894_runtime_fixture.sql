-- Synthetic authorized producer/queue evidence, NEVER runtime qualification.
-- Caller owns BEGIN/ROLLBACK or an isolated-project reset after committed races.
insert into auth.users(id,instance_id,aud,role,email,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
select ('89400000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','study894-'||i||'@invalid.test','{}','{}',now(),now() from generate_series(1,3)i;
insert into private.users(id,raw_user_meta_data,contact)
select ('89400000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,'{}',null from generate_series(1,3)i on conflict(id) do nothing;
insert into private.teams(id,json,rank,is_public) values('89400000-0000-4000-8000-000000000100','{"name":"Study894 isolated fixture"}',0,false);
insert into private.roles(user_id,team_id,role) values
 ('89400000-0000-4000-8000-000000000001','89400000-0000-4000-8000-000000000100','owner'),
 ('89400000-0000-4000-8000-000000000002','89400000-0000-4000-8000-000000000100','member');
insert into private.studies(id,owner_id,title) values('89400000-0000-4000-8000-000000000010','89400000-0000-4000-8000-000000000001','Fixture personal Study');
insert into private.studies(id,owner_id,team_id,title) values('89400000-0000-4000-8000-000000000011','89400000-0000-4000-8000-000000000001','89400000-0000-4000-8000-000000000100','Fixture team Study');
insert into private.study_members values
 ('89400000-0000-4000-8000-000000000010','89400000-0000-4000-8000-000000000001','owner'),
 ('89400000-0000-4000-8000-000000000011','89400000-0000-4000-8000-000000000001','owner');
insert into private.lca_calculation_contracts(fingerprint,descriptor) values(encode(extensions.digest('{"schema":"study894-test-only"}','sha256'),'hex'),'{"schema":"study894-test-only"}');
insert into private.study_profiles values('lca.study-explicit-v1',encode(extensions.digest('{"schema":"study894-test-only"}','sha256'),'hex'),true);
insert into private.worker_job_kinds(job_kind,worker_queue,payload_schema_version,result_schema_version,description)
 values('study.source_acquire','solver','lca.study-job.v1','lca.study-job-receipt.v1','TEST fixture only; not producer qualification'),
 ('study.model_prepare','solver','lca.study-job.v1','lca.study-job-receipt.v1','TEST fixture only; not compiler qualification'),
 ('study.run','solver','lca.study-job.v1','lca.study-job-receipt.v1','TEST fixture only; not solver qualification');
insert into private.worker_jobs(id,job_kind,worker_queue,requested_by,status,leased_by,lease_token,lease_expires_at,payload_schema_version,payload_json)
values
 ('89400000-0000-4000-8000-000000000030','study.source_acquire','solver','89400000-0000-4000-8000-000000000001','running','study894-test','89400000-0000-4000-8000-000000000040',clock_timestamp()+interval '1 hour','lca.study-job.v1','{"studyId":"89400000-0000-4000-8000-000000000010","acquisitionId":"89400000-0000-4000-8000-000000000020"}'),
 ('89400000-0000-4000-8000-000000000031','study.model_prepare','solver','89400000-0000-4000-8000-000000000001','running','study894-test','89400000-0000-4000-8000-000000000041',clock_timestamp()+interval '1 hour','lca.study-job.v1','{"studyId":"89400000-0000-4000-8000-000000000010","preparationId":"89400000-0000-4000-8000-000000000021"}');
insert into private.study_source_acquisitions(id,study_id,origin_ref,requested_by,job_id)
values('89400000-0000-4000-8000-000000000020','89400000-0000-4000-8000-000000000010','{"type":"datasetRevision","datasetType":"lifecyclemodel","id":"source-model","version":"01.00.000"}','89400000-0000-4000-8000-000000000001','89400000-0000-4000-8000-000000000030');

create function pg_temp.study894_claim(p_actor integer,p_client text default null,p_service boolean default false) returns void
language plpgsql as $$ begin
  perform set_config('request.jwt.claim.role','',true);
  perform set_config('request.jwt.claim.sub','',true);
  perform set_config('request.jwt.claims',jsonb_strip_nulls(jsonb_build_object('role',case when p_service then 'service_role' else 'authenticated' end,'sub',case when p_actor is null then null else '89400000-0000-4000-8000-'||lpad(p_actor::text,12,'0') end,'client_id',p_client))::text,true);
end $$;
create function pg_temp.study894_cmd(p_actor integer,p_op text,p_fields jsonb,p_key text default null,p_client text default null) returns jsonb language plpgsql as $$ begin
  perform pg_temp.study894_claim(p_actor,p_client);
  return api.cmd_study_v1(jsonb_build_object('schemaVersion','lca.study-api.v2','requestId',gen_random_uuid(),'idempotencyKey',coalesce(p_key,gen_random_uuid()::text),'operation',p_op)||p_fields);
end $$;
create function pg_temp.study894_qry(p_actor integer,p_op text,p_fields jsonb,p_client text default null) returns jsonb language plpgsql as $$ begin
  perform pg_temp.study894_claim(p_actor,p_client);
  return api.qry_study_v1(jsonb_build_object('schemaVersion','lca.study-api.v2','requestId',gen_random_uuid(),'operation',p_op)||p_fields);
end $$;
create function pg_temp.study894_definition() returns jsonb language sql as $$ select '{"goal":"Synthetic test only","functionalUnit":{"amount":"1","unit":"kg","referenceFlowId":"flow-1"},"systemBoundary":"explicit tested links only","methodRefs":[{"type":"datasetRevision","datasetType":"lciamethod","id":"method-1","version":"01.00.000"}],"assumptions":[]}'::jsonb $$;
create function pg_temp.study894_model() returns jsonb language sql as $$ select jsonb_build_object('type','modelRevision','modelRevisionId','model-894','contentHash',repeat('b',64),'digestScope','worker_prepared_model') $$;
create function pg_temp.study894_complete() returns jsonb language sql as $$ select jsonb_build_object('modelRef',pg_temp.study894_model(),'profileId','lca.study-explicit-v1','calculationContractRef',jsonb_build_object('kind','calculation_contract','schema','lca.calculation-contract.v1','sha256',encode(extensions.digest('{"schema":"study894-test-only"}','sha256'),'hex')),'inputArtifactRef',jsonb_build_object('type','modelInput','id','89400000-0000-4000-8000-000000000061','contentHash',repeat('c',64),'digestScope','artifact_bytes_sha256','byteSize',2,'mediaType','application/json','schemaVersion','lca.study-prepared-input.v1'),'inputHash',null,'storageBucket','study-artifacts','storageObjectPath','study/89400000-0000-4000-8000-000000000010/89400000-0000-4000-8000-000000000061/input.json') $$;

do $$ declare response jsonb; begin
  perform pg_temp.study894_claim(null,null,true);
  response:=api.svc_study_source_record_v1('89400000-0000-4000-8000-000000000020','89400000-0000-4000-8000-000000000030','89400000-0000-4000-8000-000000000040',jsonb_build_object(
    'snapshotId','89400000-0000-4000-8000-000000000050','originRef','{"type":"datasetRevision","datasetType":"lifecyclemodel","id":"source-model","version":"01.00.000"}'::jsonb,
    'sourceArtifactRef',jsonb_build_object('type','modelSource','id','89400000-0000-4000-8000-000000000060','contentHash',repeat('a',64),'digestScope','artifact_bytes_sha256','byteSize',2,'mediaType','application/zip','schemaVersion','tidas-package.v1'),
    'licenseRef','test-only-license','issuerId','test-only-exporter','observedAt','2026-11-03T00:00:00Z',
    'sourceAuthorization',jsonb_build_object('schemaVersion','lca.study-source-authorization.v1','requestedBy','89400000-0000-4000-8000-000000000001','originRef','{"type":"datasetRevision","datasetType":"lifecyclemodel","id":"source-model","version":"01.00.000"}'::jsonb,'sourceScope','[]'::jsonb),
    'storageBucket','study-artifacts','storageObjectPath','study/89400000-0000-4000-8000-000000000010/89400000-0000-4000-8000-000000000060/source.zip'),'source-complete');
  if response->>'ok'<>'true' then raise exception 'synthetic source fixture failed: %',response; end if;
end $$;
insert into private.study_model_preparations(id,study_id,source,source_document,source_snapshot_id,method_refs,profile_id,calculation_contract_ref,job_id)
values('89400000-0000-4000-8000-000000000021','89400000-0000-4000-8000-000000000010',jsonb_build_object('type','modelSourceSnapshot','snapshotId','89400000-0000-4000-8000-000000000050','contentHash',repeat('a',64),'digestScope','artifact_bytes_sha256'),'{"syntheticFixture":true}','89400000-0000-4000-8000-000000000050',pg_temp.study894_definition()->'methodRefs','lca.study-explicit-v1',pg_temp.study894_complete()->'calculationContractRef','89400000-0000-4000-8000-000000000031');
