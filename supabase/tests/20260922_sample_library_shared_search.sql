-- Database #690: independent sl scope on the existing query surface.

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, api, private, auth;
select plan(15);

select ok(
  (select count(*) = 3
   from pg_proc p
   join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'private'
     and p.proname in (
       'semantic_process_candidates', 'semantic_flow_candidates',
       'semantic_simple_dataset_candidates'
     )
     and 'hnsw.iterative_scan=strict_order' = any(p.proconfig)),
  'existing semantic helpers retain their strict-order HNSW setting'
);
select ok(
  (select count(*) = 2
   from pg_proc p
   join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'private'
     and p.proname in (
       'semantic_sample_library_candidates_v1',
       'semantic_dataset_candidates_dispatch_v1'
     )
     and not exists (
       select 1 from unnest(coalesce(p.proconfig, array[]::text[])) setting
       where setting like 'hnsw.iterative_scan=%'
     )),
  'new Sample Library helpers require no HNSW parameter SET privilege'
);

create temporary table sample_library_shared_webhook_calls (
  edge_function text not null,
  body jsonb not null,
  timeout_milliseconds integer not null
) on commit drop;

create or replace function util.invoke_edge_function(
  name text,
  body jsonb,
  timeout_milliseconds integer default ((5 * 60) * 1000)
) returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into pg_temp.sample_library_shared_webhook_calls values (name, body, timeout_milliseconds);
end;
$$;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at, is_sso_user, is_anonymous
) values
  ('00000000-0000-0000-0000-000000000000','69000000-0000-4000-8000-000000000001',
   'authenticated','authenticated','sample-shared-manager@example.invalid','x',now(),'{}','{}',now(),now(),false,false),
  ('00000000-0000-0000-0000-000000000000','69000000-0000-4000-8000-000000000002',
   'authenticated','authenticated','sample-shared-owner@example.invalid','x',now(),'{}','{}',now(),now(),false,false);

insert into private.users(id, raw_user_meta_data, contact) values
  ('69000000-0000-4000-8000-000000000001','{}',null),
  ('69000000-0000-4000-8000-000000000002','{}',null);
insert into private.teams(id, json, rank, is_public)
values ('00000000-0000-0000-0000-000000000000','{"name":"System"}',0,false)
on conflict (id) do nothing;
insert into private.roles(user_id, team_id, role) values
  ('69000000-0000-4000-8000-000000000001','00000000-0000-0000-0000-000000000000','data_product_manager');

insert into public.processes(id, version, state_code, user_id, json, modified_at) values
  ('69000000-0000-4000-8000-000000000010','01.00.000',100,null,
   '{"processDataSet":{"processInformation":{"dataSetInformation":{"name":{"baseName":[{"@xml:lang":"en","#text":"literature steel"}]}}}}}', now() - interval '1 day'),
  ('69000000-0000-4000-8000-000000000011','01.00.000',100,
   '69000000-0000-4000-8000-000000000002',
   '{"processDataSet":{"processInformation":{"dataSetInformation":{"name":{"baseName":[{"@xml:lang":"en","#text":"enterprise steel"}]}}}}}', now()),
  ('69000000-0000-4000-8000-000000000012','01.00.000',200,null,'{"name":"commercial only"}',now());

insert into public.sources(id, version, state_code, user_id, json, modified_at) values
  ('69000000-0000-4000-8000-000000000020','01.00.000',100,null,
   '{"sourceDataSet":{"sourceInformation":{"dataSetInformation":{"nameOfSource":[{"@xml:lang":"en","#text":"literature source"}]}}},"ref":"69000000-0000-4000-8000-000000000010"}',now()),
  ('69000000-0000-4000-8000-000000000021','01.00.000',100,
   '69000000-0000-4000-8000-000000000002','{"name":"enterprise source"}',now());

update public.processes
set embedding_ft = ('[' || array_to_string(array_fill(0.1::double precision, array[1024]), ',') || ']')::extensions.vector(1024)
where id in (
  '69000000-0000-4000-8000-000000000010',
  '69000000-0000-4000-8000-000000000011'
);
update public.sources
set embedding_ft = ('[' || array_to_string(array_fill(0.1::double precision, array[1024]), ',') || ']')::extensions.vector(1024)
where id = '69000000-0000-4000-8000-000000000020';

