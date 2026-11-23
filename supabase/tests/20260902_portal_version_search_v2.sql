-- Rollback-only proof on a uniquely named isolated local Database #600 stack.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = extensions,public,auth;
select extensions.no_plan();

create or replace function pg_temp.portal_versions_localized(p_text text)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select pg_catalog.jsonb_build_array(
    pg_catalog.jsonb_build_object('@xml:lang', 'en', '#text', p_text)
  )
$$;

create or replace function pg_temp.portal_versions_publication(
  p_version text,
  p_license text
)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select pg_catalog.jsonb_build_object(
    'common:dataSetVersion', p_version,
    'common:licenseType', p_license,
    'common:referenceToOwnershipOfDataSet', pg_catalog.jsonb_build_object(
      '@type', 'contact data set',
      '@refObjectId', '52900000-0000-4000-8000-000000000900',
      '@version', '01.00.000',
      '@uri', 's3://portal-private/provider.json',
      'common:shortDescription', pg_temp.portal_versions_localized('Portal Provider')
    )
  )
$$;

create or replace function pg_temp.portal_versions_process_payload(
  p_name text,
  p_version text
)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select pg_catalog.jsonb_build_object(
    'processDataSet', pg_catalog.jsonb_build_object(
      'processInformation', pg_catalog.jsonb_build_object(
        'dataSetInformation', pg_catalog.jsonb_build_object(
          'name', pg_catalog.jsonb_build_object(
            'baseName', pg_temp.portal_versions_localized(p_name)
          ),
          'common:generalComment', pg_temp.portal_versions_localized(p_name || ' summary'),
          'classificationInformation', pg_catalog.jsonb_build_object(
            'common:classification', pg_catalog.jsonb_build_array(
              pg_catalog.jsonb_build_object(
                'common:class', pg_catalog.jsonb_build_object(
                  '@level', '0', '@classId', 'PORTAL-HYBRID', '#text', 'Hybrid fixture'
                )
              )
            )
          )
        ),
        'time', pg_catalog.jsonb_build_object('common:referenceYear', '2024'),
        'geography', pg_catalog.jsonb_build_object(
          'locationOfOperationSupplyOrProduction', pg_catalog.jsonb_build_object(
            '@location', 'CN',
            'descriptionOfRestrictions', pg_temp.portal_versions_localized('China')
          )
        ),
        'technology', pg_catalog.jsonb_build_object(
          'technologyDescriptionAndIncludedProcesses',
          pg_temp.portal_versions_localized('Hybrid fixture technology')
        )
      ),
      'modellingAndValidation', pg_catalog.jsonb_build_object(
        'LCIMethodAndAllocation', pg_catalog.jsonb_build_object(
          'typeOfDataSet', 'Unit process, single operation'
        )
      ),
      'administrativeInformation', pg_catalog.jsonb_build_object(
        'publicationAndOwnership', pg_temp.portal_versions_publication(
          p_version, 'Free of charge for all users and uses'
        )
      ),
      'privateLocator', 's3://portal-private/process/' || p_name
    )
  )
$$;

create or replace function pg_temp.portal_versions_flow_payload(
  p_name text,
  p_version text
)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select pg_catalog.jsonb_build_object(
    'flowDataSet', pg_catalog.jsonb_build_object(
      'flowInformation', pg_catalog.jsonb_build_object(
        'dataSetInformation', pg_catalog.jsonb_build_object(
          'name', pg_catalog.jsonb_build_object(
            'baseName', pg_temp.portal_versions_localized(p_name)
          ),
          'common:generalComment', pg_temp.portal_versions_localized(p_name || ' summary'),
          'classificationInformation', pg_catalog.jsonb_build_object(
            'common:classification', pg_catalog.jsonb_build_array(
              pg_catalog.jsonb_build_object(
                'common:class', pg_catalog.jsonb_build_object(
                  '@level', '0', '@classId', 'PORTAL-HYBRID', '#text', 'Hybrid fixture'
                )
              )
            )
          ),
          'CASNumber', '50-00-0'
        ),
        'geography', pg_catalog.jsonb_build_object(
          'locationOfSupply', pg_catalog.jsonb_build_object(
            '@location', 'CN',
            'descriptionOfRestrictions', pg_temp.portal_versions_localized('China')
          )
        )
      ),
      'modellingAndValidation', pg_catalog.jsonb_build_object(
        'LCIMethod', pg_catalog.jsonb_build_object('typeOfDataSet', 'Product flow')
      ),
      'administrativeInformation', pg_catalog.jsonb_build_object(
        'publicationAndOwnership', pg_temp.portal_versions_publication(
          p_version, 'Free of charge for all users and uses'
        )
      ),
      'objectLocator', 's3://portal-private/flow/' || p_name
    )
  )
