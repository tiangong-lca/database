-- Database #793: terminal index disposition and preserved current runtime contracts.
-- Actual domain GC/reuse behavior remains covered by the scope-closure suites;
-- representative natural plans and large JSON costs belong to benchmark_search_index_retirement.py.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path=extensions,public;
select no_plan();

select is(to_regclass('private.lcia_scope_closure_issue_roots_issue_idx'),null::regclass,
 'the redundant four-key issue roots index is retired');
select ok((select indisprimary and indisunique and indisvalid and indisready and indislive
 from pg_index where indexrelid='private.lcia_scope_closure_issue_roots_pkey'::regclass),
 'five-key primary index remains valid and live');
select is((select pg_get_constraintdef(oid) from pg_constraint
 where conrelid='private.lcia_scope_closure_issue_roots'::regclass and contype='p'),
 'PRIMARY KEY (closure_issue_id, root_dataset_type, root_dataset_id, root_dataset_version, impact_role)',
 'impact roles retain exact five-key uniqueness');
select is((select pg_get_constraintdef(oid) from pg_constraint
 where conrelid='private.lcia_scope_closure_issue_roots'::regclass and contype='f'),
 'FOREIGN KEY (closure_issue_id) REFERENCES private.lcia_scope_closure_issues(id) ON DELETE CASCADE',
 'issue deletion retains canonical cascade ownership');
select is(to_regclass('public.lciamethods_json_idx'),null::regclass,
 'qualified whole JSON GIN is retired while relation containment remains supported');
select is(to_regclass('public.lciamethods_json_pgroonga'),null::regclass,
 'unreached LCIA JSON PGroonga is retired');
select is(to_regclass('private.portal_catalog_search_process_document_v1_pgroonga'),null::regclass,
 'unused frozen Process V1 document access method is retired');
select is(to_regclass('private.portal_catalog_search_process_exact_rank_v1_gin'),null::regclass,
 'unused frozen Process V1 rank access method is retired');
select ok((select indisvalid and indisready and indislive from pg_index
 where indexrelid='private.portal_catalog_search_flow_document_v1_pgroonga'::regclass),
 'live Flow V1 document PGroonga remains valid and ready');
select ok((select bool_and(to_regprocedure(identity) is null) from unnest(array[
 'private.catalog_portal_process_keyword_relevance_v1_impl(text,text,uuid,text,integer,text)',
 'private.catalog_portal_process_keyword_keys_v1(text,text,uuid,text,integer)',
 'private.assert_portal_process_keyword_rank_contract_v1()',
 'private.portal_process_keyword_rank_manifest_sha256_v1()']) identity),
 'the four owner-only legacy Process rank helpers retire as one contract');
-- Exercise closed guards as their admitted owner; rollback restores this exact
-- task-only membership edge even when an assertion fails.
grant portal_public_executor to postgres with inherit false,set true;
set local role portal_public_executor;
select lives_ok('select private.assert_portal_catalog_projection_contract_cn1()',
 'current Process V2 and Flow V1 routing contract remains live');
select lives_ok('select private.assert_portal_process_keyword_rank_contract_cn1()',
 'current Process V2 keyword rank guard remains live');
reset role;
select ok((select pg_get_functiondef('private.catalog_portal_process_pattern_versions_v1(text)'::regprocedure)
 like '%private.portal_catalog_search_current_v2%'),
 'retained pattern function name still dispatches through the current mixed-kind projection');
select ok((select pg_get_functiondef(
 'private.catalog_portal_process_keyword_keys_cn1(text,text,uuid,text,integer)'::regprocedure)
 like '%private.portal_catalog_search_rows_v2%'),
 'current Process ranking uses V2 physical rows');
select ok((select array_agg(tgname) = array['portal_catalog_projection_content_sync_v2']::name[] from pg_trigger where tgrelid='public.processes'::regclass
 and tgname like 'portal_catalog_projection_content_sync_%' and tgenabled='O'),
 'only the current Process writer remains enabled');
select ok((select exists(select 1 from pg_policies where schemaname='public' and tablename='lciamethods'
 and cmd='SELECT' and roles=array['authenticated']::name[] and qual='true')),
 'authenticated LCIA public relation SELECT contract remains');
select ok((select exists(select 1 from pg_policies where schemaname='public' and tablename='lciamethods'
 and policyname='oauth_client_select_capability_guard' and permissive='RESTRICTIVE'
 and qual like '%DB-CORE-READ-01%')),
 'OAuth LCIA relation capability guard remains restrictive');

-- Ordinary actor relation queries retain SQL value semantics without either
-- legacy JSON access method. This one exact task fixture never reuses a row.
do $$begin
 if exists(select 1 from public.lciamethods where id='79310000-0000-4000-8000-000000000001') then
  raise exception 'Database 793 LCIA fixture collision';
 end if;
end$$;
insert into public.lciamethods(id,version,json_ordered) values(
 '79310000-0000-4000-8000-000000000001','01.00.000',
 '{"LCIAMethodDataSet":{"administrativeInformation":{"publicationAndOwnership":{"common:dataSetVersion":"01.00.000"}},"factors":[{"reference":"factor793","amount":1},{"reference":"other793","amount":2}]}}');
set local role authenticated;
select set_config('request.jwt.claims','{"role":"authenticated","sub":"79310000-0000-4000-8000-000000000002"}',true);
select is((select count(*) from public.lciamethods where id='79310000-0000-4000-8000-000000000001'
 and json @> '{"LCIAMethodDataSet":{"factors":[{"reference":"factor793"}]}}'),1::bigint,
 'authenticated nested JSON containment remains available without GIN');
select is((select count(*) from public.lciamethods where id='79310000-0000-4000-8000-000000000001'
 and json @> '{"LCIAMethodDataSet":{"factors":[{"reference":"absent793"}]}}'),0::bigint,
 'authenticated missing nested value remains a zero match');
select is((select count(*) from public.lciamethods where id='79310000-0000-4000-8000-000000000001'
 and json @> '{"LCIAMethodDataSet":{"factors":[]}}'),1::bigint,
 'authenticated structural empty-array containment remains supported');
select is((select count(*) from public.lciamethods where id='79310000-0000-4000-8000-000000000001'
 and json ? 'LCIAMethodDataSet'),1::bigint,
 'authenticated whole JSON key existence remains supported');
select is((select version::text from public.lciamethods where id='79310000-0000-4000-8000-000000000001'),
 '01.00.000','canonical JSON/version synchronization survives access-method retirement');
select set_config('request.jwt.claims','{"role":"authenticated","sub":"79310000-0000-4000-8000-000000000002","client_id":"79310000-0000-4000-8000-000000000003"}',true);
select is((select count(*) from public.lciamethods where id='79310000-0000-4000-8000-000000000001'),0::bigint,
 'an unknown OAuth client still cannot read the LCIA fixture');
reset role;

select * from finish();
rollback;
