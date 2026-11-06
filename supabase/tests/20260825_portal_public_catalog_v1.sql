begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, auth;

select extensions.no_plan();

create function pg_temp.portal_test_cursor_v1(p_payload jsonb)
returns text
language sql
immutable
parallel safe
set search_path = ''
as $function$
  select pg_catalog.rtrim(
    pg_catalog.translate(
      pg_catalog.replace(
        pg_catalog.replace(
          pg_catalog.encode(
            pg_catalog.convert_to(p_payload::text, 'UTF8'),
            'base64'
          ),
          E'\n',
          ''
        ),
        E'\r',
        ''
      ),
      '+/',
      '-_'
    ),
    '='
  )
$function$;

grant execute on function pg_temp.portal_test_cursor_v1(jsonb) to anon;

create temporary table portal_expected_routines (
  routine_identity text primary key
) on commit drop;

insert into portal_expected_routines (routine_identity)
values
  ('api.portal_search_processes_v1(text, jsonb, text, text, integer)'),
  ('api.portal_search_flows_v1(text, jsonb, text, text, integer)'),
  ('api.portal_get_dataset_v1(text, uuid, text)'),
  ('api.portal_list_versions_v1(text, uuid, text, integer)'),
  ('api.portal_list_process_exchanges_v1(uuid, text, text, text, integer)'),
  ('api.portal_facets_v1(text, text, jsonb)'),
  ('api.portal_sitemap_entries_v1(text, text, integer)'),
  ('api.portal_sitemap_manifest_v1()'),
  ('api.portal_sitemap_shard_v1(text)'),
  ('api.portal_catalog_summary_v1()');

create temporary table portal_legacy_search_acl_snapshot (
  routine_identity text primary key
) on commit drop;

-- This is the canonical pre-Portal Search/Hybrid ACL surface. A post-migration
-- test cannot reconstruct pre-migration function bytes, so this snapshot locks
-- the legacy exact identities and grants instead.
insert into portal_legacy_search_acl_snapshot (routine_identity)
values
  ('api.search_contacts(text, jsonb, integer, integer, text, text, uuid, integer)'),
  ('api.search_flowproperties(text, jsonb, integer, integer, text, text, uuid, integer)'),
  ('api.search_flows(text, jsonb, integer, integer, text, text, uuid, integer, text[])'),
  ('api.search_lifecyclemodels(text, jsonb, integer, integer, text, text, uuid, integer, text[])'),
  ('api.search_processes(text, jsonb, integer, integer, text, text, uuid, integer, text, text[], boolean)'),
  ('api.search_sources(text, jsonb, integer, integer, text, text, uuid, integer)'),
  ('api.search_unitgroups(text, jsonb, integer, integer, text, text, uuid, integer)'),
  ('api.hybrid_search_contacts(text, text, jsonb, double precision, integer, double precision, double precision, integer, text, integer, integer, text[], integer, uuid)'),
  ('api.hybrid_search_flowproperties(text, text, jsonb, double precision, integer, double precision, double precision, integer, text, integer, integer, text[], integer, uuid)'),
  ('api.hybrid_search_flows(text, text, jsonb, double precision, integer, double precision, double precision, integer, text, integer, integer, text[])'),
  ('api.hybrid_search_lifecyclemodels(text, text, jsonb, double precision, integer, double precision, double precision, integer, text, integer, integer, text[])'),
  ('api.hybrid_search_processes(text, text, jsonb, double precision, integer, double precision, double precision, integer, text, integer, integer, text[])'),
  ('api.hybrid_search_sources(text, text, jsonb, double precision, integer, double precision, double precision, integer, text, integer, integer, text[], integer, uuid)'),
  ('api.hybrid_search_unitgroups(text, text, jsonb, double precision, integer, double precision, double precision, integer, text, integer, integer, text[], integer, uuid)');

select extensions.is(
  (
    select count(*)
    from pg_catalog.pg_proc as routine
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = routine.pronamespace
    where namespace.nspname = 'api'
      and routine.proname in (
        'portal_search_processes_v1', 'portal_search_flows_v1',
        'portal_get_dataset_v1', 'portal_list_versions_v1',
        'portal_list_process_exchanges_v1', 'portal_facets_v1',
        'portal_sitemap_entries_v1', 'portal_sitemap_manifest_v1',
        'portal_sitemap_shard_v1', 'portal_catalog_summary_v1'
      )
  ),
  10::bigint,
  'exactly ten Portal catalogue routines exist without overloads'
);

select extensions.ok(
  (
    select routine.prosrc ~ 'cas_unique_values as materialized'
      and routine.prosrc ~ 'limit 64'
      and routine.prosrc ~ 'having pg_catalog.count\(\*\) = 1'
    from pg_catalog.pg_proc as routine
    where routine.oid = 'api.portal_catalog_summary_v1()'::regprocedure
  ),
  'catalog summary chooses a history-unique CAS through a fixed 64-value index probe'
);

select extensions.is(
  (
    with actual as (
      select pg_catalog.format(
        '%I.%I(%s)',
        namespace.nspname,
        routine.proname,
        pg_catalog.oidvectortypes(routine.proargtypes)
      ) as routine_identity
      from pg_catalog.pg_proc as routine
      join pg_catalog.pg_namespace as namespace
        on namespace.oid = routine.pronamespace
      where namespace.nspname = 'api'
        and routine.proname in (
          'portal_search_processes_v1', 'portal_search_flows_v1',
          'portal_get_dataset_v1', 'portal_list_versions_v1',
          'portal_list_process_exchanges_v1', 'portal_facets_v1',
          'portal_sitemap_entries_v1', 'portal_sitemap_manifest_v1',
          'portal_sitemap_shard_v1', 'portal_catalog_summary_v1'
        )
    )
    select count(*)
    from (
      (select routine_identity from actual
       except
       select routine_identity from portal_expected_routines)
      union all
      (select routine_identity from portal_expected_routines
       except
       select routine_identity from actual)
    ) as symmetric_difference
  ),
  0::bigint,
  'Portal catalogue routines have the ten exact frozen regprocedure signatures'
);

select extensions.is(
  (
    select count(*)
    from pg_catalog.pg_proc as routine
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = routine.pronamespace
    join portal_expected_routines as expected
      on expected.routine_identity = pg_catalog.format(
        '%I.%I(%s)',
        namespace.nspname,
        routine.proname,
        pg_catalog.oidvectortypes(routine.proargtypes)
      )
    join pg_catalog.pg_roles as owner_role
      on owner_role.oid = routine.proowner
    where pg_catalog.pg_get_function_result(routine.oid) = 'jsonb'
      and routine.prosecdef
      and routine.proconfig @> array['search_path=""']::text[]
      and owner_role.rolname = 'portal_public_executor'
  ),
  10::bigint,
  'all Portal catalogue routines return jsonb and use the hardened executor boundary'
);

select extensions.is(
  (
    select count(*)
    from pg_catalog.pg_proc as routine
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = routine.pronamespace
    join portal_expected_routines as expected
      on expected.routine_identity = pg_catalog.format(
        '%I.%I(%s)',
        namespace.nspname,
        routine.proname,
        pg_catalog.oidvectortypes(routine.proargtypes)
      )
    where routine.prosrc like '%when query_canceled then%'
  ),
  10::bigint,
  'all public Portal routines converge statement cancellation to the generic unavailable error'
);

select extensions.ok(
  exists (
    select 1
    from pg_catalog.pg_roles
    where rolname = 'portal_public_executor'
      and not rolcanlogin
      and not rolinherit
      and not rolbypassrls
      and not rolsuper
      and not rolcreatedb
      and not rolcreaterole
      and not rolreplication
  ),
  'portal_public_executor is NOLOGIN, NOBYPASSRLS, and non-superuser'
);

select extensions.is(
  (
    with expected(table_name, column_name) as (
      values
        ('processes', 'id'), ('processes', 'json'),
        ('processes', 'state_code'), ('processes', 'version'),
        ('processes', 'modified_at'), ('processes', 'embedding_ft'),
        ('flows', 'id'), ('flows', 'json'), ('flows', 'state_code'),
        ('flows', 'version'), ('flows', 'modified_at'),
        ('flows', 'embedding_ft'),
        ('flowproperties', 'id'), ('flowproperties', 'json'),
        ('flowproperties', 'state_code'), ('flowproperties', 'version'),
        ('flowproperties', 'modified_at'),
        ('unitgroups', 'id'), ('unitgroups', 'json'),
        ('unitgroups', 'state_code'), ('unitgroups', 'version'),
        ('unitgroups', 'modified_at')
    ), actual as (
      select privilege.table_name, privilege.column_name
      from information_schema.column_privileges as privilege
      where privilege.grantee = 'portal_public_executor'
        and privilege.table_schema = 'public'
        and privilege.privilege_type = 'SELECT'
    )
    select count(*)
    from (
      (select * from actual except select * from expected)
      union all
      (select * from expected except select * from actual)
    ) as symmetric_difference
  ),
  0::bigint,
  'portal_public_executor has exactly the frozen minimum column-level SELECT grants'
);

select extensions.is(
  (
    select count(*)
    from information_schema.table_privileges as privilege
    where privilege.grantee = 'portal_public_executor'
  ),
  0::bigint,
  'portal_public_executor has no broad table-level privilege'
);

select extensions.ok(
  pg_catalog.has_schema_privilege('portal_public_executor', 'api', 'USAGE')
  and pg_catalog.has_schema_privilege('portal_public_executor', 'private', 'USAGE')
  and pg_catalog.has_schema_privilege('portal_public_executor', 'public', 'USAGE')
  and pg_catalog.has_schema_privilege('portal_public_executor', 'extensions', 'USAGE')
  and not pg_catalog.has_schema_privilege('portal_public_executor', 'api', 'CREATE')
  and not pg_catalog.has_schema_privilege('portal_public_executor', 'private', 'CREATE'),
  'portal_public_executor retains only required schema USAGE and no CREATE privilege'
);

select extensions.is(
  (
    select count(*)
    from pg_catalog.pg_auth_members as membership
    where membership.member = 'portal_public_executor'::regrole
       or membership.roleid = 'portal_public_executor'::regrole
  ),
  1::bigint,
  'portal_public_executor has exactly one PostgreSQL-17 creator-control membership edge'
);

select extensions.ok(
  exists (
    select 1
    from pg_catalog.pg_auth_members as membership
    where membership.roleid = 'portal_public_executor'::regrole
      and membership.member = 'postgres'::regrole
      and membership.admin_option
      and not membership.inherit_option
      and not membership.set_option
  ),
  'the creator-control edge cannot SET or inherit the runtime executor role'
);

select extensions.is(
  (
    select count(*)
    from private.api_capability_grants as manifest
    where manifest.capability_id = 'PORTAL-CATALOG-01'
  ),
  31::bigint,
  'PORTAL-CATALOG-01 contains seventeen legacy and fourteen display catalogue routines'
);

select extensions.is(
  (
    select count(*)
    from private.api_capability_grants as manifest
    join portal_expected_routines as expected
      on expected.routine_identity = manifest.routine_identity
    where manifest.capability_id = 'PORTAL-CATALOG-01'
      and manifest.allow_anon
      and manifest.allow_authenticated
      and not manifest.allow_service_role
  ),
  10::bigint,
  'PORTAL-CATALOG-01 grants only anon and authenticated in the manifest'
);

select extensions.is(
  (
    select count(*)
    from pg_catalog.pg_proc as routine
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = routine.pronamespace
    join portal_expected_routines as expected
      on expected.routine_identity = pg_catalog.format(
        '%I.%I(%s)',
        namespace.nspname,
        routine.proname,
        pg_catalog.oidvectortypes(routine.proargtypes)
      )
    where pg_catalog.has_function_privilege('anon', routine.oid, 'EXECUTE')
      and pg_catalog.has_function_privilege('authenticated', routine.oid, 'EXECUTE')
      and not pg_catalog.has_function_privilege('service_role', routine.oid, 'EXECUTE')
      and not exists (
        select 1
        from pg_catalog.aclexplode(
          coalesce(
            routine.proacl,
            pg_catalog.acldefault('f', routine.proowner)
          )
        ) as acl
        where acl.grantee = 0
          and acl.privilege_type = 'EXECUTE'
      )
  ),
  10::bigint,
  'runtime ACLs grant anon/authenticated while revoking service_role and PUBLIC'
);

select extensions.is(
  (
    with expected as (
      select routine_identity, grant_row.grantee, 'EXECUTE'::text as privilege_type,
        grant_row.is_grantable
      from portal_expected_routines
      cross join (values
        ('portal_public_executor'::text, false),
        ('anon'::text, false),
        ('authenticated'::text, false)
      ) as grant_row(grantee, is_grantable)
    ), actual as (
      select
        pg_catalog.format(
          '%I.%I(%s)',
          namespace.nspname,
          routine.proname,
          pg_catalog.oidvectortypes(routine.proargtypes)
        ) as routine_identity,
        coalesce(grantee_role.rolname, 'PUBLIC') as grantee,
        acl.privilege_type,
        acl.is_grantable
      from pg_catalog.pg_proc as routine
      join pg_catalog.pg_namespace as namespace
        on namespace.oid = routine.pronamespace
      cross join lateral pg_catalog.aclexplode(
        coalesce(routine.proacl, pg_catalog.acldefault('f', routine.proowner))
      ) as acl
      left join pg_catalog.pg_roles as grantee_role
        on grantee_role.oid = acl.grantee
      where namespace.nspname = 'api'
        and routine.proname in (
          'portal_search_processes_v1', 'portal_search_flows_v1',
          'portal_get_dataset_v1', 'portal_list_versions_v1',
          'portal_list_process_exchanges_v1', 'portal_facets_v1',
          'portal_sitemap_entries_v1', 'portal_sitemap_manifest_v1',
          'portal_sitemap_shard_v1', 'portal_catalog_summary_v1'
        )
    )
    select count(*)
    from (
      (select * from actual except select * from expected)
      union all
      (select * from expected except select * from actual)
    ) as symmetric_difference
  ),
  0::bigint,
  'Portal function ACLs contain only owner plus non-grantable anon/authenticated EXECUTE entries'
);

select extensions.is(
  (
    select count(*)
    from pg_catalog.pg_proc as routine
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = routine.pronamespace
    where namespace.nspname = 'private'
      and routine.proname like 'portal\_%\_v1' escape '\'
      and routine.proname not in ('portal_navigation_v1','portal_navigation_impl_v1','portal_navigation_matched_versions_v1')
      and routine.proowner = 'portal_public_executor'::regrole
  ),
  49::bigint,
  'the private executor-owned Portal helper surface retains 49 routines after retiring the closed Process v1 rank manifest helper'
);

select extensions.ok(
  exists (
    select 1
    from pg_catalog.pg_index as index_catalog
    join pg_catalog.pg_class as index_relation
      on index_relation.oid = index_catalog.indexrelid
    join pg_catalog.pg_am as access_method
      on access_method.oid = index_relation.relam
    where index_catalog.indexrelid =
      'private.portal_sitemap_rows_shard_v1_idx'::regclass
      and index_catalog.indrelid =
        'private.portal_sitemap_rows_v1'::regclass
      and index_relation.relowner = 'postgres'::regrole
      and access_method.amname = 'btree'
      and index_catalog.indisvalid
      and index_catalog.indisready
      and index_catalog.indislive
      and index_catalog.indnkeyatts = 6
      and index_catalog.indnatts = 6
      and index_catalog.indpred is null
      and index_catalog.indexprs is null
  ),
  'the sitemap shard index is the exact healthy latest-version covering index'
);

select extensions.is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_trigger as trigger
    where trigger.tgrelid =
      'private.portal_catalog_facet_rows_v1'::regclass
      and not trigger.tgisinternal
      and trigger.tgenabled = 'O'
      and trigger.tgname = 'portal_sitemap_rows_sync_v1'
      and trigger.tgtype = 21
      and trigger.tgfoid =
        'private.sync_portal_sitemap_row_v1()'::regprocedure
  ),
  1::bigint,
  'the governed facet writer has one exact INSERT/UPDATE sitemap trigger'
);

select extensions.is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_constraint as constraint_catalog
    where constraint_catalog.conrelid =
      'private.portal_sitemap_rows_v1'::regclass
      and constraint_catalog.confrelid =
        'private.portal_catalog_facet_rows_v1'::regclass
      and constraint_catalog.conname = 'portal_sitemap_rows_source_v1_fk'
      and constraint_catalog.contype = 'f'
      and constraint_catalog.convalidated
      and constraint_catalog.confupdtype = 'r'
      and constraint_catalog.confdeltype = 'c'
  ),
  1::bigint,
  'each sitemap version is exact-FK fenced to its facet row with delete cascade'
);

select extensions.is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_constraint as constraint_catalog
    where constraint_catalog.conrelid =
      'private.portal_sitemap_rows_v1'::regclass
      and constraint_catalog.contype = 'p'
      and pg_catalog.pg_get_constraintdef(
        constraint_catalog.oid,
        false
      ) = 'PRIMARY KEY (dataset_kind, id, version)'
  ),
  1::bigint,
  'the sitemap child primary key is the exact version identity'
);

select extensions.is(
  pg_catalog.to_regclass(
    'private.portal_sitemap_latest_rows_v1'
  )::text,
  null::text,
  'the retired shared latest-winner table is absent'
);

select extensions.is(
  (
    select pg_catalog.md5(routine.prosrc)
    from pg_catalog.pg_proc as routine
    where routine.oid =
      'private.display_legacy_sitemap_entries_v1(text,text,integer)'::regprocedure
  ),
  '03dd37bd0871c220fcd94cb2dec203ed',
  'the retained legacy sitemap façade remains byte-identical'
);

select extensions.is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_proc as routine
    where routine.oid =
      'private.assert_portal_sitemap_projection_v1()'::regprocedure
      and routine.proowner = 'portal_public_executor'::regrole
      and not routine.prosecdef
      and routine.provolatile = 's'
      and routine.proparallel = 'r'
      and coalesce(routine.proacl::text, '') =
        '{portal_public_executor=X/portal_public_executor}'
  ),
  1::bigint,
  'the sitemap projection assertion is ACL-closed and owned by the constrained executor'
);

select extensions.is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_proc as routine
    where routine.oid =
      'private.sync_portal_sitemap_row_v1()'::regprocedure
      and routine.proowner = 'api_internal_executor'::regrole
      and routine.prosecdef
      and routine.provolatile = 'v'
      and routine.proparallel = 'u'
      and pg_catalog.md5(routine.prosrc) =
        '9bc7007c0e8fef48c75d997ea8ef96d8'
      and coalesce(routine.proacl::text, '') =
        '{api_internal_executor=X/api_internal_executor}'
  ),
  1::bigint,
  'the exact-version sitemap sync helper is owner-only and security-definer fenced'
);

select extensions.is(
  pg_catalog.to_regprocedure(
    'private.sync_portal_sitemap_latest_delete_v1()'
  )::text,
  null::text,
  'the retired shared-winner DELETE helper is absent'
);