$$;

create or replace function pg_temp.portal_versions_vector_text(
  p_first real,
  p_second real
)
returns text
language sql
immutable
set search_path = ''
as $$
  select '[' || p_first::text || ',' || p_second::text || ','
    || pg_catalog.array_to_string(pg_catalog.array_fill('0'::text, array[1022]), ',') || ']'
$$;

create or replace function pg_temp.portal_versions_vector(
  p_first real,
  p_second real
)
returns extensions.vector(1024)
language sql
immutable
set search_path = ''
as $$
  select pg_temp.portal_versions_vector_text(p_first, p_second)::extensions.vector(1024)
$$;

create or replace function pg_temp.portal_versions_has_forbidden_key(p_payload jsonb)
returns boolean
language sql
immutable
set search_path = ''
as $$
  with recursive walk(value) as (
    select p_payload
    union all
    select child.value
    from walk as parent
    cross join lateral (
      select array_value.value
      from pg_catalog.jsonb_array_elements(
        case when pg_catalog.jsonb_typeof(parent.value) = 'array'
          then parent.value else '[]'::jsonb end
      ) as array_value(value)
      union all
      select object_value.value
      from pg_catalog.jsonb_each(
        case when pg_catalog.jsonb_typeof(parent.value) = 'object'
          then parent.value else '{}'::jsonb end
      ) as object_value(key, value)
    ) as child
  ), keys as (
    select pg_catalog.lower(object_key.key) as key
    from walk
    cross join lateral pg_catalog.jsonb_object_keys(
      case when pg_catalog.jsonb_typeof(walk.value) = 'object'
        then walk.value else '{}'::jsonb end
    ) as object_key(key)
  )
  select exists (
    select 1
    from keys
    where key = any (array[
      'user_id', 'userid', 'team_id', 'teamid', 'review_id', 'reviewid',
      'state_code', 'statecode', 'actor', 'owner', 'data_source', 'datasource',
      'json', 'json_ordered', 'search_text', 'extracted_md', 'embedding',
      'embedding_ft', 'embedding_ft_at', 'model_id', 'modelid', 'service_role',
      'secret', 'credential', 'bucket', 'object_path', 'storage_path', 'locator',
      'privatelocator', 'objectlocator', 'error', 'internalerror'
    ])
  )
$$;

-- Synthetic future state codes are admitted ONLY in this rollback fixture.
-- The query allowlist must remain correct if the authoring enum later expands.
alter table public.processes drop constraint processes_state_code_check;
alter table public.flows drop constraint flows_state_code_check;
alter table public.processes disable trigger user;
alter table public.flows disable trigger user;
alter table public.processes enable trigger portal_catalog_projection_content_sync_v2;
alter table public.flows enable trigger portal_catalog_projection_content_sync_v1;

