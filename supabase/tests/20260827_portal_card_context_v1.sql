begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, auth;

select extensions.no_plan();

create temporary table portal_card_context_expected_routines (
  routine_identity text primary key
) on commit drop;

insert into portal_card_context_expected_routines(routine_identity)
values
  ('private.portal_card_context_v1(text,integer,jsonb)'),
  ('private.portal_decorate_card_context_v1(jsonb)'),
  ('private.portal_card_context_manifest_sha256_v1()'),
  ('private.assert_portal_card_context_contract_v1()');

select extensions.is(
  (
    with actual as (
      select routine.oid::regprocedure::text as routine_identity
      from pg_catalog.pg_proc as routine
      where routine.oid in (
        'private.portal_card_context_v1(text,integer,jsonb)'::regprocedure,
        'private.portal_decorate_card_context_v1(jsonb)'::regprocedure,
        'private.portal_card_context_manifest_sha256_v1()'::regprocedure,
        'private.assert_portal_card_context_contract_v1()'::regprocedure
      )
    )
    select count(*)
    from (
      (select routine_identity from actual
       except
       select routine_identity from portal_card_context_expected_routines)
      union all
      (select routine_identity from portal_card_context_expected_routines
       except
       select routine_identity from actual)
    ) as symmetric_difference
  ),
  0::bigint,
  'the card-context surface has exactly four private v1 functions'
);

select extensions.is(
  (
    select count(*)
    from pg_catalog.pg_proc as routine
    join pg_catalog.pg_language as language
      on language.oid = routine.prolang
    join portal_card_context_expected_routines as expected
      on expected.routine_identity = routine.oid::regprocedure::text
    where routine.proowner = 'portal_public_executor'::regrole
      and language.lanname in ('plpgsql', 'sql')
      and routine.provolatile = 's'
      and routine.proparallel = 'r'
      and routine.prosecdef
      and pg_catalog.pg_get_function_result(routine.oid) in ('jsonb', 'text', 'void')
      and coalesce(routine.proconfig, '{}'::text[])
        @> array['search_path=""', 'row_security=on']::text[]
  ),
  4::bigint,
  'all context functions use the constrained definer, fixed empty search path, RLS, and stable restricted execution'
);

select extensions.ok(
  (
    select routine.proconfig @> array[
      'statement_timeout=20s',
      'plan_cache_mode=force_custom_plan'
    ]::text[]
    from pg_catalog.pg_proc as routine
    where routine.oid =
      'private.portal_decorate_card_context_v1(jsonb)'::regprocedure
  ),
  'the bounded exact-key decorator retains the Hybrid correctness-first 20-second/custom-plan budget'
);

select extensions.is(
  (
    select count(*)
    from pg_catalog.pg_proc as routine
    join portal_card_context_expected_routines as expected
      on expected.routine_identity = routine.oid::regprocedure::text
    where pg_catalog.has_function_privilege('anon', routine.oid, 'EXECUTE')
       or pg_catalog.has_function_privilege(
         'authenticated', routine.oid, 'EXECUTE'
       )
       or pg_catalog.has_function_privilege(
         'service_role', routine.oid, 'EXECUTE'
       )
       or pg_catalog.has_function_privilege(
         'api_internal_executor', routine.oid, 'EXECUTE'
       )
  ),
  0::bigint,
  'no application role can call the raw context, decorator, or manifest controls'
);

select extensions.is(
  (
    select count(*)
    from pg_catalog.pg_proc as routine
    where routine.oid in (
      'api.portal_search_processes_v1(text,jsonb,text,text,integer)'::regprocedure,
      'api.portal_search_flows_v1(text,jsonb,text,text,integer)'::regprocedure,
      'api.portal_hybrid_search_v1(text,text[],text,jsonb,integer)'::regprocedure
    )
      and routine.prosrc ~ 'portal_decorate_card_context_v1'
      and (
        pg_catalog.length(routine.prosrc) - pg_catalog.length(
          pg_catalog.replace(
            routine.prosrc,
            'portal_decorate_card_context_v1',
            ''
          )
        )
      ) / pg_catalog.length('portal_decorate_card_context_v1') = 1
  ),
  3::bigint,
  'the three existing public wrappers call the shared decorator exactly once'
);

select extensions.ok(
  not exists (
    select 1
    from pg_catalog.pg_class as relation
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = relation.relnamespace
    where namespace.nspname in ('private', 'public')
      and relation.relname like 'portal%context%'
  )
  and not exists (
    select 1
    from pg_catalog.pg_trigger as trigger
    where not trigger.tgisinternal
      and trigger.tgname like 'portal%context%'
  ),
  'selected-row context adds no table, index, RLS relation, or source trigger'
);