select extensions.is(
  (
    with expected(column_name) as (
      values
        ('dataset_kind'::text),
        ('id'),
        ('version'),
        ('modified_at'),
        ('shard_no'),
        ('contract_version')
    ), actual as (
      select privilege.column_name
      from information_schema.column_privileges as privilege
      where privilege.grantee = 'portal_public_executor'
        and privilege.table_schema = 'private'
        and privilege.table_name = 'portal_sitemap_rows_v1'
        and privilege.privilege_type = 'SELECT'
    )
    select pg_catalog.count(*)
    from (
      (select * from actual except select * from expected)
      union all
      (select * from expected except select * from actual)
    ) as symmetric_difference
  ),
  0::bigint,
  'the Portal executor can read only the six locator-free exact sitemap columns'
);

select extensions.is(
  (
    select count(*)
    from pg_catalog.pg_proc as routine
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = routine.pronamespace
    where namespace.nspname = 'private'
      and routine.proname like 'portal\_%\_v1' escape '\'
      and routine.proname not in ('portal_navigation_v1','portal_navigation_impl_v1','portal_navigation_matched_versions_v1')
      and routine.proowner = 'portal_public_executor'::regrole
      and not routine.prosecdef
      and routine.proconfig @> array['search_path=""']::text[]
  ),
  42::bigint,
  'all 42 invoker Portal helpers are executor-owned and pinned to an empty search path'
);

select extensions.is(
  (
    select count(*)
    from pg_catalog.pg_proc as routine
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = routine.pronamespace
    cross join lateral pg_catalog.aclexplode(
      coalesce(routine.proacl, pg_catalog.acldefault('f', routine.proowner))
    ) as acl
    where namespace.nspname = 'private'
      and routine.proname like 'portal\_%\_v1' escape '\'
      and routine.proname not in ('portal_navigation_v1','portal_navigation_impl_v1','portal_navigation_matched_versions_v1')
      and routine.proowner = 'portal_public_executor'::regrole
      and (
        acl.grantee <> routine.proowner
        or acl.privilege_type <> 'EXECUTE'
        or acl.is_grantable
      )
      and not (
        routine.proname in (
          'portal_canonical_decimal_v1',
          'portal_timestamp_v1',
          'portal_process_open_capability_bridge_v1'
        )
        and acl.grantee = 'postgres'::regrole
        and acl.privilege_type = 'EXECUTE'
        and not acl.is_grantable
      )
      and not (
        routine.proname = 'portal_public_hybrid_card_v1'
        and acl.grantee = 'api_internal_executor'::regrole
        and acl.privilege_type = 'EXECUTE'
        and not acl.is_grantable
      )
      and not (
        routine.proname in (
          'portal_catalog_character_set_v1',
          'portal_catalog_character_field_set_v1'
        )
        and acl.grantee = 'api_internal_executor'::regrole
        and acl.privilege_type = 'EXECUTE'
        and not acl.is_grantable
      )
      and not (
        routine.proname in (
          'portal_process_rank_name_keys_v1',
          'portal_process_rank_classification_keys_v1'
        )
        and acl.grantee in (
          'api_internal_executor'::regrole,
          'postgres'::regrole
        )
        and acl.privilege_type = 'EXECUTE'
        and not acl.is_grantable
      )
  ),
  0::bigint,
  'private catalogue helpers have only the reviewed postgres primitives, Hybrid/character writer edges, and Process-rank writer/maintenance edges'
);

select extensions.is(
  (
    with actual as (
      select pg_catalog.format(
        '%I.%I(%s)',
        namespace.nspname,
        routine.proname,
        pg_catalog.oidvectortypes(routine.proargtypes)
      ) as routine_identity
      from pg_catalog.pg_proc as routine
      join pg_catalog.pg_namespace as namespace
        on namespace.oid = routine.pronamespace
      join portal_legacy_search_acl_snapshot as expected
        on expected.routine_identity = pg_catalog.format(
          '%I.%I(%s)',
          namespace.nspname,
          routine.proname,
          pg_catalog.oidvectortypes(routine.proargtypes)
        )
      where pg_catalog.has_function_privilege('anon', routine.oid, 'EXECUTE')
        and pg_catalog.has_function_privilege('authenticated', routine.oid, 'EXECUTE')
        and not pg_catalog.has_function_privilege('service_role', routine.oid, 'EXECUTE')
    )
    select count(*)
    from (
      (select routine_identity from actual
       except
       select routine_identity from portal_legacy_search_acl_snapshot)
      union all
      (select routine_identity from portal_legacy_search_acl_snapshot
       except
       select routine_identity from actual)
    ) as symmetric_difference
  ),
  0::bigint,
  'the pre-Portal canonical Search/Hybrid signature and grant snapshot is unchanged'
);

-- Raw core tables must gain no anonymous *access grant*. A RESTRICTIVE policy only removes
-- rows from whatever the permissive set already allows, so it grants nothing on its own and
-- is deliberately not counted here. Counting it as a grant would make a strict narrowing
-- fence indistinguishable from a real anonymous read grant.
select extensions.is(
  (
    select count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = any (array[
        'processes',
        'flows',
        'flowproperties',
        'unitgroups'
      ])
      and permissive = 'PERMISSIVE'
      and (
        'anon' = any(roles)
        or 'public' = any(roles)
      )
  ),
  0::bigint,
  'raw core tables gain no permissive anon or PUBLIC SELECT grant'
);

-- The Result isolation fence is the one reviewed exception, and it must stay a fence: a
-- RESTRICTIVE SELECT policy that admits no role beyond the anonymous/executor roles the
-- permissive set already covers. Asserting the exact permissive/restrictive pair keeps the
-- anonymous surface unchanged while proving the fence cannot silently become a grant.
select extensions.is(
  (
    select count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'processes'
      and policyname = 'result_process_no_generic_read'
      and permissive = 'RESTRICTIVE'
      and cmd = 'SELECT'
      and roles @> array['authenticated', 'anon']::name[]
      and roles <@ array['authenticated', 'anon']::name[]
      and qual like '%IS DISTINCT FROM 120%'
  ),
  1::bigint,
  'the Result read-isolation fence on public.processes stays a RESTRICTIVE SELECT policy'
);

-- and that no role outside that exact set was added to it.
select extensions.is(
  (
    select count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'processes'
      and policyname = 'result_process_no_generic_read'
      and not (
        roles @> array['authenticated', 'anon']::name[]
        and roles <@ array['authenticated', 'anon']::name[]
      )
  ),
  0::bigint,
  'the Result read-isolation fence admits no role beyond authenticated and anon'
);

select extensions.is(
  (
    select count(*)
    from pg_catalog.pg_class as relation
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname in ('processes', 'flows', 'flowproperties', 'unitgroups')
      and relation.relrowsecurity
      and relation.relowner <> 'portal_public_executor'::regrole
  ),
  4::bigint,
  'all four Portal source relations retain RLS and are not owned by the executor'
);

select extensions.has_function(
  'private',
  'portal_canonical_decimal_v1',
  array['text'],
  'the exact private canonical-decimal helper exists'
);

-- Exercise the private helper as its constrained owner. The membership is
-- transaction-local test scaffolding and rolls back with this pgTAP suite.
grant portal_public_executor to postgres;
set local role portal_public_executor;

select extensions.is(
  private.portal_canonical_decimal_v1('  +000001.230000  '),
  '1.23',
  'canonical decimal strips whitespace, plus sign, leading zeroes, and trailing fractional zeroes'
);

select extensions.is(
  private.portal_canonical_decimal_v1('-0.000000'),
  '0',
  'canonical decimal normalizes negative zero'
);

select extensions.is(
  private.portal_canonical_decimal_v1('.5000'),
  '0.5',
  'canonical decimal accepts a leading-dot TIDAS value and emits a leading zero'
);

select extensions.is(
  private.portal_canonical_decimal_v1('12345678901234567890123456789012345678'),
  '12345678901234567890123456789012345678',
  'canonical decimal accepts exactly 38 digits'
);

select extensions.is(
  private.portal_canonical_decimal_v1('123456789012345678901234567890123456789'),
  null::text,
  'canonical decimal rejects 39 digits'
);

select extensions.is(
  private.portal_canonical_decimal_v1('1e3'),
  '1000',
  'canonical decimal expands a valid TIDAS exponent to non-exponent Portal output'
);

select extensions.is(
  private.portal_canonical_decimal_v1('-0e2'),
  '0',
  'canonical decimal normalizes exponent-form negative zero'
);

select extensions.is(
  private.portal_canonical_decimal_v1('NaN'),
  null::text,
  'canonical decimal rejects non-finite text'
);

select extensions.is(
  private.portal_canonical_decimal_v1('1.2.3'),
  null::text,
  'canonical decimal rejects malformed input'
);

select extensions.is(
  (
    private.portal_capabilities_v1(
      'process',
      100,
      '{"processDataSet":{"administrativeInformation":{"publicationAndOwnership":{}}}}'::jsonb
    ) ->> 'exchangesVisible'
  )::boolean,
  false,
  'missing license evidence emits a boolean false capability rather than JSON null'
);

select extensions.is(
  private.portal_named_reference_v1(
    '{"@refObjectId":"52700000-0000-4000-8000-000000000099","common:shortDescription":{"#text":"partial"}}'::jsonb
  ) -> 'id',
  'null'::jsonb,
  'a named reference with an ID but no exact version fails closed as an all-null identity'
);

select extensions.is(
  private.portal_named_reference_v1(
    '{"@version":"01.00.000","common:shortDescription":{"#text":"partial"}}'::jsonb
  ) -> 'version',
  'null'::jsonb,
  'a named reference with a version but no ID fails closed as an all-null identity'
);

select extensions.is(
  private.portal_named_reference_v1(
    '[{"@refObjectId":"52700000-0000-4000-8000-000000000099","@version":"01.00.000","common:shortDescription":{"#text":"single"}}]'::jsonb
  ) ->> 'id',
  '52700000-0000-4000-8000-000000000099',
  'a one-element TIDAS reference array normalizes to the exact named reference'
);

select extensions.is(
  private.portal_named_reference_v1(
    '[{"@refObjectId":"52700000-0000-4000-8000-000000000098","@version":"01.00.000"},{"@refObjectId":"52700000-0000-4000-8000-000000000099","@version":"01.00.000"}]'::jsonb
  ) -> 'id',
  'null'::jsonb,
  'multiple source references fail closed instead of silently selecting one identity'
);

select extensions.is(
  private.portal_source_v1(
    'process',
    '{"processDataSet":{"modellingAndValidation":{"dataSourcesTreatmentAndRepresentativeness":{"referenceToDataSource":[{"@refObjectId":"52700000-0000-4000-8000-000000000098"},{"@refObjectId":"52700000-0000-4000-8000-000000000099"}]}},"administrativeInformation":{"publicationAndOwnership":{}}}}'::jsonb
  ) -> 'sourceRecordId',
  'null'::jsonb,
  'multiple public data-source references do not silently collapse to the first record'
);

select extensions.is(
  private.portal_localized_text_v1(
    '{"@xml:lang":"en-abcdefgh-abcdefgh-abcdefgh-abcdefgh","#text":"bounded"}'::jsonb
  ) #>> '{0,language}',
  'und',
  'an otherwise-shaped language tag above the schema maxLength normalizes to und'
);

select extensions.is(
  private.portal_localized_text_v1(
    '{"@xml:lang":"en","#text":{"privateLocator":"hidden"}}'::jsonb
  ),
  '[]'::jsonb,
  'object-polluted localized text fails closed instead of serializing hidden JSON'
);

select extensions.ok(
  private.portal_administration_v1(
    'process',
    '{"processDataSet":{"administrativeInformation":{"publicationAndOwnership":{"common:workflowAndPublicationStatus":{"privateLocator":"hidden"},"common:licenseType":{"privateLocator":"hidden"},"common:registrationNumber":{"privateLocator":"hidden"}}}}}'::jsonb
  ) #> '{workflowStatus}' = 'null'::jsonb
  and private.portal_administration_v1(
    'process',
    '{"processDataSet":{"administrativeInformation":{"publicationAndOwnership":{"common:workflowAndPublicationStatus":{"privateLocator":"hidden"},"common:licenseType":{"privateLocator":"hidden"},"common:registrationNumber":{"privateLocator":"hidden"}}}}}'::jsonb
  ) #> '{licenseType}' = 'null'::jsonb
  and private.portal_administration_v1(
    'process',
    '{"processDataSet":{"administrativeInformation":{"publicationAndOwnership":{"common:workflowAndPublicationStatus":{"privateLocator":"hidden"},"common:licenseType":{"privateLocator":"hidden"},"common:registrationNumber":{"privateLocator":"hidden"}}}}}'::jsonb
  ) #> '{registrationNumber}' = 'null'::jsonb,
  'object-polluted allowlisted administration scalars fail closed to JSON null'
);

select extensions.is(
  private.portal_flow_kind_v1('not a product flow'),
  'unknown',
  'substring lookalikes do not become a public Product-flow capability'
);

select extensions.is(
  private.portal_flow_kind_v1(
    private.portal_scalar_text_v1('{"privateLocator":"product flow"}'::jsonb)
  ),
  'unknown',
  'object-polluted Flow type does not become a public numeric capability'
);

select extensions.is(
  private.portal_safe_year_v1('999999999999999999999999999999'),
  null::integer,
  'malformed oversized year text fails closed before any integer cast'
);

reset role;
revoke portal_public_executor from postgres;

select extensions.ok(
  not pg_catalog.has_function_privilege(
    'anon',
    'private.portal_canonical_decimal_v1(text)'::regprocedure,
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'authenticated',
    'private.portal_canonical_decimal_v1(text)'::regprocedure,
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'service_role',
    'private.portal_canonical_decimal_v1(text)'::regprocedure,
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'anon',
    'private.portal_scalar_text_v1(jsonb)'::regprocedure,
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'authenticated',
    'private.portal_scalar_text_v1(jsonb)'::regprocedure,
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'service_role',
    'private.portal_scalar_text_v1(jsonb)'::regprocedure,
    'EXECUTE'
  ),
  'the private decimal helper is not an external API surface'
);

create or replace function pg_temp.portal_localized(p_text text)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select pg_catalog.jsonb_build_array(
    pg_catalog.jsonb_build_object(
      '@xml:lang', 'en',
      '#text', p_text
    )
  );
$$;

create or replace function pg_temp.portal_publication_and_ownership(
  p_version text,
  p_license_type text,
  p_access_restrictions text,
  p_exclusive_access boolean
)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select pg_catalog.jsonb_strip_nulls(
    pg_catalog.jsonb_build_object(
      'common:dataSetVersion', p_version,
      'common:licenseType', p_license_type,
      'common:dateOfLastRevision', '2026-08-25T10:00:00',
      'common:referenceToUnchangedRepublication', pg_catalog.jsonb_build_object(
        '@type', 'source data set',
        '@refObjectId', '52700000-0000-4000-8000-000000000903',
        '@version', '01.00.000',
        '@uri', 's3://portal-private-bucket/databases/catalog.json',
        'common:shortDescription', pg_temp.portal_localized('Portal Fixture Database')
      ),
      'common:referenceToOwnershipOfDataSet', pg_catalog.jsonb_build_object(
        '@type', 'contact data set',
        '@refObjectId', '52700000-0000-4000-8000-000000000902',
        '@version', '01.00.000',
        '@uri', 's3://portal-private-bucket/contacts/provider.json',
        'common:shortDescription', pg_temp.portal_localized('Portal Provider')
      ),
      'common:accessRestrictions',
        case
          when p_access_restrictions is null then null
          else pg_temp.portal_localized(p_access_restrictions)
        end,
      'common:referenceToEntitiesWithExclusiveAccess',
        case
          when p_exclusive_access then pg_catalog.jsonb_build_object(
            '@refObjectId', '52700000-0000-4000-8000-000000000901',
            '@uri', 's3://portal-private-bucket/exclusive-contact.json'
          )
          else null
        end
    )
  );
$$;

create or replace function pg_temp.portal_process_payload(
  p_name text,
  p_version text,
  p_flow_id uuid,
  p_flow_version text,
  p_mean_amount text,
  p_resulting_amount text,
  p_license_type text,
  p_access_restrictions text,
  p_exclusive_access boolean
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
          'UUID of process data set', p_flow_id::text,
          'name', pg_catalog.jsonb_build_object(
            'baseName', pg_temp.portal_localized(p_name)
          ),
          'common:generalComment', pg_temp.portal_localized(
            p_name || ' public general comment'
          ),
          'classificationInformation', pg_catalog.jsonb_build_object(
            'common:classification', pg_catalog.jsonb_build_array(
              pg_catalog.jsonb_build_object(
                '@classes', 's3://portal-private-bucket/classes.xml',
                'common:class', pg_catalog.jsonb_build_object(
                  '@level', '0',
                  '@classId', 'PORTAL-FIXTURE',
                  '#text', 'Portal fixture class'
                )
              )
            )
          )
        ),
        'quantitativeReference', pg_catalog.jsonb_build_object(
          'referenceToReferenceFlow', '1',
          'functionalUnitOrOther', pg_temp.portal_localized(
            'one kilogram of portal fixture product'
          )
        ),
        'time', pg_catalog.jsonb_build_object('common:referenceYear', '2024'),
        'geography', pg_catalog.jsonb_build_object(
          'locationOfOperationSupplyOrProduction',
          pg_catalog.jsonb_build_object(
            '@location', 'CN',
            'descriptionOfRestrictions', pg_temp.portal_localized('China')
          )
        ),
        'technology', pg_catalog.jsonb_build_object(
          'technologyDescriptionAndIncludedProcesses',
          pg_temp.portal_localized('Portal fixture technology')
        )
      ),
      'exchanges', pg_catalog.jsonb_build_object(
        'exchange', pg_catalog.jsonb_build_array(
          pg_catalog.jsonb_strip_nulls(
            pg_catalog.jsonb_build_object(
              '@dataSetInternalID', '1',
              'exchangeDirection', 'Output',
              'meanAmount', p_mean_amount,
              'resultingAmount', p_resulting_amount,
              'referenceToFlowDataSet', pg_catalog.jsonb_build_object(
                '@type', 'flow data set',
                '@refObjectId', p_flow_id::text,
                '@version', p_flow_version,
                '@uri', 's3://portal-private-bucket/flows/' || p_flow_id::text,
                'common:shortDescription', pg_temp.portal_localized(p_name || ' flow')
              )
            )
          )
        )
      ),
      'modellingAndValidation', pg_catalog.jsonb_build_object(
        'LCIMethodAndAllocation', pg_catalog.jsonb_build_object(
          'typeOfDataSet', 'Unit process, single operation'
        ),
        'dataSourcesTreatmentAndRepresentativeness', pg_catalog.jsonb_build_object(
          'referenceToDataSource', pg_catalog.jsonb_build_object(
            '@type', 'source data set',
            '@refObjectId', '52700000-0000-4000-8000-000000000904',
            '@version', '01.00.000',
            '@uri', 's3://portal-private-bucket/sources/process-source.json',
            'common:shortDescription', pg_temp.portal_localized('Portal Fixture Source')
          )
        ),
        'validation', pg_catalog.jsonb_build_object(
          'review', pg_catalog.jsonb_build_array(
            pg_catalog.jsonb_build_object(
              '@type', 'Independent external review'
            )
          )
        )
      ),
      'administrativeInformation', pg_catalog.jsonb_build_object(
        'publicationAndOwnership',
        pg_temp.portal_publication_and_ownership(
          p_version,
          p_license_type,
          p_access_restrictions,
          p_exclusive_access
        ) || pg_catalog.jsonb_build_object(
          'common:permanentDataSetURI',
          'https://storage.example.test/private/portal-bucket/processes/' || p_name
        )
      ),
      'privateLocator', 'portal-private-bucket/processes/' || p_name
    )
  );