create function pg_temp.version_fixture(
  p_kind text,p_id uuid,p_version text,p_state integer,p_name text,p_vector extensions.vector,
  p_geography text default 'CN'
) returns void language plpgsql as $$
declare v_json jsonb; v_table text; v_root text; v_info text; v_geography text;
begin
  if p_kind = 'process' then
    v_json := pg_temp.portal_versions_process_payload(p_name,p_version);
    v_table := 'processes'; v_root := 'processDataSet'; v_info := 'processInformation';
    v_geography := 'locationOfOperationSupplyOrProduction';
  elsif p_kind = 'flow' then
    v_json := pg_temp.portal_versions_flow_payload(p_name,p_version);
    v_table := 'flows'; v_root := 'flowDataSet'; v_info := 'flowInformation';
    v_geography := 'locationOfSupply';
  else raise exception 'invalid fixture kind';
  end if;
  v_json := jsonb_set(v_json,array[v_root,v_info,'geography',v_geography,'@location'],to_jsonb(p_geography));
  v_json := jsonb_set(v_json,array[v_root,v_info,'dataSetInformation','name','baseName'],
    jsonb_build_array(
      jsonb_build_object('@xml:lang','en','#text',p_name),
      jsonb_build_object('@xml:lang','fr','#text','électricité ' || p_name),
      jsonb_build_object('@xml:lang','ru','#text','медь ' || p_name),
      jsonb_build_object('@xml:lang','ar','#text','نحاس ' || p_name),
      jsonb_build_object('@xml:lang','zh','#text','铜 ' || p_name)
    ));
  execute format(
    'insert into public.%I(id,version,json,json_ordered,state_code,user_id,rule_verification,
      modified_at,embedding_ft,extracted_md,search_text)
     values($1,$2,$3,$3::json,$4,$5,true,$6,$7,$8,$9)',v_table)
    using p_id,p_version,v_json,p_state,'60000000-0000-4000-8000-000000000999'::uuid,
      '2026-09-02 08:00:00+00'::timestamptz,p_vector,
      'Private derivative text must not be searchable through Portal',
      array['PRIVATE_DERIVATIVE_ONLY'];
end;
$$;

do $$
declare k text; s integer; n integer; i integer; ord integer;
begin
  foreach k in array array['process','flow'] loop
    ord := 0;
    foreach s in array array[0,20,50,99,100,101,199,200,201,300] loop
      ord := ord + 1;
      perform pg_temp.version_fixture(k,'60000000-0000-4000-8000-000000000001',
        '01.00.' || lpad(ord::text,3,'0'),s,'AllowlistNeedle',
        pg_temp.portal_versions_vector(1,0));
    end loop;
    perform pg_temp.version_fixture(k,'60000000-0000-4000-8000-000000000002','01.00.000',
      100,'HistoricNeedle',pg_temp.portal_versions_vector(0,1));
    perform pg_temp.version_fixture(k,'60000000-0000-4000-8000-000000000002','01.00.001',
      100,'Different Latest Name',pg_temp.portal_versions_vector(1,0));
    for i in 1..35 loop
      perform pg_temp.version_fixture(k,'60000000-0000-4000-8000-000000000003',
        '01.00.' || lpad(i::text,3,'0'),100,'VersionPageNeedle',null);
    end loop;
    foreach n in array array[6,199,200] loop
      for i in 1..n loop
        perform pg_temp.version_fixture(k,md5(k || ':cardinality:' || n || ':' || i)::uuid,
          '01.00.000',100,'CardinalityNeedle',pg_temp.portal_versions_vector(1,0),'ZZ' || n);
      end loop;
    end loop;
    for i in 1..250 loop
      perform pg_temp.version_fixture(k,('60000000-0000-4000-9000-' || lpad(i::text,12,'0'))::uuid,
        '01.00.000',100,'PrefilterNeedle',
        case when i <= 245 then pg_temp.portal_versions_vector(1,0) else pg_temp.portal_versions_vector(0.9,0.1) end,
        case when i <= 245 then 'US' else 'ZZF' end);
    end loop;
  end loop;
end $$;

create temporary table version_results(label text primary key,payload jsonb);
grant select,insert on version_results to anon,authenticated;
grant execute on function pg_temp.portal_versions_vector_text(real,real) to anon,authenticated;
grant execute on function pg_temp.portal_versions_has_forbidden_key(jsonb) to anon,authenticated;
grant execute on function pg_temp.portal_versions_vector(real,real) to api_internal_executor;
grant execute on function pg_temp.portal_versions_vector_text(real,real) to api_internal_executor;

