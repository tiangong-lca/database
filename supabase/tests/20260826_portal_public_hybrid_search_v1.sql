begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, auth;

select extensions.no_plan();

select extensions.is(
  (
    select count(*)
    from pg_catalog.pg_proc as routine
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = routine.pronamespace
    where namespace.nspname = 'api'
      and routine.proname = 'portal_hybrid_search_v1'
  ),
  1::bigint,
  'exactly one Portal Hybrid API routine exists'
);

select extensions.ok(
  pg_catalog.to_regprocedure(
    'api.portal_hybrid_search_v1(text,text[],text,jsonb,integer)'
  ) is not null,
  'Portal Hybrid API has the exact additive signature'
);

select extensions.ok(
  (
    select routine.proowner = 'portal_public_executor'::regrole
      and routine.prosecdef
      and pg_catalog.pg_get_function_result(routine.oid) = 'jsonb'
      and routine.proconfig @> array['search_path=""', 'statement_timeout=20s']::text[]
      and routine.prosrc ~ 'portal_lcia_decorate_item_page_v1'
      and routine.proargnames = array[
        'p_kind', 'p_query_terms', 'p_query_embedding', 'p_filters', 'p_limit'
      ]::text[]
    from pg_catalog.pg_proc as routine
    where routine.oid = 'api.portal_hybrid_search_v1(text,text[],text,jsonb,integer)'::regprocedure
  ),
  'Portal Hybrid wrapper has its frozen owner, arguments, result, security, and correctness-first 20-second config'
);

select extensions.ok(
  (
    select routine.proowner = 'api_internal_executor'::regrole
      and routine.prosecdef
      and routine.proconfig @> array[
        'search_path=""', 'statement_timeout=20s',
        'plan_cache_mode=force_custom_plan', 'hnsw.iterative_scan=strict_order'
      ]::text[]
    from pg_catalog.pg_proc as routine
    where routine.oid = 'private.portal_projection_hybrid_search_v1_impl(text,text[],extensions.vector,jsonb,integer,text)'::regprocedure
  ),
  'Portal Hybrid kernel is owned by the NOLOGIN/NOBYPASSRLS internal executor with fixed plan controls'
);

select extensions.ok(
  exists (
    select 1 from pg_catalog.pg_roles
    where rolname = 'api_internal_executor'
      and not rolcanlogin and not rolbypassrls and not rolsuper
  )
  and exists (
    select 1 from pg_catalog.pg_roles
    where rolname = 'portal_public_executor'
      and not rolcanlogin and not rolbypassrls and not rolsuper
  ),
  'both Portal Hybrid executor roles remain NOLOGIN, NOBYPASSRLS, and non-superuser'
);

select extensions.ok(
  pg_catalog.has_function_privilege(
    'anon', 'api.portal_hybrid_search_v1(text,text[],text,jsonb,integer)', 'EXECUTE'
  )
  and pg_catalog.has_function_privilege(
    'authenticated', 'api.portal_hybrid_search_v1(text,text[],text,jsonb,integer)', 'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'service_role', 'api.portal_hybrid_search_v1(text,text[],text,jsonb,integer)', 'EXECUTE'
  ),
  'only anon and authenticated gain the public Portal Hybrid grant'
);

select extensions.ok(
  not pg_catalog.has_function_privilege(
    'anon',
    'private.portal_public_hybrid_input_v1(text,text[],text,jsonb,integer)',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'authenticated',
    'private.portal_public_hybrid_input_v1(text,text[],text,jsonb,integer)',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'service_role',
    'private.portal_public_hybrid_input_v1(text,text[],text,jsonb,integer)',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'service_role',
    'private.portal_projection_hybrid_search_v1_impl(text,text[],extensions.vector,jsonb,integer,text)',
    'EXECUTE'
  ),
  'private Portal Hybrid helpers remain external- and service-role-opaque'
);

select extensions.ok(
  exists (
    select 1
    from private.api_capability_grants as manifest
    where manifest.routine_identity
      = 'api.portal_hybrid_search_v1(text, text[], text, jsonb, integer)'
      and manifest.capability_id = 'PORTAL-HYBRID-01'
      and manifest.allow_anon
      and manifest.allow_authenticated
      and not manifest.allow_service_role
  ),
  'capability manifest records the exact Portal Hybrid signature and grants'
);

