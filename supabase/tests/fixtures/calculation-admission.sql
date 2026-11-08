-- Synthetic, local-only certificate evidence. Caller owns transaction/reset.
-- Service RPCs and all admission triggers run normally; only source-row seeding
-- suppresses dataset writer triggers. No solver or storage service is invoked.
\if :{?admission_scale}
\else
\set admission_scale 5741
\endif
create temporary table admission_scope as
select jsonb_build_object(
  'coverageMode','global_eligible',
  'processes', (select jsonb_agg(jsonb_build_object('id',
    ('c9581000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
    'version','01.00.000') order by n) from generate_series(1,:admission_scale) n),
  'lciaMethods', (select jsonb_agg(jsonb_build_object('id',
    ('c9582000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
    'version','01.00.000') order by n) from generate_series(1,25) n)
) as manifest;

insert into auth.users(instance_id,id,aud,role,email,encrypted_password,
  email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at,
  is_sso_user,is_anonymous)
select '00000000-0000-0000-0000-000000000000',
  ('c9580000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
  'authenticated','authenticated','admission958-'||n||'@example.com','x',
  now(),'{}','{}',now(),now(),false,false from generate_series(1,3) n;
insert into private.users(id,raw_user_meta_data,contact)
select ('c9580000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'{}',null
from generate_series(1,3) n;
insert into private.teams(id,json,rank,is_public)
values('00000000-0000-0000-0000-000000000000','{"name":"System"}',0,false)
on conflict(id) do nothing;
insert into private.roles(user_id,team_id,role)
select ('c9580000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
  '00000000-0000-0000-0000-000000000000','data_product_manager'
from generate_series(1,2) n;

insert into private.lca_release_runs(id,release_version,selection_manifest_hash,
  input_manifest_hash,calculation_bundle_hash,calculation_bundle_ref,
  profile_lock_hash,publish_plan_hash,publish_plan,artifact_set_hash,
  release_manifest_hash,release_manifest,status,idempotency_key,request_hash,created_by)
values('c9580000-0000-4000-8000-000000000010','95.08.001',repeat('a',64),
  repeat('b',64),repeat('c',64),'{}',repeat('d',64),repeat('e',64),'{}',
  repeat('f',64),repeat('9',64),'{}','published','admission958-release',
  repeat('1',64),'c9580000-0000-4000-8000-000000000001');
insert into private.lca_release_approvals(id,release_run_id,publish_plan_hash,
  approval_hash,approved_by,approved_at,expires_at)
values('c9580000-0000-4000-8000-000000000011',
  'c9580000-0000-4000-8000-000000000010',repeat('e',64),repeat('2',64),
  'c9580000-0000-4000-8000-000000000001',now(),now()+interval '1 day');
insert into private.lca_release_publications(id,release_run_id,release_version,
  approval_id,approval_hash,publish_plan_hash,release_manifest_hash,
  artifact_set_hash,approved_by,executed_by,credential_fingerprint,idempotency_key,published_at)
values('c9580000-0000-4000-8000-000000000012',
  'c9580000-0000-4000-8000-000000000010','95.08.001',
  'c9580000-0000-4000-8000-000000000011',repeat('2',64),repeat('e',64),
  repeat('9',64),repeat('f',64),'c9580000-0000-4000-8000-000000000001',
  'c9580000-0000-4000-8000-000000000001',repeat('3',64),
  'admission958-publication',now());
insert into private.lca_release_dataset_versions(release_run_id,dataset_type,
  dataset_role,dataset_uuid,dataset_version,source_process_uuid,
  source_process_version,version_significant_hash,semantic_hash,canonical_content_hash,artifact_ref)
select 'c9580000-0000-4000-8000-000000000010',kind,
  case when kind='process' then 'unit_process' else 'support' end,
  (p->>'id')::uuid,'01.00.000',
  case when kind='process' then (p->>'id')::uuid end,
  case when kind='process' then '01.00.000' end,
  repeat('4',64),repeat('5',64),repeat('6',64),'{}'
from admission_scope cross join lateral (
  select 'process' as kind, value p from jsonb_array_elements(manifest->'processes')
  union all select 'lciamethod',value from jsonb_array_elements(manifest->'lciaMethods')
) members;

alter table public.processes disable trigger user;
insert into public.processes(id,version,json,user_id,state_code)
select (p->>'id')::uuid,'01.00.000','{"processDataSet":{"name":"synthetic admission input"}}',
  'c9580000-0000-4000-8000-000000000001',100
from admission_scope cross join lateral jsonb_array_elements(manifest->'processes') p;
alter table public.processes enable trigger user;

select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claim.sub','c9580000-0000-4000-8000-000000000001',true);
create temporary table admission_closure_response as
select api.cmd_lcia_scope_closure_check_request_v2(manifest-'processes','admission958-closure','{}') response
from admission_scope;
do $$begin
  if (select response->>'ok' from admission_closure_response) is distinct from 'true'
  then raise exception 'synthetic closure request failed: %', (select response from admission_closure_response); end if;
end$$;
create temporary table admission_parameters as
select id,requested_scope_hash,policy_fingerprint,worker_job_id,scan_execution_id
from private.lcia_scope_closure_checks where request_idempotency_token='admission958-closure';
grant select on admission_parameters to authenticated;

update private.worker_jobs set status='running',
  lease_token='c9580000-0000-4000-8000-000000000101',
  lease_expires_at=now()+interval '10 minutes',started_at=now()
where id=(select worker_job_id from admission_parameters);
select set_config('request.jwt.claim.role','service_role',true);
select private.svc_lcia_scope_closure_claim_scan_execution(scan_execution_id,worker_job_id,
  'c9580000-0000-4000-8000-000000000101') from admission_parameters;
insert into private.worker_job_artifacts(id,job_id,artifact_type,storage_bucket,
  storage_path,content_type,byte_size,checksum_sha256,metadata)
select ('c9580000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,worker_job_id,
  case n when 201 then 'closure_report_xlsx' when 203 then 'closure_bundle'
    else 'closure_complete_machine_result' end,'test',
  'admission958/'||n||'.json','application/json',100,
  case n when 201 then repeat('a',64) when 203 then repeat('b',64) else repeat('c',64) end,
  jsonb_build_object('closureCheckId',id)||case n when 203 then
    '{"completeMachineResultArtifactId":"c9580000-0000-4000-8000-000000000204"}'::jsonb
    else '{}'::jsonb end
from admission_parameters cross join generate_series(201,204) n where n<>202;
update private.lca_network_snapshots set status='ready',source_hash='admission958-source'
where id=(select numerical_snapshot_id from private.lcia_scope_closure_scan_executions
  where id=(select scan_execution_id from admission_parameters));
insert into private.lca_snapshot_artifacts(id,snapshot_id,artifact_url,artifact_sha256,
  artifact_byte_size,artifact_format,process_count,flow_count,impact_count,
  a_nnz,b_nnz,c_nnz,status,snapshot_index_sha256,snapshot_build_contract_hash,
  effective_scope_hash,data_snapshot_token,closure_bundle_hash)
select 'c9580000-0000-4000-8000-000000000204',e.numerical_snapshot_id,
  's3://test/admission958/snapshot.h5',repeat('c',64),100,'snapshot-hdf5:v1',
  :admission_scale,1,25,:admission_scale,:admission_scale,25,'ready',repeat('d',64),
  private.lcia_scope_closure_sha256_text('lcia.numerical-snapshot-build-contract.v1'||chr(10)
    ||private.lcia_scope_closure_sha256(c.requested_scope_manifest)||chr(10)
    ||c.data_snapshot_token||chr(10)||repeat('b',64)||chr(10)
    ||e.numerical_snapshot_id::text||chr(10)||'snapshot-hdf5:v1'),
  private.lcia_scope_closure_sha256(c.requested_scope_manifest),c.data_snapshot_token,repeat('b',64)
from private.lcia_scope_closure_checks c join private.lcia_scope_closure_scan_executions e
  on e.id=c.scan_execution_id where c.id=(select id from admission_parameters);
create temporary table admission_certificate_response as
select private.svc_lcia_scope_closure_check_record_result_v3(
  c.id,c.worker_job_id,'c9580000-0000-4000-8000-000000000101','passed','complete',
  c.requested_scope_manifest,jsonb_build_object(
    'schemaVersion','lcia.scope-closure-evidence.v2','sourceFingerprint','admission958-source',
    'resolutionMapHash',repeat('e',64),'closureBundleArtifactId',bundle.id,
    'closureBundleHash',bundle.checksum_sha256,'snapshotId',artifact.snapshot_id,
    'snapshotHash',artifact.artifact_sha256,'snapshotArtifactId',artifact.id,
    'snapshotIndexSha256',artifact.snapshot_index_sha256,
    'snapshotBuildContractHash',artifact.snapshot_build_contract_hash,
    'reportArtifactManifestHash',private.lcia_scope_closure_sha256(jsonb_build_object(
      'artifactId',report.id,'bucket',report.storage_bucket,'objectPath',report.storage_path,
      'mediaType',report.content_type,'byteSize',report.byte_size,'checksumSha256',report.checksum_sha256)),
    'evidenceHash',hash.evidence_hash),
  jsonb_build_object('schemaVersion','lcia.scope-closure-summary.v1','evidenceHash',hash.evidence_hash),
  '[]','{}',report.id,bundle.id,artifact.id) response
from private.lcia_scope_closure_checks c
join private.lca_snapshot_artifacts artifact on artifact.id='c9580000-0000-4000-8000-000000000204'
join private.worker_job_artifacts report on report.id='c9580000-0000-4000-8000-000000000201'
join private.worker_job_artifacts bundle on bundle.id='c9580000-0000-4000-8000-000000000203'
cross join lateral (select private.lcia_scope_closure_sha256_text(
  'lcia.scope-closure-evidence.v2'||chr(10)||'admission958-source'||chr(10)||repeat('e',64)||chr(10)
  ||bundle.checksum_sha256||chr(10)||bundle.id::text||chr(10)||artifact.snapshot_id::text||chr(10)
  ||artifact.artifact_sha256||chr(10)||artifact.id::text||chr(10)||artifact.snapshot_index_sha256||chr(10)
  ||artifact.snapshot_build_contract_hash) evidence_hash) hash
where c.id=(select id from admission_parameters);
do $$begin
  if (select response->>'ok' from admission_certificate_response) is distinct from 'true'
  then raise exception 'synthetic certificate completion failed: %', (select response from admission_certificate_response); end if;
end$$;
select set_config('request.jwt.claim.role','authenticated',true);

create function pg_temp.admission_submit(p_key text, p_scope_hash text default null,
  p_policy text default null) returns jsonb language sql as $$
  select api.cmd_lcia_result_build_request_v2('admission958 build',null,'global_eligible',
    null,'[]',p_key,id,coalesce(p_scope_hash,requested_scope_hash),
    coalesce(p_policy,policy_fingerprint),'{}') from admission_parameters
$$;

grant execute on function pg_temp.admission_submit(text,text,text) to authenticated;