select extensions.ok(
  (select p.prosrc !~ 'exact_v1|limit 5000|newer\.|latest'
      and p.prosrc ~ 'v_exact_cutover constant integer := 2000'
      and p.prosrc ~ 'v_indexed_probe'
      and p.prosrc ~ 'portal_catalog_facet_rows_v1'
      and p.prosrc ~ 'facet_geography'
      and p.prosrc ~ 'facet_access_level'
      and p.prosrc ~ 'limit v_exact_cutover \+ 1'
      and p.prosrc ~ 'offset 0'
      and p.proconfig @> array['hnsw.iterative_scan=strict_order','hnsw.ef_search=200',
        'hnsw.max_scan_tuples=20000','hnsw.scan_mem_multiplier=2','statement_timeout=20s','row_security=on']
    from pg_proc p
    where p.oid='private.portal_projection_semantic_process_v2(vector,jsonb)'::regprocedure),
  'Process routes at most 2000 indexed exact versions and retains the predecessor HNSW fallback');

select extensions.ok(
  (select p.prosrc !~ 'exact_v1|limit 5000|newer\.|latest'
      and p.prosrc ~ 'v_exact_cutover constant integer := 2000'
      and p.prosrc ~ 'v_indexed_probe'
      and p.prosrc ~ 'portal_catalog_facet_rows_v1'
      and p.prosrc ~ 'facet_geography'
      and p.prosrc ~ 'facet_access_level'
      and p.prosrc ~ 'limit v_exact_cutover \+ 1'
      and p.prosrc ~ 'offset 0'
      and p.proconfig @> array['hnsw.iterative_scan=strict_order','hnsw.ef_search=200',
        'hnsw.max_scan_tuples=20000','hnsw.scan_mem_multiplier=2','statement_timeout=20s','row_security=on']
    from pg_proc p
    where p.oid='private.portal_projection_semantic_flow_v2(vector,jsonb)'::regprocedure),
  'Flow routes at most 2000 indexed exact versions and retains the predecessor HNSW fallback');

select extensions.ok(
  not exists(
    select 1 from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace,
      unnest(array['anon','authenticated','service_role']) as role_name
    where ns.nspname='private'
      and p.proname in ('portal_card_matches_filters_v2','catalog_portal_candidate_rows_v2',
        'portal_projection_semantic_process_v2','portal_projection_semantic_flow_v2',
        'portal_projection_semantic_candidates_v2','portal_projection_hybrid_candidates_v2',
        'portal_projection_hybrid_search_v2_impl','portal_search_v2','catalog_portal_search_v2_impl')
      and has_function_privilege(role_name,p.oid,'EXECUTE')
  ),'private version helpers remain unavailable to every external role');

select extensions.ok(
  has_function_privilege('anon','api.portal_hybrid_search_v2(text,text[],text,jsonb,integer,text)','EXECUTE')
  and not has_function_privilege('service_role','api.portal_hybrid_search_v2(text,text[],text,jsonb,integer,text)','EXECUTE'),
  'new Hybrid API retains the existing public-only role boundary');

-- Prove actual cardinalities (including 199) without relying on textual code checks.
grant api_internal_executor to postgres;
set local role api_internal_executor;
select extensions.is(
  (select count(*) from private.portal_projection_semantic_candidates_v2(
    k,pg_temp.portal_versions_vector(1,0),jsonb_build_object('geography','zz' || n))),
  n::bigint,k || ' semantic ' || n || ' candidates does not trigger pool-filling'
) from unnest(array['process','flow']) as k cross join unnest(array[0,6,199,200]) as n;

