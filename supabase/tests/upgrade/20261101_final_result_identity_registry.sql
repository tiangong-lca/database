-- Run only on an owned disposable database at 20261030084747. The harness
-- expands the exact migration include in the same psql session. Reset the
-- project afterward: the seeded pre-upgrade legacy row intentionally persists.
begin;
do $$ begin
  if to_regclass('private.final_result_identities') is not null then
    raise exception 'upgrade fixture requires the pre-identity migration head';
  end if;
  if exists(select 1 from public.processes where id='87900000-0000-4000-8000-000000000003') then
    raise exception 'upgrade fixture already exists; owner reset required';
  end if;
  if exists(select 1 from vault.secrets where name in ('project_url','project_secret_key')) then
    raise exception 'upgrade fixture requires an empty local Vault';
  end if;
  perform vault.create_secret('test-only-invalid-service-key','project_secret_key');
  perform vault.create_secret('http://127.0.0.1:1','project_url');
end $$;
insert into public.processes(id,version,json_ordered) values(
  '87900000-0000-4000-8000-000000000003','01.00.000',
  '{"processDataSet":{"administrativeInformation":{"publicationAndOwnership":{"common:dataSetVersion":"01.00.000"}}}}');
create temporary table prior_processes as select * from public.processes;
create temporary table prior_publications as select * from private.result_process_publications;
create temporary table prior_members as select * from private.lca_release_dataset_versions;
commit;

\ir ../../migrations/20261101063159_final_result_identity_registry.sql

begin;
create extension if not exists pgtap with schema extensions;
set local search_path=extensions,public,api,private,auth;
select no_plan();
select is((select count(*) from private.final_result_identities),0::bigint,'upgrade does not invent content equivalence or backfill legacy identities');
select is((select count(*) from ((select row_to_json(t)::text from public.processes t except select row_to_json(t)::text from prior_processes t) union all (select row_to_json(t)::text from prior_processes t except select row_to_json(t)::text from public.processes t)) changes),0::bigint,'populated Process rows survive byte-identically');
select is((select count(*) from ((select row_to_json(t)::text from private.result_process_publications t except select row_to_json(t)::text from prior_publications t) union all (select row_to_json(t)::text from prior_publications t except select row_to_json(t)::text from private.result_process_publications t)) changes),0::bigint,'legacy Result receipts survive unchanged');
select is((select count(*) from ((select row_to_json(t)::text from private.lca_release_dataset_versions t except select row_to_json(t)::text from prior_members t) union all (select row_to_json(t)::text from prior_members t except select row_to_json(t)::text from private.lca_release_dataset_versions t)) changes),0::bigint,'legacy formal release membership survives unchanged');
create function pg_temp.occupied_identity_request() returns jsonb language sql immutable as $$ select '{"schemaVersion":"tiangong.final-result-identity-request.v1","result":{"uuid":"87900000-0000-4000-8000-000000000003","version":"01.00.000"},"producer":"synthetic-upgrade","contentHash":"c185a7decb82b134a6b1c2b89f7f5f45df5bba2ff5f20e995591660c98e59efc","hashDomain":"tiangong.final-result-content.jcs.v1","canonicalContentHash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","semanticDependencies":[{"key":"flow:87900000-0000-4000-8000-000000000002@01.00.000","contentHash":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}]}'::jsonb $$;
select throws_ok($q$select api.svc_result_identity_register(pg_temp.occupied_identity_request())$q$,'55000','Legacy Result identity is occupied; explicit equivalence migration or a new version is required','pre-existing legacy content blocks new registration without backfill');
select lives_ok($q$update public.processes set extracted_md='synthetic upgrade fixture' where id='87900000-0000-4000-8000-000000000003'$q$,'ordinary legacy metadata updates still work');
select is((select registration_kind from private.final_result_identities where result_id='87900000-0000-4000-8000-000000000003'),'legacy','first post-upgrade write records occupancy without content equivalence');
select lives_ok($q$delete from public.processes where id='87900000-0000-4000-8000-000000000003'$q$,'ordinary non-Result legacy deletion still works');
select throws_ok($q$select api.svc_result_identity_register(pg_temp.occupied_identity_request())$q$,'55000','Legacy Result identity is occupied; explicit equivalence migration or a new version is required','deletion cannot free a previously used identity');
select * from finish();
rollback;
