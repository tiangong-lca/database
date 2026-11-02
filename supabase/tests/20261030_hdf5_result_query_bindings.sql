begin;
create extension if not exists pgtap with schema extensions;
set local search_path=extensions,public,api,private,auth;
select no_plan();

select is((select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='private' and c.relname in ('result_query_artifacts','result_query_sources','result_query_release_bindings') and c.relrowsecurity),3::bigint,'all three private relations have RLS');
select ok(not has_table_privilege('authenticated','private.result_query_artifacts','select')
  and not has_table_privilege('service_role','private.result_query_sources','insert'),'raw artifact relations remain ACL closed');
select is((select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='api'
 and p.proname in ('svc_result_query_stage','svc_result_query_seal','svc_result_query_bind_release','svc_result_query_resolve') and p.prosecdef and p.proconfig=array['search_path=""']::text[]
 and has_function_privilege('service_role',p.oid,'execute') and not has_function_privilege('authenticated',p.oid,'execute')
 and not has_function_privilege('anon',p.oid,'execute')),4::bigint,'all four descriptor/writer functions are fixed-path service-only');
select is((select count(*) from private.api_capability_grants where routine_identity in ('api.svc_result_query_stage(uuid, jsonb, jsonb, jsonb)','api.svc_result_query_seal(uuid)','api.svc_result_query_bind_release(uuid, uuid)','api.svc_result_query_resolve(uuid, text, uuid)')
  and capability_id='EDGE-DATA-PRODUCT-01' and allow_service_role and not allow_authenticated and not allow_anon),4::bigint,'exact manifest admission is service-only');

