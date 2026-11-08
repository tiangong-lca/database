-- Run on the exact 20261108065201 predecessor. Rollback-only populated upgrade.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path=extensions,public,api,private;
select no_plan();
select is((select max(version)::text from supabase_migrations.schema_migrations),
  '20261108065201','populated proof starts at the exact predecessor migration');
select is(to_regprocedure('private.lcia_result_build_request_envelope(text,jsonb,text,text,jsonb,text,jsonb,jsonb)'),
  null::regprocedure,'new envelope helper is absent before the forward migration');
\set admission_scale 3
\ir ../fixtures/calculation-admission.sql
set local role authenticated;
create temporary table admission_old_response as
select pg_temp.admission_submit('admission958-old-build') response;
reset role;
select is((select response->>'ok' from admission_old_response),'true',
  'predecessor admits the populated historical build');
create temporary table admission_legacy_before as
select 'global_eligible' mode,private.cmd_lcia_result_build_request_legacy(
  'legacy',null,'global_eligible',null,'[]','admission958-legacy-global','{}') response
union all select 'subset',private.cmd_lcia_result_build_request_legacy('legacy',
  '[{"id":"c9581000-0000-4000-8000-000000000001","version":"01.00.000"}]',
  'subset',null,'[]','admission958-legacy-subset','{}');
create temporary table admission_history as
select 'check' kind,to_jsonb(c) content from private.lcia_scope_closure_checks c
union all select 'job',to_jsonb(j) from private.worker_jobs j
union all select 'snapshot',to_jsonb(s) from private.lca_network_snapshots s
union all select 'artifact',to_jsonb(a) from private.worker_job_artifacts a
union all select 'event',to_jsonb(e) from private.worker_job_events e
union all select 'audit',to_jsonb(a) from private.command_audit_log a;
create temporary table admission_routines as
select oid,proowner,proacl,proconfig,pg_get_functiondef(oid) definition
from pg_proc where oid in (
 'api.cmd_lcia_result_build_request_v2(text,jsonb,text,text,jsonb,text,uuid,text,text,jsonb)'::regprocedure,
 'private.cmd_lcia_result_build_request_v2_without_expiry(text,jsonb,text,text,jsonb,text,uuid,text,text,jsonb)'::regprocedure,
 'api.lcia_result_current_eligible_manifest()'::regprocedure);
\ir ../../migrations/20261108073842_certificate_scoped_calculation_admission.sql
\ir ../../migrations/20261108073842_certificate_scoped_calculation_admission.sql
select is((select count(*) from admission_routines b join pg_proc p on p.oid=b.oid
  where (p.proowner,p.proacl,p.proconfig,pg_get_functiondef(p.oid))
    is distinct from (b.proowner,b.proacl,b.proconfig,b.definition)),0::bigint,
  'upgrade preserves exposed RPC, strong guards and legacy manifest definitions/ACLs');
with after_history as (
 select 'check' kind,to_jsonb(c) content from private.lcia_scope_closure_checks c
 union all select 'job',to_jsonb(j) from private.worker_jobs j
 union all select 'snapshot',to_jsonb(s) from private.lca_network_snapshots s
 union all select 'artifact',to_jsonb(a) from private.worker_job_artifacts a
 union all select 'event',to_jsonb(e) from private.worker_job_events e
 union all select 'audit',to_jsonb(a) from private.command_audit_log a
), changes as (
 (select * from after_history except all select * from admission_history)
 union all (select * from admission_history except all select * from after_history)
)
select is((select count(*) from changes),0::bigint,
 'reapplying migration preserves every populated row and immutable binding');
select is(private.cmd_lcia_result_build_request_legacy('legacy',null,'global_eligible',
  null,'[]','admission958-legacy-global','{}'),
  (select response from admission_legacy_before where mode='global_eligible'),
  'legacy global response remains byte-for-byte equivalent as JSONB');
select is(private.cmd_lcia_result_build_request_legacy('legacy',
  '[{"id":"c9581000-0000-4000-8000-000000000001","version":"01.00.000"}]',
  'subset',null,'[]','admission958-legacy-subset','{}'),
  (select response from admission_legacy_before where mode='subset'),
  'legacy manual response retains global eligible count and exact selected metadata');
create or replace function api.lcia_result_current_eligible_manifest()
returns jsonb language plpgsql stable security definer
set search_path=api,private,public,util,extensions,pg_temp as $$
begin raise exception 'unexpected global manifest reconstruction'; end $$;
set local role authenticated;
select is(pg_temp.admission_submit('admission958-old-build')#>>'{data,workerJobId}',
  (select response#>>'{data,workerJobId}' from admission_old_response),
  'an existing pre-upgrade active build retries without new global work or payload drift');
select is(pg_temp.admission_submit('admission958-new-build')->>'ok','true',
  'a new post-upgrade request uses the retained certificate without global work');
reset role;
select is((select to_jsonb(j) from private.worker_jobs j
  where id=(select (response#>>'{data,workerJobId}')::uuid from admission_old_response)),
  (select content from admission_history where kind='job'
    and content->>'id'=(select response#>>'{data,workerJobId}' from admission_old_response)),
  'retry leaves the complete pre-upgrade queued row unchanged');
select * from finish();
rollback;