select extensions.ok(
  (
    select routine.prosrc !~ 'card_context|decorate_card_context'
    from pg_catalog.pg_proc as routine
    where routine.oid =
      'private.sync_portal_catalog_search_row_v1()'::regprocedure
  )
  and (
    select count(*)
    from pg_catalog.pg_trigger as trigger
    where not trigger.tgisinternal
      and (trigger.tgrelid,trigger.tgname) in (
        ('public.processes'::regclass,'portal_catalog_projection_content_sync_v2'),
        ('public.flows'::regclass,'portal_catalog_projection_content_sync_v1'),
        ('private.portal_catalog_search_rows_v1'::regclass,'portal_catalog_facet_sync_v1'),
        ('private.portal_catalog_search_rows_v2'::regclass,'portal_catalog_facet_sync_v2')
      )
  ) = 4,
  'each source has its own projection writer and facet trigger, with zero context work'
);

grant portal_public_executor to postgres;
set local role portal_public_executor;

select extensions.is(
  private.portal_card_context_manifest_sha256_v1(),
  'db78336c8604848af1e068352f8a39d9ee740308c44c59c639b986ed2660c47e',
  'the live context/decorator allowlist closure matches its committed digest'
);

select extensions.lives_ok(
  $$select private.assert_portal_card_context_contract_v1()$$,
  'the committed context derivation contract is live'
);

reset role;

set local role anon;

select extensions.ok(
  api.portal_search_processes_v1(
    '', '{}'::jsonb, 'modified_desc', null, 50
  ) #> '{items}' = '[]'::jsonb
  and api.portal_search_flows_v1(
    '', '{}'::jsonb, 'modified_desc', null, 50
  ) #> '{items}' = '[]'::jsonb,
  'empty bounded Search pages remain valid after exact-key decoration'
);

select extensions.ok(
  api.portal_hybrid_search_v1(
    'process',
    array['empty'],
    '[' || pg_catalog.array_to_string(
      pg_catalog.array_fill('0'::text, array[1024]),
      ','
    ) || ']',
    '{}'::jsonb,
    20
  ) #> '{items}' = '[]'::jsonb,
  'empty bounded Hybrid pages remain valid after exact-key decoration'
);

reset role;
set local role portal_public_executor;

select extensions.throws_ok(
  $$
    select private.portal_decorate_card_context_v1(
      pg_catalog.jsonb_build_object(
        'schemaVersion', 'portal.public-search-page.v1',
        'kind', 'process',
        'items', pg_catalog.jsonb_build_array(
          pg_catalog.jsonb_build_object(
            'key', pg_catalog.jsonb_build_object(
              'kind', 'process',
              'id', '53200000-0000-4000-8000-000000000001',
              'version', '01.00.000'
            )
          )
        )
      )
    )
  $$,
  '55000',
  'Portal card context exact-key hydration failed',
  'a missing exact source identity fails closed'
);

select extensions.throws_ok(
  $$
    select private.portal_decorate_card_context_v1(
      pg_catalog.jsonb_build_object(
        'schemaVersion', 'portal.public-search-page.v1',
        'kind', 'process',
        'items', pg_catalog.jsonb_build_array(
          pg_catalog.jsonb_build_object(
            'key', pg_catalog.jsonb_build_object(
              'kind', 'flow',
              'id', '53200000-0000-4000-8000-000000000001',
              'version', '01.00.000'
            )
          )
        )
      )
    )
  $$,
  '55000',
  'Portal card context exact-key hydration failed',
  'an item kind that differs from the page kind fails closed'
);

select extensions.throws_ok(
  $$
    select private.portal_decorate_card_context_v1(
      pg_catalog.jsonb_build_object(
        'schemaVersion', 'portal.public-search-page.v1',
        'kind', 'process',
        'items', (
          select pg_catalog.jsonb_agg('{}'::jsonb order by ordinal)
          from pg_catalog.generate_series(1, 51) as ordinal
        )
      )
    )
  $$,
  '54000',
  'Portal card context page exceeds its fixed bound',
  'Search decoration rejects more than 50 final items'
);

select extensions.throws_ok(
  $$
    select private.portal_decorate_card_context_v1(
      pg_catalog.jsonb_build_object(
        'schemaVersion', 'portal.public-hybrid-candidate-page.v1',
        'kind', 'flow',
        'items', (
          select pg_catalog.jsonb_agg('{}'::jsonb order by ordinal)
          from pg_catalog.generate_series(1, 21) as ordinal
        )
      )
    )
  $$,
  '54000',
  'Portal card context page exceeds its fixed bound',
  'Hybrid decoration rejects more than 20 final items'
);

alter function private.portal_process_functional_unit_v1(integer, jsonb)
  parallel safe;

select extensions.throws_ok(
  $$select private.assert_portal_card_context_contract_v1()$$,
  '55000',
  'Portal card context derivation contract drifted',
  'transitive public-allowlist drift fails closed before context hydration'
);

reset role;
revoke portal_public_executor from postgres;

select * from extensions.finish();
rollback;
