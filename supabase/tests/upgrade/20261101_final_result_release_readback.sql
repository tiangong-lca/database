-- Run on the populated 20261101200000 predecessor, including an existing
-- activated v2 run. This migration only adds observation behavior.
create extension if not exists pgtap with schema extensions;
set search_path=extensions,public,api,private,auth;
select no_plan();
do $$ begin
 if to_regprocedure('api.cmd_final_result_release_readback_v2(uuid,text,text)') is not null or not exists(select 1 from private.lca_release_publications p join private.lca_release_runs r on r.id=p.release_run_id where r.publication_format='final-result-pair.v2' and p.is_current) then raise exception 'Expected activated readback predecessor'; end if;
end $$;
create temporary table readback_upgrade_runs as select * from private.lca_release_runs;
create temporary table readback_upgrade_publications as select * from private.lca_release_publications;
create temporary table readback_upgrade_functions as select p.oid,p.prosrc,p.proowner,p.proacl,p.proconfig from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in('api','private');
\ir ../../migrations/20261101220000_final_result_release_readback.sql
select is((select jsonb_agg(to_jsonb(r) order by id) from private.lca_release_runs r),(select jsonb_agg(to_jsonb(r) order by id) from readback_upgrade_runs r),'additive observation migration preserves all run content, status and historical evidence');
select is((select jsonb_agg(to_jsonb(p) order by id) from private.lca_release_publications p),(select jsonb_agg(to_jsonb(p) order by id) from readback_upgrade_publications p),'current and historical publication authority is unchanged');
select ok(not exists(select 1 from readback_upgrade_functions old join pg_proc p using(oid) where old.prosrc is distinct from p.prosrc or old.proowner is distinct from p.proowner or old.proacl is distinct from p.proacl or old.proconfig is distinct from p.proconfig),'every predecessor function body, owner, grant and configuration is preserved');
select ok(not has_function_privilege('service_role','api.cmd_final_result_release_readback_v2(uuid,text,text)','execute'),'upgrade grants no publication observation authority to service role');
select * from finish();
