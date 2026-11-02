-- Populated head 20261101180000: current legacy release plus ready/approved v2
-- selection. Only the exact owned synthetic stack may be reset afterwards.
create extension if not exists pgtap with schema extensions;
set search_path=extensions,public,api,private,auth;
select no_plan();
do $$ begin
 if to_regprocedure('api.qry_final_result_publication_head_v2()') is not null or not exists(select 1 from private.lca_release_approvals where status='approved' and audit_correlation->>'schemaVersion'='tiangong.final-result-approval.v2') then raise exception 'Expected approved recovery predecessor'; end if;
end $$;
create function pg_temp.recovery_snapshot() returns jsonb language plpgsql as $$
declare name text; value jsonb; snapshot jsonb:='{}';
begin
 foreach name in array array['lca_release_runs','lca_release_approvals','lca_release_publications','final_result_publication_bindings','final_result_release_readiness','roles'] loop
  execute format('select coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text),''[]''::jsonb) from private.%I t',name) into value;
  snapshot:=snapshot||jsonb_build_object(name,value);
 end loop;
 return snapshot;
end $$;
create temporary table before_recovery as select pg_temp.recovery_snapshot() value;
create temporary table before_recovery_functions as select p.oid,p.prosrc,p.proowner,p.proacl,p.proconfig from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in('api','private');
\ir ../../migrations/20261101200000_final_result_release_recovery_views.sql
select is(pg_temp.recovery_snapshot(),(select value from before_recovery),'recovery upgrade changes no publication, approval, runtime evidence or authority rows');
select is((select count(*) from before_recovery_functions old join pg_proc p using(oid) where old.prosrc<>p.prosrc),1::bigint,'only the existing run recovery DTO body changes');
select ok(not exists(select 1 from before_recovery_functions old join pg_proc p using(oid) where old.proowner is distinct from p.proowner or old.proacl is distinct from p.proacl or old.proconfig is distinct from p.proconfig),'all predecessor function ACLs/owners/configuration remain unchanged');
select set_config('request.jwt.claim.sub','87930000-0000-4000-8000-000000000001',false);
set role authenticated;
select is(api.qry_final_result_publication_head_v2()#>>'{data,format}','legacy-four-zip.v1','legacy current format is reported explicitly');
select is(api.qry_final_result_publication_head_v2()#>'{data,candidateHash}','null'::jsonb,'legacy current is not assigned a final Candidate');
select is(api.qry_final_result_release_v2('87930000-0000-4000-8000-000000000010')#>>'{data,activeApproval,approvalId}','87960000-0000-4000-8000-000000000001','existing approved v2 run recovers exact approval');
select is(api.qry_final_result_release_approval_v2('87930000-0000-4000-8000-000000000010','87960000-0000-4000-8000-000000000001')#>>'{data,status}','approved','historical approval details are independently queryable');
reset role;
select * from finish();
