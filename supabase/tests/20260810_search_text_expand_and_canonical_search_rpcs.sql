begin;

create extension if not exists pgtap with schema extensions;

select extensions.plan(31);

create temporary table issue_459_canonical_search_rpcs (
  routine_identity text primary key,
  rpc_family text not null
) on commit drop;

insert into issue_459_canonical_search_rpcs (routine_identity, rpc_family)
values
  ('api.search_contacts(text, jsonb, integer, integer, text, text, uuid, integer)', 'lexical'),
  ('api.search_flowproperties(text, jsonb, integer, integer, text, text, uuid, integer)', 'lexical'),
  ('api.search_flows(text, jsonb, integer, integer, text, text, uuid, integer, text[])', 'lexical'),
  ('api.search_lifecyclemodels(text, jsonb, integer, integer, text, text, uuid, integer, text[])', 'lexical'),
  ('api.search_processes(text, jsonb, integer, integer, text, text, uuid, integer, text, text[], boolean)', 'lexical'),
  ('api.search_sources(text, jsonb, integer, integer, text, text, uuid, integer)', 'lexical'),
  ('api.search_unitgroups(text, jsonb, integer, integer, text, text, uuid, integer)', 'lexical'),
  ('api.hybrid_search_contacts(text, text, jsonb, double precision, integer, double precision, double precision, integer, text, integer, integer, text[], integer, uuid)', 'hybrid'),
  ('api.hybrid_search_flowproperties(text, text, jsonb, double precision, integer, double precision, double precision, integer, text, integer, integer, text[], integer, uuid)', 'hybrid'),
  ('api.hybrid_search_flows(text, text, jsonb, double precision, integer, double precision, double precision, integer, text, integer, integer, text[])', 'hybrid'),
  ('api.hybrid_search_lifecyclemodels(text, text, jsonb, double precision, integer, double precision, double precision, integer, text, integer, integer, text[])', 'hybrid'),
  ('api.hybrid_search_processes(text, text, jsonb, double precision, integer, double precision, double precision, integer, text, integer, integer, text[])', 'hybrid'),
  ('api.hybrid_search_sources(text, text, jsonb, double precision, integer, double precision, double precision, integer, text, integer, integer, text[], integer, uuid)', 'hybrid'),
  ('api.hybrid_search_unitgroups(text, text, jsonb, double precision, integer, double precision, double precision, integer, text, integer, integer, text[], integer, uuid)', 'hybrid');

select extensions.is(
  (select count(*) from information_schema.columns
   where table_schema = 'public'
     and table_name in ('contacts', 'flowproperties', 'flows', 'lifecyclemodels', 'processes', 'sources', 'unitgroups')
     and column_name = 'search_text'
     and data_type = 'ARRAY'
     and udt_name = '_text'
     and is_nullable = 'YES'
     and column_default is null),
  7::bigint,
  'all seven search_text columns are nullable text[] values with no default'
);

select extensions.ok(
  (
    select trigger.tgtype = 19 and trigger.tgattr = ''::int2vector
      and trigger.tgfoid = 'private.dataset_flow_identity_active_fence()'::regprocedure
    from pg_trigger as trigger
    where trigger.tgrelid = 'public.flows'::regclass
      and trigger.tgname = 'flows_z_identity_active_fence'
      and not trigger.tgisinternal
  ),
  'Flow updates including search_text reach the row-value identity fence'
);

select extensions.is(
  (
    select count(*)
    from pg_proc as routine
    join pg_namespace as namespace on namespace.oid = routine.pronamespace
    where namespace.nspname = 'api'
      and routine.proname = any (array[
        'search_contacts', 'search_flowproperties', 'search_flows',
        'search_lifecyclemodels', 'search_processes', 'search_sources',
        'search_unitgroups', 'hybrid_search_contacts',
        'hybrid_search_flowproperties', 'hybrid_search_flows',
        'hybrid_search_lifecyclemodels', 'hybrid_search_processes',
        'hybrid_search_sources', 'hybrid_search_unitgroups'
      ])
  ),
  14::bigint,
  'exactly fourteen no-suffix canonical Search RPC overloads exist'
);

