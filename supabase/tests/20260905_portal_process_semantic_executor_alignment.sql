-- Database #620 catalog, ACL, and RLS proof for the Process semantic executor.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = extensions,public,auth;
select extensions.no_plan();

select extensions.ok(
  exists (
    select 1
    from pg_catalog.pg_roles as role
    where role.rolname = 'portal_public_executor'
      and not role.rolsuper
      and not role.rolinherit
      and not role.rolcreaterole
      and not role.rolcreatedb
      and not role.rolcanlogin
      and not role.rolreplication
      and not role.rolbypassrls
  ),
  'Portal executor remains an isolated NOLOGIN NOINHERIT NOBYPASSRLS role'
);

select extensions.is(
  (
    select pg_catalog.pg_get_userbyid(routine.proowner)
    from pg_catalog.pg_proc as routine
    where routine.oid =
      'private.portal_projection_semantic_process_v2(extensions.vector,jsonb)'::regprocedure
  ),
  'portal_public_executor'::name,
  'Process semantic leaf executes as the fixed public Portal role'
);

select extensions.is(
  pg_catalog.encode(
    extensions.digest(
      pg_catalog.convert_to(
        pg_catalog.pg_get_functiondef(
          'private.portal_projection_semantic_process_v2(extensions.vector,jsonb)'::regprocedure
        ),
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  ),
  '903b55f1ba30c6b6b19c030bbee4055ec0d53e6fbd54691d59b4548ce204637f'::text,
  'Process semantic body retains executor alignment with reviewed composite storage routing'
);

select extensions.ok(
  (
    select routine.prosecdef
      and routine.provolatile = 's'
      and routine.proparallel = 'r'
      and routine.proconfig = array[
        'search_path=""',
        'statement_timeout=20s',
        'plan_cache_mode=force_custom_plan',
        'hnsw.iterative_scan=strict_order',
        'hnsw.ef_search=200',
        'hnsw.max_scan_tuples=20000',
        'hnsw.scan_mem_multiplier=2',
        'jit=off',
        'row_security=on'
      ]::text[]
    from pg_catalog.pg_proc as routine
    where routine.oid =
      'private.portal_projection_semantic_process_v2(extensions.vector,jsonb)'::regprocedure
  ),
  'security definer hardening, timeout, and HNSW settings remain unchanged'
);

select extensions.ok(
  pg_catalog.has_column_privilege(
    'portal_public_executor', 'public.processes', 'id', 'SELECT'
  )
  and pg_catalog.has_column_privilege(
    'portal_public_executor', 'public.processes', 'version', 'SELECT'
  )
  and pg_catalog.has_column_privilege(
    'portal_public_executor', 'public.processes', 'state_code', 'SELECT'
  )
  and pg_catalog.has_column_privilege(
    'portal_public_executor', 'public.processes', 'embedding_ft', 'SELECT'
  )
  and not pg_catalog.has_table_privilege(
    'portal_public_executor', 'public.processes', 'SELECT'
  )
  and not pg_catalog.has_column_privilege(
    'portal_public_executor', 'public.processes', 'search_text', 'SELECT'
  )
  and not pg_catalog.has_column_privilege(
    'portal_public_executor', 'public.processes', 'extracted_md', 'SELECT'
  )
  and pg_catalog.has_column_privilege(
    'portal_public_executor', 'public.flows', 'embedding_ft', 'SELECT'
  ),
  'Portal executor has only the reviewed Process and Flow vector-column grants'
);

select extensions.ok(
  pg_catalog.has_function_privilege(
    'api_internal_executor',
    'private.portal_projection_semantic_process_v2(extensions.vector,jsonb)',
    'EXECUTE'
  )
  and pg_catalog.has_function_privilege(
    'portal_public_executor',
    'private.portal_projection_semantic_process_v2(extensions.vector,jsonb)',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'anon',
    'private.portal_projection_semantic_process_v2(extensions.vector,jsonb)',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'authenticated',
    'private.portal_projection_semantic_process_v2(extensions.vector,jsonb)',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'service_role',
    'private.portal_projection_semantic_process_v2(extensions.vector,jsonb)',
    'EXECUTE'
  ),
  'internal caller remains admitted while every external role stays denied'
);

select extensions.ok(
  (
    select relation.relrowsecurity
      and relation.relowner <> 'portal_public_executor'::regrole
    from pg_catalog.pg_class as relation
    where relation.oid = 'public.processes'::regclass
  )
  and exists (
    select 1
    from pg_catalog.pg_policy as policy
    where policy.polrelid = 'public.processes'::regclass
      and policy.polname = 'portal_public_executor_select_processes_v1'
      and policy.polpermissive
      and policy.polcmd = 'r'
      and policy.polroles =
        array['portal_public_executor'::regrole::oid]::oid[]
      and pg_catalog.pg_get_expr(policy.polqual, policy.polrelid) =
        '(state_code = ANY (ARRAY[100, 200]))'
      and policy.polwithcheck is null
  ),
  'Process source keeps RLS with the exact Portal public-state policy'
);

-- Controlled source rows prove that the new vector privilege does not bypass
-- RLS. User triggers are disabled only inside this rollback-only transaction.
alter table public.processes disable trigger user;
alter table private.portal_catalog_search_rows_v2 disable trigger user;
alter table private.portal_catalog_facet_rows_v1 disable trigger user;
insert into public.processes(id, version, state_code, embedding_ft)
values
  (
    '62000000-0000-4000-8000-000000000001',
    '01.00.000',
    20,
    pg_catalog.array_cat(
      array[1::real,0::real],
      pg_catalog.array_fill(0::real,array[1022])
    )::extensions.vector(1024)
  ),
  (
    '62000000-0000-4000-8000-000000000002',
    '01.00.000',
    100,
    pg_catalog.array_cat(
      array[0.99::real,0.01::real],
      pg_catalog.array_fill(0::real,array[1022])
    )::extensions.vector(1024)
  );

insert into private.portal_catalog_search_rows_v2(
  dataset_kind,
  id,
  version,
  state_code,
  modified_at,
  card,
  document,
  projection_contract_version
)
values(
  'process',
  '62000000-0000-4000-8000-000000000002',
  '01.00.000',
  100,
  '2026-09-04 00:00:00+00',
  '{"accessLevel":"open","geography":{"code":"zz620"},"document":""}',
  '',
  2
);

insert into private.portal_catalog_facet_rows_v1(
  dataset_kind,
  id,
  version,
  state_code,
  modified_at,
  facet_access_level,
  facet_geography,
  facet_contract_version
)
values(
  'process',
  '62000000-0000-4000-8000-000000000002',
  '01.00.000',
  100,
  '2026-09-04 00:00:00+00',
  'open',
  'zz620',
  1
);

grant portal_public_executor to postgres;
set local role portal_public_executor;

select extensions.is(
  (
    select pg_catalog.count(*)
    from public.processes
    where id in (
      '62000000-0000-4000-8000-000000000001'::uuid,
      '62000000-0000-4000-8000-000000000002'::uuid
    )
  ),
  1::bigint,
  'Portal executor sees the controlled public row and not the state-20 row'
);

select extensions.lives_ok(
  $$select id, version, state_code, embedding_ft
    from public.processes
    where id = '62000000-0000-4000-8000-000000000002'::uuid$$,
  'Portal executor can read exactly the Process columns needed by the semantic leaf'
);

select extensions.is(
  (
    select pg_catalog.array_agg(candidate.id order by candidate.id)
    from private.portal_projection_semantic_process_v2(
      pg_catalog.array_cat(
        array[1::real,0::real],
        pg_catalog.array_fill(0::real,array[1022])
      )::extensions.vector(1024),
      '{"geography":"zz620","accessLevel":"open"}'::jsonb
    ) as candidate
    where candidate.id in (
      '62000000-0000-4000-8000-000000000001'::uuid,
      '62000000-0000-4000-8000-000000000002'::uuid
    )
  ),
  array['62000000-0000-4000-8000-000000000002'::uuid],
  'selective exact route hides the closest nonpublic vector and returns the public vector'
);

select extensions.is(
  (
    select pg_catalog.count(*)
    from private.portal_projection_semantic_process_v2(
      pg_catalog.array_cat(
        array[1::real,0::real],
        pg_catalog.array_fill(0::real,array[1022])
      )::extensions.vector(1024),
      '{"geography":"missing"}'::jsonb
    )
  ),
  0::bigint,
  'an empty indexed Process candidate set returns directly without HNSW fill'
);

reset role;
revoke portal_public_executor from postgres;

select * from extensions.finish();
rollback;