select extensions.is(
  (
    -- Database #697 routes Sample Library semantic candidates through separate
    -- private helpers. Pin the preserved legacy candidates and changed Hybrid
    -- dispatchers with their owners, security and ACL expectations.
    with expected(
      routine_identity,
      definition_md5,
      owner_name,
      security_definer,
      proconfig_text,
      acl_text
    ) as (
      values
        (
          'api.hybrid_search_flows_v2(text,text,text,double precision,integer,double precision,double precision,integer,text,integer,integer,text[])',
          'a36294ce86731379f01c88ced5c37ca4', 'api_internal_executor', true,
          '{"search_path=api, private, public, util, extensions, extensions, pg_temp",statement_timeout=60s}',
          '{api_internal_executor=X/api_internal_executor,anon=X/api_internal_executor,authenticated=X/api_internal_executor}'
        ),
        (
          'api.hybrid_search_flows(text,text,jsonb,double precision,integer,double precision,double precision,integer,text,integer,integer,text[])',
          'd6a6eaa2291c53ce4c2301a98146f50b', 'api_internal_executor', true,
          '{"search_path=api, private, public, util, extensions, extensions, pg_temp",statement_timeout=60s}',
          '{api_internal_executor=X/api_internal_executor,anon=X/api_internal_executor,authenticated=X/api_internal_executor}'
        ),
        (
          'api.hybrid_search_processes_v2(text,text,text,double precision,integer,double precision,double precision,integer,text,integer,integer,text[])',
          'b4a75c92187f9a88e9db131590c1efd1', 'api_internal_executor', true,
          '{"search_path=api, private, public, util, extensions, extensions, pg_temp",statement_timeout=60s}',
          '{api_internal_executor=X/api_internal_executor,anon=X/api_internal_executor,authenticated=X/api_internal_executor}'
        ),
        (
          'api.hybrid_search_processes(text,text,jsonb,double precision,integer,double precision,double precision,integer,text,integer,integer,text[])',
          'a540312d04fda305d64c0c03e60ed6d3', 'api_internal_executor', true,
          '{"search_path=api, private, public, util, extensions, extensions, pg_temp",statement_timeout=60s}',
          '{api_internal_executor=X/api_internal_executor,anon=X/api_internal_executor,authenticated=X/api_internal_executor}'
        ),
        (
          'private.hybrid_search_flows_v2_impl(text,text,text,double precision,integer,double precision,double precision,integer,text,integer,integer,text[])',
          'd54aa2edb42eeb40878e209c620f7d9e', 'postgres', false,
          '{statement_timeout=60s,"search_path=private, api, public, util, extensions, extensions, pg_temp"}',
          '{postgres=X/postgres,service_role=X/postgres,api_internal_executor=X/postgres}'
        ),
        (
          'private.hybrid_search_processes_v2_impl(text,text,text,double precision,integer,double precision,double precision,integer,text,integer,integer,text[])',
          '8933b5919ef3e7001be9c5320690b57c', 'postgres', false,
          '{statement_timeout=60s,"search_path=private, api, public, util, extensions, extensions, pg_temp"}',
          '{postgres=X/postgres,service_role=X/postgres,api_internal_executor=X/postgres}'
        ),
        (
          'private.semantic_flow_candidates(text,text,double precision,integer,text)',
          'e3d07471dd6bdb23e0eb73ce2e75c519', 'postgres', true,
          '{"search_path=private, api, public, util, extensions, extensions, pg_temp",statement_timeout=60s,plan_cache_mode=force_custom_plan,hnsw.iterative_scan=strict_order}',
          '{postgres=X/postgres,service_role=X/postgres,api_internal_executor=X/postgres}'
        ),
        (
          'private.semantic_process_candidates(text,text,double precision,integer,text)',
          'bcc38849cd377dc7a9ceecef818c0fdd', 'postgres', true,
          '{"search_path=private, api, public, util, extensions, extensions, pg_temp",statement_timeout=60s,plan_cache_mode=force_custom_plan,hnsw.iterative_scan=strict_order}',
          '{postgres=X/postgres,service_role=X/postgres,api_internal_executor=X/postgres}'
        )
    ), actual as (
      select expected.routine_identity,
        pg_catalog.md5(pg_catalog.pg_get_functiondef(routine.oid)) as definition_md5,
        owner_role.rolname as owner_name,
        routine.prosecdef as security_definer,
        coalesce(routine.proconfig, '{}'::text[])::text as proconfig_text,
        coalesce(routine.proacl::text, '') as acl_text
      from expected
      join pg_catalog.pg_proc as routine
        on routine.oid = pg_catalog.to_regprocedure(expected.routine_identity)
      join pg_catalog.pg_roles as owner_role
        on owner_role.oid = routine.proowner
    )
    select count(*)
    from (
      (select * from actual except select * from expected)
      union all
      (select * from expected except select * from actual)
    ) as difference
  ),
  0::bigint,
  'all eight raw Hybrid definitions, owners, security modes, configs, and ACLs match the reviewed Sample Library baseline'
);

select extensions.is(
  (
    with actual as (
      select routine.oid::regprocedure::text as routine_identity,
        coalesce(grantee_role.rolname, 'PUBLIC') as grantee,
        acl.privilege_type,
        acl.is_grantable
      from pg_catalog.pg_proc as routine
      cross join lateral pg_catalog.aclexplode(
        coalesce(routine.proacl, pg_catalog.acldefault('f', routine.proowner))
      ) as acl
      left join pg_catalog.pg_roles as grantee_role on grantee_role.oid = acl.grantee
      where routine.oid in (
        'private.portal_public_hybrid_input_v1(text,text[],text,jsonb,integer)'::regprocedure,
        'private.portal_public_hybrid_card_v1(text,integer,jsonb)'::regprocedure,
        'private.portal_projection_hybrid_search_v1_impl(text,text[],extensions.vector,jsonb,integer,text)'::regprocedure
      )
    ), expected(routine_identity, grantee, privilege_type, is_grantable) as (
      values
        ('private.portal_public_hybrid_input_v1(text,text[],text,jsonb,integer)', 'portal_public_executor', 'EXECUTE', false),
        ('private.portal_public_hybrid_card_v1(text,integer,jsonb)', 'portal_public_executor', 'EXECUTE', false),
        ('private.portal_public_hybrid_card_v1(text,integer,jsonb)', 'api_internal_executor', 'EXECUTE', false),
        ('private.portal_projection_hybrid_search_v1_impl(text,text[],vector,jsonb,integer,text)', 'portal_public_executor', 'EXECUTE', false)
    )
    select count(*)
    from (
      (select * from actual except select * from expected)
      union all
      (select * from expected except select * from actual)
    ) as difference
  ),
  0::bigint,
  'private input, card bridge, and rank kernel have only their exact owner-to-owner execute edges'
);

create or replace function pg_temp.portal_hybrid_localized(p_text text)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select pg_catalog.jsonb_build_array(
    pg_catalog.jsonb_build_object('@xml:lang', 'en', '#text', p_text)
  )
$$;

create or replace function pg_temp.portal_hybrid_publication(
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
      'common:shortDescription', pg_temp.portal_hybrid_localized('Portal Provider')
    )
  )
$$;

create or replace function pg_temp.portal_hybrid_process_payload(
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
            'baseName', pg_temp.portal_hybrid_localized(p_name)
          ),
          'common:generalComment', pg_temp.portal_hybrid_localized(p_name || ' summary'),
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
            'descriptionOfRestrictions', pg_temp.portal_hybrid_localized('China')
          )
        ),
        'technology', pg_catalog.jsonb_build_object(
          'technologyDescriptionAndIncludedProcesses',
          pg_temp.portal_hybrid_localized('Hybrid fixture technology')
        )
      ),
      'modellingAndValidation', pg_catalog.jsonb_build_object(
        'LCIMethodAndAllocation', pg_catalog.jsonb_build_object(
          'typeOfDataSet', 'Unit process, single operation'
        )
      ),
      'administrativeInformation', pg_catalog.jsonb_build_object(
        'publicationAndOwnership', pg_temp.portal_hybrid_publication(
          p_version, 'Free of charge for all users and uses'
        )
      ),
      'privateLocator', 's3://portal-private/process/' || p_name
    )
  )
$$;

create or replace function pg_temp.portal_hybrid_flow_payload(
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
            'baseName', pg_temp.portal_hybrid_localized(p_name)
          ),
          'common:generalComment', pg_temp.portal_hybrid_localized(p_name || ' summary'),
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
            'descriptionOfRestrictions', pg_temp.portal_hybrid_localized('China')
          )
        )
      ),
      'modellingAndValidation', pg_catalog.jsonb_build_object(
        'LCIMethod', pg_catalog.jsonb_build_object('typeOfDataSet', 'Product flow')
      ),
      'administrativeInformation', pg_catalog.jsonb_build_object(
        'publicationAndOwnership', pg_temp.portal_hybrid_publication(
          p_version, 'Free of charge for all users and uses'
        )
      ),
      'objectLocator', 's3://portal-private/flow/' || p_name
    )
  )
