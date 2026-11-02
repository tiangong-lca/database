-- Exact disposable project at 20261101090000, with the preceding v1 upgrade
-- fixture and query-v2 regression fixtures committed. Owner resets afterwards.
create extension if not exists pgtap with schema extensions;
set search_path=extensions,public,api,private,auth;
select no_plan();
do $$ begin
  if to_regclass('private.final_result_candidates') is not null
    or not exists(select 1 from private.lca_release_publications where is_current)
    or not exists(select 1 from private.final_result_query_seals) then
    raise exception 'Expected populated v1 publication and sealed v2 query baseline';
  end if;
end $$;
create function pg_temp.retained_snapshot() returns jsonb language plpgsql as $$
declare name text; value jsonb; snapshot jsonb:='{}';
begin
  foreach name in array array['lcia_result_packages','result_query_artifacts','result_query_sources',
    'result_query_release_bindings','lca_release_runs','lca_release_dataset_versions',
    'lca_release_approvals','lca_release_publications','final_result_identities',
    'final_result_query_artifacts','final_result_query_rows','final_result_query_sources','final_result_query_seals'] loop
    execute format('select coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text),''[]''::jsonb) from private.%I t',name) into value;
    snapshot:=snapshot||jsonb_build_object(name,value);
  end loop;
  return snapshot;
end $$;
create temporary table before_candidate_rows as select pg_temp.retained_snapshot() value;
create temporary table before_candidate_functions as
  select p.oid,pg_get_functiondef(p.oid) definition from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='api' and p.proname in ('svc_result_query_stage','svc_result_query_seal',
    'svc_result_query_bind_release','svc_result_query_resolve','cmd_lca_release_publish','cmd_lca_release_readback_verify',
    'svc_result_identity_register','svc_result_identity_versions','svc_result_query_stage_v2','svc_result_query_seal_v2');
\ir ../../migrations/20261101103000_final_result_candidate_catalog.sql
select is(pg_temp.retained_snapshot(),(select value from before_candidate_rows),'Candidate upgrade preserves all populated v1 publication and v2 identity/query evidence');
select is((select count(*) from before_candidate_functions where definition=pg_get_functiondef(oid)),10::bigint,'existing identity, query and activation RPC bodies remain exact');
select is(api.svc_result_query_resolve('87700000-0000-4000-8000-000000000901','01.00.000')#>>'{data,artifact,artifactId}',
  '87700000-0000-4000-8000-000000000701','existing current v1 publication stays readable');
select is(api.svc_result_query_resolve('87700000-0000-4000-8000-000000000901','02.00.000')->>'code',
  'published_result_not_available','unpublished file-contained version stays denied');
select ok((select bool_and(api.svc_result_query_describe_v2(artifact_id,target_hash)#>'{data,readbackReceipt}'=receipt)
  from private.final_result_query_seals),'new reconciliation recovers every existing exact v2 target seal');
select is((select count(*) from private.final_result_candidates),0::bigint,'upgrade does not infer Candidates from existing artifacts');
select * from finish();