set local role authenticated;
select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claim.sub','69000000-0000-4000-8000-000000000002',true);
select is(
  (select count(*)::text from api.get_latest_process_versions(
    data_source => 'sl', sample_origin_filter => 'all', sample_publication_status_filter => 'all')),
  '0',
  'sl list access is denied to a non-manager'
);
select is(
  (select count(*)::text from api.hybrid_search_processes_v2(
    query_text => '', query_embedding => '[' || array_to_string(array_fill(0.1::double precision, array[1024]), ',') || ']',
    data_source => 'sl')),
  '0',
  'sl semantic candidates remain denied to a non-manager'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claim.sub','69000000-0000-4000-8000-000000000001',true);

select is(
  (select count(*)::text from api.get_latest_process_versions(
    data_source => 'sl', sample_origin_filter => 'all', sample_publication_status_filter => 'all')),
  '2',
  'sl list is fixed to state_code 100 independently of tg'
);
select is(
  (select count(*)::text from api.hybrid_search_processes_v2(
    query_text => '', query_embedding => '[' || array_to_string(array_fill(0.1::double precision, array[1024]), ',') || ']',
    data_source => 'sl')),
  '2',
  'sl Process hybrid routes through the dedicated semantic candidate path'
);
select is(
  (select count(*)::text from api.hybrid_search_sources_v2(
    query_text => '', query_embedding => '[' || array_to_string(array_fill(0.1::double precision, array[1024]), ',') || ']',
    data_source => 'sl')),
  '1',
  'sl foundation hybrid routes through the dedicated semantic candidate path'
);
select is(
  (select count(*)::text from api.get_latest_process_versions(
    data_source => 'sl', sample_origin_filter => 'literature', sample_publication_status_filter => 'all')),
  '1',
  'shared Process list applies literature origin before paging'
);
select is(
  (select count(*)::text from api.get_latest_source_versions(
    data_source => 'sl', sample_origin_filter => 'enterprise')),
  '1',
  'shared foundation list applies enterprise origin'
);
select is(
  (select count(*)::text from api.search_processes(
    query_text => '69000000-0000-4000-8000-000000000010',
    data_source => 'sl',
    filter_condition => '{"__sampleLibraryOrigin":"literature","__sampleLibraryPublicationStatus":"all"}'::jsonb)),
  '1',
  'existing Process keyword/UUID search accepts sl without routing through tg'
);
select is(
  (select count(*)::text from api.search_sources(
    query_text => '69000000-0000-4000-8000-000000000020',
    data_source => 'sl',
    filter_condition => '{"__sampleLibraryOrigin":"literature"}'::jsonb)),
  '1',
  'existing foundation keyword/UUID search accepts sl control filters'
);
select is(
  (select count(*)::text from api.search_dataset_json_uuid_mentions(
    p_uuid => '69000000-0000-4000-8000-000000000010',
    p_source_entity_kinds => array['source'],
    p_data_source => 'sl',
    p_sample_origin_filter => 'literature')),
  '1',
  'existing reference search accepts the independent sl scope'
);

select is(
  api.cmd_sample_library_publish_processes_v1(
    '[{"id":"69000000-0000-4000-8000-000000000010","version":"01.00.000"}]'
  ) #>> '{data,publishedCount}',
  '1',
  'the existing publication command records the selected exact version'
);
select is(
  (select count(*)::text from api.get_latest_process_versions(
    data_source => 'sl', sample_origin_filter => 'all', sample_publication_status_filter => 'published')),
  '1',
  'shared Process list applies published status'
);
select is(
  api.qry_sample_library_process_publications_v1(
    '[{"id":"69000000-0000-4000-8000-000000000010","version":"01.00.000"}]'
  ) #>> '{data,0,published}',
  'true',
  'the current page can decorate Process rows with publication status'
);

select * from finish();
rollback;