$$;

create or replace function pg_temp.portal_flow_payload(
  p_name text,
  p_version text,
  p_flowproperty_id uuid,
  p_flowproperty_version text,
  p_license_type text,
  p_access_restrictions text,
  p_cas_number text default '50-00-0'
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
            'baseName', pg_temp.portal_localized(p_name)
          ),
          'common:generalComment', pg_temp.portal_localized(
            p_name || ' public general comment'
          ),
          'CASNumber', p_cas_number
        ),
        'quantitativeReference', pg_catalog.jsonb_build_object(
          'referenceToReferenceFlowProperty', '1'
        ),
        'typeOfDataSet', 'Product flow'
      ),
      'flowProperties', pg_catalog.jsonb_build_object(
        'flowProperty', pg_catalog.jsonb_build_array(
          pg_catalog.jsonb_build_object(
            '@dataSetInternalID', '1',
            'meanValue', '1.0000',
            'referenceToFlowPropertyDataSet', pg_catalog.jsonb_build_object(
              '@type', 'flow property data set',
              '@refObjectId', p_flowproperty_id::text,
              '@version', p_flowproperty_version,
              '@uri', 's3://portal-private-bucket/flow-properties/' || p_flowproperty_id::text,
              'common:shortDescription', pg_temp.portal_localized(p_name || ' property')
            )
          )
        )
      ),
      'modellingAndValidation', pg_catalog.jsonb_build_object(
        'LCIMethod', pg_catalog.jsonb_build_object(
          'typeOfDataSet', 'Product flow'
        ),
        'dataSourcesTreatmentAndRepresentativeness', pg_catalog.jsonb_build_object(
          'referenceToDataSource', pg_catalog.jsonb_build_object(
            '@type', 'source data set',
            '@refObjectId', '52700000-0000-4000-8000-000000000904',
            '@version', '01.00.000',
            '@uri', 's3://portal-private-bucket/sources/flow-source.json',
            'common:shortDescription', pg_temp.portal_localized('Portal Fixture Source')
          )
        )
      ),
      'administrativeInformation', pg_catalog.jsonb_build_object(
        'publicationAndOwnership',
        pg_temp.portal_publication_and_ownership(
          p_version,
          p_license_type,
          p_access_restrictions,
          false
        )
      ),
      'objectLocator', 'portal-private-bucket/flows/' || p_name
    )
  );
$$;

create or replace function pg_temp.portal_mixed_process_payload(
  p_name text,
  p_version text,
  p_valid_flow_id uuid,
  p_invalid_flow_id uuid
)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  with base as (
    select pg_temp.portal_process_payload(
      p_name,
      p_version,
      p_valid_flow_id,
      '01.00.000',
      '5.0000',
      null,
      'Free of charge for all users and uses',
      null,
      false
    ) as payload
  )
  select pg_catalog.jsonb_set(
    base.payload,
    '{processDataSet,exchanges,exchange}',
    (base.payload #> '{processDataSet,exchanges,exchange}')
      || pg_catalog.jsonb_build_array(
        pg_catalog.jsonb_build_object(
          '@dataSetInternalID', '2',
          'exchangeDirection', 'Input',
          'meanAmount', '6.0000',
          'referenceToFlowDataSet', pg_catalog.jsonb_build_object(
            '@type', 'flow data set',
            '@refObjectId', p_invalid_flow_id::text,
            '@version', '01.00.000',
            '@uri', 's3://portal-private-bucket/flows/' || p_invalid_flow_id::text,
            'common:shortDescription',
              pg_temp.portal_localized('state 200 support must remain hidden')
          )
        )
      ),
    false
  )
  from base;
$$;

create or replace function pg_temp.portal_incomplete_reference_process_payload(
  p_name text,
  p_version text,
  p_flow_id uuid
)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  with base as (
    select pg_temp.portal_process_payload(
      p_name,
      p_version,
      p_flow_id,
      '01.00.000',
      'not-a-decimal',
      null,
      'Free of charge for all users and uses',
      null,
      false
    ) as payload
  )
  select pg_catalog.jsonb_set(
    base.payload,
    '{processDataSet,exchanges,exchange}',
    (base.payload #> '{processDataSet,exchanges,exchange}')
      || pg_catalog.jsonb_build_array(
        pg_catalog.jsonb_build_object(
          '@dataSetInternalID', '2',
          'exchangeDirection', 'Input',
          'meanAmount', '8.0000',
          'referenceToFlowDataSet', pg_catalog.jsonb_build_object(
            '@type', 'flow data set',
            '@refObjectId', p_flow_id::text,
            '@version', '01.00.000',
            '@uri', 's3://portal-private-bucket/flows/' || p_flow_id::text,
            'common:shortDescription',
              pg_temp.portal_localized('otherwise valid non-reference Exchange')
          )
        )
      ),
    false
  )
  from base;
$$;

create or replace function pg_temp.portal_duplicate_internal_process_payload(
  p_name text,
  p_version text,
  p_flow_id uuid
)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  with base as (
    select pg_temp.portal_process_payload(
      p_name,
      p_version,
      p_flow_id,
      '01.00.000',
      '9.0000',
      null,
      'Free of charge for all users and uses',
      null,
      false
    ) as payload
  )
  select pg_catalog.jsonb_set(
    base.payload,
    '{processDataSet,exchanges,exchange}',
    (base.payload #> '{processDataSet,exchanges,exchange}')
      || pg_catalog.jsonb_build_array(
        pg_catalog.jsonb_build_object(
          '@dataSetInternalID', '1',
          'exchangeDirection', 'Input',
          'meanAmount', '10.0000',
          'referenceToFlowDataSet', pg_catalog.jsonb_build_object(
            '@type', 'flow data set',
            '@refObjectId', p_flow_id::text,
            '@version', '01.00.000',
            '@uri', 's3://portal-private-bucket/flows/' || p_flow_id::text,
            'common:shortDescription',
              pg_temp.portal_localized('duplicate internal id must be hidden')
          )
        )
      ),
    false
  )
  from base;
$$;

create or replace function pg_temp.portal_flowproperty_payload(
  p_name text,
  p_version text,
  p_unitgroup_id uuid,
  p_unitgroup_version text,
  p_license_type text
)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select pg_catalog.jsonb_build_object(
    'flowPropertyDataSet', pg_catalog.jsonb_build_object(
      'flowPropertiesInformation', pg_catalog.jsonb_build_object(
        'dataSetInformation', pg_catalog.jsonb_build_object(
          'common:name', pg_temp.portal_localized(p_name)
        ),
        'quantitativeReference', pg_catalog.jsonb_build_object(
          'referenceToReferenceUnitGroup', pg_catalog.jsonb_build_object(
            '@type', 'unit group data set',
            '@refObjectId', p_unitgroup_id::text,
            '@version', p_unitgroup_version,
            '@uri', 's3://portal-private-bucket/unit-groups/' || p_unitgroup_id::text,
            'common:shortDescription', pg_temp.portal_localized(p_name || ' unit group')
          )
        )
      ),
      'administrativeInformation', pg_catalog.jsonb_build_object(
        'publicationAndOwnership',
        pg_temp.portal_publication_and_ownership(
          p_version,
          p_license_type,
          'none',
          false
        )
      )
    )
  );
$$;

create or replace function pg_temp.portal_unitgroup_payload(
  p_name text,
  p_version text,
  p_license_type text
)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select pg_catalog.jsonb_build_object(
    'unitGroupDataSet', pg_catalog.jsonb_build_object(
      'unitGroupInformation', pg_catalog.jsonb_build_object(
        'dataSetInformation', pg_catalog.jsonb_build_object(
          'common:name', pg_temp.portal_localized(p_name)
        ),
        'quantitativeReference', pg_catalog.jsonb_build_object(
          'referenceToReferenceUnit', '1'
        )
      ),
      'units', pg_catalog.jsonb_build_object(
        'unit', pg_catalog.jsonb_build_array(
          pg_catalog.jsonb_build_object(
            '@dataSetInternalID', '1',
            'name', 'kg',
            'meanValue', '1.0000'
          )
        )
      ),
      'administrativeInformation', pg_catalog.jsonb_build_object(
        'publicationAndOwnership',
        pg_temp.portal_publication_and_ownership(
          p_version,
          p_license_type,
          'none',
          false
        )
      )
    )
  );
$$;

create or replace function pg_temp.portal_has_forbidden_key(p_payload jsonb)
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
        case
          when pg_catalog.jsonb_typeof(parent.value) = 'array'
            then parent.value
          else '[]'::jsonb
        end
      ) as array_value(value)
      union all
      select object_value.value
      from pg_catalog.jsonb_each(
        case
          when pg_catalog.jsonb_typeof(parent.value) = 'object'
            then parent.value
          else '{}'::jsonb
        end
      ) as object_value(key, value)
    ) as child
  ), keys as (
    select pg_catalog.lower(object_key.key) as key
    from walk
    cross join lateral pg_catalog.jsonb_object_keys(
      case
        when pg_catalog.jsonb_typeof(walk.value) = 'object'
          then walk.value
        else '{}'::jsonb
      end
    ) as object_key(key)
  )
  select exists (
    select 1
    from keys
    where key = any (array[
      'user_id',
      'userid',
      'team_id',
      'teamid',
      'review_id',
      'reviewid',
      'state_code',
      'statecode',
      'data_source',
      'datasource',
      'json',
      'json_ordered',
      'search_text',
      'extracted_md',
      'embedding_ft',
      'embedding_ft_at',
      'service_role',
      'secret',
      'credential',
      'bucket',
      'object_path',
      'storage_path',
      'locator',
      'privatelocator',
      'objectlocator'
    ])
  );
$$;

-- Fixture writes bypass every other production side-effect/fence trigger only
-- inside this rollback-only transaction, while retaining the synchronized
-- Portal projection trigger that the candidate-first readers intentionally use.
alter table public.processes disable trigger user;
alter table public.flows disable trigger user;
alter table public.processes
  enable trigger portal_catalog_projection_content_sync_v1;
alter table public.processes
  enable trigger portal_catalog_projection_content_sync_v2;
alter table public.flows
  enable trigger portal_catalog_projection_content_sync_v1;
alter table public.flowproperties disable trigger user;
alter table public.unitgroups disable trigger user;

insert into public.unitgroups (
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
  extracted_md,
  search_text
)
values (
  '52700000-0000-4000-8000-000000000401',
  '01.00.000',
  pg_temp.portal_unitgroup_payload(
    'Portal Fixture Kilogram Unit Group',
    '01.00.000',
    'Free of charge for all users and uses'
  ),
  pg_temp.portal_unitgroup_payload(
    'Portal Fixture Kilogram Unit Group',
    '01.00.000',
    'Free of charge for all users and uses'
  )::json,
  '52700000-0000-4000-8000-000000000001',
  '52700000-0000-4000-8000-000000000002',
  '52700000-0000-4000-8000-000000000003',
  100,
  true,
  '2026-08-25 08:00:00+00',
  'Portal Fixture Kilogram Unit Group',
  array['Portal Fixture Kilogram Unit Group', 'kg']
);

