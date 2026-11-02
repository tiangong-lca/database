-- Run only against the owner-reset disposable project at 20261101063159.
-- Creates a synthetic current v1 publication and retains it until owner reset.
create extension if not exists pgtap with schema extensions;
set search_path=extensions,public,api,private,auth;
select no_plan();
do $$ begin
  if to_regclass('private.final_result_query_artifacts') is not null
    or exists(select 1 from private.lca_release_publications) then
    raise exception 'Expected exact empty publication baseline before v2 upgrade';
  end if;
end $$;
begin;
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

select api.svc_result_query_stage('87700000-0000-4000-8000-000000000501',pg_temp.artifact_ref(),pg_temp.manifest(),pg_temp.rows(0));
select api.svc_result_query_stage('87700000-0000-4000-8000-000000000501',pg_temp.artifact_ref(),pg_temp.manifest(),pg_temp.rows(1));
select api.svc_result_query_seal('87700000-0000-4000-8000-000000000701');
insert into private.lca_release_runs(id,release_version,selection_manifest_hash,input_manifest_hash,calculation_bundle_hash,calculation_bundle_ref,profile_lock_hash,publish_plan_hash,publish_plan,artifact_set_hash,release_manifest_hash,release_manifest,status,idempotency_key,request_hash,created_by)
 values('87700000-0000-4000-8000-000000001001','01.00.000',repeat('d',64),repeat('d',64),repeat('b',64),pg_temp.bundle(),repeat('d',64),repeat('d',64),'{}',repeat('d',64),repeat('d',64),'{}','published','hdf5-fixture',repeat('d',64),'87700000-0000-4000-8000-000000000001');
insert into private.lca_release_dataset_versions(release_run_id,dataset_type,dataset_role,dataset_uuid,dataset_version,source_process_uuid,source_process_version,version_significant_hash,semantic_hash,canonical_content_hash,artifact_ref)
 values('87700000-0000-4000-8000-000000001001','process','unit_process','87700000-0000-4000-8000-000000000901','01.00.000','87700000-0000-4000-8000-000000000901','01.00.000',repeat('d',64),repeat('d',64),repeat('d',64),'{}');
insert into private.lca_release_approvals(id,release_run_id,publish_plan_hash,approval_hash,status,approved_by,approved_at,expires_at)
 values('87700000-0000-4000-8000-000000001101','87700000-0000-4000-8000-000000001001',repeat('d',64),repeat('d',64),'approved','87700000-0000-4000-8000-000000000001',now(),now()+interval '1 hour');
insert into private.lca_release_publications(id,release_run_id,release_version,approval_id,approval_hash,publish_plan_hash,release_manifest_hash,artifact_set_hash,approved_by,executed_by,credential_fingerprint,idempotency_key,published_at)
 values('87700000-0000-4000-8000-000000001201','87700000-0000-4000-8000-000000001001','01.00.000','87700000-0000-4000-8000-000000001101',repeat('d',64),repeat('d',64),repeat('d',64),repeat('d',64),'87700000-0000-4000-8000-000000000001','87700000-0000-4000-8000-000000000001',repeat('d',64),'hdf5-fixture',now());
select api.svc_result_query_bind_release('87700000-0000-4000-8000-000000001001','87700000-0000-4000-8000-000000000701');
update private.lca_release_runs set status='readback_verified',readback_verified_at=now(),readback_receipt='{}' where id='87700000-0000-4000-8000-000000001001';
commit;
create temporary table before_rows as select jsonb_build_object('lcia_result_packages',(select coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text),'[]'::jsonb) from private.lcia_result_packages t),'result_query_artifacts',(select coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text),'[]'::jsonb) from private.result_query_artifacts t),'result_query_sources',(select coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text),'[]'::jsonb) from private.result_query_sources t),'result_query_release_bindings',(select coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text),'[]'::jsonb) from private.result_query_release_bindings t),'lca_release_runs',(select coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text),'[]'::jsonb) from private.lca_release_runs t),'lca_release_dataset_versions',(select coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text),'[]'::jsonb) from private.lca_release_dataset_versions t),'lca_release_approvals',(select coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text),'[]'::jsonb) from private.lca_release_approvals t),'lca_release_publications',(select coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text),'[]'::jsonb) from private.lca_release_publications t)) as value;
create temporary table before_functions as select p.oid,pg_get_functiondef(p.oid) definition from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='api' and p.proname in ('svc_result_query_stage','svc_result_query_seal','svc_result_query_bind_release','svc_result_query_resolve','cmd_lca_release_publish','cmd_lca_release_readback_verify');
\ir ../../migrations/20261101090000_final_result_query_artifacts_v2.sql
select is(jsonb_build_object('lcia_result_packages',(select coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text),'[]'::jsonb) from private.lcia_result_packages t),'result_query_artifacts',(select coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text),'[]'::jsonb) from private.result_query_artifacts t),'result_query_sources',(select coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text),'[]'::jsonb) from private.result_query_sources t),'result_query_release_bindings',(select coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text),'[]'::jsonb) from private.result_query_release_bindings t),'lca_release_runs',(select coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text),'[]'::jsonb) from private.lca_release_runs t),'lca_release_dataset_versions',(select coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text),'[]'::jsonb) from private.lca_release_dataset_versions t),'lca_release_approvals',(select coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text),'[]'::jsonb) from private.lca_release_approvals t),'lca_release_publications',(select coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text),'[]'::jsonb) from private.lca_release_publications t)),(select value from before_rows),'populated v1 package, artifact, memberships, approval and current publication remain byte-equivalent');
select is((select count(*) from before_functions where definition=pg_get_functiondef(oid)),6::bigint,'all v1 query and activation functions retain their exact bodies');
select is(api.svc_result_query_resolve('87700000-0000-4000-8000-000000000901','01.00.000')#>>'{data,artifact,artifactId}','87700000-0000-4000-8000-000000000701','current v1 published Result remains readable');
select is(api.svc_result_query_resolve('87700000-0000-4000-8000-000000000901','02.00.000')->>'code','published_result_not_available','file-contained unpublished version remains denied');
select is(api.svc_result_query_stage('87700000-0000-4000-8000-000000000501',pg_temp.artifact_ref(),pg_temp.manifest(),pg_temp.rows(0))#>>'{data,registeredProcessCount}','2','legacy stage retry remains idempotent');
select is(api.svc_result_query_seal('87700000-0000-4000-8000-000000000701')#>>'{data,status}','ready','legacy seal retry remains idempotent');
select is((select count(*) from private.final_result_query_artifacts),0::bigint,'upgrade does not invent final Result artifacts');
select * from finish();
