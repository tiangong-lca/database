-- Exact task-owned baseline at 20261101103000 with current v1 and registered
-- Candidate fixtures. This forward upgrade retains them for the owner's reset.
create extension if not exists pgtap with schema extensions;
set search_path=extensions,public,api,private,auth;
select no_plan();
do $$ begin
  if to_regclass('private.final_result_release_plans') is not null
    or not exists(select 1 from private.lca_release_publications where is_current)
    or not exists(select 1 from private.final_result_candidate_storage) then
    raise exception 'Expected populated current-v1 and qualified Candidate baseline';
  end if;
end $$;
create function pg_temp.retained_selection_snapshot() returns jsonb language plpgsql as $$
declare name text; value jsonb; snapshot jsonb:='{}';
begin
  foreach name in array array['lca_release_runs','lca_release_dataset_versions','lca_release_approvals',
    'lca_release_publications','result_query_artifacts','result_query_sources','result_query_release_bindings',
    'final_result_identities','final_result_query_artifacts','final_result_query_rows','final_result_query_sources',
    'final_result_query_seals','final_result_candidates','final_result_candidate_artifacts',
    'final_result_candidate_members','final_result_candidate_storage'] loop
    execute format('select coalesce(jsonb_agg(to_jsonb(t)-''publication_format'' order by to_jsonb(t)::text),''[]''::jsonb) from private.%I t',name) into value;
    snapshot:=snapshot||jsonb_build_object(name,value);
  end loop;
  return snapshot;
end $$;
create temporary table before_selection_rows as select pg_temp.retained_selection_snapshot() value;
create temporary table before_selection_functions as
  select p.oid,pg_get_functiondef(p.oid) definition from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='api' and p.proname in ('svc_result_query_stage','svc_result_query_seal',
    'svc_result_query_bind_release','svc_result_query_resolve','cmd_lca_release_publish','cmd_lca_release_readback_verify',
    'cmd_lca_release_prepare','cmd_lca_release_approve','svc_result_identity_register','svc_result_identity_versions',
    'svc_result_query_stage_v2','svc_result_query_seal_v2','svc_result_candidate_register_v2');
\ir ../../migrations/20261101120000_final_result_release_selection.sql
select is(pg_temp.retained_selection_snapshot(),(select value from before_selection_rows),'selection upgrade preserves existing rows and evidence except explicit format default');
select is((select count(*) from before_selection_functions where definition=pg_get_functiondef(oid)),13::bigint,'all existing prepare/approval/publication and storage API bodies remain exact');
select ok((select bool_and(publication_format='legacy-four-zip.v1') from private.lca_release_runs),'every existing run retains explicit legacy format');
select is(api.svc_result_query_resolve('87700000-0000-4000-8000-000000000901','01.00.000')#>>'{data,artifact,artifactId}',
  '87700000-0000-4000-8000-000000000701','current legacy publication remains readable');
select is(api.svc_result_query_resolve('87700000-0000-4000-8000-000000000901','02.00.000')->>'code',
  'published_result_not_available','unpublished legacy version remains unavailable');
select ok((select bool_and(api.svc_result_candidate_describe_v2(candidate_hash,target_hash)#>'{data,readbackReceipt}'=receipt)
  from private.final_result_candidate_storage),'registered Candidate original receipts survive the run-format migration');
select is((select count(*) from private.final_result_release_plans),0::bigint,'upgrade does not infer selections or publication authorization');
select * from finish();