insert into public.flowproperties (
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
  extracted_md,
  search_text
)
values (
  '52700000-0000-4000-8000-000000000301',
  '01.00.000',
  pg_temp.portal_flowproperty_payload(
    'Portal Fixture Mass Flow Property',
    '01.00.000',
    '52700000-0000-4000-8000-000000000401',
    '01.00.000',
    'Free of charge for all users and uses'
  ),
  pg_temp.portal_flowproperty_payload(
    'Portal Fixture Mass Flow Property',
    '01.00.000',
    '52700000-0000-4000-8000-000000000401',
    '01.00.000',
    'Free of charge for all users and uses'
  )::json,
  '52700000-0000-4000-8000-000000000001',
  '52700000-0000-4000-8000-000000000002',
  '52700000-0000-4000-8000-000000000003',
  100,
  true,
  '2026-08-25 08:01:00+00',
  'Portal Fixture Mass Flow Property',
  array['Portal Fixture Mass Flow Property', 'mass']
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
  extracted_md,
  search_text
)
values
  (
    '52700000-0000-4000-8000-000000000201',
    '01.00.000',
    pg_temp.portal_flow_payload(
      'Portal Fixture Valid Product Flow',
      '01.00.000',
      '52700000-0000-4000-8000-000000000301',
      '01.00.000',
      'Free of charge for all users and uses',
      ' none '
    ),
    pg_temp.portal_flow_payload(
      'Portal Fixture Valid Product Flow',
      '01.00.000',
      '52700000-0000-4000-8000-000000000301',
      '01.00.000',
      'Free of charge for all users and uses',
      ' none '
    )::json,
    '52700000-0000-4000-8000-000000000001',
    '52700000-0000-4000-8000-000000000002',
    '52700000-0000-4000-8000-000000000003',
    100,
    true,
    '2026-08-25 08:02:00+00',
    'Portal Fixture Valid Product Flow',
    array['Portal Fixture Valid Product Flow', 'valid flow']
  ),
  (
    '52700000-0000-4000-8000-000000000202',
    '01.00.000',
    pg_temp.portal_flow_payload(
      'Portal Fixture Missing Chain Flow',
      '01.00.000',
      '52700000-0000-4000-8000-000000000399',
      '01.00.000',
      'Free of charge for all users and uses',
      null,
      '64-17-5'
    ),
    pg_temp.portal_flow_payload(
      'Portal Fixture Missing Chain Flow',
      '01.00.000',
      '52700000-0000-4000-8000-000000000399',
      '01.00.000',
      'Free of charge for all users and uses',
      null,
      '64-17-5'
    )::json,
    '52700000-0000-4000-8000-000000000001',
    '52700000-0000-4000-8000-000000000002',
    '52700000-0000-4000-8000-000000000003',
    100,
    true,
    '2026-08-25 08:03:00+00',
    'Portal Fixture Missing Chain Flow',
    array['Portal Fixture Missing Chain Flow', 'missing chain']
  ),
  (
    '52700000-0000-4000-8000-000000000203',
    '01.00.000',
    pg_temp.portal_flow_payload(
      'Portal Fixture State 200 Flow',
      '01.00.000',
      '52700000-0000-4000-8000-000000000301',
      '01.00.000',
      'Free of charge for all users and uses',
      null
    ),
    pg_temp.portal_flow_payload(
      'Portal Fixture State 200 Flow',
      '01.00.000',
      '52700000-0000-4000-8000-000000000301',
      '01.00.000',
      'Free of charge for all users and uses',
      null
    )::json,
    '52700000-0000-4000-8000-000000000001',
    '52700000-0000-4000-8000-000000000002',
    '52700000-0000-4000-8000-000000000003',
    200,
    true,
    '2026-08-25 08:04:00+00',
    'Portal Fixture State 200 Flow',
    array['Portal Fixture State 200 Flow', 'state 200']
  ),
  (
    '52700000-0000-4000-8000-000000000204',
    '01.00.000',
    pg_temp.portal_flow_payload(
      'Portal Fixture Hidden Draft Flow',
      '01.00.000',
      '52700000-0000-4000-8000-000000000301',
      '01.00.000',
      'Free of charge for all users and uses',
      null
    ),
    pg_temp.portal_flow_payload(
      'Portal Fixture Hidden Draft Flow',
      '01.00.000',
      '52700000-0000-4000-8000-000000000301',
      '01.00.000',
      'Free of charge for all users and uses',
      null
    )::json,
    '52700000-0000-4000-8000-000000000001',
    '52700000-0000-4000-8000-000000000002',
    '52700000-0000-4000-8000-000000000003',
    0,
    true,
    '2026-08-25 08:05:00+00',
    'Portal Fixture Hidden Draft Flow',
    array['Portal Fixture Hidden Draft Flow', 'hidden draft']
  );

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
  extracted_md,
  search_text,
  model_id
)
values
  (
    '52700000-0000-4000-8000-000000000101',
    '01.00.000',
    pg_temp.portal_process_payload(
      'Portal Fixture Valid Process Legacy',
      '01.00.000',
      '52700000-0000-4000-8000-000000000201',
      '01.00.000',
      '1.0000',
      null,
      'Free of charge for all users and uses',
      null,
      false
    ),
    pg_temp.portal_process_payload(
      'Portal Fixture Valid Process Legacy',
      '01.00.000',
      '52700000-0000-4000-8000-000000000201',
      '01.00.000',
      '1.0000',
      null,
      'Free of charge for all users and uses',
      null,
      false
    )::json,
    '52700000-0000-4000-8000-000000000001',
    '52700000-0000-4000-8000-000000000002',
    '52700000-0000-4000-8000-000000000003',
    100,
    true,
    '2026-08-25 09:00:00+00',
    'Portal Fixture Valid Process Legacy',
    array['Portal Fixture Valid Process Legacy', 'legacy'],
    '52700000-0000-4000-8000-000000000010'
  ),
  (
    '52700000-0000-4000-8000-000000000101',
    '01.00.001',
    pg_temp.portal_process_payload(
      'Portal Fixture Valid Process Latest',
      '01.00.001',
      '52700000-0000-4000-8000-000000000201',
      '01.00.000',
      '999.000',
      '  +000001.230000  ',
      'Free of charge for all users and uses',
      ' NoNe ',
      false
    ),
    pg_temp.portal_process_payload(
      'Portal Fixture Valid Process Latest',
      '01.00.001',
      '52700000-0000-4000-8000-000000000201',
      '01.00.000',
      '999.000',
      '  +000001.230000  ',
      'Free of charge for all users and uses',
      ' NoNe ',
      false
    )::json,
    '52700000-0000-4000-8000-000000000001',
    '52700000-0000-4000-8000-000000000002',
    '52700000-0000-4000-8000-000000000003',
    100,
    true,
    '2026-08-25 10:00:00+00',
    'Portal Fixture Valid Process Latest',
    array['Portal Fixture Valid Process Latest', 'stable cursor alpha'],
    '52700000-0000-4000-8000-000000000010'
  ),
  (
    '52700000-0000-4000-8000-000000000101',
    '01.00.002',
    pg_temp.portal_process_payload(
      'Portal Fixture Hidden Review Version',
      '01.00.002',
      '52700000-0000-4000-8000-000000000201',
      '01.00.000',
      '9',
      null,
      'Free of charge for all users and uses',
      null,
      false
    ),
    pg_temp.portal_process_payload(
      'Portal Fixture Hidden Review Version',
      '01.00.002',
      '52700000-0000-4000-8000-000000000201',
      '01.00.000',
      '9',
      null,
      'Free of charge for all users and uses',
      null,
      false
    )::json,
    '52700000-0000-4000-8000-000000000001',
    '52700000-0000-4000-8000-000000000002',
    '52700000-0000-4000-8000-000000000003',
    20,
    true,
    '2026-08-25 11:00:00+00',
    'Portal Fixture Hidden Review Version',
    array['Portal Fixture Hidden Review Version', 'hidden review'],
    '52700000-0000-4000-8000-000000000010'
  ),
  (
    '52700000-0000-4000-8000-000000000102',
    '01.00.000',
    pg_temp.portal_process_payload(
      'Portal Fixture Missing Chain Process',
      '01.00.000',
      '52700000-0000-4000-8000-000000000202',
      '01.00.000',
      '2.0000',
      null,
      'Free of charge for all users and uses',
      null,
      false
    ),
    pg_temp.portal_process_payload(
      'Portal Fixture Missing Chain Process',
      '01.00.000',
      '52700000-0000-4000-8000-000000000202',
      '01.00.000',
      '2.0000',
      null,
      'Free of charge for all users and uses',
      null,
      false
    )::json,
    '52700000-0000-4000-8000-000000000001',
    '52700000-0000-4000-8000-000000000002',
    '52700000-0000-4000-8000-000000000003',
    100,
    true,
    '2026-08-25 09:00:00+00',
    'Portal Fixture Missing Chain Process',
    array['Portal Fixture Missing Chain Process', 'stable cursor beta'],
    '52700000-0000-4000-8000-000000000010'
  ),
  (
    '52700000-0000-4000-8000-000000000103',
    '01.00.000',
    pg_temp.portal_process_payload(
      'Portal Fixture State 200 Process',
      '01.00.000',
      '52700000-0000-4000-8000-000000000201',
      '01.00.000',
      '3.0000',
      null,
      'Free of charge for all users and uses',
      null,
      false
    ),
    pg_temp.portal_process_payload(
      'Portal Fixture State 200 Process',
      '01.00.000',
      '52700000-0000-4000-8000-000000000201',
      '01.00.000',
      '3.0000',
      null,
      'Free of charge for all users and uses',
      null,
      false
    )::json,
    '52700000-0000-4000-8000-000000000001',
    '52700000-0000-4000-8000-000000000002',
    '52700000-0000-4000-8000-000000000003',
    200,
    true,
    '2026-08-25 08:00:00+00',
    'Portal Fixture State 200 Process',
    array['Portal Fixture State 200 Process', 'metadata only'],
    '52700000-0000-4000-8000-000000000010'
  ),
  (
    '52700000-0000-4000-8000-000000000104',
    '01.00.000',
    pg_temp.portal_process_payload(
      'Portal Fixture Conflicting License Process',
      '01.00.000',
      '52700000-0000-4000-8000-000000000201',
      '01.00.000',
      '4.0000',
      null,
      'Free of charge for all users and uses',
      'Portal members only',
      false
    ),
    pg_temp.portal_process_payload(
      'Portal Fixture Conflicting License Process',
      '01.00.000',
      '52700000-0000-4000-8000-000000000201',
      '01.00.000',
      '4.0000',
      null,
      'Free of charge for all users and uses',
      'Portal members only',
      false
    )::json,
    '52700000-0000-4000-8000-000000000001',
    '52700000-0000-4000-8000-000000000002',
    '52700000-0000-4000-8000-000000000003',
    100,
    true,
    '2026-08-25 07:00:00+00',
    'Portal Fixture Conflicting License Process',
    array['Portal Fixture Conflicting License Process', 'license conflict'],
    '52700000-0000-4000-8000-000000000010'
  ),
  (
    '52700000-0000-4000-8000-000000000105',
    '01.00.000',
    pg_temp.portal_mixed_process_payload(
      'Portal Fixture Mixed Support Process',
      '01.00.000',
      '52700000-0000-4000-8000-000000000201',
      '52700000-0000-4000-8000-000000000203'
    ),
    pg_temp.portal_mixed_process_payload(
      'Portal Fixture Mixed Support Process',
      '01.00.000',
      '52700000-0000-4000-8000-000000000201',
      '52700000-0000-4000-8000-000000000203'
    )::json,
    '52700000-0000-4000-8000-000000000001',
    '52700000-0000-4000-8000-000000000002',
    '52700000-0000-4000-8000-000000000003',
    100,
    true,
    '2026-08-25 06:00:00+00',
    'Portal Fixture Mixed Support Process',
    array['Portal Fixture Mixed Support Process', 'mixed valid and closed support'],
    '52700000-0000-4000-8000-000000000010'
  ),
  (
    '52700000-0000-4000-8000-000000000106',
    '01.00.000',
    pg_temp.portal_process_payload(
      'Portal Fixture Hidden Draft Process',
      '01.00.000',
      '52700000-0000-4000-8000-000000000201',
      '01.00.000',
      '6',
      null,
      'Free of charge for all users and uses',
      null,
      false
    ),
    pg_temp.portal_process_payload(
      'Portal Fixture Hidden Draft Process',
      '01.00.000',
      '52700000-0000-4000-8000-000000000201',
      '01.00.000',
      '6',
      null,
      'Free of charge for all users and uses',
      null,
      false
    )::json,
    '52700000-0000-4000-8000-000000000001',
    '52700000-0000-4000-8000-000000000002',
    '52700000-0000-4000-8000-000000000003',
    0,
    true,
    '2026-08-25 12:00:00+00',
    'Portal Fixture Hidden Draft Process',
    array['Portal Fixture Hidden Draft Process', 'hidden draft'],
    '52700000-0000-4000-8000-000000000010'
  ),
  (
    '52700000-0000-4000-8000-000000000107',
    '01.00.000',
    pg_temp.portal_process_payload(
      'Portal Fixture Hidden Review Process',
      '01.00.000',
      '52700000-0000-4000-8000-000000000201',
      '01.00.000',
      '7',
      null,
      'Free of charge for all users and uses',
      null,
      false
    ),
    pg_temp.portal_process_payload(
      'Portal Fixture Hidden Review Process',
      '01.00.000',
      '52700000-0000-4000-8000-000000000201',
      '01.00.000',
      '7',
      null,
      'Free of charge for all users and uses',
      null,
      false
    )::json,
    '52700000-0000-4000-8000-000000000001',
    '52700000-0000-4000-8000-000000000002',
    '52700000-0000-4000-8000-000000000003',
    20,
    true,
    '2026-08-25 13:00:00+00',
    'Portal Fixture Hidden Review Process',
    array['Portal Fixture Hidden Review Process', 'hidden review'],
    '52700000-0000-4000-8000-000000000010'
  ),
  (
    '52700000-0000-4000-8000-000000000108',
    '01.00.000',
    pg_temp.portal_incomplete_reference_process_payload(
      'Portal Fixture Incomplete Functional Unit Process',
      '01.00.000',
      '52700000-0000-4000-8000-000000000201'
    ),
    pg_temp.portal_incomplete_reference_process_payload(
      'Portal Fixture Incomplete Functional Unit Process',
      '01.00.000',
      '52700000-0000-4000-8000-000000000201'
    )::json,
    '52700000-0000-4000-8000-000000000001',
    '52700000-0000-4000-8000-000000000002',
    '52700000-0000-4000-8000-000000000003',
    100,
    true,
    '2026-08-25 05:00:00+00',
    'Portal Fixture Incomplete Functional Unit Process',
    array['Portal Fixture Incomplete Functional Unit Process', 'invalid reference amount'],
    '52700000-0000-4000-8000-000000000010'
  ),
  (
    '52700000-0000-4000-8000-000000000109',
    '01.00.000',
    pg_temp.portal_duplicate_internal_process_payload(
      'Portal Fixture Duplicate Internal Process',
      '01.00.000',
      '52700000-0000-4000-8000-000000000201'
    ),
    pg_temp.portal_duplicate_internal_process_payload(
      'Portal Fixture Duplicate Internal Process',
      '01.00.000',
      '52700000-0000-4000-8000-000000000201'
    )::json,
    '52700000-0000-4000-8000-000000000001',
    '52700000-0000-4000-8000-000000000002',
    '52700000-0000-4000-8000-000000000003',
    100,
    true,
    '2026-08-25 04:00:00+00',
    'Portal Fixture Duplicate Internal Process',
    array['Portal Fixture Duplicate Internal Process', 'duplicate internal id'],
    '52700000-0000-4000-8000-000000000010'
  );

update public.processes
set
  json = pg_catalog.jsonb_set(
    json,
    '{processDataSet,processInformation,dataSetInformation,name,baseName,0,@xml:lang}',
    '"invalid_lang!"'::jsonb,
    false
  ),
  json_ordered = pg_catalog.jsonb_set(
    json_ordered::jsonb,
    '{processDataSet,processInformation,dataSetInformation,name,baseName,0,@xml:lang}',
    '"invalid_lang!"'::jsonb,
    false
  )::json
where id = '52700000-0000-4000-8000-000000000101'
  and version = '01.00.001';

create temporary table portal_test_results (
  label text primary key,
  payload jsonb
) on commit drop;

grant select, insert, update, delete on portal_test_results to anon;

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

insert into portal_test_results (label, payload)
values
  (
    'process_search_full',
    api.portal_search_processes_v1(
      'Portal Fixture',
      '{}'::jsonb,
      'modified_desc',
      null,
      50
    )
  ),
  (
    'process_search_page_1',
    api.portal_search_processes_v1(
      'Portal Fixture',
      '{}'::jsonb,
      'modified_desc',
      null,
      1
    )
  ),
  (
    'process_search_name_page_1',
    api.portal_search_processes_v1(
      'Portal Fixture',
      '{}'::jsonb,
      'name_asc',
      null,
      1
    )
  ),
  (
    'process_search_relevance_page_1',
    api.portal_search_processes_v1(
      'Portal Fixture',
      '{}'::jsonb,
      'relevance',
      null,
      1
    )
  ),
  (
    'process_search_exact_id',
    api.portal_search_processes_v1(
      '52700000-0000-4000-8000-000000000101',
      '{}'::jsonb,
      'relevance',
      null,
      20
    )
  ),
  (
    'process_search_lexical',
    api.portal_search_processes_v1(
      'Valid Process Latest',
      '{}'::jsonb,
      'relevance',
      null,
      20
    )
  ),
  (
    'process_search_metadata_filter',
    api.portal_search_processes_v1(
      'Portal Fixture',
      '{"accessLevel":"metadata_only"}'::jsonb,
      'modified_desc',
      null,
      50
    )
  ),
  (
    'flow_search_full',
    api.portal_search_flows_v1(
      'Portal Fixture',
      '{}'::jsonb,
      'modified_desc',
      null,
      50
    )
  ),
  (
    'flow_search_exact_id',
    api.portal_search_flows_v1(
      '52700000-0000-4000-8000-000000000201',
      '{}'::jsonb,
      'relevance',
      null,
      20
    )
  ),
  (
    'process_hybrid_context',
    api.portal_hybrid_search_v1(
      'process',
      array['portal', 'fixture'],
      '[' || pg_catalog.array_to_string(
        pg_catalog.array_fill('0'::text, array[1024]),
        ','
      ) || ']',
      '{}'::jsonb,
      20
    )
  ),
  (
    'flow_hybrid_context',
    api.portal_hybrid_search_v1(
      'flow',
      array['portal', 'fixture'],
      '[' || pg_catalog.array_to_string(
        pg_catalog.array_fill('0'::text, array[1024]),
        ','
      ) || ']',
      '{}'::jsonb,
      20
    )
  ),
  (
    'process_detail_open',
    api.portal_get_dataset_v1(
      'process',
      '52700000-0000-4000-8000-000000000101',
      '01.00.001'
    )
  ),
  (
    'process_detail_state_200',
    api.portal_get_dataset_v1(
      'process',
      '52700000-0000-4000-8000-000000000103',
      '01.00.000'
    )
  ),
  (
    'process_detail_conflicting_license',
    api.portal_get_dataset_v1(
      'process',
      '52700000-0000-4000-8000-000000000104',
      '01.00.000'
    )
  ),
  (
    'process_detail_mixed_support',
    api.portal_get_dataset_v1(
      'process',
      '52700000-0000-4000-8000-000000000105',
      '01.00.000'
    )
  ),
  (
    'flow_detail_open',
    api.portal_get_dataset_v1(
      'flow',
      '52700000-0000-4000-8000-000000000201',
      '01.00.000'
    )
  ),
  (
    'process_detail_state_0',
    api.portal_get_dataset_v1(
      'process',
      '52700000-0000-4000-8000-000000000106',
      '01.00.000'
    )
  ),
  (
    'process_detail_state_20',
    api.portal_get_dataset_v1(
      'process',
      '52700000-0000-4000-8000-000000000107',
      '01.00.000'
    )
  ),
  (
    'process_detail_hidden_newer_version',
    api.portal_get_dataset_v1(
      'process',
      '52700000-0000-4000-8000-000000000101',
      '01.00.002'
    )
  ),
  (
    'process_detail_missing_version',
    api.portal_get_dataset_v1(
      'process',
      '52700000-0000-4000-8000-000000000101',
      '99.99.999'
    )
  ),
  (
    'process_versions_page_1',
    api.portal_list_versions_v1(
      'process',
      '52700000-0000-4000-8000-000000000101',
      null,
      1
    )
  ),
  (
    'exchange_open',
    api.portal_list_process_exchanges_v1(
      '52700000-0000-4000-8000-000000000101',
      '01.00.001',
      'all',
      null,
      50
    )
  ),
  (
    'exchange_open_technosphere',
    api.portal_list_process_exchanges_v1(
      '52700000-0000-4000-8000-000000000101',
      '01.00.001',
      'technosphere',
      null,
      50
    )
  ),
  (
    'exchange_open_elementary',
    api.portal_list_process_exchanges_v1(
      '52700000-0000-4000-8000-000000000101',
      '01.00.001',
      'elementary',
      null,
      50
    )
  ),
  (
    'exchange_missing_chain',
    api.portal_list_process_exchanges_v1(
      '52700000-0000-4000-8000-000000000102',
      '01.00.000',
      'all',
      null,
      50
    )
  ),
  (
    'exchange_state_200',
    api.portal_list_process_exchanges_v1(
      '52700000-0000-4000-8000-000000000103',
      '01.00.000',
      'all',
      null,
      50
    )
  ),
  (
    'exchange_conflicting_license',
    api.portal_list_process_exchanges_v1(
      '52700000-0000-4000-8000-000000000104',
      '01.00.000',
      'all',
      null,
      50
    )
  ),
  (
    'exchange_mixed_support',
    api.portal_list_process_exchanges_v1(
      '52700000-0000-4000-8000-000000000105',
      '01.00.000',
      'all',
      null,
      50
    )
  ),
  (
    'exchange_missing_process',
    api.portal_list_process_exchanges_v1(
      '52700000-0000-4000-8000-000000000199',
      '01.00.000',
      'all',
      null,
      50
    )
  ),
  (
    'exchange_incomplete_functional_unit',
    api.portal_list_process_exchanges_v1(
      '52700000-0000-4000-8000-000000000108',
      '01.00.000',
      'all',
      null,
      50
    )
  ),
  (
    'exchange_duplicate_internal_id',
    api.portal_list_process_exchanges_v1(
      '52700000-0000-4000-8000-000000000109',
      '01.00.000',
      'all',
      null,
      50
    )
  ),
  (
    'process_facets',
    api.portal_facets_v1('process', 'Portal Fixture', '{}'::jsonb)
  ),
  (
    'process_facets_metadata_filter',
    api.portal_facets_v1(
      'process',
      'Portal Fixture',
      '{"accessLevel":"metadata_only"}'::jsonb
    )
  ),
  (
    'flow_facets',
    api.portal_facets_v1('flow', 'Portal Fixture', '{}'::jsonb)
  ),
  (
    'all_facets',
    api.portal_facets_v1('all', 'Portal Fixture', '{}'::jsonb)
  ),
  (
    'process_sitemap_full',
    api.portal_sitemap_entries_v1('process', null, 1000)
  ),
  (
    'all_sitemap_page_1',
    api.portal_sitemap_entries_v1('all', null, 1)
  ),
  (
    'sitemap_manifest',
    api.portal_sitemap_manifest_v1()
  ),
  (
    'catalog_summary_initial',
    api.portal_catalog_summary_v1()
  );

insert into portal_test_results (label, payload)
select
  'sitemap_shards_union',
  pg_catalog.jsonb_build_object(
    'items',
    coalesce(
      pg_catalog.jsonb_agg(
        item.value
        order by item.value #>> '{key,kind}',
          item.value #>> '{key,id}'
      ),
      '[]'::jsonb
    )
  )
from portal_test_results as manifest
cross join lateral pg_catalog.jsonb_array_elements(
  manifest.payload -> 'shards'
) as descriptor(value)
cross join lateral pg_catalog.jsonb_array_elements(
  api.portal_sitemap_shard_v1(
    descriptor.value ->> 'shardCursor'
  ) -> 'items'
) as item(value)
where manifest.label = 'sitemap_manifest';

insert into portal_test_results (label, payload)
select
  'process_search_page_2',
  api.portal_search_processes_v1(
    'Portal Fixture',
    '{}'::jsonb,
    'modified_desc',
    first_page.payload ->> 'nextCursor',
    1
  )
from portal_test_results as first_page
where first_page.label = 'process_search_page_1';

insert into portal_test_results (label, payload)
select
  'process_search_name_page_2',
  api.portal_search_processes_v1(
    'Portal Fixture',
    '{}'::jsonb,
    'name_asc',
    first_page.payload ->> 'nextCursor',
    1
  )
from portal_test_results as first_page
where first_page.label = 'process_search_name_page_1';

insert into portal_test_results (label, payload)
select
  'process_search_relevance_page_2',
  api.portal_search_processes_v1(
    'Portal Fixture',
    '{}'::jsonb,
    'relevance',
    first_page.payload ->> 'nextCursor',
    1
  )
from portal_test_results as first_page
where first_page.label = 'process_search_relevance_page_1';

insert into portal_test_results (label, payload)
select
  'process_versions_page_2',
  api.portal_list_versions_v1(
    'process',
    '52700000-0000-4000-8000-000000000101',
    first_page.payload ->> 'nextCursor',
    1
  )
from portal_test_results as first_page
where first_page.label = 'process_versions_page_1';

insert into portal_test_results (label, payload)
select
  'all_sitemap_page_2',
  api.portal_sitemap_entries_v1(
    'all',
    first_page.payload ->> 'nextCursor',
    1
  )
from portal_test_results as first_page
where first_page.label = 'all_sitemap_page_1';

select extensions.throws_ok(
  $$
    select api.portal_search_processes_v1(
      'Portal Fixture',
      '{"actorId":"52700000-0000-4000-8000-000000000001"}'::jsonb,
      'relevance',
      null,
      20
    )
  $$,
  '22023',
  'invalid portal request',
  'a forged actor filter fails closed without SQL detail'
);

select extensions.throws_ok(
  $$
    select api.portal_search_processes_v1(
      repeat(' ', 513) || 'x', '{}'::jsonb, 'relevance', null, 20
    )
  $$,
  '22023',
  'invalid portal request',
  'raw query length is bounded before whitespace normalization'
);

select extensions.throws_ok(
  $$
    select api.portal_search_processes_v1(
      'x', '{}'::jsonb, repeat(' ', 100) || 'relevance', null, 20
    )
  $$,
  '22023',
  'invalid portal request',
  'raw sort input is bounded before whitespace normalization'
);

