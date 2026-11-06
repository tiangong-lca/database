-- Reuse the full actual registration/readiness/activation/query/download/readback/
-- withdrawal path, with a Unit Process dependency and unchanged Result rows.
\set process_support true
begin;
create extension if not exists pgtap with schema extensions;
set local search_path=extensions,public,api,private,auth;
select no_plan();
\ir fixtures/final-result-candidate-setup.sql
set local role service_role;
select throws_ok($q$select pg_temp.register_candidate('{}',jsonb_build_object('datasets',jsonb_set((pg_temp.candidate_fixture()->>'catalogText')::jsonb->'datasets','{0,role}','"support"')))$q$,'22023','Invalid final Result Candidate member','Process dependencies require an explicit unit_process role');
select throws_ok($q$select pg_temp.register_candidate('{}',jsonb_build_object('datasets',jsonb_set((pg_temp.candidate_fixture()->>'catalogText')::jsonb->'datasets','{0,role}','"result_process"')))$q$,'22023','Final Result Candidate root/closure coverage mismatch','support cannot become a Result without a matching root and query row');
select throws_ok($q$select pg_temp.register_candidate('{}',jsonb_build_object('datasets',(select jsonb_agg(case when e->>'role'='result_process' then jsonb_set(e,'{references}','[]') else e end order by n) from jsonb_array_elements((pg_temp.candidate_fixture()->>'catalogText')::jsonb->'datasets') with ordinality a(e,n))))$q$,'22023','Final Result Candidate contains unreachable package members','unused Process support is rejected');
select throws_ok($q$select pg_temp.register_candidate('{}',jsonb_build_object('datasets',jsonb_set((pg_temp.candidate_fixture()->>'catalogText')::jsonb->'datasets','{1,references}','["process:87920000-0000-4000-8000-000000000050@02.00.000"]')))$q$,'22023','Final Result Candidate closure reference is absent','Process support must match the exact referenced version');
select is(pg_temp.register_candidate()#>>'{data,resultCount}','3','four Process members produce exactly three Results');
reset role;
select is((select count(*) from private.final_result_query_rows),3::bigint,'support dependency never creates an HDF5 query row');
select is((select count(*) from private.final_result_candidates),1::bigint,'failed candidates leave no partial registration');
select * from finish();
rollback;
\unset process_support