select extensions.is(
  (select count(*) from private.portal_projection_semantic_candidates_v2(
    k,pg_temp.portal_versions_vector(1,0),
    '{"geography":"zz199","accessLevel":"open","classification":"portal-hybrid"}'::jsonb)),
  199::bigint,
  k || ' exact route uses indexed geography/access candidates and reapplies the complete filter'
) from unnest(array['process','flow']) as k;

select extensions.is(
  (select pg_catalog.array_agg(candidate.version order by candidate.version)
   from private.portal_projection_semantic_candidates_v2(
     k,pg_temp.portal_versions_vector(0.7,0.7),
     '{"geography":"cn","accessLevel":"open"}'::jsonb
   ) as candidate
   where candidate.id='60000000-0000-4000-8000-000000000002'::uuid),
  array['01.00.000','01.00.001']::text[],
  k || ' exact route returns both qualifying exact versions of one dataset identity'
) from unnest(array['process','flow']) as k;

select extensions.is(
  (select count(*) from private.portal_projection_semantic_candidates_v2(
    k,pg_temp.portal_versions_vector(1,0),
    '{"accessLevel":"open"}'::jsonb)),
  200::bigint,
  k || ' access-level-only exact route retains the 200-candidate branch bound'
) from unnest(array['process','flow']) as k;

select extensions.is(
  (select count(*) from private.portal_projection_hybrid_candidates_v2(
    k,array['cardinalityneedle'],pg_temp.portal_versions_vector(0,0),jsonb_build_object('geography','zz' || n))),
  n::bigint,k || ' lexical ' || n || ' candidates is version-specific and bounded'
) from unnest(array['process','flow']) as k cross join unnest(array[0,6,199,200]) as n;

select extensions.is(
  (select count(*) from private.portal_projection_hybrid_candidates_v2(
    k,array['prefilterneedle'],pg_temp.portal_versions_vector(1,0),'{"geography":"zzf"}')),
  5::bigint,k || ' applies a selective explicit filter before BOTH candidate cutoffs'
) from unnest(array['process','flow']) as k;

select extensions.ok(
  (select count(*) <= 400 and max(lexical_rank) <= 200 and max(semantic_rank) <= 200
    from private.portal_projection_hybrid_candidates_v2(k,array['prefilterneedle'],
      pg_temp.portal_versions_vector(1,0),'{}')),
  k || ' fuses at most 400 unique exact versions from two 200-candidate branches'
) from unnest(array['process','flow']) as k;

reset role;
set local role anon;
insert into version_results values
  ('process_allowlist',api.portal_hybrid_search_v2('process',array['allowlistneedle'],
    pg_temp.portal_versions_vector_text(0,0),'{}',20)),
  ('flow_allowlist',api.portal_hybrid_search_v2('flow',array['allowlistneedle'],
    pg_temp.portal_versions_vector_text(0,0),'{}',20)),
  ('process_split',api.portal_hybrid_search_v2('process',array['historicneedle'],
    pg_temp.portal_versions_vector_text(1,0),'{"geography":"cn"}',20)),
  ('flow_split',api.portal_hybrid_search_v2('flow',array['historicneedle'],
    pg_temp.portal_versions_vector_text(1,0),'{"geography":"cn"}',20)),
  ('lexical_old',api.portal_search_processes_v2('historicneedle')),
  ('legacy_lexical_old',api.portal_search_processes_v1('historicneedle')),
  ('facets_old',api.portal_facets_v2('all','historicneedle')),
  ('versions',api.portal_list_versions_v1('process','60000000-0000-4000-8000-000000000001',null,50));

select extensions.is(
  coalesce((payload ->> 'candidateCount')::integer,jsonb_array_length(payload -> 'items')),
  2,label || ' contains only states 100 and 200')