$$;

create or replace function pg_temp.portal_hybrid_vector_text(
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

create or replace function pg_temp.portal_hybrid_vector(
  p_first real,
  p_second real
)
returns extensions.vector(1024)
language sql
immutable
set search_path = ''
as $$
  select pg_temp.portal_hybrid_vector_text(p_first, p_second)::extensions.vector(1024)
$$;

create or replace function pg_temp.portal_hybrid_has_forbidden_key(p_payload jsonb)
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

grant execute on function pg_temp.portal_hybrid_vector_text(real, real)
  to anon, authenticated;
grant execute on function pg_temp.portal_hybrid_has_forbidden_key(jsonb)
  to anon, authenticated;

-- Fixture writes bypass every other production derivative hook only inside
-- this rollback-only transaction, while retaining the synchronized Portal
-- projection trigger. Hybrid never depends on a legacy RPC side effect.
alter table public.processes disable trigger user;
alter table public.flows disable trigger user;
alter table public.processes
  enable trigger portal_catalog_projection_content_sync_v1;
alter table public.processes
  enable trigger portal_catalog_projection_content_sync_v2;
alter table public.flows
  enable trigger portal_catalog_projection_content_sync_v1;

insert into public.processes (
  id,
  version,
  json,
  json_ordered,
  user_id,
  team_id,
  review_id,
  state_code,
  rule_verification,
  modified_at,
  embedding_ft,
  embedding_ft_at,
  extracted_md,
  search_text,
  model_id
)
values
  (
    '52900000-0000-4000-8000-000000000101',
    '01.00.000',
    pg_temp.portal_hybrid_process_payload('R2HybridNeedle Combined Process', '01.00.000'),
    pg_temp.portal_hybrid_process_payload('R2HybridNeedle Combined Process', '01.00.000')::json,
    '52900000-0000-4000-8000-000000000001',
    '52900000-0000-4000-8000-000000000002',
    '52900000-0000-4000-8000-000000000003',
    100,
    true,
    '2026-08-26 03:20:01+00',
    pg_temp.portal_hybrid_vector(1, 0),
    '2026-08-26 03:19:01+00',
    'private process derivative must not be returned',
    array['private process search text must not be returned'],
    '52900000-0000-4000-8000-000000000010'
  ),
  (
    '52900000-0000-4000-8000-000000000101',
    '01.00.001',
    pg_temp.portal_hybrid_process_payload('Hidden Newer Combined Process', '01.00.001'),
    pg_temp.portal_hybrid_process_payload('Hidden Newer Combined Process', '01.00.001')::json,
    '52900000-0000-4000-8000-000000000001',
    '52900000-0000-4000-8000-000000000002',
    '52900000-0000-4000-8000-000000000003',
    20,
    true,
    '2026-08-26 03:20:02+00',
    pg_temp.portal_hybrid_vector(1, 0),
    '2026-08-26 03:19:02+00',
    'hidden newer derivative',
    array['hidden newer search text'],
    '52900000-0000-4000-8000-000000000010'
  ),
  (
    '52900000-0000-4000-8000-000000000102',
    '01.00.000',
    pg_temp.portal_hybrid_process_payload('R2HybridNeedle Lexical Process', '01.00.000'),
    pg_temp.portal_hybrid_process_payload('R2HybridNeedle Lexical Process', '01.00.000')::json,
    '52900000-0000-4000-8000-000000000001',
    '52900000-0000-4000-8000-000000000002',
    '52900000-0000-4000-8000-000000000003',
    100,
    true,
    '2026-08-26 03:20:03+00',
    pg_temp.portal_hybrid_vector(0, 1),
    '2026-08-26 03:19:03+00',
    'lexical-only private derivative',
    array['lexical-only private search text'],
    '52900000-0000-4000-8000-000000000010'
  ),
  (
    '52900000-0000-4000-8000-000000000103',
    '01.00.000',
    pg_temp.portal_hybrid_process_payload('Semantic Only Process', '01.00.000'),
    pg_temp.portal_hybrid_process_payload('Semantic Only Process', '01.00.000')::json,
    '52900000-0000-4000-8000-000000000001',
    '52900000-0000-4000-8000-000000000002',
    '52900000-0000-4000-8000-000000000003',
    100,
    true,
    '2026-08-26 03:20:04+00',
    pg_temp.portal_hybrid_vector(1, 0),
    '2026-08-26 03:19:04+00',
    'semantic-only private derivative',
    array['semantic-only private search text'],
    '52900000-0000-4000-8000-000000000010'
  ),
  (
    '52900000-0000-4000-8000-000000000104',
    '01.00.000',
    pg_temp.portal_hybrid_process_payload('R2HybridNeedle Metadata Process', '01.00.000'),
    pg_temp.portal_hybrid_process_payload('R2HybridNeedle Metadata Process', '01.00.000')::json,
    '52900000-0000-4000-8000-000000000001',
    '52900000-0000-4000-8000-000000000002',
    '52900000-0000-4000-8000-000000000003',
    200,
    true,
    '2026-08-26 03:20:05+00',
    pg_temp.portal_hybrid_vector(1, 0),
    '2026-08-26 03:19:05+00',
    'state-200 private derivative',
    array['state-200 private search text'],
    '52900000-0000-4000-8000-000000000010'
  ),
  (
    '52900000-0000-4000-8000-000000000105',
    '01.00.000',
    pg_temp.portal_hybrid_process_payload('R2HybridNeedle Draft Process', '01.00.000'),
    pg_temp.portal_hybrid_process_payload('R2HybridNeedle Draft Process', '01.00.000')::json,
    '52900000-0000-4000-8000-000000000001',
    '52900000-0000-4000-8000-000000000002',
    '52900000-0000-4000-8000-000000000003',
    0,
    true,
    '2026-08-26 03:20:06+00',
    pg_temp.portal_hybrid_vector(1, 0),
    '2026-08-26 03:19:06+00',
    'draft private derivative',
    array['draft private search text'],
    '52900000-0000-4000-8000-000000000010'
  ),
  (
    '52900000-0000-4000-8000-000000000106',
    '01.00.000',
    pg_temp.portal_hybrid_process_payload('R2HybridNeedle Review Process', '01.00.000'),
    pg_temp.portal_hybrid_process_payload('R2HybridNeedle Review Process', '01.00.000')::json,
    '52900000-0000-4000-8000-000000000001',
    '52900000-0000-4000-8000-000000000002',
    '52900000-0000-4000-8000-000000000003',
    20,
    true,
    '2026-08-26 03:20:07+00',
    pg_temp.portal_hybrid_vector(1, 0),
    '2026-08-26 03:19:07+00',
    'review private derivative',
    array['review private search text'],
    '52900000-0000-4000-8000-000000000010'
  ),
  (
    '52900000-0000-4000-8000-000000000107',
    '01.00.000',
    pg_temp.portal_hybrid_process_payload('R2HybridNeedle Historical Trap', '01.00.000'),
    pg_temp.portal_hybrid_process_payload('R2HybridNeedle Historical Trap', '01.00.000')::json,
    '52900000-0000-4000-8000-000000000001',
    '52900000-0000-4000-8000-000000000002',
    '52900000-0000-4000-8000-000000000003',
    100,
    true,
    '2026-08-26 03:20:08+00',
    pg_temp.portal_hybrid_vector(1, 0),
    '2026-08-26 03:19:08+00',
    'historical private derivative',
    array['historical private search text'],
    '52900000-0000-4000-8000-000000000010'
  ),
  (
    '52900000-0000-4000-8000-000000000107',
    '01.00.001',
    pg_temp.portal_hybrid_process_payload('Latest Far Process', '01.00.001'),
    pg_temp.portal_hybrid_process_payload('Latest Far Process', '01.00.001')::json,
    '52900000-0000-4000-8000-000000000001',
    '52900000-0000-4000-8000-000000000002',
    '52900000-0000-4000-8000-000000000003',
    100,
    true,
    '2026-08-26 03:20:09+00',
    pg_temp.portal_hybrid_vector(-1, 0),
    '2026-08-26 03:19:09+00',
    'latest far private derivative',
    array['latest far private search text'],
    '52900000-0000-4000-8000-000000000010'
  );

insert into public.flows (
  id,
  version,
  json,
  json_ordered,
  user_id,
  team_id,
  review_id,
  state_code,
  rule_verification,
  modified_at,
  embedding_ft,
  embedding_ft_at,
  extracted_md,
  search_text
)
values
  (
    '52900000-0000-4000-8000-000000000201',
    '01.00.000',
    pg_temp.portal_hybrid_flow_payload('R2HybridNeedle Combined Flow', '01.00.000'),
    pg_temp.portal_hybrid_flow_payload('R2HybridNeedle Combined Flow', '01.00.000')::json,
    '52900000-0000-4000-8000-000000000001',
    '52900000-0000-4000-8000-000000000002',
    '52900000-0000-4000-8000-000000000003',
    100,
    true,
    '2026-08-26 03:21:01+00',
    pg_temp.portal_hybrid_vector(1, 0),
    '2026-08-26 03:19:11+00',
    'private flow derivative must not be returned',
    array['private flow search text must not be returned']
  ),
  (
    '52900000-0000-4000-8000-000000000202',
    '01.00.000',
    pg_temp.portal_hybrid_flow_payload('Semantic Metadata Flow', '01.00.000'),
    pg_temp.portal_hybrid_flow_payload('Semantic Metadata Flow', '01.00.000')::json,
    '52900000-0000-4000-8000-000000000001',
    '52900000-0000-4000-8000-000000000002',
    '52900000-0000-4000-8000-000000000003',
    200,
    true,
    '2026-08-26 03:21:02+00',
    pg_temp.portal_hybrid_vector(1, 0),
    '2026-08-26 03:19:12+00',
    'private metadata flow derivative',
    array['private metadata flow search text']
  ),
  (
    '52900000-0000-4000-8000-000000000203',
    '01.00.000',
    pg_temp.portal_hybrid_flow_payload('R2HybridNeedle Draft Flow', '01.00.000'),
    pg_temp.portal_hybrid_flow_payload('R2HybridNeedle Draft Flow', '01.00.000')::json,
    '52900000-0000-4000-8000-000000000001',
    '52900000-0000-4000-8000-000000000002',
    '52900000-0000-4000-8000-000000000003',
    0,
    true,
    '2026-08-26 03:21:03+00',
    pg_temp.portal_hybrid_vector(1, 0),
    '2026-08-26 03:19:13+00',
    'private draft flow derivative',
    array['private draft flow search text']
  ),
  (
    '52900000-0000-4000-8000-000000000204',
    '01.00.000',
    pg_temp.portal_hybrid_flow_payload('R2HybridNeedle Review Flow', '01.00.000'),
    pg_temp.portal_hybrid_flow_payload('R2HybridNeedle Review Flow', '01.00.000')::json,
    '52900000-0000-4000-8000-000000000001',
    '52900000-0000-4000-8000-000000000002',
    '52900000-0000-4000-8000-000000000003',
    20,
    true,
    '2026-08-26 03:21:04+00',
    pg_temp.portal_hybrid_vector(1, 0),
    '2026-08-26 03:19:14+00',
    'private review flow derivative',
    array['private review flow search text']
  );

create temporary table portal_hybrid_results (
  label text primary key,
  payload jsonb not null
) on commit drop;

grant select, insert, update, delete on portal_hybrid_results to anon, authenticated;

set local role anon;

select extensions.is(
  (select count(*) from public.processes),
  0::bigint,
  'anon cannot read raw Process rows through table RLS'
);

select extensions.is(
  (select count(*) from public.flows),
  0::bigint,
  'anon cannot read raw Flow rows through table RLS'
);

insert into portal_hybrid_results (label, payload)
values
  (
    'process_main',
    api.portal_hybrid_search_v1(
      'process',
      array[' R2HYBRIDNEEDLE '],
      pg_temp.portal_hybrid_vector_text(1, 0),
      '{}'::jsonb,
      20
    )
  ),
  (
    'process_repeat',
    api.portal_hybrid_search_v1(
      'process',
      array['r2hybridneedle'],
      pg_temp.portal_hybrid_vector_text(1, 0),
      '{}'::jsonb,
      20
    )
  ),
  (
    'process_open',
    api.portal_hybrid_search_v1(
      'process',
      array['r2hybridneedle'],
      pg_temp.portal_hybrid_vector_text(1, 0),
      '{"accessLevel":"open"}'::jsonb,
      20
    )
  ),
  (
    'process_metadata',
    api.portal_hybrid_search_v1(
      'process',
      array['r2hybridneedle'],
      pg_temp.portal_hybrid_vector_text(1, 0),
      '{"accessLevel":"metadata_only"}'::jsonb,
      20
    )
  ),
  (
    'process_all_filters',
    api.portal_hybrid_search_v1(
      'process',
      array['r2hybridneedle'],
      pg_temp.portal_hybrid_vector_text(1, 0),
      '{
        "accessLevel":"open",
        "geography":" CN ",
        "classification":" PORTAL-HYBRID ",
        "referenceYearFrom":2024,
        "referenceYearTo":2024,
        "processSubtype":" UNIT PROCESS, SINGLE OPERATION ",
        "source":" PORTAL PROVIDER "
      }'::jsonb,
      20
    )
  ),
  (
    'process_empty',
    api.portal_hybrid_search_v1(
      'process',
      array['never-matches-lexically'],
      pg_temp.portal_hybrid_vector_text(0, 1),
      '{"geography":"zz"}'::jsonb,
      20
    )
  ),
  (
    'flow_main',
    api.portal_hybrid_search_v1(
      'flow',
      array['r2hybridneedle'],
      pg_temp.portal_hybrid_vector_text(1, 0),
      '{}'::jsonb,
      20
    )
  ),
  (
    'flow_metadata',
    api.portal_hybrid_search_v1(
      'flow',
      array['never-matches-lexically'],
      pg_temp.portal_hybrid_vector_text(1, 0),
      '{"accessLevel":"metadata_only"}'::jsonb,
      20
    )
  );