select extensions.is(
  (
    with actual as (
      select format('%I.%I(%s)', namespace.nspname, routine.proname,
        pg_catalog.oidvectortypes(routine.proargtypes)) as routine_identity
      from pg_proc as routine
      join pg_namespace as namespace on namespace.oid = routine.pronamespace
      where namespace.nspname = 'api'
        and routine.proname = any (array[
          'search_contacts', 'search_flowproperties', 'search_flows',
          'search_lifecyclemodels', 'search_processes', 'search_sources',
          'search_unitgroups', 'hybrid_search_contacts',
          'hybrid_search_flowproperties', 'hybrid_search_flows',
          'hybrid_search_lifecyclemodels', 'hybrid_search_processes',
          'hybrid_search_sources', 'hybrid_search_unitgroups'
        ])
    )
    select count(*) from (select * from actual except select routine_identity from issue_459_canonical_search_rpcs) as unexpected
  ),
  0::bigint,
  'canonical Search RPCs have no unexpected exact regprocedure identity'
);

select extensions.is(
  (
    with actual as (
      select format('%I.%I(%s)', namespace.nspname, routine.proname,
        pg_catalog.oidvectortypes(routine.proargtypes)) as routine_identity
      from pg_proc as routine
      join pg_namespace as namespace on namespace.oid = routine.pronamespace
      where namespace.nspname = 'api'
        and routine.proname = any (array[
          'search_contacts', 'search_flowproperties', 'search_flows',
          'search_lifecyclemodels', 'search_processes', 'search_sources',
          'search_unitgroups', 'hybrid_search_contacts',
          'hybrid_search_flowproperties', 'hybrid_search_flows',
          'hybrid_search_lifecyclemodels', 'hybrid_search_processes',
          'hybrid_search_sources', 'hybrid_search_unitgroups'
        ])
    )
    select count(*) from (select routine_identity from issue_459_canonical_search_rpcs except select * from actual) as missing
  ),
  0::bigint,
  'every canonical Search RPC has its expected exact regprocedure identity'
);

select extensions.is(
  (
    select count(*)
    from pg_proc as routine
    join pg_namespace as namespace on namespace.oid = routine.pronamespace
    join issue_459_canonical_search_rpcs as expected
      on expected.routine_identity = format('%I.%I(%s)', namespace.nspname, routine.proname,
        pg_catalog.oidvectortypes(routine.proargtypes))
    where namespace.nspname = 'api'
      and expected.rpc_family = 'lexical'
      and 'order_by' = any (coalesce(routine.proargnames, '{}'::text[]))
  ),
  0::bigint,
  'canonical lexical RPCs have no unused order_by argument'
);

select extensions.is(
  (
    select count(*)
    from pg_proc as routine
    join pg_namespace as namespace on namespace.oid = routine.pronamespace
    join issue_459_canonical_search_rpcs as expected
      on expected.routine_identity = format('%I.%I(%s)', namespace.nspname, routine.proname,
        pg_catalog.oidvectortypes(routine.proargtypes))
    where expected.rpc_family = 'lexical'
      and pg_get_function_arguments(routine.oid) like '%page_size integer DEFAULT 10%'
      and pg_get_function_arguments(routine.oid) like '%page_current integer DEFAULT 1%'
  ),
  7::bigint,
  'all canonical lexical RPCs use integer page_size and page_current'
);

select extensions.is(
  (
    select count(*)
    from pg_proc as routine
    join pg_namespace as namespace on namespace.oid = routine.pronamespace
    join issue_459_canonical_search_rpcs as expected
      on expected.routine_identity = format('%I.%I(%s)', namespace.nspname, routine.proname,
        pg_catalog.oidvectortypes(routine.proargtypes))
    where namespace.nspname = 'api'
      and expected.rpc_family = 'hybrid'
      and pg_get_function_arguments(routine.oid) like '%filter_condition jsonb DEFAULT ''{}''::jsonb%'
      and pg_get_function_arguments(routine.oid) like '%page_size integer DEFAULT 10%'
      and pg_get_function_arguments(routine.oid) like '%page_current integer DEFAULT 1%'
  ),
  7::bigint,
  'all canonical hybrid RPCs use the JSON filter contract and integer pagination'
);

