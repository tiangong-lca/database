-- Prior head 20261101140000 with synthetic current-v1 and sealed final selection.
-- Only the exact disposable task project is used; owner resets afterwards.
create extension if not exists pgtap with schema extensions;
set search_path=extensions,public,api,private,auth;
select no_plan();
do $$ begin
  if to_regclass('private.final_result_release_readiness') is not null or not exists(select 1 from private.final_result_query_runtime_head)
    or not exists(select 1 from private.lca_release_publications where is_current)
    or not exists(select 1 from private.final_result_release_selection_seals) then
    raise exception 'Expected populated current-v1 and sealed final selection baseline';
  end if;
end $$;
create function pg_temp.readiness_upgrade_snapshot() returns jsonb language plpgsql as $$
declare name text; value jsonb; snapshot jsonb:='{}';
begin
  foreach name in array array['lca_release_runs','lca_release_dataset_versions','lca_release_approvals','lca_release_publications',
    'result_query_artifacts','result_query_sources','result_query_release_bindings','final_result_identities',
    'final_result_query_artifacts','final_result_query_rows','final_result_query_sources','final_result_query_seals',
    'final_result_candidates','final_result_candidate_artifacts','final_result_candidate_members','final_result_candidate_storage',
    'final_result_release_plans','final_result_release_members','final_result_release_selection_seals',
    'final_result_query_runtime_revisions','final_result_query_runtime_head'] loop
    execute format('select coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text),''[]''::jsonb) from private.%I t',name) into value;
    snapshot:=snapshot||jsonb_build_object(name,value);
  end loop;
  return snapshot;
end $$;
create temporary table before_readiness_rows as select pg_temp.readiness_upgrade_snapshot() value;
create temporary table before_readiness_functions as select p.oid,pg_get_functiondef(p.oid) definition from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='api' and p.proname in ('svc_result_query_stage','svc_result_query_seal','svc_result_query_bind_release','svc_result_query_resolve',
    'cmd_lca_release_prepare','cmd_lca_release_approve','cmd_lca_release_publish','cmd_lca_release_readback_verify',
    'svc_result_identity_register','svc_result_identity_versions','svc_result_query_stage_v2','svc_result_query_seal_v2','svc_result_candidate_register_v2',
    'cmd_final_result_release_prepare_v2','cmd_final_result_release_members_v2','cmd_final_result_release_seal_v2','qry_final_result_release_v2','svc_result_query_runtime_configure_v2','svc_result_query_runtime_read_v2',
    'qry_final_result_release_probe_page_v2','qry_final_result_release_probe_v2');
\ir ../../migrations/20261101160000_final_result_release_readiness.sql
select is(pg_temp.readiness_upgrade_snapshot(),(select value from before_readiness_rows),'readiness addition preserves existing publication, identities, storage and sealed selections');
select is((select count(*) from before_readiness_functions where definition=pg_get_functiondef(oid)),21::bigint,'all prior twenty-one bound API definitions remain exact');
select is(api.svc_result_query_resolve('87700000-0000-4000-8000-000000000901','01.00.000')#>>'{data,artifact,artifactId}','87700000-0000-4000-8000-000000000701','existing current-v1 Result remains readable');
select is(api.svc_result_query_resolve('87700000-0000-4000-8000-000000000901','02.00.000')->>'code','published_result_not_available','file-contained unpublished legacy version remains denied');
select is((select count(*) from private.final_result_release_readiness),0::bigint,'upgrade does not invent successful readiness');
select is((select count(*) from private.final_result_release_members where release_run_id='87930000-0000-4000-8000-000000000010'),2::bigint,'populated final selection still has exactly two members');
select set_config('request.jwt.claim.sub','87930000-0000-4000-8000-000000000001',false);
set role authenticated;
select is(api.qry_final_result_release_probe_page_v2('87930000-0000-4000-8000-000000000010',(api.qry_final_result_release_v2('87930000-0000-4000-8000-000000000010')#>>'{data,publishPlanHash}'))#>>'{data,runtimeRevision}','87940000-0000-4000-8000-000000000001','retained selected scope keeps its exact admitted runtime');
reset role;
select * from finish();