select extensions.ok(
  (
    select (select count(*) from pg_catalog.jsonb_object_keys(payload)) = 4
      and payload ->> 'schemaVersion' = 'portal.public-hybrid-candidate-page.v1'
      and payload ->> 'kind' = 'process'
      and payload ->> 'queryFingerprint' ~ '^[0-9a-f]{64}$'
      and pg_catalog.jsonb_typeof(payload -> 'items') = 'array'
    from portal_hybrid_results
    where label = 'process_main'
  ),
  'Process Hybrid output has the exact candidate-page envelope'
);

select extensions.ok(
  (
    select (select count(*) from pg_catalog.jsonb_object_keys(payload)) = 4
      and payload ->> 'schemaVersion' = 'portal.public-hybrid-candidate-page.v1'
      and payload ->> 'kind' = 'flow'
      and payload ->> 'queryFingerprint' ~ '^[0-9a-f]{64}$'
      and pg_catalog.jsonb_typeof(payload -> 'items') = 'array'
    from portal_hybrid_results
    where label = 'flow_main'
  ),
  'Flow Hybrid output has the exact candidate-page envelope'
);

select extensions.ok(
  not exists (
    select 1
    from portal_hybrid_results as result
    cross join lateral pg_catalog.jsonb_object_keys(result.payload) as envelope_key(key)
    where envelope_key.key not in ('schemaVersion', 'kind', 'queryFingerprint', 'items')
  ),
  'Hybrid envelopes contain no uncontracted field'
);

