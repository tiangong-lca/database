-- Run on populated head 20261101160000: current v1, selected final scope,
-- admitted runtime and a sealed synthetic readiness receipt. Owner resets later.
create extension if not exists pgtap with schema extensions;
set search_path=extensions,public,api,private,auth;
select no_plan();
do $$ begin
 if to_regclass('private.final_result_publication_bindings') is not null or not exists(select 1 from private.final_result_release_readiness)
   or not exists(select 1 from private.lca_release_publications where is_current) then raise exception 'Expected populated activation predecessor'; end if;
end $$;
create function pg_temp.activation_upgrade_snapshot() returns jsonb language plpgsql as $$
declare name text; value jsonb; snapshot jsonb:='{}';
begin
  foreach name in array array['lca_release_runs','lca_release_dataset_versions','lca_release_approvals','lca_release_publications',
    'result_query_artifacts','result_query_sources','result_query_release_bindings','final_result_identities',
    'final_result_query_artifacts','final_result_query_rows','final_result_query_sources','final_result_query_seals',
    'final_result_candidates','final_result_candidate_artifacts','final_result_candidate_members','final_result_candidate_storage',
    'final_result_release_plans','final_result_release_members','final_result_release_selection_seals',
    'final_result_query_runtime_revisions','final_result_query_runtime_head',
    'final_result_release_verifications','final_result_release_artifact_proofs','final_result_release_readiness'] loop
    execute format('select coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text),''[]''::jsonb) from private.%I t',name) into value;
    snapshot:=snapshot||jsonb_build_object(name,value);
  end loop;
  return snapshot;
end $$;
create temporary table before_activation_rows as select pg_temp.activation_upgrade_snapshot() value;
create temporary table before_activation_functions as select p.oid,p.prosrc,p.proowner,p.proacl,p.proconfig
 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('api','private');
create temporary table before_activation_authority as select
 (select coalesce(jsonb_agg(to_jsonb(m) order by oid),'[]'::jsonb) from pg_auth_members m where roleid='api_internal_executor'::regrole and member='postgres'::regrole) memberships,
 (select to_jsonb(n) from pg_namespace n where oid='private'::regnamespace) schema_state;
\ir ../../migrations/20261101180000_final_result_release_activation.sql
select is(pg_temp.activation_upgrade_snapshot(),(select value from before_activation_rows),'activation upgrade preserves all existing publication, selection, runtime and readiness rows');
select is((select count(*) from before_activation_functions old join pg_proc p using(oid) where old.prosrc<>p.prosrc),6::bigint,'only six exact legacy dispatch bodies change');
select ok(not exists(select 1 from before_activation_functions old join pg_proc p using(oid)
 where old.proowner is distinct from p.proowner or old.proacl is distinct from p.proacl or old.proconfig is distinct from p.proconfig),'all pre-existing function owners, ACLs and configuration remain unchanged');
select is((select coalesce(jsonb_agg(to_jsonb(m) order by oid),'[]'::jsonb) from pg_auth_members m where roleid='api_internal_executor'::regrole and member='postgres'::regrole),(select memberships from before_activation_authority),'borrowed owner membership restores exactly');
select is((select to_jsonb(n) from pg_namespace n where oid='private'::regnamespace),(select schema_state from before_activation_authority),'borrowed schema CREATE privilege restores exactly');
select is(api.svc_result_query_resolve('87700000-0000-4000-8000-000000000901','01.00.000')#>>'{data,artifact,artifactId}','87700000-0000-4000-8000-000000000701','legacy current query remains readable');
select is(api.svc_result_query_resolve('87700000-0000-4000-8000-000000000901','02.00.000')->>'code','published_result_not_available','legacy unpublished version stays denied');
select is((select count(*) from private.final_result_publication_bindings),0::bigint,'migration does not activate stored final Results');
select is((select count(*) from private.final_result_release_readiness),1::bigint,'sealed readiness survives without becoming publication authority');
select * from finish();