select extensions.is(
  (
    select count(*)
    from pg_proc as routine
    join pg_namespace as namespace on namespace.oid = routine.pronamespace
    join issue_459_canonical_search_rpcs as expected
      on expected.routine_identity = format('%I.%I(%s)', namespace.nspname, routine.proname,
        pg_catalog.oidvectortypes(routine.proargtypes))
    where namespace.nspname = 'api'
      and expected.rpc_family = 'hybrid'
      and routine.prosrc like '%filter_condition::text%'
  ),
  7::bigint,
  'canonical hybrid RPCs convert JSON only at their existing private text boundary'
);

select extensions.is(
  (
    select count(*)
    from pg_proc as routine
    join pg_namespace as namespace on namespace.oid = routine.pronamespace
    join issue_459_canonical_search_rpcs as expected
      on expected.routine_identity = format('%I.%I(%s)', namespace.nspname, routine.proname,
        pg_catalog.oidvectortypes(routine.proargtypes))
    where namespace.nspname = 'api'
      and expected.rpc_family = 'lexical'
      and routine.prosrc like '%page_size::bigint%'
      and routine.prosrc like '%page_current::bigint%'
  ),
  7::bigint,
  'canonical lexical RPCs convert integer pagination only at their existing private bigint boundary'
);

select extensions.is(
  (
    select count(*)
    from private.api_capability_grants as manifest
    join issue_459_canonical_search_rpcs as expected
      on expected.routine_identity = manifest.routine_identity
    where manifest.capability_id = 'NX-CORE-02'
      and manifest.allow_anon
      and manifest.allow_authenticated
      and not manifest.allow_service_role
  ),
  14::bigint,
  'all fourteen canonical RPCs have exact NX-CORE-02 capability entries'
);

select extensions.is(
  (
    select count(*)
    from pg_proc as routine
    join pg_namespace as namespace on namespace.oid = routine.pronamespace
    join issue_459_canonical_search_rpcs as expected
      on expected.routine_identity = format('%I.%I(%s)', namespace.nspname, routine.proname,
        pg_catalog.oidvectortypes(routine.proargtypes))
    where has_function_privilege('anon', routine.oid, 'EXECUTE')
      and has_function_privilege('authenticated', routine.oid, 'EXECUTE')
      and not has_function_privilege('service_role', routine.oid, 'EXECUTE')
  ),
  14::bigint,
  'canonical ACLs exactly match their anon/authenticated capability contract'
);

select extensions.is(
  (
    select count(*)
    from pg_proc as routine
    join pg_namespace as namespace on namespace.oid = routine.pronamespace
    where namespace.nspname = 'api'
      and (
        routine.proname = any (array[
          'search_contacts_latest', 'search_flowproperties_latest',
          'search_flows_latest', 'search_lifecyclemodels_latest',
          'search_processes_latest', 'search_processes_latest_v2',
          'search_sources_latest', 'search_unitgroups_latest'
        ])
        or routine.proname = any (array[
          'hybrid_search_contacts_v2', 'hybrid_search_flowproperties_v2',
          'hybrid_search_flows_v2', 'hybrid_search_lifecyclemodels_v2',
          'hybrid_search_processes_v2', 'hybrid_search_sources_v2',
          'hybrid_search_unitgroups_v2'
        ])
      )
      and has_function_privilege('service_role', routine.oid, 'EXECUTE')
  ),
  0::bigint,
  'legacy Search and Hybrid entrypoints retain the manifest-approved non-service contract'
);