select extensions.ok(
  not exists (
    select 1
    from portal_hybrid_results as result
    cross join lateral pg_catalog.jsonb_array_elements(result.payload -> 'items') as candidate(item)
    where (select count(*) from pg_catalog.jsonb_object_keys(candidate.item)) <> 10
       or exists (
         select 1
         from pg_catalog.jsonb_object_keys(candidate.item) as candidate_key(key)
         where candidate_key.key not in (
           'key', 'accessLevel', 'capabilities', 'names', 'summary', 'geography',
           'referenceYear', 'context', 'modifiedAt', 'match'
         )
       )
  ),
  'every Hybrid item contains only the exact R1 card projection plus match evidence'
);

select extensions.ok(
  exists (
    select 1
    from portal_hybrid_results as result
    cross join lateral pg_catalog.jsonb_array_elements(result.payload -> 'items') as candidate(item)
    where result.label = 'process_main'
      and candidate.item #>> '{key,id}' = '52900000-0000-4000-8000-000000000101'
      and candidate.item #>> '{key,version}' = '01.00.000'
      and candidate.item #> '{match,reasonCodes}' = jsonb_build_array(
        'lexical_public_projection', 'semantic_public_projection'
      )
      and (candidate.item #>> '{match,evidence,lexicalRank}')::integer >= 1
      and (candidate.item #>> '{match,evidence,semanticRank}')::integer >= 1
      and (candidate.item #>> '{match,evidence,semanticDistance}')::numeric >= 0
  ),
  'combined Process candidate exposes both actual retrieval branches and the latest visible exact version'
);

select extensions.ok(
  exists (
    select 1
    from portal_hybrid_results as result
    cross join lateral pg_catalog.jsonb_array_elements(result.payload -> 'items') as candidate(item)
    where result.label = 'process_main'
      and candidate.item #>> '{key,id}' = '52900000-0000-4000-8000-000000000102'
      and candidate.item #> '{match,reasonCodes}' = jsonb_build_array(
        'lexical_public_projection'
      )
      and (candidate.item #>> '{match,evidence,lexicalRank}')::integer >= 1
      and candidate.item #> '{match,evidence,semanticRank}' = 'null'::jsonb
      and candidate.item #> '{match,evidence,semanticDistance}' = 'null'::jsonb
  ),
  'lexical-only Process evidence does not invent a semantic match'
);

select extensions.ok(
  exists (
    select 1
    from portal_hybrid_results as result
    cross join lateral pg_catalog.jsonb_array_elements(result.payload -> 'items') as candidate(item)
    where result.label = 'process_main'
      and candidate.item #>> '{key,id}' = '52900000-0000-4000-8000-000000000103'
      and candidate.item #> '{match,reasonCodes}' = jsonb_build_array(
        'semantic_public_projection'
      )
      and candidate.item #> '{match,evidence,lexicalRank}' = 'null'::jsonb
      and (candidate.item #>> '{match,evidence,semanticRank}')::integer >= 1
      and (candidate.item #>> '{match,evidence,semanticDistance}')::numeric >= 0
  ),
  'semantic-only Process evidence does not invent a lexical match'
);

select extensions.ok(
  exists (
    select 1
    from portal_hybrid_results as result
    cross join lateral pg_catalog.jsonb_array_elements(result.payload -> 'items') as candidate(item)
    where result.label = 'process_main'
      and candidate.item #>> '{key,id}' = '52900000-0000-4000-8000-000000000104'
      and candidate.item ->> 'accessLevel' = 'metadata_only'
  ),
  'fixed Process scope unifies state 100 and state 200 before ranking'
);

select extensions.ok(
  not exists (
    select 1
    from portal_hybrid_results as result
    cross join lateral pg_catalog.jsonb_array_elements(result.payload -> 'items') as candidate(item)
    where result.label = 'process_main'
      and candidate.item #>> '{key,id}' in (
        '52900000-0000-4000-8000-000000000105',
        '52900000-0000-4000-8000-000000000106',
        '52900000-0000-4000-8000-000000000107'
      )
  ),
  'draft, review, and historical-near/latest-far Process rows are opaque to Hybrid output'
);

select extensions.ok(
  exists (
    select 1
    from portal_hybrid_results as result
    cross join lateral pg_catalog.jsonb_array_elements(result.payload -> 'items') as candidate(item)
    where result.label = 'flow_main'
      and candidate.item #>> '{key,id}' = '52900000-0000-4000-8000-000000000201'
      and candidate.item #> '{match,reasonCodes}' = jsonb_build_array(
        'lexical_public_projection', 'semantic_public_projection'
      )
  )
  and exists (
    select 1
    from portal_hybrid_results as result
    cross join lateral pg_catalog.jsonb_array_elements(result.payload -> 'items') as candidate(item)
    where result.label = 'flow_main'
      and candidate.item #>> '{key,id}' = '52900000-0000-4000-8000-000000000202'
      and candidate.item ->> 'accessLevel' = 'metadata_only'
      and candidate.item #> '{match,reasonCodes}' = jsonb_build_array(
        'semantic_public_projection'
      )
  ),
  'Flow ranking combines exact state-100 and state-200 lexical and semantic candidates'
);