select extensions.throws_ok(
  $$
    select api.portal_search_processes_v1(
      'x',
      jsonb_build_object('source', repeat(' ', 5000) || 'portal provider'),
      'relevance',
      null,
      20
    )
  $$,
  '22023',
  'invalid portal request',
  'the complete filter object has an encoded-size bound before scalar normalization'
);

select extensions.throws_ok(
  $$select api.portal_facets_v1(repeat('x', 64), '', '{}'::jsonb)$$,
  '22023',
  'invalid portal request',
  'facet kind input is bounded before normalization'
);

select extensions.throws_ok(
  $$
    select api.portal_search_processes_v1(
      'x', '{"referenceYearFrom":100000}'::jsonb, 'relevance', null, 20
    )
  $$,
  '22023',
  'invalid portal request',
  'oversized year filters fail closed before integer comparison'
);

select extensions.throws_ok(
  $$
    select api.portal_search_processes_v1(
      'Portal Fixture',
      '{"team_id":"52700000-0000-4000-8000-000000000002"}'::jsonb,
      'relevance',
      null,
      20
    )
  $$,
  '22023',
  'invalid portal request',
  'a forged team filter fails closed without SQL detail'
);

select extensions.throws_ok(
  $$
    select api.portal_search_processes_v1(
      'Portal Fixture',
      '{"state":0}'::jsonb,
      'relevance',
      null,
      20
    )
  $$,
  '22023',
  'invalid portal request',
  'a forged state filter fails closed without SQL detail'
);

select extensions.throws_ok(
  $$
    select api.portal_search_processes_v1(
      'Portal Fixture',
      '{"data_source":"my"}'::jsonb,
      'relevance',
      null,
      20
    )
  $$,
  '22023',
  'invalid portal request',
  'a forged data-source filter fails closed without SQL detail'
);

select extensions.throws_ok(
  $$
    select api.portal_search_flows_v1(
      'Portal Fixture',
      '{"processSubtype":"unit_process"}'::jsonb,
      'relevance',
      null,
      20
    )
  $$,
  '22023',
  'invalid portal request',
  'a Process-only filter on Flow search fails closed'
);

select extensions.throws_ok(
  $$
    select api.portal_search_processes_v1(
      'Portal Fixture',
      '[]'::jsonb,
      'relevance',
      null,
      20
    )
  $$,
  '22023',
  'invalid portal request',
  'a non-object filter fails closed'
);

select extensions.throws_ok(
  $$
    select api.portal_search_processes_v1(
      'Portal Fixture',
      '{"accessLevel":"owner"}'::jsonb,
      'relevance',
      null,
      20
    )
  $$,
  '22023',
  'invalid portal request',
  'an unsupported capability filter fails closed'
);

select extensions.throws_ok(
  $$
    select api.portal_search_processes_v1(
      pg_catalog.repeat('x', 513),
      '{}'::jsonb,
      'relevance',
      null,
      20
    )
  $$,
  '22023',
  'invalid portal request',
  'a query over 512 characters fails closed'
);

select extensions.throws_ok(
  $$
    select api.portal_search_processes_v1(
      'Portal Fixture',
      '{}'::jsonb,
      'created_desc',
      null,
      20
    )
  $$,
  '22023',
  'invalid portal request',
  'an unsupported sort fails closed'
);

select extensions.throws_ok(
  $$
    select api.portal_search_processes_v1(
      'Portal Fixture',
      '{}'::jsonb,
      'relevance',
      'not-a-base64url-cursor',
      20
    )
  $$,
  '22023',
  'invalid portal request',
  'a malformed cursor fails closed'
);

select extensions.throws_ok(
  pg_catalog.format(
    'select api.portal_search_processes_v1(%L, %L::jsonb, %L, %L, 1)',
    'Different Query',
    '{}'::jsonb::text,
    'modified_desc',
    first_page.payload ->> 'nextCursor'
  ),
  '22023',
  'invalid portal request',
  'a cursor bound to another query fails closed'
)
from portal_test_results as first_page
where first_page.label = 'process_search_page_1';

select extensions.throws_ok(
  $$
    select api.portal_search_processes_v1(
      'Portal Fixture', '{}'::jsonb, 'relevance', null, 0
    )
  $$,
  '22023',
  'invalid portal request',
  'a zero search limit fails closed'
);

select extensions.throws_ok(
  $$
    select api.portal_search_processes_v1(
      'Portal Fixture', '{}'::jsonb, 'relevance', null, 51
    )
  $$,
  '22023',
  'invalid portal request',
  'a search limit above 50 fails closed'
);

select extensions.throws_ok(
  $$
    select api.portal_get_dataset_v1(
      'processes',
      '52700000-0000-4000-8000-000000000101',
      '01.00.001'
    )
  $$,
  '22023',
  'invalid portal request',
  'a forged dataset kind fails closed'
);

select extensions.throws_ok(
  $$
    select api.portal_list_process_exchanges_v1(
      '52700000-0000-4000-8000-000000000101',
      '01.00.001',
      'biosphere',
      null,
      20
    )
  $$,
  '22023',
  'invalid portal request',
  'an unsupported exchange kind fails closed'
);

select extensions.throws_ok(
  $$select api.portal_sitemap_entries_v1('all', null, 1001)$$,
  '22023',
  'invalid portal request',
  'a sitemap limit above 1000 fails closed'
);

select extensions.throws_ok(
  $$select api.portal_sitemap_shard_v1('not-a-cursor')$$,
  '22023',
  'invalid portal request',
  'a malformed sitemap shard cursor fails closed without SQL detail'
);

select extensions.throws_ok(
  pg_catalog.format(
    'select api.portal_sitemap_shard_v1(%L)',
    pg_temp.portal_test_cursor_v1(forgery.payload)
  ),
  '22023',
  'invalid portal request',
  forgery.description
)
from (values
  (
    '{"scope":"sitemap-shard","bucket":0,"shardCount":64,"extra":true}'::jsonb,
    'a canonical four-key shard cursor missing v fails closed'::text
  ),
  (
    '{"v":1,"bucket":0,"shardCount":64,"extra":true}'::jsonb,
    'a canonical four-key shard cursor missing scope fails closed'
  ),
  (
    '{"v":1,"scope":"sitemap-shard","bucket":0,"extra":true}'::jsonb,
    'a canonical four-key shard cursor missing shardCount fails closed'
  ),
  (
    '{"v":"1","scope":"sitemap-shard","bucket":"0","shardCount":"64"}'::jsonb,
    'a canonical shard cursor with string-typed numeric fields fails closed'
  ),
  (
    '{"v":1.0,"scope":"sitemap-shard","bucket":0,"shardCount":64.0}'::jsonb,
    'a noncanonical numeric-scale shard cursor fails closed'
  )
) as forgery(payload, description);

select extensions.throws_ok(
  pg_catalog.format(
    'select api.portal_sitemap_shard_v1(%L)',
    first_page.payload ->> 'nextCursor'
  ),
  '22023',
  'invalid portal request',
  'an opaque cursor from the legacy sitemap scope cannot cross into a shard'
)
from portal_test_results as first_page
where first_page.label = 'all_sitemap_page_1';

select extensions.throws_ok(
  pg_catalog.format(
    'select api.portal_list_versions_v1(%L, %L::uuid, %L, 1)',
    'process',
    '52700000-0000-4000-8000-000000000102',
    first_page.payload ->> 'nextCursor'
  ),
  '22023',
  'invalid portal request',
  'a version cursor bound to another dataset fails closed'
)
from portal_test_results as first_page
where first_page.label = 'process_versions_page_1';

select extensions.throws_ok(
  pg_catalog.format(
    'select api.portal_sitemap_entries_v1(%L, %L, 1)',
    'process',
    first_page.payload ->> 'nextCursor'
  ),
  '22023',
  'invalid portal request',
  'a sitemap cursor bound to another kind fails closed'
)
from portal_test_results as first_page
where first_page.label = 'all_sitemap_page_1';

select extensions.is(
  pg_catalog.jsonb_array_length(
    api.portal_search_processes_v1(
      'portal-private-bucket',
      '{}'::jsonb,
      'relevance',
      null,
      20
    ) -> 'items'
  ),
  0,
  'search does not expose hidden locator or stripped-field presence through match side channels'
);

select extensions.ok(
  api.portal_search_processes_v1(
    'PORTAL-FIXTURE',
    '{}'::jsonb,
    'relevance',
    null,
    20
  ) #>> '{items,0,match,kind}' = 'identifier'
  and api.portal_search_processes_v1(
    'PORTAL-FIXTURE',
    '{}'::jsonb,
    'relevance',
    null,
    20
  ) #> '{items,0,match,reasonCodes}' = '["classification"]'::jsonb,
  'canonical classification code search returns explicit identifier evidence'
);

select extensions.is(
  pg_catalog.jsonb_array_length(
    api.portal_search_processes_v1(
      'Portal Fixture',
      '{"geography":"  CN  "}'::jsonb,
      'relevance',
      null,
      50
    ) -> 'items'
  ),
  7,
  'facet values round-trip through the same bounded case/whitespace normalization as filters'
);

select extensions.is(
  api.portal_facets_v1(
    'process', 'Portal Fixture', '{"source":" PORTAL PROVIDER "}'::jsonb
  ) ->> 'queryFingerprint',
  api.portal_facets_v1(
    'process', 'Portal Fixture', '{"source":"portal provider"}'::jsonb
  ) ->> 'queryFingerprint',
  'canonical filter normalization produces one stable facet query fingerprint'
);

select extensions.ok(
  not exists (
    with filter_case(label, filters, expected_count) as (
      values
        ('accessLevel', '{"accessLevel":"metadata_only"}'::jsonb, 2),
        ('geography', '{"geography":"cn"}'::jsonb, 7),
        ('classification', '{"classification":"portal-fixture"}'::jsonb, 7),
        ('referenceYearFrom', '{"referenceYearFrom":2024}'::jsonb, 7),
        ('referenceYearTo', '{"referenceYearTo":2024}'::jsonb, 7),
        (
          'processSubtype',
          '{"processSubtype":"unit process, single operation"}'::jsonb,
          7
        ),
        ('source', '{"source":"portal provider"}'::jsonb, 7),
        (
          'conjunction',
          '{"accessLevel":"metadata_only","geography":"cn","classification":"portal-fixture","referenceYearFrom":2024,"referenceYearTo":2024,"processSubtype":"unit process, single operation","source":"portal provider"}'::jsonb,
          2
        )
    ), response as (
      select filter_case.*,
        api.portal_facets_v1(
          'process',
          'Portal Fixture',
          filter_case.filters
        ) as payload
      from filter_case
    ), kind_count as (
      select response.label,
        response.expected_count,
        (facet_value.value ->> 'count')::integer as actual_count
      from response
      cross join lateral pg_catalog.jsonb_array_elements(
        response.payload -> 'groups'
      ) as facet_group(value)
      cross join lateral pg_catalog.jsonb_array_elements(
        facet_group.value -> 'values'
      ) as facet_value(value)
      where facet_group.value ->> 'id' = 'kind'
        and facet_value.value ->> 'value' = 'process'
    )
    select 1
    from filter_case
    left join kind_count using (label, expected_count)
    where kind_count.actual_count is distinct from filter_case.expected_count
  ),
  'all seven retained facet filters and their conjunction preserve exact card-path counts'
);

reset role;

alter table public.processes disable row level security;
alter table public.flows disable row level security;
alter table public.flowproperties disable row level security;
alter table public.unitgroups disable row level security;

set local role anon;

select extensions.is(
  api.portal_get_dataset_v1(
    'process',
    '52700000-0000-4000-8000-000000000106',
    '01.00.000'
  ),
  null::jsonb,
  'explicit state predicates keep state-0 detail opaque even if source-table RLS drifts off'
);

select extensions.is(
  pg_catalog.jsonb_array_length(
    api.portal_search_processes_v1(
      'Portal Fixture State 0 Process',
      '{}'::jsonb,
      'relevance',
      null,
      20
    ) -> 'items'
  ),
  0,
  'explicit state predicates keep state-0 search opaque even if source-table RLS drifts off'
);

reset role;

alter table public.processes enable row level security;
alter table public.flows enable row level security;
alter table public.flowproperties enable row level security;
alter table public.unitgroups enable row level security;

select extensions.is(
  (
    select pg_catalog.jsonb_array_length(payload -> 'shards')
    from portal_test_results
    where label = 'sitemap_manifest'
  ),
  64,
  'the sitemap manifest always contains the complete fixed 64-shard boundary set'
);

select extensions.is(
  (
    select pg_catalog.count(distinct descriptor.value ->> 'shardCursor')
    from portal_test_results as result
    cross join lateral pg_catalog.jsonb_array_elements(
      result.payload -> 'shards'
    ) as descriptor(value)
    where result.label = 'sitemap_manifest'
      and pg_catalog.jsonb_typeof(descriptor.value) = 'object'
      and (
        select pg_catalog.count(*)
        from pg_catalog.jsonb_object_keys(descriptor.value)
      ) = 2
      and descriptor.value -> 'maxItems' = '4096'::jsonb
      and descriptor.value ->> 'shardCursor' ~ '^[A-Za-z0-9_-]+$'
  ),
  64::bigint,
  'all sitemap descriptors are exhaustive, unique, bounded, and opaque'
);

select extensions.is(
  api.portal_sitemap_manifest_v1(),
  (
    select payload
    from portal_test_results
    where label = 'sitemap_manifest'
  ),
  'the constant-cost sitemap manifest is byte-stable across repeated reads'
);

select extensions.is(
  (
    select pg_catalog.count(*)
    from portal_test_results as manifest
    cross join lateral pg_catalog.jsonb_array_elements(
      manifest.payload -> 'shards'
    ) as descriptor(value)
    cross join lateral (
      select api.portal_sitemap_shard_v1(
        descriptor.value ->> 'shardCursor'
      ) as payload
    ) as shard
    where manifest.label = 'sitemap_manifest'
      and shard.payload ->> 'schemaVersion' =
        'portal.public-sitemap-shard.v1'
      and shard.payload ->> 'shardCursor' =
        descriptor.value ->> 'shardCursor'
      and pg_catalog.jsonb_array_length(shard.payload -> 'items') <= 4096
      and (
        select pg_catalog.count(*)
        from pg_catalog.jsonb_object_keys(shard.payload)
      ) = 3
  ),
  64::bigint,
  'every manifest descriptor resolves to one strict bounded shard page'
);

select extensions.is(
  (
    select payload -> 'items'
    from portal_test_results
    where label = 'sitemap_shards_union'
  ),
  api.portal_sitemap_entries_v1('all', null, 1000) -> 'items',
  'the ordered union of all 64 shards equals the complete legacy latest-visible sitemap set'
);

select extensions.is(
  (
    select pg_catalog.jsonb_array_length(payload -> 'items')
    from portal_test_results
    where label = 'sitemap_shards_union'
  ),
  (
    select pg_catalog.count(distinct (
      item.value #>> '{key,kind}',
      item.value #>> '{key,id}',
      item.value #>> '{key,version}'
    ))::integer
    from portal_test_results as result
    cross join lateral pg_catalog.jsonb_array_elements(
      result.payload -> 'items'
    ) as item(value)
    where result.label = 'sitemap_shards_union'
  ),
  'the globally disjoint shard union contains no duplicate exact identity'
);