select extensions.ok(
  exists (
    select 1
    from private.api_capability_grants as manifest
    where manifest.routine_identity = 'api.svc_dataset_search_text_backfill_enqueue(text, uuid, text, integer)'
      and manifest.capability_id = 'DBA-SEARCH-01'
      and not manifest.allow_anon
      and not manifest.allow_authenticated
      and manifest.allow_service_role
  )
  and has_function_privilege('service_role', 'api.svc_dataset_search_text_backfill_enqueue(text,uuid,text,integer)'::regprocedure, 'EXECUTE')
  and not has_function_privilege('authenticated', 'api.svc_dataset_search_text_backfill_enqueue(text,uuid,text,integer)'::regprocedure, 'EXECUTE')
  and not has_function_privilege('anon', 'api.svc_dataset_search_text_backfill_enqueue(text,uuid,text,integer)'::regprocedure, 'EXECUTE'),
  'enqueue has an exact service-only capability entry and matching ACL'
);

select extensions.ok(
  pg_get_functiondef('private.search_processes_latest_v2_impl(text,jsonb,bigint,bigint,text,text,uuid,integer,text,text[],boolean)'::regprocedure)
    like '%search_text%',
  'Database B switches Process lexical execution to search_text'
);

select extensions.is(
  (select count(*) from pg_indexes where schemaname = 'public' and indexdef ilike '%search_text%'),
  7::bigint,
  'Database B creates one search_text index per dataset table'
);

select extensions.ok(
  pg_get_functiondef(
    'private.search_processes_latest_v2_impl(text,jsonb,bigint,bigint,text,text,uuid,integer,text,text[],boolean)'::regprocedure
  ) like '%where p.search_text &@~| $11%',
  'Database B switches the Process lexical private implementation to search_text'
);

select extensions.is(
  (api.svc_dataset_search_text_backfill_enqueue('not-a-kind', null, null, 1) ->> 'code'),
  'SERVICE_ROLE_REQUIRED',
  'enqueue rejects a non-service call before processing input'
);

select set_config('request.jwt.claim.role', 'service_role', true);

select extensions.is(
  (api.svc_dataset_search_text_backfill_enqueue('not-a-kind', null, null, 1) ->> 'code'),
  'INVALID_ENTITY_KIND',
  'enqueue has a fixed entity allowlist'
);

select extensions.is(
  (api.svc_dataset_search_text_backfill_enqueue('flow', null, '01.00.000', 1) ->> 'code'),
  'INVALID_CURSOR',
  'enqueue requires an id with a version cursor'
);

select extensions.is(
  (api.svc_dataset_search_text_backfill_enqueue('flow', null, null, 5000) -> 'data' ->> 'limit')::integer,
  500,
  'enqueue caps batches at 500'
);

delete from pgmq.q_dataset_extraction_jobs;
alter table public.flows disable trigger user;
insert into public.flows (id, version, user_id, state_code, json, json_ordered)
values (
  'fa459000-0000-4000-8000-000000000001'::uuid,
  '01.00.000',
  'fa459000-0000-4000-8000-000000000002'::uuid,
  100,
  '{}'::jsonb,
  '{}'::json
);
alter table public.flows enable trigger user;

select extensions.is(
  (api.svc_dataset_search_text_backfill_enqueue('flow', null, null, 500) -> 'data' ->> 'enqueued')::integer,
  1,
  'missing Flow search_text is enqueued once as a bounded replay job'
);

select extensions.ok(
  exists (
    select 1
    from pgmq.q_dataset_extraction_jobs as queued
    where queued.message @> jsonb_build_object(
      'schema', 'public',
      'table', 'flows',
      'id', 'fa459000-0000-4000-8000-000000000001',
      'version', '01.00.000',
      'entity_kind', 'flow',
      'extraction_kind', 'search_text'
    )
  ),
  'replay payload is compact, allowlisted, and names search_text explicitly'
);

select extensions.is(
  (api.svc_dataset_search_text_backfill_enqueue('flow', null, null, 500) -> 'data' ->> 'already_queued')::integer,
  1,
  'replay enqueue deduplicates an existing matching queue job'
);