select extensions.ok(
  not exists (
    select 1
    from portal_hybrid_results as result
    cross join lateral pg_catalog.jsonb_array_elements(result.payload -> 'items') as candidate(item)
    where result.label = 'flow_main'
      and candidate.item #>> '{key,id}' in (
        '52900000-0000-4000-8000-000000000203',
        '52900000-0000-4000-8000-000000000204'
      )
  ),
  'Flow draft and review candidates remain opaque'
);

select extensions.ok(
  not exists (
    select 1
    from portal_hybrid_results as result
    cross join lateral pg_catalog.jsonb_array_elements(result.payload -> 'items') as candidate(item)
    where candidate.item #>> '{key,kind}' <> result.payload ->> 'kind'
       or candidate.item #>> '{key,version}' !~ '^\d{2}\.\d{2}\.\d{3}$'
       or candidate.item #>> '{match,kind}' <> 'hybrid'
       or candidate.item #>> '{match,algorithmVersion}' <> 'portal-hybrid-rank-v1'
       or pg_catalog.jsonb_typeof(candidate.item #> '{match,score}') <> 'number'
       or (candidate.item #>> '{match,score}')::numeric not between 0 and 1
       or pg_catalog.jsonb_array_length(candidate.item #> '{match,reasonCodes}') not between 1 and 2
       or (
         (candidate.item #> '{match,reasonCodes}' ? 'lexical_public_projection')
         <> (candidate.item #> '{match,evidence,lexicalRank}' <> 'null'::jsonb)
       )
       or (
         (candidate.item #> '{match,reasonCodes}' ? 'semantic_public_projection')
         <> (
           candidate.item #> '{match,evidence,semanticRank}' <> 'null'::jsonb
           and candidate.item #> '{match,evidence,semanticDistance}' <> 'null'::jsonb
         )
       )
       or (
         candidate.item #> '{match,evidence,semanticDistance}' <> 'null'::jsonb
         and (
           candidate.item #>> '{match,evidence,semanticDistance}'
             !~ '^(0|[1-9][0-9]*(\.[0-9]*[1-9])?|0\.[0-9]*[1-9])$'
           or (candidate.item #>> '{match,evidence,semanticDistance}')::numeric < 0
         )
       )
  ),
  'all match scores, evidence pairs, reason codes, kinds, versions, and distances satisfy the exact contract'
);

select extensions.ok(
  not exists (
    select 1
    from portal_hybrid_results as result
    cross join lateral pg_catalog.jsonb_array_elements(result.payload -> 'items') as candidate(item)
    group by result.label,
      candidate.item #>> '{key,kind}',
      candidate.item #>> '{key,id}',
      candidate.item #>> '{key,version}'
    having count(*) > 1
  ),
  'every page contains unique exact kind:id@version candidate references'
);

select extensions.ok(
  not exists (
    select 1
    from portal_hybrid_results
    where pg_catalog.jsonb_array_length(payload -> 'items') > 20
       or pg_catalog.octet_length(pg_catalog.convert_to(payload::text, 'UTF8')) > 524288
  ),
  'every Hybrid page stays within the fixed 20-item and 512-KiB response bounds'
);

select extensions.is(
  (select payload from portal_hybrid_results where label = 'process_main'),
  (select payload from portal_hybrid_results where label = 'process_repeat'),
  'equivalent normalized Hybrid inputs are deterministic, including their fingerprint'
);

select extensions.is(
  (select pg_catalog.jsonb_array_length(payload -> 'items') from portal_hybrid_results where label = 'process_metadata'),
  1,
  'metadata-only filter is applied to public cards before the final limit'
);

select extensions.is(
  (
    select candidate.item #>> '{key,id}'
    from portal_hybrid_results as result
    cross join lateral pg_catalog.jsonb_array_elements(result.payload -> 'items') as candidate(item)
    where result.label = 'process_metadata'
  ),
  '52900000-0000-4000-8000-000000000104',
  'metadata-only filter selects the exact state-200 Process card'
);

select extensions.ok(
  not exists (
    select 1
    from portal_hybrid_results as result
    cross join lateral pg_catalog.jsonb_array_elements(result.payload -> 'items') as candidate(item)
    where result.label = 'process_open'
      and candidate.item ->> 'accessLevel' <> 'open'
  ),
  'open filter excludes all metadata-only candidates'
);

select extensions.ok(
  exists (
    select 1
    from portal_hybrid_results as result
    cross join lateral pg_catalog.jsonb_array_elements(result.payload -> 'items') as candidate(item)
    where result.label = 'process_all_filters'
      and candidate.item #>> '{key,id}' = '52900000-0000-4000-8000-000000000101'
  )
  and not exists (
    select 1
    from portal_hybrid_results as result
    cross join lateral pg_catalog.jsonb_array_elements(result.payload -> 'items') as candidate(item)
    where result.label = 'process_all_filters'
      and candidate.item ->> 'accessLevel' <> 'open'
  ),
  'geography, classification, year, subtype, and source filters normalize then match public cards'
);

select extensions.is(
  (select payload -> 'items' from portal_hybrid_results where label = 'process_empty'),
  '[]'::jsonb,
  'a filtered empty result is a strict empty candidate array'
);

select extensions.is(
  (select pg_catalog.jsonb_array_length(payload -> 'items') from portal_hybrid_results where label = 'flow_metadata'),
  1,
  'Flow metadata-only filter selects the fixed state-200 semantic candidate'
);

select extensions.ok(
  not exists (
    select 1
    from portal_hybrid_results
    where pg_temp.portal_hybrid_has_forbidden_key(payload)
  ),
  'Hybrid DTOs recursively exclude actor, team, review, state, raw JSON, embeddings, locators, and errors'
);

select extensions.ok(
  not exists (
    select 1
    from portal_hybrid_results
    where payload::text like '%52900000-0000-4000-8000-000000000001%'
       or payload::text like '%52900000-0000-4000-8000-000000000002%'
       or payload::text like '%52900000-0000-4000-8000-000000000003%'
       or payload::text like '%private derivative%'
       or payload::text ~* '(service_role|s3://portal-private|private search text)'
  ),
  'Hybrid DTO values contain no fixture identities, derivatives, credentials, or storage locators'
);

insert into portal_hybrid_results (label, payload)
values
  (
    'normalized_unicode_filter_boundary',
    api.portal_hybrid_search_v1(
      'process',
      array['never-matches-lexically'],
      pg_temp.portal_hybrid_vector_text(0, 1),
      pg_catalog.jsonb_build_object('source', repeat('İ', 64)),
      20
    )
  ),
  (
    'normalized_whitespace_filter',
    api.portal_hybrid_search_v1(
      'process',
      array['never-matches-lexically'],
      pg_temp.portal_hybrid_vector_text(0, 1),
      pg_catalog.jsonb_build_object('source', repeat(' ', 5000) || 'portal provider'),
      20
    )
  );

select extensions.ok(
  exists (
    select 1
    from portal_hybrid_results
    where label = 'normalized_unicode_filter_boundary'
      and payload ->> 'queryFingerprint' ~ '^[0-9a-f]{64}$'
  ),
  '64 capital dotted-I filter characters pass after trim/lower expansion to 128 code points'
);

select extensions.ok(
  exists (
    select 1
    from portal_hybrid_results
    where label = 'normalized_whitespace_filter'
      and payload ->> 'queryFingerprint' ~ '^[0-9a-f]{64}$'
  ),
  'filter scalar and serialized-size bounds are applied after trim/lower normalization'
);

select extensions.throws_ok(
  $$
    select api.portal_hybrid_search_v1(
      null,
      array['term'],
      pg_temp.portal_hybrid_vector_text(1, 0),
      '{}'::jsonb,
      20
    )
  $$,
  '22023',
  'invalid portal request',
  'null kind fails closed'
);

select extensions.throws_ok(
  $$
    select api.portal_hybrid_search_v1(
      'all',
      array['term'],
      pg_temp.portal_hybrid_vector_text(1, 0),
      '{}'::jsonb,
      20
    )
  $$,
  '22023',
  'invalid portal request',
  'only fixed Process and Flow kinds are accepted'
);

select extensions.throws_ok(
  $$
    select api.portal_hybrid_search_v1(
      'process',
      array[]::text[],
      pg_temp.portal_hybrid_vector_text(1, 0),
      '{}'::jsonb,
      20
    )
  $$,
  '22023',
  'invalid portal request',
  'zero query terms fail closed'
);

select extensions.throws_ok(
  $$
    select api.portal_hybrid_search_v1(
      'process',
      array(select 'term-' || ordinal from pg_catalog.generate_series(1, 13) as ordinal),
      pg_temp.portal_hybrid_vector_text(1, 0),
      '{}'::jsonb,
      20
    )
  $$,
  '22023',
  'invalid portal request',
  'the thirteenth query term is rejected'
);

select extensions.throws_ok(
  $$
    select api.portal_hybrid_search_v1(
      'process',
      array[' Term ', 'term'],
      pg_temp.portal_hybrid_vector_text(1, 0),
      '{}'::jsonb,
      20
    )
  $$,
  '22023',
  'invalid portal request',
  'query terms must be unique after canonical trim/lower normalization'
);

select extensions.throws_ok(
  $$
    select api.portal_hybrid_search_v1(
      'process',
      array[['term-a', 'term-b']]::text[],
      pg_temp.portal_hybrid_vector_text(1, 0),
      '{}'::jsonb,
      20
    )
  $$,
  '22023',
  'invalid portal request',
  'multidimensional query-term arrays fail closed'
);

select extensions.throws_ok(
  $$
    select api.portal_hybrid_search_v1(
      'process',
      array[null]::text[],
      pg_temp.portal_hybrid_vector_text(1, 0),
      '{}'::jsonb,
      20
    )
  $$,
  '22023',
  'invalid portal request',
  'null query terms fail closed'
);

select extensions.throws_ok(
  $$
    select api.portal_hybrid_search_v1(
      'process',
      array[repeat('x', 513)],
      pg_temp.portal_hybrid_vector_text(1, 0),
      '{}'::jsonb,
      20
    )
  $$,
  '22023',
  'invalid portal request',
  'normalized query terms cannot exceed 512 Unicode code points'
);

select extensions.throws_ok(
  $$
    select api.portal_hybrid_search_v1(
      'process',
      array['bad' || pg_catalog.chr(1) || 'term'],
      pg_temp.portal_hybrid_vector_text(1, 0),
      '{}'::jsonb,
      20
    )
  $$,
  '22023',
  'invalid portal request',
  'C0 controls are rejected in normalized query terms'
);

select extensions.throws_ok(
  $$
    select api.portal_hybrid_search_v1(
      'process',
      array['bad' || pg_catalog.chr(133) || 'term'],
      pg_temp.portal_hybrid_vector_text(1, 0),
      '{}'::jsonb,
      20
    )
  $$,
  '22023',
  'invalid portal request',
  'C1 controls are rejected in normalized query terms'
);

select extensions.throws_ok(
  $$
    select api.portal_hybrid_search_v1(
      'process',
      array['term'],
      '[0]',
      '{}'::jsonb,
      20
    )
  $$,
  '22023',
  'invalid portal request',
  'query embeddings must have exactly 1024 dimensions'
);

select extensions.throws_ok(
  $$
    select api.portal_hybrid_search_v1(
      'process',
      array['term'],
      '[NaN]',
      '{}'::jsonb,
      20
    )
  $$,
  '22023',
  'invalid portal request',
  'NaN embedding input fails closed'
);

select extensions.throws_ok(
  $$
    select api.portal_hybrid_search_v1(
      'process',
      array['term'],
      '[Infinity]',
      '{}'::jsonb,
      20
    )
  $$,
  '22023',
  'invalid portal request',
  'infinite embedding input fails closed'
);

select extensions.throws_ok(
  $$
    select api.portal_hybrid_search_v1(
      'process',
      array['term'],
      pg_temp.portal_hybrid_vector_text(1, 0),
      '{"actor":"forged"}'::jsonb,
      20
    )
  $$,
  '22023',
  'invalid portal request',
  'forged actor and every extra filter field fail closed'
);

select extensions.throws_ok(
  $$
    select api.portal_hybrid_search_v1(
      'flow',
      array['term'],
      pg_temp.portal_hybrid_vector_text(1, 0),
      '{"processSubtype":"product flow"}'::jsonb,
      20
    )
  $$,
  '22023',
  'invalid portal request',
  'Flow rejects the Process-only subtype filter'
);

select extensions.throws_ok(
  $$
    select api.portal_hybrid_search_v1(
      'process',
      array['term'],
      pg_temp.portal_hybrid_vector_text(1, 0),
      pg_catalog.jsonb_build_object('source', repeat('İ', 128)),
      20
    )
  $$,
  '22023',
  'invalid portal request',
  '128 capital dotted-I filter characters fail after lowercase expansion beyond 128 code points'
);

select extensions.throws_ok(
  $$
    select api.portal_hybrid_search_v1(
      'process',
      array['term'],
      pg_temp.portal_hybrid_vector_text(1, 0),
      pg_catalog.jsonb_build_object('source', 'bad' || pg_catalog.chr(133) || 'filter'),
      20
    )
  $$,
  '22023',
  'invalid portal request',
  'normalized filters reject C0/C1 controls'
);

select extensions.throws_ok(
  $$
    select api.portal_hybrid_search_v1(
      'process',
      array['term'],
      pg_temp.portal_hybrid_vector_text(1, 0),
      '{"source":"   "}'::jsonb,
      20
    )
  $$,
  '22023',
  'invalid portal request',
  'blank normalized filter strings fail closed'
);

select extensions.throws_ok(
  $$
    select api.portal_hybrid_search_v1(
      'process',
      array['term'],
      pg_temp.portal_hybrid_vector_text(1, 0),
      '{"accessLevel":" OPEN "}'::jsonb,
      20
    )
  $$,
  '22023',
  'invalid portal request',
  'accessLevel remains an exact public enum rather than a free-form normalized filter'
);

select extensions.throws_ok(
  $$
    select api.portal_hybrid_search_v1(
      'process',
      array['term'],
      pg_temp.portal_hybrid_vector_text(1, 0),
      '{"referenceYearFrom":2025,"referenceYearTo":2024}'::jsonb,
      20
    )
  $$,
  '22023',
  'invalid portal request',
  'reference year lower bound cannot exceed the upper bound'
);

select extensions.throws_ok(
  $$
    select api.portal_hybrid_search_v1(
      'process',
      array['term'],
      pg_temp.portal_hybrid_vector_text(1, 0),
      '{"referenceYearFrom":1.5}'::jsonb,
      20
    )
  $$,
  '22023',
  'invalid portal request',
  'reference years must be integers'
);

select extensions.throws_ok(
  $$
    select api.portal_hybrid_search_v1(
      'process',
      array['term'],
      pg_temp.portal_hybrid_vector_text(1, 0),
      '{"referenceYearTo":10000}'::jsonb,
      20
    )
  $$,
  '22023',
  'invalid portal request',
  'reference years are capped at 9999'
);

select extensions.throws_ok(
  $$
    select api.portal_hybrid_search_v1(
      'process',
      array['term'],
      pg_temp.portal_hybrid_vector_text(1, 0),
      '{}'::jsonb,
      0
    )
  $$,
  '22023',
  'invalid portal request',
  'Hybrid limit zero fails closed'
);

select extensions.throws_ok(
  $$
    select api.portal_hybrid_search_v1(
      'process',
      array['term'],
      pg_temp.portal_hybrid_vector_text(1, 0),
      '{}'::jsonb,
      21
    )
  $$,
  '22023',
  'invalid portal request',
  'Hybrid limit cannot exceed 20'
);

reset role;
set local role authenticated;

select extensions.ok(
  (
    select result ->> 'schemaVersion' = 'portal.public-hybrid-candidate-page.v1'
      and result ->> 'kind' = 'flow'
    from (
      select api.portal_hybrid_search_v1(
        'flow',
        array['r2hybridneedle'],
        pg_temp.portal_hybrid_vector_text(1, 0),
        '{}'::jsonb,
        20
      ) as result
    ) as direct_call
  ),
  'authenticated receives the same exact public Hybrid facade contract'
);

reset role;

select extensions.ok(
  (
    select pg_catalog.pg_get_functiondef(routine.oid)
      !~ 'api\.hybrid_search_(processes|flows)'
      and pg_catalog.pg_get_functiondef(routine.oid)
        !~ 'private\.hybrid_search_(processes|flows)_v2_impl'
      and pg_catalog.pg_get_functiondef(routine.oid)
        !~ 'private\.semantic_(process|flow)_candidates'
    from pg_catalog.pg_proc as routine
    where routine.oid = 'api.portal_hybrid_search_v1(text,text[],text,jsonb,integer)'::regprocedure
  )
  and (
    select pg_catalog.pg_get_functiondef(routine.oid)
      !~ 'api\.hybrid_search_(processes|flows)'
      and pg_catalog.pg_get_functiondef(routine.oid)
        !~ 'private\.hybrid_search_(processes|flows)_v2_impl'
      and pg_catalog.pg_get_functiondef(routine.oid)
        !~ 'private\.semantic_(process|flow)_candidates'
    from pg_catalog.pg_proc as routine
    where routine.oid = 'private.portal_projection_hybrid_search_v1_impl(text,text[],extensions.vector,jsonb,integer,text)'::regprocedure
  ),
  'Portal Hybrid routines call only the projection kernel and isolated source-HNSW helpers'
);

select extensions.ok(
  pg_catalog.to_regprocedure(
    'private.portal_public_hybrid_search_v1_impl(text,text[],extensions.vector,jsonb,integer,text)'
  ) is null,
  'the superseded raw-source Portal Hybrid kernel is removed at cutover'
);

select * from extensions.finish();

rollback;