from version_results where label in ('process_allowlist','flow_allowlist','versions');
select extensions.is(
  (select array_agg(item #>> '{key,version}' order by item #>> '{key,version}')
    from jsonb_array_elements(case when payload ? 'versionGroups'
      then jsonb_path_query_array(payload,'$.versionGroups[*].matches[*]')
      else payload -> 'items' end) as item),
  array['01.00.005','01.00.008']::text[],
  label || ' excludes EVERY other synthetic present/future state code'
) from version_results where label in ('process_allowlist','flow_allowlist','versions');

select extensions.is(
  api.portal_get_dataset_v1(k,'60000000-0000-4000-8000-000000000001',
    '01.00.' || lpad(n::text,3,'0')),
  null::jsonb,k || ' detail conceals non-public state ordinal ' || n
) from unnest(array['process','flow']) as k cross join unnest(array[1,2,3,4,6,7,9,10]) as n;

select extensions.ok(
  exists(select 1 from jsonb_path_query(payload,'$.versionGroups[*].matches[*]') as item
    where item #>> '{key,id}' = '60000000-0000-4000-8000-000000000002'
      and item #>> '{key,version}'='01.00.000'
      and item #> '{match,reasonCodes}'='["lexical_public_projection"]'::jsonb
      and item #> '{match,evidence,semanticRank}'='null'::jsonb)
  and exists(select 1 from jsonb_path_query(payload,'$.versionGroups[*].matches[*]') as item
    where item #>> '{key,id}'='60000000-0000-4000-8000-000000000002'
      and item #>> '{key,version}'='01.00.001'
      and item #> '{match,reasonCodes}'='["semantic_public_projection"]'::jsonb
      and item #> '{match,evidence,lexicalRank}'='null'::jsonb),
  label || ' does not borrow rank or content across versions of one id'
) from version_results where label in ('process_split','flow_split');

select extensions.is(
  (select jsonb_array_length(payload -> 'items') from version_results where label='lexical_old'),
  1,'ordinary V2 search exposes an older matching public version');
select extensions.is(
  (select payload #>> '{items,0,key,version}' from version_results where label='lexical_old'),
  '01.00.000','ordinary V2 search hydrates the exact matching historical version');
select extensions.is(
  (select jsonb_array_length(payload -> 'items') from version_results where label='legacy_lexical_old'),
  0,'unmigrated ordinary V1 callers retain their previous latest-only behavior');

select extensions.is(
  jsonb_array_length(api.portal_hybrid_search_v2('process',array[query],
    pg_temp.portal_versions_vector_text(0,0),'{}',20) -> 'items'),
  1,'original-language literal remains searchable: ' || language
) from (values('fr','électricité historicneedle'),('ru','медь historicneedle'),
  ('ar','نحاس historicneedle'),('zh','铜 historicneedle')) as localized(language,query);

select extensions.is(
  jsonb_array_length(api.portal_search_processes_v2('PRIVATE_DERIVATIVE_ONLY') -> 'items'),
  0,'Portal never broadens multilingual search into private source derivatives');

-- Group BEFORE pagination: many versions must not consume the first result page.
insert into version_results values('version_group',api.portal_hybrid_search_v2(
  'process',array['versionpageneedle'],pg_temp.portal_versions_vector_text(0,0),'{}',10));
select extensions.is(
  (select jsonb_array_length(payload -> 'items') from version_results where label='version_group'),
  1,'35 matching versions occupy one representative result card');
select extensions.is(
  (select jsonb_array_length(payload #> '{versionGroups,0,matches}') from version_results where label='version_group'),
  35,'every matching version remains expandable in that card, not only the latest');
select extensions.is(
  (select payload ->> 'nextCursor' from version_results where label='version_group'),
  null::text,'version-rich groups do not create duplicate group pages');

-- A full 200-candidate union remains traversable across group keyset pages.
with recursive pages(n,payload) as (
  select 1,api.portal_hybrid_search_v2('process',array['prefilterneedle'],
    pg_temp.portal_versions_vector_text(0,0),'{}',10)
  union all
  select pages.n+1,api.portal_hybrid_search_v2('process',array['prefilterneedle'],
    pg_temp.portal_versions_vector_text(0,0),'{}',10,pages.payload ->> 'nextCursor')
  from pages where pages.payload ->> 'nextCursor' is not null and pages.n < 21
)
insert into version_results select 'page_' || n,payload from pages;
select extensions.is(
  (select count(*) from version_results,jsonb_array_elements(payload -> 'items') as item where label like 'page_%'),
  200::bigint,'all 200 recalled dataset groups are reachable through bounded keyset pages');
select extensions.is(
  (select count(distinct item -> 'key') from version_results,jsonb_array_elements(payload -> 'items') as item where label like 'page_%'),
  200::bigint,'Hybrid pagination never duplicates or substitutes exact identities');
select extensions.ok(
  (select bool_and((payload ->> 'candidateCount')::integer=200 and (payload ->> 'datasetCount')::integer=200
    and jsonb_array_length(payload -> 'items')<=10)
    from version_results where label like 'page_%'),
  'candidateCount describes the bounded version union, not a globally exhaustive count');
select extensions.is(
  (select payload ->> 'nextCursor' from version_results where label='page_20'),
  null::text,'last bounded candidate page terminates cleanly');

select extensions.throws_ok(
  $$select api.portal_hybrid_search_v2('process',array['differentquery'],
    pg_temp.portal_versions_vector_text(0,0),'{}',10,
    (select payload ->> 'nextCursor' from version_results where label='page_1'))$$,
  '22023','invalid portal request','Hybrid cursor rejects a changed query');
select extensions.throws_ok(
  $$select api.portal_hybrid_search_v2('process',array['prefilterneedle'],
    pg_temp.portal_versions_vector_text(0,0),'{}',20,
    (select payload ->> 'nextCursor' from version_results where label='page_1'))$$,
  '22023','invalid portal request','Hybrid cursor rejects a changed page size');
select extensions.throws_ok(
  $$select api.portal_hybrid_search_v2('process',array['allowlistneedle'],
    pg_temp.portal_versions_vector_text(1,0),'{"state_code":20}',20)$$,
  '22023','invalid portal request','callers cannot inject a state override');
select extensions.throws_ok(
  $$select api.portal_hybrid_search_v2('process',array['allowlistneedle'],
    pg_temp.portal_versions_vector_text(1,0),'{"team_id":"x"}',20)$$,
  '22023','invalid portal request','callers cannot inject a team override');

select extensions.ok(
  not pg_temp.portal_versions_has_forbidden_key(payload),
  label || ' remains recursively free of raw fields, state, actor and locator data'
) from version_results;
select extensions.ok(
  not exists(
    select 1 from version_results as result,
      jsonb_array_elements(result.payload -> 'versionGroups') with ordinality as groups(value,ordinality)
    where groups.value -> 'key' is distinct from result.payload #> array['items',(groups.ordinality-1)::text,'key']
      or groups.value #> '{matches,0,match}' is distinct from result.payload #> array['items',(groups.ordinality-1)::text,'match']
      or groups.value #> '{matches,0,key}' is distinct from groups.value -> 'key'
      or exists(
        select 1 from jsonb_array_elements(groups.value -> 'matches') as member
        where (member #>> '{match,score}')::numeric > (groups.value #>> '{matches,0,match,score}')::numeric
          or member #>> '{key,id}' is distinct from groups.value #>> '{key,id}'
          or member #>> '{key,kind}' is distinct from groups.value #>> '{key,kind}'
      )
  ),'each group is ranked by its best exact version and keeps version-specific evidence');
select extensions.ok(
  not exists(select 1 from version_results,jsonb_array_elements(coalesce(payload -> 'items','[]'::jsonb)) as item
    where (item #>> '{capabilities,lciaVisible}')::boolean),
  'version-aware catalog reads do not invent LCIA publication authority');

reset role;
grant portal_public_executor to postgres;
set local role portal_public_executor;
select extensions.lives_ok($$select private.assert_portal_catalog_projection_contract_v1()$$,
  'original immutable card/document manifest is unchanged');
select extensions.lives_ok($$select private.assert_portal_card_context_contract_v1()$$,
  'original exact-key context manifest is unchanged');
reset role;
select * from extensions.finish();
rollback;