select extensions.is(
  (select search_text from public.flows where id = 'fa459000-0000-4000-8000-000000000001'::uuid),
  null,
  'enqueue does not write the projection synchronously'
);

select extensions.ok(
  not exists (
    (
      select * from api.search_contacts('__issue_459_no_match__', '{}'::jsonb, 0, 1)
      except all
      select * from api.search_contacts_latest('__issue_459_no_match__', '{}'::jsonb, 0, 1)
    )
    union all
    (
      select * from api.search_contacts_latest('__issue_459_no_match__', '{}'::jsonb, 0, 1)
      except all
      select * from api.search_contacts('__issue_459_no_match__', '{}'::jsonb, 0, 1)
    )
  ),
  'canonical simple lexical RPC remains behaviorally equivalent to its latest compatibility wrapper'
);

select extensions.ok(
  not exists (
    (
      select * from api.search_processes('__issue_459_no_match__', '{}'::jsonb, 0, 1)
      except all
      select * from api.search_processes_latest_v2('__issue_459_no_match__', '{}'::jsonb, '{}'::jsonb, 0, 1)
    )
    union all
    (
      select * from api.search_processes_latest_v2('__issue_459_no_match__', '{}'::jsonb, '{}'::jsonb, 0, 1)
      except all
      select * from api.search_processes('__issue_459_no_match__', '{}'::jsonb, 0, 1)
    )
  ),
  'canonical Process lexical RPC remains behaviorally equivalent to its v2 compatibility wrapper'
);

select extensions.ok(
  not exists (
    (
      select * from api.hybrid_search_contacts(
        query_text => '__issue_459_no_match__', query_embedding => null,
        filter_condition => '{}'::jsonb, page_size => 0
      )
      except all
      select * from api.hybrid_search_contacts_v2(
        query_text => '__issue_459_no_match__', query_embedding => null,
        filter_condition => '', page_size => 0
      )
    )
    union all
    (
      select * from api.hybrid_search_contacts_v2(
        query_text => '__issue_459_no_match__', query_embedding => null,
        filter_condition => '', page_size => 0
      )
      except all
      select * from api.hybrid_search_contacts(
        query_text => '__issue_459_no_match__', query_embedding => null,
        filter_condition => '{}'::jsonb, page_size => 0
      )
    )
  ),
  'canonical simple hybrid RPC remains behaviorally equivalent to its text-filter v2 wrapper'
);

select extensions.ok(
  not exists (
    (
      select * from api.hybrid_search_processes(
        query_text => '__issue_459_no_match__', query_embedding => null,
        filter_condition => '{}'::jsonb, page_size => 0
      )
      except all
      select * from api.hybrid_search_processes_v2(
        query_text => '__issue_459_no_match__', query_embedding => null,
        filter_condition => '', page_size => 0
      )
    )
    union all
    (
      select * from api.hybrid_search_processes_v2(
        query_text => '__issue_459_no_match__', query_embedding => null,
        filter_condition => '', page_size => 0
      )
      except all
      select * from api.hybrid_search_processes(
        query_text => '__issue_459_no_match__', query_embedding => null,
        filter_condition => '{}'::jsonb, page_size => 0
      )
    )
  ),
  'canonical Process hybrid RPC remains behaviorally equivalent to its text-filter v2 wrapper'
);

select extensions.ok(
  pg_get_functiondef('api.search_processes(text,jsonb,integer,integer,text,text,uuid,integer,text,text[],boolean)'::regprocedure)
    like '%private.search_processes_latest_v2_impl%',
  'canonical Process facade calls the existing private implementation'
);

select extensions.ok(
  pg_get_functiondef('api.search_processes_latest(text,jsonb,jsonb,bigint,bigint,text,text,uuid,integer,text,text[])'::regprocedure)
    like '%private.search_processes_latest_v2_impl%',
  'legacy Process facade calls the same private implementation'
);

select * from extensions.finish();

rollback;