select extensions.is(
  (
    select pg_catalog.count(*)
    from portal_test_results as manifest
    cross join lateral pg_catalog.jsonb_array_elements(
      manifest.payload -> 'shards'
    ) with ordinality as descriptor(value, ordinality)
    cross join lateral pg_catalog.jsonb_array_elements(
      api.portal_sitemap_shard_v1(
        descriptor.value ->> 'shardCursor'
      ) -> 'items'
    ) as item(value)
    where manifest.label = 'sitemap_manifest'
      and (descriptor.ordinality - 1)::integer <> (
        pg_catalog.get_byte(
          pg_catalog.decode(
            pg_catalog.md5(
              (item.value #>> '{key,kind}') || ':'::text ||
              (item.value #>> '{key,id}')
            ),
            'hex'::text
          ),
          0
        ) / 4
      )
  ),
  0::bigint,
  'every emitted identity belongs to exactly the opaque shard bucket that returned it'
);

select extensions.is(
  (
    select pg_catalog.jsonb_array_length(payload -> 'items')
    from portal_test_results
    where label = 'process_search_full'
  ),
  7,
  'Process search returns one latest visible row for each public fixture id'
);

select extensions.ok(
  not exists (
    select 1
    from portal_test_results as result
    cross join lateral pg_catalog.jsonb_array_elements(
      coalesce(result.payload -> 'items', '[]'::jsonb)
    ) as item(value)
    where result.label in ('process_search_full', 'process_sitemap_full')
      and (
        item.value #>> '{key,id}' in (
          '52700000-0000-4000-8000-000000000106',
          '52700000-0000-4000-8000-000000000107'
        )
        or (
          item.value #>> '{key,id}' = '52700000-0000-4000-8000-000000000101'
          and item.value #>> '{key,version}' = '01.00.002'
        )
      )
  ),
  'state 0/20 rows and a hidden newer version are opaque in search and sitemap'
);

select extensions.is(
  (
    select payload #>> '{items,0,key,version}'
    from portal_test_results
    where label = 'process_search_full'
  ),
  '01.00.001',
  'search selects the latest visible version rather than a newer hidden version'
);

select extensions.is(
  (
    select payload #>> '{items,0,key,id}'
    from portal_test_results
    where label = 'process_search_page_1'
  ),
  '52700000-0000-4000-8000-000000000101',
  'the first modified-desc keyset page has the deterministic first Process'
);

select extensions.is(
  (
    select payload #>> '{items,0,key,id}'
    from portal_test_results
    where label = 'process_search_page_2'
  ),
  '52700000-0000-4000-8000-000000000102',
  'the next keyset page advances without overlap'
);

select extensions.ok(
  (
    select payload ->> 'nextCursor' is not null
    from portal_test_results
    where label = 'process_search_page_1'
  ),
  'a bounded Process search page emits an opaque continuation cursor'
);

select extensions.ok(
  (
    select first_page.payload #>> '{items,0,key,id}'
      is distinct from second_page.payload #>> '{items,0,key,id}'
      and pg_catalog.length(first_page.payload ->> 'nextCursor') <= 4096
    from portal_test_results as first_page
    join portal_test_results as second_page
      on second_page.label = 'process_search_name_page_2'
    where first_page.label = 'process_search_name_page_1'
  ),
  'name-ascending keyset pagination advances with a schema-bounded cursor'
);

select extensions.ok(
  (
    select first_page.payload #>> '{items,0,key,id}'
      is distinct from second_page.payload #>> '{items,0,key,id}'
      and pg_catalog.length(first_page.payload ->> 'nextCursor') <= 4096
    from portal_test_results as first_page
    join portal_test_results as second_page
      on second_page.label = 'process_search_relevance_page_2'
    where first_page.label = 'process_search_relevance_page_1'
  ),
  'relevance keyset pagination advances with a schema-bounded cursor'
);

select extensions.is(
  (
    select payload ->> 'queryFingerprint'
    from portal_test_results
    where label = 'process_search_full'
  ),
  pg_catalog.encode(extensions.digest(pg_catalog.convert_to('composite-names-v2:' ||
pg_catalog.encode(
    extensions.digest(
      pg_catalog.convert_to(
        pg_catalog.jsonb_build_object(
          'kind', 'process',
          'query', 'portal fixture',
          'filters', '{}'::jsonb,
          'sort', 'modified_desc'
        )::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  ), 'UTF8'), 'sha256'), 'hex'),
  'Process search publishes the exact canonical query fingerprint'
);

select extensions.is(
  (
    select payload #>> '{items,0,key,id}'
    from portal_test_results
    where label = 'process_search_exact_id'
  ),
  '52700000-0000-4000-8000-000000000101',
  'exact UUID search resolves the exact Process id'
);

select extensions.is(
  (
    select payload #>> '{items,0,match,kind}'
    from portal_test_results
    where label = 'process_search_exact_id'
  ),
  'identifier',
  'exact UUID search reports identifier match semantics'
);

select extensions.ok(
  (
    select payload #> '{items,0,match,reasonCodes}' @> '["exact_id"]'::jsonb
    from portal_test_results
    where label = 'process_search_exact_id'
  ),
  'exact UUID search exposes the exact_id reason only through the public DTO'
);

select extensions.is(
  (
    select payload #>> '{items,0,key,id}'
    from portal_test_results
    where label = 'process_search_lexical'
  ),
  '52700000-0000-4000-8000-000000000101',
  'lexical search resolves the matching latest Process'
);

select extensions.is(
  (
    select payload #>> '{items,0,names,0,language}'
    from portal_test_results
    where label = 'process_search_lexical'
  ),
  'und',
  'an invalid source language tag is normalized to the schema-safe und tag'
);

select extensions.is(
  (
    select payload #>> '{items,0,match,kind}'
    from portal_test_results
    where label = 'process_search_lexical'
  ),
  'lexical',
  'name search reports lexical match semantics'
);

select extensions.is(
  (
    select pg_catalog.jsonb_array_length(payload -> 'items')
    from portal_test_results
    where label = 'process_search_metadata_filter'
  ),
  2,
  'the validated metadata-only filter returns exactly the state-200 and license-conflict fixtures'
);

select extensions.is(
  (
    select pg_catalog.jsonb_array_length(payload -> 'items')
    from portal_test_results
    where label = 'flow_search_full'
  ),
  3,
  'Flow search unifies state 100 and 200 while excluding state 0'
);

select extensions.is(
  (
    select payload #>> '{items,0,key,id}'
    from portal_test_results
    where label = 'flow_search_exact_id'
  ),
  '52700000-0000-4000-8000-000000000201',
  'exact UUID search resolves the exact Flow id'
);

select extensions.ok(
  (
    select item.value #>> '{context,reference,kind}' = 'reference_product'
      and item.value #> '{context,reference,name}' =
        '[{"language":"en","value":"Portal Fixture Valid Product Flow"}]'::jsonb
      and item.value #>> '{context,functionalUnit,amount}' = '1.23'
      and item.value #>> '{context,functionalUnit,unit}' = 'kg'
      and item.value #> '{context,technology}' =
        '[{"language":"en","value":"Portal fixture technology"}]'::jsonb
      and item.value #>> '{context,source,databaseId}' =
        '52700000-0000-4000-8000-000000000903'
      and item.value #>> '{context,source,databaseVersion}' = '01.00.000'
      and item.value #>> '{context,source,sourceRecordId}' =
        '52700000-0000-4000-8000-000000000904'
      and item.value #> '{context,source,providerName}' =
        '[{"language":"en","value":"Portal Provider"}]'::jsonb
      and item.value #>> '{context,quality,reviewStatus}' =
        'Independent external review'
    from portal_test_results as result
    cross join lateral pg_catalog.jsonb_array_elements(
      result.payload -> 'items'
    ) as item(value)
    where result.label = 'process_search_full'
      and item.value #>> '{key,id}' =
        '52700000-0000-4000-8000-000000000101'
      and item.value #>> '{key,version}' = '01.00.001'
  ),
  'state-100 Process Search card exposes exact allowlisted reference, functional-unit, technology, source, and quality evidence'
);

select extensions.ok(
  (
    select item.value ->> 'accessLevel' = 'metadata_only'
      and item.value #>> '{context,reference,kind}' = 'reference_product'
      and item.value #> '{context,reference,name}' =
        '[{"language":"en","value":"Portal Fixture Valid Product Flow"}]'::jsonb
      and item.value #>> '{context,functionalUnit,amount}' = '3'
      and item.value #>> '{context,functionalUnit,unit}' = 'kg'
      and item.value #> '{context,technology}' =
        '[{"language":"en","value":"Portal fixture technology"}]'::jsonb
      and item.value #>> '{context,source,sourceRecordId}' =
        '52700000-0000-4000-8000-000000000904'
      and item.value #>> '{context,quality,reviewStatus}' =
        'Independent external review'
    from portal_test_results as result
    cross join lateral pg_catalog.jsonb_array_elements(
      result.payload -> 'items'
    ) as item(value)
    where result.label = 'process_search_full'
      and item.value #>> '{key,id}' =
        '52700000-0000-4000-8000-000000000103'
      and item.value #>> '{key,version}' = '01.00.000'
  ),
  'state-200 Process Search card preserves exact metadata context without inventing numeric access'
);

select extensions.ok(
  (
    select item.value #> '{context,functionalUnit}' = 'null'::jsonb
    from portal_test_results as result
    cross join lateral pg_catalog.jsonb_array_elements(
      result.payload -> 'items'
    ) as item(value)
    where result.label = 'process_search_full'
      and item.value #>> '{key,id}' =
        '52700000-0000-4000-8000-000000000108'
      and item.value #>> '{key,version}' = '01.00.000'
  ),
  'Process card uses explicit null when complete functional-unit evidence is unavailable'
);

select extensions.ok(
  not exists (
    select 1
    from portal_test_results as result
    cross join lateral pg_catalog.jsonb_array_elements(
      result.payload -> 'items'
    ) as item(value)
    where result.label = 'flow_search_full'
      and item.value #>> '{key,id}' in (
        '52700000-0000-4000-8000-000000000201',
        '52700000-0000-4000-8000-000000000203'
      )
      and (
        item.value #>> '{context,reference,kind}'
          is distinct from 'reference_flow_property'
        or item.value #> '{context,reference,name}' is distinct from
          '[{"language":"en","value":"Portal Fixture Mass Flow Property"}]'::jsonb
        or item.value #> '{context,functionalUnit}' is distinct from 'null'::jsonb
        or item.value #> '{context,technology}' is distinct from '[]'::jsonb
        or item.value #>> '{context,source,databaseId}' is distinct from
          '52700000-0000-4000-8000-000000000903'
        or item.value #>> '{context,source,sourceRecordId}' is distinct from
          '52700000-0000-4000-8000-000000000904'
        or item.value #> '{context,quality,reviewStatus}' is distinct from
          'null'::jsonb
      )
  )
  and (
    select count(*)
    from portal_test_results as result
    cross join lateral pg_catalog.jsonb_array_elements(
      result.payload -> 'items'
    ) as item(value)
    where result.label = 'flow_search_full'
      and item.value #>> '{key,id}' in (
        '52700000-0000-4000-8000-000000000201',
        '52700000-0000-4000-8000-000000000203'
      )
  ) = 2,
  'state-100/state-200 Flow Search cards expose reference-property/source evidence and explicit Process-only nulls'
);

select extensions.ok(
  not exists (
    with expected(
      dataset_kind,
      dataset_id,
      dataset_version,
      search_label,
      hybrid_label
    ) as (
      values
        (
          'process',
          '52700000-0000-4000-8000-000000000101',
          '01.00.001',
          'process_search_full',
          'process_hybrid_context'
        ),
        (
          'process',
          '52700000-0000-4000-8000-000000000103',
          '01.00.000',
          'process_search_full',
          'process_hybrid_context'
        ),
        (
          'flow',
          '52700000-0000-4000-8000-000000000201',
          '01.00.000',
          'flow_search_full',
          'flow_hybrid_context'
        ),
        (
          'flow',
          '52700000-0000-4000-8000-000000000203',
          '01.00.000',
          'flow_search_full',
          'flow_hybrid_context'
        )
    )
    select 1
    from expected
    left join lateral (
      select item.value
      from portal_test_results as result
      cross join lateral pg_catalog.jsonb_array_elements(
        result.payload -> 'items'
      ) as item(value)
      where result.label = expected.search_label
        and item.value #>> '{key,kind}' = expected.dataset_kind
        and item.value #>> '{key,id}' = expected.dataset_id
        and item.value #>> '{key,version}' = expected.dataset_version
    ) as search_item on true
    left join lateral (
      select item.value
      from portal_test_results as result
      cross join lateral pg_catalog.jsonb_array_elements(
        result.payload -> 'items'
      ) as item(value)
      where result.label = expected.hybrid_label
        and item.value #>> '{key,kind}' = expected.dataset_kind
        and item.value #>> '{key,id}' = expected.dataset_id
        and item.value #>> '{key,version}' = expected.dataset_version
    ) as hybrid_item on true
    where search_item.value is null
       or hybrid_item.value is null
       or search_item.value - 'match' is distinct from
          hybrid_item.value - 'match'
  ),
  'Search and Hybrid emit byte-identical Process/Flow cards outside their versioned match objects'
);

select extensions.ok(
  pg_catalog.jsonb_array_length(
    api.portal_search_flows_v1(
      '50-00-0',
      '{}'::jsonb,
      'relevance',
      null,
      20
    ) -> 'items'
  ) > 0
  and api.portal_search_flows_v1(
    '50-00-0',
    '{}'::jsonb,
    'relevance',
    null,
    20
  ) #>> '{items,0,match,kind}' = 'identifier',
  'canonical Flow CASNumber is projected and searchable as identifier evidence'
);

select extensions.ok(
  (
    select payload ?& array[
      'schemaVersion',
      'key',
      'accessLevel',
      'capabilities',
      'metadata',
      'provenance',
      'publication',
      'modifiedAt'
    ]
    from portal_test_results
    where label = 'process_detail_open'
  ),
  'Process detail returns the exhaustive public envelope sections'
);

select extensions.is(
  (
    select payload ->> 'schemaVersion'
    from portal_test_results
    where label = 'process_detail_open'
  ),
  'portal.public-dataset.v1',
  'Process detail uses the versioned public dataset schema'
);

select extensions.is(
  (
    select payload #>> '{key,version}'
    from portal_test_results
    where label = 'process_detail_open'
  ),
  '01.00.001',
  'Process detail binds the requested exact version'
);

select extensions.is(
  (
    select payload ->> 'accessLevel'
    from portal_test_results
    where label = 'process_detail_open'
  ),
  'open',
  'state 100 with exact full-free evidence is open'
);

select extensions.ok(
  (
    select (payload #>> '{capabilities,metadataVisible}')::boolean
      and (payload #>> '{capabilities,exchangesVisible}')::boolean
      and (payload #>> '{capabilities,citationVisible}')::boolean
      and payload #>> '{capabilities,policyVersion}' = 'portal-capability-policy.v1'
      and payload #> '{capabilities,reasonCodes}' = '["public_license_confirmed"]'::jsonb
    from portal_test_results
    where label = 'process_detail_open'
  ),
  'open detail has the exact capability-policy evidence and Exchange grant'
);

select extensions.ok(
  (
    select payload #>> '{metadata,geography,code}' = 'CN'
      and payload #>> '{metadata,geography,precision}' = 'unknown'
    from portal_test_results
    where label = 'process_detail_open'
  ),
  'geography precision remains unknown without an authoritative classifier'
);

select extensions.is(
  (
    select payload #>> '{metadata,technology,0,value}'
    from portal_test_results
    where label = 'process_detail_open'
  ),
  'Portal fixture technology',
  'array-valued localized technology metadata is flattened into the public allowlist'
);

select extensions.ok(
  (
    select payload #>> '{metadata,classifications,0,system}' = 'ILCD'
      and payload #> '{metadata,administration,permanentDataSetUri}' = 'null'::jsonb
    from portal_test_results
    where label = 'process_detail_open'
  ),
  'classification locators and unauthorised HTTPS permanent URIs remain outside the DTO'
);

select extensions.ok(
  (
    select payload #> '{metadata,administration,lastRevisionAt}' = 'null'::jsonb
    from portal_test_results
    where label = 'process_detail_open'
  ),
  'an administration date without an explicit timezone fails closed to null'
);

select extensions.is(
  (
    select payload ->> 'accessLevel'
    from portal_test_results
    where label = 'process_detail_state_200'
  ),
  'metadata_only',
  'state 200 is always metadata-only even with a full-free license'
);

select extensions.ok(
  (
    select not (payload #>> '{capabilities,exchangesVisible}')::boolean
      and not (payload #>> '{capabilities,lciaVisible}')::boolean
      and payload #> '{capabilities,reasonCodes}' @> '["state_200_metadata_only"]'::jsonb
      and payload #> '{metadata,functionalUnit,amount}' = 'null'::jsonb
      and payload #> '{metadata,functionalUnit,unit}' = 'null'::jsonb
    from portal_test_results
    where label = 'process_detail_state_200'
  ),
  'state 200 exposes no numeric capability or functional-unit amount/unit'
);

select extensions.ok(
  (
    select payload ->> 'accessLevel' = 'metadata_only'
      and not (payload #>> '{capabilities,exchangesVisible}')::boolean
      and payload #> '{capabilities,reasonCodes}' @> '["access_restrictions_present"]'::jsonb
    from portal_test_results
    where label = 'process_detail_conflicting_license'
  ),
  'conflicting license evidence fails closed to metadata-only'
);

select extensions.ok(
  (
    select payload ->> 'accessLevel' = 'open'
      and (payload #>> '{capabilities,exchangesVisible}')::boolean
    from portal_test_results
    where label = 'process_detail_mixed_support'
  ),
  'an open Process keeps dataset-level Exchange capability when one support row is state 200'
);

select extensions.is(
  (
    select payload #>> '{metadata,kind}'
    from portal_test_results
    where label = 'flow_detail_open'
  ),
  'flow',
  'Flow detail uses the Flow metadata projection'
);

select extensions.is(
  (
    select count(*)
    from portal_test_results
    where label in (
      'process_detail_state_0',
      'process_detail_state_20',
      'process_detail_hidden_newer_version',
      'process_detail_missing_version'
    )
      and payload is null
  ),
  4::bigint,
  'draft, review, hidden exact-version, and missing detail all use the same NULL opacity'
);

select extensions.is(
  (
    select payload #>> '{items,0,key,version}'
    from portal_test_results
    where label = 'process_versions_page_1'
  ),
  '01.00.001',
  'version history starts with the latest visible exact version'
);

select extensions.is(
  (
    select payload #>> '{items,0,key,version}'
    from portal_test_results
    where label = 'process_versions_page_2'
  ),
  '01.00.000',
  'version history cursor advances to the next visible exact version'
);

select extensions.ok(
  (
    select payload ->> 'nextCursor' is not null
    from portal_test_results
    where label = 'process_versions_page_1'
  ),
  'version history emits a bound continuation cursor'
);

select extensions.ok(
  (
    select payload ?& array[
      'schemaVersion', 'process', 'processContext', 'rows', 'nextCursor'
    ]
    from portal_test_results
    where label = 'exchange_open'
  ),
  'Exchange projection returns the complete versioned page envelope'
);

select extensions.is(
  (
    select pg_catalog.jsonb_array_length(payload -> 'rows')
    from portal_test_results
    where label = 'exchange_open'
  ),
  1,
  'the valid exact Process/Flow/FlowProperty/UnitGroup chain emits one Exchange'
);

select extensions.ok(
  (
    select payload #>> '{rows,0,internalId}' = '1'
      and payload #>> '{rows,0,kind}' = 'technosphere'
      and payload #>> '{rows,0,direction}' = 'output'
      and payload #>> '{rows,0,flow,id}' = '52700000-0000-4000-8000-000000000201'
      and payload #>> '{rows,0,flow,version}' = '01.00.000'
      and payload #>> '{rows,0,amount}' = '1.23'
      and payload #>> '{rows,0,unit}' = 'kg'
      and (payload #>> '{rows,0,isQuantitativeReference}')::boolean
    from portal_test_results
    where label = 'exchange_open'
  ),
  'Exchange output binds public internal id, kind, direction, exact Flow, canonical amount, unit, and quantitative reference'
);

select extensions.ok(
  (
    select payload #>> '{processContext,functionalUnit,amount}' = '1.23'
      and payload #>> '{processContext,functionalUnit,unit}' = 'kg'
      and payload #>> '{processContext,capabilityPolicyVersion}' = 'portal-capability-policy.v1'
    from portal_test_results
    where label = 'exchange_open'
  ),
  'Exchange page binds the canonical functional unit and capability-policy version'
);

select extensions.is(
  (
    select pg_catalog.jsonb_array_length(payload -> 'rows')
    from portal_test_results
    where label = 'exchange_open_technosphere'
  ),
  1,
  'the exact technosphere filter retains the valid Product-flow Exchange'
);

select extensions.is(
  (
    select pg_catalog.jsonb_array_length(payload -> 'rows')
    from portal_test_results
    where label = 'exchange_open_elementary'
  ),
  0,
  'a valid but non-matching Exchange-kind filter returns an empty page'
);

select extensions.is(
  (
    select count(*)
    from portal_test_results
    where label in (
      'exchange_missing_chain',
      'exchange_state_200',
      'exchange_conflicting_license'
    )
      and pg_catalog.jsonb_array_length(payload -> 'rows') = 0
      and payload -> 'nextCursor' = 'null'::jsonb
  ),
  3::bigint,
  'missing support, state 200, and license conflict all return empty Exchange pages'
);

select extensions.ok(
  (
    select pg_catalog.jsonb_array_length(payload -> 'rows') = 1
      and payload #>> '{rows,0,internalId}' = '1'
      and payload #>> '{rows,0,flow,id}' = '52700000-0000-4000-8000-000000000201'
      and payload::text not like '%52700000-0000-4000-8000-000000000203%'
    from portal_test_results
    where label = 'exchange_mixed_support'
  ),
  'a mixed Process emits its valid Exchange and independently hides the state-200 support row'
);

select extensions.ok(
  (
    select pg_catalog.jsonb_array_length(payload -> 'rows') = 0
      and payload #> '{processContext,functionalUnit,amount}' = 'null'::jsonb
      and payload #> '{processContext,functionalUnit,unit}' = 'null'::jsonb
    from portal_test_results
    where label = 'exchange_incomplete_functional_unit'
  ),
  'an incomplete reference functional unit suppresses all Exchanges, including an otherwise valid non-reference row'
);

select extensions.is(
  (
    select pg_catalog.jsonb_array_length(payload -> 'rows')
    from portal_test_results
    where label = 'exchange_duplicate_internal_id'
  ),
  0,
  'all Exchange rows sharing a duplicate internalId fail closed'
);

select extensions.ok(
  (
    select payload #> '{processContext,functionalUnit,amount}' = 'null'::jsonb
      and payload #> '{processContext,functionalUnit,unit}' = 'null'::jsonb
    from portal_test_results
    where label = 'exchange_state_200'
  ),
  'a state-200 Exchange page does not leak functional-unit numeric context'
);

select extensions.is(
  (
    select payload
    from portal_test_results
    where label = 'exchange_missing_process'
  ),
  null::jsonb,
  'a missing Process Exchange request uses NULL opacity'
);

select extensions.ok(
  (
    select not pg_temp.portal_has_forbidden_key(payload)
      and payload::text !~* '(@uri|s3://|portal-private-bucket|privateLocator|objectLocator)'
    from portal_test_results
    where label = 'exchange_open'
  ),
  'Exchange projection strips every URI, storage locator, and private field from URI-bearing source JSON'
);

select extensions.is(
  (
    select pg_catalog.jsonb_path_query_array(
      payload,
      '$.groups[*].id'
    )
    from portal_test_results
    where label = 'process_facets'
  ),
  '["kind", "accessLevel", "geography", "referenceYear", "processSubtype", "source"]'::jsonb,
  'Process facet groups use the fixed order and exhaustive group ids'
);

select extensions.is(
  (
    select (facet_value.value ->> 'count')::integer
    from portal_test_results as result
    cross join lateral pg_catalog.jsonb_array_elements(result.payload -> 'groups') as facet_group(value)
    cross join lateral pg_catalog.jsonb_array_elements(facet_group.value -> 'values') as facet_value(value)
    where result.label = 'process_facets'
      and facet_group.value ->> 'id' = 'kind'
      and facet_value.value ->> 'value' = 'process'
  ),
  7,
  'Process facets count all seven latest visible Process ids, independent of page size'
);

select extensions.is(
  (
    select (facet_value.value ->> 'count')::integer
    from portal_test_results as result
    cross join lateral pg_catalog.jsonb_array_elements(result.payload -> 'groups') as facet_group(value)
    cross join lateral pg_catalog.jsonb_array_elements(facet_group.value -> 'values') as facet_value(value)
    where result.label = 'process_facets'
      and facet_group.value ->> 'id' = 'geography'
      and facet_value.value ->> 'value' = 'cn'
  ),
  7,
  'Process facets count geography over the complete result set'
);

select extensions.is(
  (
    select (facet_value.value ->> 'count')::integer
    from portal_test_results as result
    cross join lateral pg_catalog.jsonb_array_elements(result.payload -> 'groups') as facet_group(value)
    cross join lateral pg_catalog.jsonb_array_elements(facet_group.value -> 'values') as facet_value(value)
    where result.label = 'process_facets'
      and facet_group.value ->> 'id' = 'accessLevel'
      and facet_value.value ->> 'value' = 'metadata_only'
  ),
  2,
  'Process facets apply capability policy before counting metadata-only results'
);

select extensions.is(
  (
    select (facet_value.value ->> 'count')::integer
    from portal_test_results as result
    cross join lateral pg_catalog.jsonb_array_elements(result.payload -> 'groups') as facet_group(value)
    cross join lateral pg_catalog.jsonb_array_elements(facet_group.value -> 'values') as facet_value(value)
    where result.label = 'process_facets_metadata_filter'
      and facet_group.value ->> 'id' = 'accessLevel'
      and facet_value.value ->> 'value' = 'metadata_only'
  ),
  2,
  'facet counts are computed from the full validated filtered result set'
);

select extensions.is(
  (
    select (facet_value.value ->> 'count')::integer
    from portal_test_results as result
    cross join lateral pg_catalog.jsonb_array_elements(result.payload -> 'groups') as facet_group(value)
    cross join lateral pg_catalog.jsonb_array_elements(facet_group.value -> 'values') as facet_value(value)
    where result.label = 'process_facets'
      and facet_group.value ->> 'id' = 'referenceYear'
      and facet_value.value ->> 'value' = '2024'
  ),
  7,
  'Process facets count reference year over the complete result set'
);

select extensions.is(
  (
    select (facet_value.value ->> 'count')::integer
    from portal_test_results as result
    cross join lateral pg_catalog.jsonb_array_elements(result.payload -> 'groups') as facet_group(value)
    cross join lateral pg_catalog.jsonb_array_elements(facet_group.value -> 'values') as facet_value(value)
    where result.label = 'process_facets'
      and facet_group.value ->> 'id' = 'processSubtype'
      and facet_value.value ->> 'value' = 'unit process, single operation'
  ),
  7,
  'Process facets count the frozen Process subtype path'
);

select extensions.is(
  (
    select (facet_value.value ->> 'count')::integer
    from portal_test_results as result
    cross join lateral pg_catalog.jsonb_array_elements(result.payload -> 'groups') as facet_group(value)
    cross join lateral pg_catalog.jsonb_array_elements(facet_group.value -> 'values') as facet_value(value)
    where result.label = 'process_facets'
      and facet_group.value ->> 'id' = 'source'
      and facet_value.value ->> 'value' = 'portal provider'
  ),
  7,
  'Process facets count the normalized public source description'
);

select extensions.is(
  (
    select pg_catalog.jsonb_path_query_array(payload, '$.groups[*].id')
    from portal_test_results
    where label = 'flow_facets'
  ),
  '["kind", "accessLevel", "source"]'::jsonb,
  'Flow facets preserve the fixed order while omitting groups with no values or applicability'
);

select extensions.ok(
  (
    select not exists (
      select 1
      from pg_catalog.jsonb_array_elements(payload -> 'groups') as facet_group(value)
      where (facet_group.value ->> 'hasMore')::boolean
         or pg_catalog.jsonb_array_length(facet_group.value -> 'values') > 100
    )
    from portal_test_results
    where label = 'all_facets'
  ),
  'facet groups expose the explicit bounded-cardinality hasMore contract'
);

select extensions.is(
  (
    select (facet_value.value ->> 'count')::integer
    from portal_test_results as result
    cross join lateral pg_catalog.jsonb_array_elements(result.payload -> 'groups') as facet_group(value)
    cross join lateral pg_catalog.jsonb_array_elements(facet_group.value -> 'values') as facet_value(value)
    where result.label = 'all_facets'
      and facet_group.value ->> 'id' = 'kind'
      and facet_value.value ->> 'value' = 'process'
  ),
  7,
  'all-kind facets count every latest visible Process id'
);

select extensions.is(
  (
    select (facet_value.value ->> 'count')::integer
    from portal_test_results as result
    cross join lateral pg_catalog.jsonb_array_elements(result.payload -> 'groups') as facet_group(value)
    cross join lateral pg_catalog.jsonb_array_elements(facet_group.value -> 'values') as facet_value(value)
    where result.label = 'all_facets'
      and facet_group.value ->> 'id' = 'kind'
      and facet_value.value ->> 'value' = 'flow'
  ),
  3,
  'all-kind facets count every latest visible Flow id'
);

select extensions.is(
  (
    select (facet_value.value ->> 'count')::integer
    from portal_test_results as result
    cross join lateral pg_catalog.jsonb_array_elements(result.payload -> 'groups') as facet_group(value)
    cross join lateral pg_catalog.jsonb_array_elements(facet_group.value -> 'values') as facet_value(value)
    where result.label = 'all_facets'
      and facet_group.value ->> 'id' = 'source'
      and facet_value.value ->> 'value' = 'portal provider'
  ),
  10,
  'all-kind facets count the normalized public source across both dataset kinds'
);

select extensions.is(
  (
    select pg_catalog.jsonb_array_length(payload -> 'items')
    from portal_test_results
    where label = 'process_sitemap_full'
  ),
  7,
  'Process sitemap contains one latest visible exact version per public id'
);

select extensions.is(
  (
    select item.value #>> '{key,version}'
    from portal_test_results as result
    cross join lateral pg_catalog.jsonb_array_elements(result.payload -> 'items') as item(value)
    where result.label = 'process_sitemap_full'
      and item.value #>> '{key,id}' = '52700000-0000-4000-8000-000000000101'
  ),
  '01.00.001',
  'sitemap selects the latest visible version and ignores a newer state-20 row'
);

select extensions.is(
  (
    select payload #>> '{items,0,key,kind}'
    from portal_test_results
    where label = 'all_sitemap_page_1'
  ),
  'flow',
  'combined sitemap ordering begins with kind=flow'
);

select extensions.ok(
  (
    select first_page.payload #> '{items,0,key}'
      is distinct from second_page.payload #> '{items,0,key}'
    from portal_test_results as first_page
    join portal_test_results as second_page
      on second_page.label = 'all_sitemap_page_2'
    where first_page.label = 'all_sitemap_page_1'
  ),
  'combined sitemap keyset cursor advances without overlap'
);

select extensions.is(
  (
    select payload -> 'counts'
    from portal_test_results
    where label = 'catalog_summary_initial'
  ),
  '{"process":7,"flow":3,"total":10}'::jsonb,
  'catalog summary counts each latest-visible state-100/200 Process and Flow id exactly once'
);

select extensions.is(
  (
    select payload -> 'latestModifiedAt'
    from portal_test_results
    where label = 'catalog_summary_initial'
  ),
  '"2026-08-25T10:00:00.000000Z"'::jsonb,
  'catalog summary latestModifiedAt ignores newer hidden state-0/20 rows'
);

select extensions.is(
  (
    select pg_catalog.jsonb_agg(example.value -> 'queryKind' order by example.ordinality)
    from portal_test_results as result
    cross join lateral pg_catalog.jsonb_array_elements(result.payload -> 'examples')
      with ordinality as example(value, ordinality)
    where result.label = 'catalog_summary_initial'
  ),
  '["uuid","cas","classification"]'::jsonb,
  'catalog summary emits at most one example in fixed UUID/CAS/classification order'
);

select extensions.ok(
  (
    select result.payload #>> '{examples,0,datasetKind}' = 'process'
      and result.payload #>> '{examples,0,query}' =
        '52700000-0000-4000-8000-000000000101'
      and result.payload #>> '{examples,1,datasetKind}' = 'flow'
      and result.payload #>> '{examples,1,query}' = '64-17-5'
      and result.payload #>> '{examples,2,datasetKind}' = 'process'
      and result.payload #>> '{examples,2,query}' = 'PORTAL-FIXTURE'
      and pg_catalog.length(
        result.payload #>> '{examples,2,query}'
      ) >= 4
    from portal_test_results as result
    where result.label = 'catalog_summary_initial'
  ),
  'catalog examples are selected deterministically from latest-visible card evidence'
);

select extensions.ok(
  not exists (
    select 1
    from portal_test_results as result
    cross join lateral pg_catalog.jsonb_array_elements(result.payload -> 'examples')
      as example(value)
    cross join lateral pg_catalog.jsonb_array_elements(example.value -> 'label')
      as label_item(value)
    where result.label = 'catalog_summary_initial'
      and (
        pg_catalog.jsonb_array_length(example.value -> 'label') not between 1 and 2
        or (select count(*) from pg_catalog.jsonb_object_keys(example.value)) <> 4
        or (select count(*) from pg_catalog.jsonb_object_keys(label_item.value)) <> 2
        or pg_catalog.length(label_item.value ->> 'language') > 35
        or pg_catalog.length(label_item.value ->> 'value') > 160
        or pg_catalog.octet_length(label_item.value ->> 'value') > 640
      )
  ),
  'catalog examples contain only the bounded query kind, dataset kind, query, and allowlisted label'
);

select extensions.ok(
  (
    select pg_catalog.bool_and(
      case example.value ->> 'datasetKind'
        when 'process' then pg_catalog.jsonb_array_length(
          api.portal_search_processes_v1(
            example.value ->> 'query', '{}'::jsonb, 'relevance', null, 20
          ) -> 'items'
        ) > 0
        else pg_catalog.jsonb_array_length(
          api.portal_search_flows_v1(
            example.value ->> 'query', '{}'::jsonb, 'relevance', null, 20
          ) -> 'items'
        ) > 0
      end
    )
    from portal_test_results as result
    cross join lateral pg_catalog.jsonb_array_elements(result.payload -> 'examples')
      as example(value)
    where result.label = 'catalog_summary_initial'
  ),
  'every returned catalog example succeeds through the current anonymous lexical facade'
);

select extensions.is(
  (
    select payload
    from portal_test_results
    where label = 'catalog_summary_initial'
  ),
  api.portal_catalog_summary_v1(),
  'catalog summary is deterministic across repeated calls with unchanged projection data'
);

select extensions.ok(
  (
    select pg_catalog.octet_length(payload::text) <= 16384
      and (select count(*) from pg_catalog.jsonb_object_keys(payload)) = 4
      and not (payload::text like any (array[
        '%52700000-0000-4000-8000-000000000106%',
        '%52700000-0000-4000-8000-000000000107%',
        '%52700000-0000-4000-8000-000000000204%'
      ]))
    from portal_test_results
    where label = 'catalog_summary_initial'
  ),
  'catalog summary is bounded and excludes hidden draft/review identities'
);

create temporary table portal_summary_search_cards_original on commit drop as
select dataset_kind, id, version, card
from private.portal_catalog_search_rows_v2;

update private.portal_catalog_search_rows_v2
set card = card - 'classifications'
where dataset_kind = 'process';

update private.portal_catalog_search_rows_v2
set card = pg_catalog.jsonb_set(
  card,
  '{classifications}',
  '[{"system":"fixture","code":"1","label":[]}]'::jsonb,
  true
)
where dataset_kind = 'flow';

set local role anon;
insert into portal_test_results (label, payload)
values ('catalog_summary_short_classification_only', api.portal_catalog_summary_v1());
reset role;

select extensions.ok(
  not exists (
    select 1
    from portal_test_results as result
    cross join lateral pg_catalog.jsonb_array_elements(result.payload -> 'examples')
      as example(value)
    where result.label = 'catalog_summary_short_classification_only'
      and example.value ->> 'queryKind' = 'classification'
  ),
  'summary omits one-character classification evidence instead of advertising a broad timeout-prone query'
);

update private.portal_catalog_search_rows_v2 as target
set card = original.card
from portal_summary_search_cards_original as original
where target.dataset_kind = original.dataset_kind
  and target.id = original.id
  and target.version = original.version;

create temporary table portal_flow_201_original on commit drop as
select json, json_ordered
from public.flows
where id = '52700000-0000-4000-8000-000000000201'
  and version = '01.00.000';

create temporary table portal_process_101_original on commit drop as
select json, json_ordered
from public.processes
where id = '52700000-0000-4000-8000-000000000101'
  and version = '01.00.001';

update public.flows
set
  json = pg_catalog.jsonb_set(
    json,
    '{flowDataSet,modellingAndValidation,LCIMethod,typeOfDataSet}',
    '"not a product flow"'::jsonb
  ),
  json_ordered = pg_catalog.jsonb_set(
    json_ordered::jsonb,
    '{flowDataSet,modellingAndValidation,LCIMethod,typeOfDataSet}',
    '"not a product flow"'::jsonb
  )::json
where id = '52700000-0000-4000-8000-000000000201'
  and version = '01.00.000';

set local role anon;
insert into portal_test_results (label, payload)
values (
  'malformed_flow_kind_exchange',
  api.portal_list_process_exchanges_v1(
    '52700000-0000-4000-8000-000000000101', '01.00.001', 'all', null, 50
  )
);
reset role;

update public.flows
set
  json = pg_catalog.jsonb_set(
    original.json,
    '{flowDataSet,modellingAndValidation,LCIMethod,typeOfDataSet}',
    '{"privateLocator":"product flow"}'::jsonb
  ),
  json_ordered = pg_catalog.jsonb_set(
    original.json_ordered::jsonb,
    '{flowDataSet,modellingAndValidation,LCIMethod,typeOfDataSet}',
    '{"privateLocator":"product flow"}'::jsonb
  )::json
from portal_flow_201_original as original
where public.flows.id = '52700000-0000-4000-8000-000000000201'
  and public.flows.version = '01.00.000';

set local role anon;
insert into portal_test_results (label, payload)
values (
  'polluted_flow_kind_exchange',
  api.portal_list_process_exchanges_v1(
    '52700000-0000-4000-8000-000000000101', '01.00.001', 'all', null, 50
  )
);
reset role;

update public.flows
set
  json = pg_catalog.jsonb_set(
    pg_catalog.jsonb_set(
      original.json,
      '{flowDataSet,flowInformation,quantitativeReference,referenceToReferenceFlowProperty}',
      '"01"'::jsonb
    ),
    '{flowDataSet,flowProperties,flowProperty,0,@dataSetInternalID}',
    '"01"'::jsonb
  ),
  json_ordered = pg_catalog.jsonb_set(
    pg_catalog.jsonb_set(
      original.json_ordered::jsonb,
      '{flowDataSet,flowInformation,quantitativeReference,referenceToReferenceFlowProperty}',
      '"01"'::jsonb
    ),
    '{flowDataSet,flowProperties,flowProperty,0,@dataSetInternalID}',
    '"01"'::jsonb
  )::json
from portal_flow_201_original as original
where public.flows.id = '52700000-0000-4000-8000-000000000201'
  and public.flows.version = '01.00.000';

set local role anon;
insert into portal_test_results (label, payload)
values (
  'leading_zero_support_exchange',
  api.portal_list_process_exchanges_v1(
    '52700000-0000-4000-8000-000000000101', '01.00.001', 'all', null, 50
  )
);
reset role;

update public.flows
set
  json = pg_catalog.jsonb_set(
    original.json,
    '{flowDataSet,flowProperties,flowProperty}',
    pg_catalog.jsonb_build_array(
      original.json #> '{flowDataSet,flowProperties,flowProperty,0}',
      original.json #> '{flowDataSet,flowProperties,flowProperty,0}'
    )
  ),
  json_ordered = pg_catalog.jsonb_set(
    original.json_ordered::jsonb,
    '{flowDataSet,flowProperties,flowProperty}',
    pg_catalog.jsonb_build_array(
      original.json_ordered::jsonb #> '{flowDataSet,flowProperties,flowProperty,0}',
      original.json_ordered::jsonb #> '{flowDataSet,flowProperties,flowProperty,0}'
    )
  )::json
from portal_flow_201_original as original
where public.flows.id = '52700000-0000-4000-8000-000000000201'
  and public.flows.version = '01.00.000';

set local role anon;
insert into portal_test_results (label, payload)
values (
  'duplicate_flowproperty_detail',
  api.portal_get_dataset_v1(
    'flow', '52700000-0000-4000-8000-000000000201', '01.00.000'
  )
);
reset role;

update public.flows
set json = original.json, json_ordered = original.json_ordered
from portal_flow_201_original as original
where public.flows.id = '52700000-0000-4000-8000-000000000201'
  and public.flows.version = '01.00.000';

update public.processes
set
  json = pg_catalog.jsonb_set(
    pg_catalog.jsonb_set(
      original.json,
      '{processDataSet,processInformation,quantitativeReference,referenceToReferenceFlow}',
      '"01"'::jsonb
    ),
    '{processDataSet,exchanges,exchange,0,@dataSetInternalID}',
    '"01"'::jsonb
  ),
  json_ordered = pg_catalog.jsonb_set(
    pg_catalog.jsonb_set(
      original.json_ordered::jsonb,
      '{processDataSet,processInformation,quantitativeReference,referenceToReferenceFlow}',
      '"01"'::jsonb
    ),
    '{processDataSet,exchanges,exchange,0,@dataSetInternalID}',
    '"01"'::jsonb
  )::json
from portal_process_101_original as original
where public.processes.id = '52700000-0000-4000-8000-000000000101'
  and public.processes.version = '01.00.001';

set local role anon;
insert into portal_test_results (label, payload)
values (
  'leading_zero_exchange_identity',
  api.portal_list_process_exchanges_v1(
    '52700000-0000-4000-8000-000000000101', '01.00.001', 'all', null, 50
  )
);
reset role;

update public.processes
set json = original.json, json_ordered = original.json_ordered
from portal_process_101_original as original
where public.processes.id = '52700000-0000-4000-8000-000000000101'
  and public.processes.version = '01.00.001';

select extensions.ok(
  not exists (
    select 1
    from portal_test_results
    where label in (
      'malformed_flow_kind_exchange',
      'polluted_flow_kind_exchange',
      'leading_zero_support_exchange',
      'leading_zero_exchange_identity'
    )
      and pg_catalog.jsonb_array_length(payload -> 'rows') <> 0
  ),
  'malformed Flow kinds and non-canonical Int5/Int6 identities never emit Exchange values'
);

select extensions.is(
  (
    select payload #> '{metadata,referenceFlowProperty}'
    from portal_test_results
    where label = 'duplicate_flowproperty_detail'
  ),
  'null'::jsonb,
  'duplicate reference FlowProperty internal IDs fail closed in Flow detail'
);

insert into public.processes (
  id, version, json, json_ordered, user_id, team_id, review_id,
  state_code, rule_verification, modified_at, extracted_md, search_text, model_id
)
values
  (
    '52700000-0000-4000-8000-000000000120',
    '01.00.000',
    pg_temp.portal_process_payload(
      repeat('界', 499) || 'b', '01.00.000',
      '52700000-0000-4000-8000-000000000201', '01.00.000',
      '1', '1', 'Free of charge for all users and uses', null, false
    ),
    pg_temp.portal_process_payload(
      repeat('界', 499) || 'b', '01.00.000',
      '52700000-0000-4000-8000-000000000201', '01.00.000',
      '1', '1', 'Free of charge for all users and uses', null, false
    )::json,
    '52700000-0000-4000-8000-000000000001',
    '52700000-0000-4000-8000-000000000002',
    '52700000-0000-4000-8000-000000000003',
    100, true, '2026-08-26 00:00:00+00',
    repeat('界', 499) || 'b', array[repeat('界', 499) || 'b'],
    '52700000-0000-4000-8000-000000000010'
  ),
  (
    '52700000-0000-4000-8000-000000000110',
    '01.00.000',
    pg_temp.portal_process_payload(
      repeat('界', 499) || 'c', '01.00.000',
      '52700000-0000-4000-8000-000000000201', '01.00.000',
      '1', '1', 'Free of charge for all users and uses', null, false
    ),
    pg_temp.portal_process_payload(
      repeat('界', 499) || 'c', '01.00.000',
      '52700000-0000-4000-8000-000000000201', '01.00.000',
      '1', '1', 'Free of charge for all users and uses', null, false
    )::json,
    '52700000-0000-4000-8000-000000000001',
    '52700000-0000-4000-8000-000000000002',
    '52700000-0000-4000-8000-000000000003',
    100, true, '2026-08-26 00:00:01+00',
    repeat('界', 499) || 'c', array[repeat('界', 499) || 'c'],
    '52700000-0000-4000-8000-000000000010'
  );

insert into public.processes (
  id, version, json, json_ordered, user_id, team_id, review_id,
  state_code, rule_verification, modified_at, extracted_md, search_text, model_id
)
values
  (
    '52700000-0000-4000-8000-000000000125', '01.00.000',
    'null'::jsonb, 'null'::json,
    '52700000-0000-4000-8000-000000000001',
    '52700000-0000-4000-8000-000000000002',
    '52700000-0000-4000-8000-000000000003',
    100, true, '2026-08-26 00:00:02+00',
    'Portal Invalid JSON Null', array['Portal Invalid JSON Null'],
    '52700000-0000-4000-8000-000000000010'
  ),
  (
    '52700000-0000-4000-8000-000000000126', '01.00.000',
    '{"flowDataSet":{}}'::jsonb, '{"flowDataSet":{}}'::json,
    '52700000-0000-4000-8000-000000000001',
    '52700000-0000-4000-8000-000000000002',
    '52700000-0000-4000-8000-000000000003',
    100, true, '2026-08-26 00:00:03+00',
    'Portal Wrong Root Process', array['Portal Wrong Root Process'],
    '52700000-0000-4000-8000-000000000010'
  );

set local role anon;

insert into portal_test_results (label, payload)
values (
  'multibyte_name_page_1',
  api.portal_search_processes_v1(
    repeat('界', 10), '{}'::jsonb, 'name_asc', null, 1
  )
);

insert into portal_test_results (label, payload)
select
  'multibyte_name_page_2',
  api.portal_search_processes_v1(
    repeat('界', 10),
    '{}'::jsonb,
    'name_asc',
    first_page.payload ->> 'nextCursor',
    1
  )
from portal_test_results as first_page
where first_page.label = 'multibyte_name_page_1';

insert into portal_test_results (label, payload)
values (
  'post_malformed_sitemap',
  api.portal_sitemap_entries_v1('process', null, 1000)
);

select extensions.is(
  api.portal_get_dataset_v1(
    'process', '52700000-0000-4000-8000-000000000125', '01.00.000'
  ),
  null::jsonb,
  'JSON literal null is opaque at exact detail'
);

select extensions.is(
  api.portal_get_dataset_v1(
    'process', '52700000-0000-4000-8000-000000000126', '01.00.000'
  ),
  null::jsonb,
  'a wrong-root JSON object is opaque at exact detail'
);

select extensions.is(
  pg_catalog.jsonb_array_length(
    api.portal_search_processes_v1(
      'Portal Invalid JSON Null', '{}'::jsonb, 'relevance', null, 20
    ) -> 'items'
  ),
  0,
  'malformed public-row JSON cannot re-enter search through internal derivative text'
);

reset role;

select extensions.ok(
  (
    select first_page.payload #>> '{items,0,key,id}' =
        '52700000-0000-4000-8000-000000000120'
      and second_page.payload #>> '{items,0,key,id}' =
        '52700000-0000-4000-8000-000000000110'
      and pg_catalog.length(first_page.payload ->> 'nextCursor') <= 4096
      and first_page.payload #>> '{items,0,match,kind}' = 'lexical'
    from portal_test_results as first_page
    join portal_test_results as second_page
      on second_page.label = 'multibyte_name_page_2'
    where first_page.label = 'multibyte_name_page_1'
  ),
  '500-character multibyte names retain full name order and a bounded reusable cursor'
);

select extensions.ok(
  not exists (
    select 1
    from portal_test_results as result
    cross join lateral pg_catalog.jsonb_array_elements(result.payload -> 'items') as item(value)
    where result.label = 'post_malformed_sitemap'
      and item.value #>> '{key,id}' in (
        '52700000-0000-4000-8000-000000000125',
        '52700000-0000-4000-8000-000000000126'
      )
  ),
  'JSON null and wrong-root rows remain absent from sitemap output'
);

with generated as (
  select
    ordinal,
    ('52720000-0000-4000-8000-' || lpad(ordinal::text, 12, '0'))::uuid as id,
    'Facet Cardinality ' || lpad(ordinal::text, 3, '0') as name,
    pg_temp.portal_process_payload(
      'Facet Cardinality ' || lpad(ordinal::text, 3, '0'),
      '01.00.000',
      '52700000-0000-4000-8000-000000000201',
      '01.00.000',
      '1',
      '1',
      'Free of charge for all users and uses',
      null,
      false
    ) as payload
  from pg_catalog.generate_series(1, 101) as series(ordinal)
), projected as (
  select generated.*,
    pg_catalog.jsonb_set(
      generated.payload,
      '{processDataSet,processInformation,geography,locationOfOperationSupplyOrProduction,@location}',
      to_jsonb('fc-' || lpad(generated.ordinal::text, 3, '0'))
    ) as final_payload
  from generated
)
insert into public.processes (
  id, version, json, json_ordered, user_id, team_id, review_id,
  state_code, rule_verification, modified_at, extracted_md, search_text, model_id
)
select
  projected.id,
  '01.00.000',
  projected.final_payload,
  projected.final_payload::json,
  '52700000-0000-4000-8000-000000000001',
  '52700000-0000-4000-8000-000000000002',
  '52700000-0000-4000-8000-000000000003',
  100,
  true,
  '2026-08-26 01:00:00+00'::timestamptz
    + projected.ordinal * interval '1 second',
  projected.name,
  array[projected.name],
  '52700000-0000-4000-8000-000000000010'
from projected;

set local role anon;
insert into portal_test_results (label, payload)
values (
  'high_cardinality_facets',
  api.portal_facets_v1('process', 'Facet Cardinality', '{}'::jsonb)
);
reset role;

select extensions.ok(
  (
    select (facet_group.value ->> 'hasMore')::boolean
      and pg_catalog.jsonb_array_length(facet_group.value -> 'values') = 100
    from portal_test_results as result
    cross join lateral pg_catalog.jsonb_array_elements(result.payload -> 'groups') as facet_group(value)
    where result.label = 'high_cardinality_facets'
      and facet_group.value ->> 'id' = 'geography'
  ),
  'the 101st canonical facet value is represented by hasMore without exceeding 100 values'
);

insert into public.flows (
  id, version, json, json_ordered, user_id, team_id, review_id,
  state_code, rule_verification, modified_at, extracted_md, search_text
)
select fixture.id,
  fixture.version,
  fixture.payload,
  fixture.payload::json,
  '52700000-0000-4000-8000-000000000001',
  '52700000-0000-4000-8000-000000000002',
  '52700000-0000-4000-8000-000000000003',
  100,
  true,
  '2026-08-26 02:00:00+00'::timestamptz +
    fixture.ordinal * interval '1 second',
  fixture.name,
  array[fixture.name]
from (
  select source.ordinal,
    source.id,
    source.version,
    source.name,
    pg_catalog.jsonb_set(
      pg_temp.portal_flow_payload(
        source.name,
        source.version,
        '52700000-0000-4000-8000-000000000301',
        '01.00.000',
        'Free of charge for all users and uses',
        'none'
      ),
      '{flowDataSet,flowInformation,geography}',
      pg_catalog.jsonb_build_object(
        'locationOfSupply',
        pg_catalog.jsonb_build_object('@location', source.location)
      ),
      true
    ) as payload
  from (values
    (1, '52730000-0000-4000-8000-000000000000'::uuid,
      '01.00.000', 'Geography Former Match', 'CN'),
    (2, '52730000-0000-4000-8000-000000000000'::uuid,
      '01.00.001', 'Geography Latest Excluded', 'DE'),
    (3, '52730000-0000-4000-8000-000000000001'::uuid,
      '01.00.000', 'Geography Fast Flow 1', 'CN'),
    (4, '52730000-0000-4000-8000-000000000002'::uuid,
      '01.00.000', 'Geography Fast Flow 2', 'CN'),
    (5, '52730000-0000-4000-8000-000000000003'::uuid,
      '01.00.000', 'Geography Former Nonmatch', 'DE'),
    (6, '52730000-0000-4000-8000-000000000003'::uuid,
      '01.00.001', 'Geography Latest Match', 'CN')
  ) as source(ordinal, id, version, name, location)
) as fixture;

set local role anon;
insert into portal_test_results (label, payload)
values (
  'flow_geography_fast_page_1',
  api.portal_search_flows_v1(
    '', '{"geography":"cn"}'::jsonb, 'relevance', null, 1
  )
);
insert into portal_test_results (label, payload)
select
  'flow_geography_fast_page_2',
  api.portal_search_flows_v1(
    '',
    '{"geography":"cn"}'::jsonb,
    'relevance',
    first_page.payload ->> 'nextCursor',
    1
  )
from portal_test_results as first_page
where first_page.label = 'flow_geography_fast_page_1';
insert into portal_test_results (label, payload)
select
  'flow_geography_fast_page_3',
  api.portal_search_flows_v1(
    '',
    '{"geography":"cn"}'::jsonb,
    'relevance',
    second_page.payload ->> 'nextCursor',
    1
  )
from portal_test_results as second_page
where second_page.label = 'flow_geography_fast_page_2';

reset role;

set local role anon;
insert into portal_test_results (label, payload)
values ('catalog_summary_before_withdraw', api.portal_catalog_summary_v1());
reset role;

update public.flows
set state_code = 20
where id = '52700000-0000-4000-8000-000000000203'
  and version = '01.00.000';

set local role anon;
insert into portal_test_results (label, payload)
values ('catalog_summary_after_withdraw', api.portal_catalog_summary_v1());
reset role;

select extensions.ok(
  (
    with latest as (
      select distinct on (facet.id)
        facet.id,
        facet.version,
        facet.facet_geography
      from private.portal_catalog_facet_rows_v1 as facet
      where facet.dataset_kind = 'flow'
      order by facet.id,
        facet.version desc,
        facet.modified_at desc,
        facet.state_code desc
    ), expected as (
      select pg_catalog.array_agg(
        bounded.id::text || '@' || bounded.version
        order by bounded.id, bounded.version desc
      ) as keys
      from (
        select latest.id,
          latest.version
        from latest
        where latest.facet_geography = 'cn'
        order by latest.id,
          latest.version desc
        limit 3
      ) as bounded
    ), actual as (
      select pg_catalog.array_agg(
        (result.payload #>> '{items,0,key,id}') || '@' ||
          (result.payload #>> '{items,0,key,version}')
        order by result.label
      ) as keys,
      pg_catalog.bool_and(
        result.payload #>> '{items,0,geography,code}' = 'CN'
        and result.payload #>> '{items,0,match,kind}' = 'lexical'
        and result.payload #> '{items,0,match,reasonCodes}' = '[]'::jsonb
      ) as shape_ok
      from portal_test_results as result
      where result.label in (
        'flow_geography_fast_page_1',
        'flow_geography_fast_page_2',
        'flow_geography_fast_page_3'
      )
    )
    select actual.keys = expected.keys
      and actual.shape_ok
      and (
        select pg_catalog.bool_and(payload ->> 'nextCursor' is not null)
        from portal_test_results
        where label in (
          'flow_geography_fast_page_1',
          'flow_geography_fast_page_2'
        )
      )
    from expected
    cross join actual
  ),
  'geography-only Flow Search filters latest narrow facts before exact ordered card hydration and cursor continuation'
);

select extensions.ok(
  (
    select
      (after_summary.payload #>> '{counts,flow}')::bigint =
        (before_summary.payload #>> '{counts,flow}')::bigint - 1
      and (after_summary.payload #>> '{counts,total}')::bigint =
        (before_summary.payload #>> '{counts,total}')::bigint - 1
      and after_summary.payload -> 'latestModifiedAt' =
        before_summary.payload -> 'latestModifiedAt'
    from portal_test_results as before_summary
    join portal_test_results as after_summary
      on after_summary.label = 'catalog_summary_after_withdraw'
    where before_summary.label = 'catalog_summary_before_withdraw'
  ),
  'a public-to-state-20 transition changes summary counts synchronously without exposing the withdrawn row'
);

update public.flows
set state_code = 200
where id = '52700000-0000-4000-8000-000000000203'
  and version = '01.00.000';

set local role anon;
insert into portal_test_results (label, payload)
values ('catalog_summary_after_restore', api.portal_catalog_summary_v1());
reset role;

select extensions.is(
  (
    select payload
    from portal_test_results
    where label = 'catalog_summary_after_restore'
  ),
  (
    select payload
    from portal_test_results
    where label = 'catalog_summary_before_withdraw'
  ),
  'restoring the same public state restores the deterministic summary exactly'
);

update public.flows
set
  json = pg_catalog.jsonb_set(
    json,
    '{flowDataSet,flowInformation,dataSetInformation,CASNumber}',
    '"50-00-1"'::jsonb,
    false
  ),
  json_ordered = pg_catalog.jsonb_set(
    json_ordered::jsonb,
    '{flowDataSet,flowInformation,dataSetInformation,CASNumber}',
    '"50-00-1"'::jsonb,
    false
  )::json
where state_code in (100, 200)
  and pg_catalog.jsonb_typeof(json) = 'object'
  and pg_catalog.jsonb_typeof(json -> 'flowDataSet') = 'object';

set local role anon;
insert into portal_test_results (label, payload)
values ('catalog_summary_invalid_cas', api.portal_catalog_summary_v1());
reset role;

select extensions.ok(
  not exists (
    select 1
    from portal_test_results as result
    cross join lateral pg_catalog.jsonb_array_elements(result.payload -> 'examples')
      as example(value)
    where result.label = 'catalog_summary_invalid_cas'
      and example.value ->> 'queryKind' = 'cas'
  ),
  'a regex-shaped CAS with an invalid check digit is not returned as an executable example'
);

update public.flows
set
  json = json #- '{flowDataSet,flowInformation,dataSetInformation,CASNumber}',
  json_ordered = (
    json_ordered::jsonb #- '{flowDataSet,flowInformation,dataSetInformation,CASNumber}'
  )::json
where state_code in (100, 200)
  and pg_catalog.jsonb_typeof(json) = 'object'
  and pg_catalog.jsonb_typeof(json -> 'flowDataSet') = 'object';

update public.processes
set
  json = json #-
    '{processDataSet,processInformation,dataSetInformation,classificationInformation}',
  json_ordered = (
    json_ordered::jsonb #-
      '{processDataSet,processInformation,dataSetInformation,classificationInformation}'
  )::json
where state_code in (100, 200)
  and pg_catalog.jsonb_typeof(json) = 'object'
  and pg_catalog.jsonb_typeof(json -> 'processDataSet') = 'object';

set local role anon;
insert into portal_test_results (label, payload)
values ('catalog_summary_without_optional_examples', api.portal_catalog_summary_v1());
reset role;

select extensions.is(
  (
    select pg_catalog.jsonb_agg(example.value -> 'queryKind' order by example.ordinality)
    from portal_test_results as result
    cross join lateral pg_catalog.jsonb_array_elements(result.payload -> 'examples')
      with ordinality as example(value, ordinality)
    where result.label = 'catalog_summary_without_optional_examples'
  ),
  '["uuid"]'::jsonb,
  'missing CAS and classification evidence omits those examples without placeholders'
);

select extensions.ok(
  not exists (
    select 1
    from portal_test_results
    where payload is not null
      and pg_temp.portal_has_forbidden_key(payload)
  ),
  'all Portal catalogue DTOs recursively exclude actor, team, review, raw JSON, embedding, credential, and locator fields'
);

select extensions.ok(
  not exists (
    select 1
    from portal_test_results
    where payload::text like '%52700000-0000-4000-8000-000000000001%'
      or payload::text like '%52700000-0000-4000-8000-000000000002%'
      or payload::text like '%52700000-0000-4000-8000-000000000003%'
      or payload::text ~* '(service_role|supabase_service_key|portal-private-bucket)'
  ),
  'public DTO values do not leak fixture actor/team/review ids, credentials, or private storage values'
);

select * from extensions.finish();

rollback;