insert into auth.users(id,aud,role,email,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
 values('87700000-0000-4000-8000-000000000001','authenticated','authenticated','hdf5-fixture@example.invalid','{}','{}',now(),now());
insert into private.users(id,raw_user_meta_data) values('87700000-0000-4000-8000-000000000001','{}') on conflict(id) do nothing;
insert into private.worker_jobs(id,job_kind,worker_runtime,worker_queue,requester_type,requested_by,status,visibility,payload_schema_version,payload_json,diagnostics)
 values('87700000-0000-4000-8000-000000000101','lcia_result.package_build','calculator','package','user','87700000-0000-4000-8000-000000000001','completed','operator','lcia_result.package_build.request.v1','{}','{}');
insert into private.lca_network_snapshots(id,scope,process_filter,source_hash,status,created_by)
 values('87700000-0000-4000-8000-000000000201','data_product','{}','hdf5-fixture','ready','87700000-0000-4000-8000-000000000001');
insert into private.lca_results(id,job_id,snapshot_id,payload,diagnostics,artifact_url,artifact_format)
 values('87700000-0000-4000-8000-000000000301','87700000-0000-4000-8000-000000000401','87700000-0000-4000-8000-000000000201','{}','{}','s3://test-only/result.json','json');
create function pg_temp.bundle() returns jsonb language sql immutable as $$
 select jsonb_build_object('schemaVersion','tiangong.calculation-bundle.v2','calculationId','87700000-0000-4000-8000-000000000301','bundleContentHash',repeat('b',64),'manifestSha256',repeat('c',64));
$$;
create function pg_temp.artifact_ref() returns jsonb language sql immutable as $$
 select jsonb_build_object('schemaVersion','tiangong.query-artifact.v1','artifactId','87700000-0000-4000-8000-000000000701','manifestSha256',repeat('a',64),'manifestByteSize',1000);
$$;
create function pg_temp.manifest() returns jsonb language sql stable as $$
 select jsonb_build_object('schemaVersion','tiangong.query-artifact.v1','artifactId','87700000-0000-4000-8000-000000000701','source',pg_temp.bundle(),'processCount',2,'impactCount',25);
$$;
create function pg_temp.rows(p_ordinal integer) returns jsonb language sql immutable as $$
 select jsonb_build_array(jsonb_build_object('ordinal',p_ordinal,'id','87700000-0000-4000-8000-000000000901','version',case when p_ordinal=0 then '01.00.000' else '02.00.000' end));
$$;
insert into private.lcia_result_packages(id,build_id,build_worker_job_id,package_version,coverage_mode,eligibility_resolved_at,
 eligible_input_count,included_input_count,input_manifest_hash,input_manifest,snapshot_id,result_id,artifact_manifest,status,created_by)
 values('87700000-0000-4000-8000-000000000501','87700000-0000-4000-8000-000000000601','87700000-0000-4000-8000-000000000101','hdf5-fixture','subset',now(),2,1,repeat('d',64),
 '{"processes":[{"id":"87700000-0000-4000-8000-000000000901","version":"01.00.000"}]}','87700000-0000-4000-8000-000000000201','87700000-0000-4000-8000-000000000301',jsonb_build_object('calculationBundle',pg_temp.bundle()),'preview_ready','87700000-0000-4000-8000-000000000001');

select throws_ok($$select api.svc_result_query_stage('87700000-0000-4000-8000-000000000501',pg_temp.artifact_ref(),jsonb_set(pg_temp.manifest(),'{source,bundleContentHash}',to_jsonb(repeat('f',64))),pg_temp.rows(0))$$,'22023','Query artifact source Bundle mismatch','wrong canonical Bundle fails before staging');
select is((select count(*) from private.result_query_artifacts),0::bigint,'rejected binding leaves no artifact');
grant execute on function pg_temp.bundle(),pg_temp.artifact_ref(),pg_temp.manifest(),pg_temp.rows(integer) to service_role;
set local role service_role;
select is(api.svc_result_query_stage('87700000-0000-4000-8000-000000000501',pg_temp.artifact_ref(),pg_temp.manifest(),pg_temp.rows(0))#>>'{data,registeredProcessCount}','1','first bounded batch staged');
select is(api.svc_result_query_stage('87700000-0000-4000-8000-000000000501',pg_temp.artifact_ref(),pg_temp.manifest(),pg_temp.rows(0))#>>'{data,registeredProcessCount}','1','exact lost-response retry is idempotent');
select throws_ok($$select api.svc_result_query_seal('87700000-0000-4000-8000-000000000701')$$,'22023','Query source axis incomplete','partial axis cannot become ready');
select throws_ok($$select api.svc_result_query_stage('87700000-0000-4000-8000-000000000501',pg_temp.artifact_ref(),pg_temp.manifest(),jsonb_set(pg_temp.rows(1),'{0,ordinal}','0'))$$,'22023','Query source row conflict','same ordinal with another source version rejected');
select is(api.svc_result_query_stage('87700000-0000-4000-8000-000000000501',pg_temp.artifact_ref(),pg_temp.manifest(),pg_temp.rows(1))#>>'{data,registeredProcessCount}','2','second exact version has independent ordinal');
select is(api.svc_result_query_seal('87700000-0000-4000-8000-000000000701')#>>'{data,status}','ready','complete axis seals');
select is(api.svc_result_query_seal('87700000-0000-4000-8000-000000000701')#>>'{data,status}','ready','seal retry preserves receipt');
select throws_ok($$select api.svc_result_query_stage('87700000-0000-4000-8000-000000000501',jsonb_set(pg_temp.artifact_ref(),'{manifestSha256}',to_jsonb(repeat('d',64))),pg_temp.manifest(),pg_temp.rows(0))$$,'22023','Query artifact identity conflict','sealed encoding cannot be replaced');
select is(api.svc_result_query_resolve('87700000-0000-4000-8000-000000000901','01.00.000')->>'code','published_result_not_available','ready artifact alone is not public');
reset role;
select throws_ok($$update private.result_query_artifacts set manifest='{}' where id='87700000-0000-4000-8000-000000000701'$$,'55000','Result query evidence is immutable','registered evidence cannot drift');
select throws_ok($$delete from private.result_query_sources where artifact_id='87700000-0000-4000-8000-000000000701'$$,'55000','Result query evidence is immutable','source mapping cannot drift');

-- Synthetic formal release includes only version 1 although the HDF5 axis has both.
insert into private.lca_release_runs(id,release_version,selection_manifest_hash,input_manifest_hash,calculation_bundle_hash,calculation_bundle_ref,profile_lock_hash,publish_plan_hash,publish_plan,artifact_set_hash,release_manifest_hash,release_manifest,status,idempotency_key,request_hash,created_by)
 values('87700000-0000-4000-8000-000000001001','01.00.000',repeat('d',64),repeat('d',64),repeat('b',64),pg_temp.bundle(),repeat('d',64),repeat('d',64),'{}',repeat('d',64),repeat('d',64),'{}','published','hdf5-fixture',repeat('d',64),'87700000-0000-4000-8000-000000000001');
insert into private.lca_release_dataset_versions(release_run_id,dataset_type,dataset_role,dataset_uuid,dataset_version,source_process_uuid,source_process_version,version_significant_hash,semantic_hash,canonical_content_hash,artifact_ref)
 values('87700000-0000-4000-8000-000000001001','process','unit_process','87700000-0000-4000-8000-000000000901','01.00.000','87700000-0000-4000-8000-000000000901','01.00.000',repeat('d',64),repeat('d',64),repeat('d',64),'{}');
insert into private.lca_release_approvals(id,release_run_id,publish_plan_hash,approval_hash,status,approved_by,approved_at,expires_at)
 values('87700000-0000-4000-8000-000000001101','87700000-0000-4000-8000-000000001001',repeat('d',64),repeat('d',64),'approved','87700000-0000-4000-8000-000000000001',now(),now()+interval '1 hour');
insert into private.lca_release_publications(id,release_run_id,release_version,approval_id,approval_hash,publish_plan_hash,release_manifest_hash,artifact_set_hash,approved_by,executed_by,credential_fingerprint,idempotency_key,published_at)
 values('87700000-0000-4000-8000-000000001201','87700000-0000-4000-8000-000000001001','01.00.000','87700000-0000-4000-8000-000000001101',repeat('d',64),repeat('d',64),repeat('d',64),repeat('d',64),'87700000-0000-4000-8000-000000000001','87700000-0000-4000-8000-000000000001',repeat('d',64),'hdf5-fixture',now());
set local role service_role;
select is(api.svc_result_query_bind_release('87700000-0000-4000-8000-000000001001','87700000-0000-4000-8000-000000000701')->>'ok','true','same-Bundle formal release binds');
select is(api.svc_result_query_bind_release('87700000-0000-4000-8000-000000001001','87700000-0000-4000-8000-000000000701')->>'ok','true','release bind retry idempotent');
select is(api.svc_result_query_resolve('87700000-0000-4000-8000-000000000901','01.00.000')->>'code','published_result_not_available','release readback must be verified');
reset role;
update private.lca_release_runs set status='readback_verified',readback_verified_at=now(),readback_receipt='{}' where id='87700000-0000-4000-8000-000000001001';
set local role service_role;
select is(api.svc_result_query_resolve('87700000-0000-4000-8000-000000000901','01.00.000')#>>'{data,artifact,artifactId}','87700000-0000-4000-8000-000000000701','authorized current release resolves exact artifact');
select is(api.svc_result_query_resolve('87700000-0000-4000-8000-000000000901','02.00.000')->>'code','published_result_not_available','file-contained unpublished version is denied');
select is(api.svc_result_query_resolve('87700000-0000-4000-8000-000000000901','01.00.000','87700000-0000-4000-8000-000000009999')->>'code','published_result_not_available','another selected publication is denied');
reset role;
update private.lca_release_publications set status='unpublished',is_current=false,unpublished_at=now() where id='87700000-0000-4000-8000-000000001201';
set local role service_role;
select is(api.svc_result_query_resolve('87700000-0000-4000-8000-000000000901','01.00.000')->>'code','published_result_not_available','revocation immediately denies another descriptor');
set local role authenticated;
select throws_ok($$select api.svc_result_query_resolve('87700000-0000-4000-8000-000000000901','01.00.000')$$,'42501',null,'browser role cannot obtain private descriptor');
select throws_ok($$select * from private.result_query_artifacts$$,'42501',null,'browser cannot read raw manifest');
reset role;
select * from finish();
rollback;
