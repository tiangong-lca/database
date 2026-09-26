begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, api, private, auth;

select plan(46);

select is(
  (
    select count(*)
    from pg_proc as routine
    join pg_namespace as namespace on namespace.oid = routine.pronamespace
    cross join lateral aclexplode(coalesce(routine.proacl, acldefault('f', routine.proowner))) as acl
    where namespace.nspname = 'api'
      and acl.grantee = 0
      and acl.privilege_type = 'EXECUTE'
  ),
  0::bigint,
  'api has no function executable through the PostgreSQL PUBLIC role'
);

select is(
  (
    with actual as (
      select
        format(
          '%I.%I(%s)', namespace.nspname, routine.proname,
          pg_catalog.oidvectortypes(routine.proargtypes)
        ) as routine_identity,
        role.rolname
      from pg_proc as routine
      join pg_namespace as namespace on namespace.oid = routine.pronamespace
      cross join lateral aclexplode(coalesce(routine.proacl, acldefault('f', routine.proowner))) as acl
      join pg_roles as role on role.oid = acl.grantee
      where namespace.nspname = 'api'
        and role.rolname in ('anon', 'authenticated', 'service_role')
        and acl.privilege_type = 'EXECUTE'
    ), expected as (
      select manifest.routine_identity, role_name
      from private.api_capability_grants as manifest
      cross join lateral (values
        ('anon', manifest.allow_anon),
        ('authenticated', manifest.allow_authenticated),
        ('service_role', manifest.allow_service_role)
      ) as role(role_name, allowed)
      where role.allowed
    )
    select count(*) from (select * from actual except select * from expected) as unexpected
  ),
  0::bigint,
  'every external API execute grant maps to an exact capability manifest entry'
);

select is(
  (
    with actual as (
      select
        format(
          '%I.%I(%s)', namespace.nspname, routine.proname,
          pg_catalog.oidvectortypes(routine.proargtypes)
        ) as routine_identity,
        role.rolname
      from pg_proc as routine
      join pg_namespace as namespace on namespace.oid = routine.pronamespace
      cross join lateral aclexplode(coalesce(routine.proacl, acldefault('f', routine.proowner))) as acl
      join pg_roles as role on role.oid = acl.grantee
      where namespace.nspname = 'api'
        and role.rolname in ('anon', 'authenticated', 'service_role')
        and acl.privilege_type = 'EXECUTE'
    ), expected as (
      select manifest.routine_identity, role_name
      from private.api_capability_grants as manifest
      cross join lateral (values
        ('anon', manifest.allow_anon),
        ('authenticated', manifest.allow_authenticated),
        ('service_role', manifest.allow_service_role)
      ) as role(role_name, allowed)
      where role.allowed
    )
    select count(*) from (select * from expected except select * from actual) as missing
  ),
  0::bigint,
  'the catalog contains every exact role grant frozen by the capability manifest'
);

select is(
  (
    select count(*)
    from pg_proc as routine
    join pg_namespace as namespace on namespace.oid = routine.pronamespace
    where namespace.nspname = 'api'
      and routine.proname = any(array[
        'qry_membership_get_mine',
        'qry_team_list',
        'qry_team_get',
        'qry_identity_get_mine',
        'qry_identity_get_visible_users',
        'qry_system_find_member_candidate_by_email',
        'qry_review_find_member_candidate_by_email',
        'svc_worker_enqueue_job',
        'svc_worker_read_job',
        'svc_worker_list_jobs',
        'svc_worker_cancel_job',
        'svc_lca_read_job_projection',
        'svc_lca_read_result_projection',
        'svc_lca_read_latest_single_solve_result',
        'svc_schema_contract_status',
        'cmd_lifecycle_model_bundle_save',
        'cmd_lifecycle_model_bundle_delete'
      ])
      and routine.prosecdef
      and routine.proconfig = array['search_path=""']::text[]
  ),
  17::bigint,
  'all new facades are SECURITY DEFINER with an empty fixed search_path'
);

select is(
  (
    select count(*)
    from pg_proc as routine
    join pg_namespace as namespace on namespace.oid = routine.pronamespace
    join pg_roles as owner_role on owner_role.oid = routine.proowner
    where namespace.nspname = 'api'
      and routine.proname = any(array[
        'search_contacts_latest', 'search_flowproperties_latest',
        'search_sources_latest', 'search_unitgroups_latest'
      ])
      and routine.prosecdef
      and owner_role.rolname = 'api_internal_executor'
      and routine.proconfig @> array['search_path=""']::text[]
  ),
  4::bigint,
  'simple-search facades traverse their helper through the constrained executor'
);

select ok(
  has_function_privilege('authenticated', 'api.qry_membership_get_mine()', 'EXECUTE')
    and has_function_privilege('authenticated', 'api.qry_team_list(text,text,integer,integer)', 'EXECUTE')
    and has_function_privilege('authenticated', 'api.qry_team_get(uuid)', 'EXECUTE')
    and has_function_privilege('authenticated', 'api.qry_identity_get_mine()', 'EXECUTE')
    and has_function_privilege('authenticated', 'api.qry_identity_get_visible_users(uuid[])', 'EXECUTE'),
  'authenticated receives the actor-derived read contracts'
);

select ok(
  not has_function_privilege('anon', 'api.qry_membership_get_mine()', 'EXECUTE')
    and not has_function_privilege('service_role', 'api.qry_membership_get_mine()', 'EXECUTE')
    and not has_function_privilege('anon', 'api.cmd_lifecycle_model_bundle_save(jsonb)', 'EXECUTE')
    and not has_function_privilege('service_role', 'api.cmd_lifecycle_model_bundle_save(jsonb)', 'EXECUTE'),
  'actor-derived contracts are not callable by anon or bare service role'
);

select ok(
  has_function_privilege('service_role', 'api.svc_worker_read_job(uuid,boolean)', 'EXECUTE')
    and has_function_privilege('service_role', 'api.svc_lca_read_result_projection(uuid,uuid,text,boolean)', 'EXECUTE'),
  'service role receives the service facade family'
);

select ok(
  not has_function_privilege('anon', 'api.svc_worker_read_job(uuid,boolean)', 'EXECUTE')
    and not has_function_privilege('authenticated', 'api.svc_worker_read_job(uuid,boolean)', 'EXECUTE'),
  'service facades reject browser roles at the ACL boundary'
);

create function api.issue_422_default_privilege_canary()
returns integer language sql as 'select 1';

select ok(
  not exists (
    select 1
    from pg_proc as routine
    cross join lateral aclexplode(coalesce(routine.proacl, acldefault('f', routine.proowner))) as acl
    where routine.oid = 'api.issue_422_default_privilege_canary()'::regprocedure
      and acl.grantee = 0
      and acl.privilege_type = 'EXECUTE'
  ),
  'future postgres-owned functions do not inherit PUBLIC execute'
);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at, is_sso_user, is_anonymous
) values
  ('00000000-0000-0000-0000-000000000000', '42200000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'owner@example.com', 'test', now(), '{"provider":"email","providers":["email"]}', '{"email":"owner@example.com","display_name":"Owner"}', now(), now(), false, false),
  ('00000000-0000-0000-0000-000000000000', '42200000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'member@example.com', 'test', now(), '{"provider":"email","providers":["email"]}', '{"email":"member@example.com","display_name":"Member"}', now(), now(), false, false),
  ('00000000-0000-0000-0000-000000000000', '42200000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'outsider@example.com', 'test', now(), '{"provider":"email","providers":["email"]}', '{"email":"outsider@example.com","display_name":"Outsider"}', now(), now(), false, false),
  ('00000000-0000-0000-0000-000000000000', '42200000-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'system@example.com', 'test', now(), '{"provider":"email","providers":["email"]}', '{"email":"system@example.com","display_name":"System"}', now(), now(), false, false),
  ('00000000-0000-0000-0000-000000000000', '42200000-0000-4000-8000-000000000005', 'authenticated', 'authenticated', 'review@example.com', 'test', now(), '{"provider":"email","providers":["email"]}', '{"email":"review@example.com","display_name":"Review"}', now(), now(), false, false);

update private.users
set contact = jsonb_build_object('kind', 'fixture')
where id = '42200000-0000-4000-8000-000000000001';

insert into private.users (id, raw_user_meta_data, contact) values
  ('42200000-0000-4000-8000-000000000001', '{"email":"owner@example.com","display_name":"Owner"}', '{"kind":"fixture"}'),
  ('42200000-0000-4000-8000-000000000002', '{"email":"member@example.com","display_name":"Member"}', null),
  ('42200000-0000-4000-8000-000000000003', '{"email":"outsider@example.com","display_name":"Outsider"}', null),
  ('42200000-0000-4000-8000-000000000004', '{"email":"system@example.com","display_name":"System"}', null),
  ('42200000-0000-4000-8000-000000000005', '{"email":"review@example.com","display_name":"Review"}', null)
on conflict (id) do update
set raw_user_meta_data = excluded.raw_user_meta_data,
    contact = excluded.contact;

insert into private.teams (id, json, rank, is_public, created_at) values
  ('42210000-0000-4000-8000-000000000001', '{"title":[{"#text":"Alpha%_Team"},{"#text":"甲团队"}]}'::jsonb, 1, true, '2026-08-01T00:00:00Z'),
  ('42210000-0000-4000-8000-000000000002', '{"title":[{"#text":"Private Team"}]}'::jsonb, -1, false, '2026-08-02T00:00:00Z'),
  ('42210000-0000-4000-8000-000000000003', '{"title":[{"#text":"Pending Team"}]}'::jsonb, 0, false, '2026-08-03T00:00:00Z');

insert into private.roles (user_id, team_id, role, created_at, modified_at) values
  ('42200000-0000-4000-8000-000000000001', '42210000-0000-4000-8000-000000000001', 'owner', '2026-08-01T00:00:00Z', '2026-08-01T01:00:00Z'),
  ('42200000-0000-4000-8000-000000000002', '42210000-0000-4000-8000-000000000001', 'member', '2026-08-01T00:00:00Z', '2026-08-01T02:00:00Z'),
  ('42200000-0000-4000-8000-000000000003', '42210000-0000-4000-8000-000000000002', 'owner', '2026-08-02T00:00:00Z', '2026-08-02T01:00:00Z'),
  ('42200000-0000-4000-8000-000000000004', '00000000-0000-0000-0000-000000000000', 'admin', '2026-08-01T00:00:00Z', '2026-08-01T00:00:00Z'),
  ('42200000-0000-4000-8000-000000000005', '00000000-0000-0000-0000-000000000000', 'review-admin', '2026-08-01T00:00:00Z', '2026-08-01T00:00:00Z');

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claims', '{"role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', '42200000-0000-4000-8000-000000000001', true);

select is(
  (select count(*) from api.qry_membership_get_mine()),
  1::bigint,
  'membership mine returns only the actor memberships'
);

select is(
  (select user_id from api.qry_membership_get_mine() limit 1),
  '42200000-0000-4000-8000-000000000001'::uuid,
  'membership mine derives the actor from auth.uid'
);

select is(
  (select count(*) from api.qry_team_list('ranked', null, 1, 10)),
  1::bigint,
  'ranked team mode returns only ranked teams'
);

select is(
  (select owner_user_id from api.qry_team_list('public', null, 1, 10) limit 1),
  '42200000-0000-4000-8000-000000000001'::uuid,
  'team list embeds only the owner relationship'
);

select is(
  (select owner_email from api.qry_team_list('public', null, 1, 10) limit 1),
  'owner@example.com'::text,
  'team list exposes the explicit owner email DTO'
);

select is(
  (select count(*) from api.qry_team_list('public', '%_', 1, 10)),
  1::bigint,
  'team keyword percent and underscore are matched literally'
);

select is(
  (select total_count from api.qry_team_list('public', null, 1, 1) limit 1),
  1::bigint,
  'team pagination carries an exact total count'
);

select is(
  (select count(*) from api.qry_team_get('42210000-0000-4000-8000-000000000002')),
  0::bigint,
  'actor cannot read an unrelated private unranked team'
);

select is(
  (select email from api.qry_identity_get_mine()),
  'owner@example.com'::text,
  'identity mine returns the actor email'
);

select is(
  (select contact from api.qry_identity_get_mine()),
  '{"kind":"fixture"}'::jsonb,
  'identity mine returns contact without raw metadata'
);

select is(
  (select count(*) from api.qry_identity_get_visible_users(array[
    '42200000-0000-4000-8000-000000000001'::uuid,
    '42200000-0000-4000-8000-000000000002'::uuid,
    '42200000-0000-4000-8000-000000000003'::uuid
  ])),
  2::bigint,
  'visible identity lookup includes self and active teammate but not outsider'
);

select throws_ok(
  $$select * from api.qry_identity_get_visible_users(array_fill('42200000-0000-4000-8000-000000000001'::uuid, array[101]))$$,
  '22023',
  'TOO_MANY_USER_IDS',
  'visible identity lookup enforces the 100-id bound'
);

select throws_ok(
  $$select * from api.qry_team_list('unranked', null, 1, 10)$$,
  '42501',
  'SYSTEM_MANAGER_REQUIRED',
  'unranked team directory requires a system manager'
);

select throws_ok(
  $$select * from api.qry_system_find_member_candidate_by_email('member@example.com')$$,
  '42501',
  'SYSTEM_MANAGER_REQUIRED',
  'ordinary actor cannot use system candidate lookup'
);

select throws_ok(
  $$select * from api.qry_review_find_member_candidate_by_email('member@example.com')$$,
  '42501',
  'REVIEW_ADMIN_REQUIRED',
  'ordinary actor cannot use review candidate lookup'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '42200000-0000-4000-8000-000000000004', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claims', '{"role":"authenticated"}', true);

select is(
  (select count(*) from api.qry_team_list('unranked', null, 1, 10)),
  1::bigint,
  'system manager can read the unranked directory'
);

select is(
  (select id from api.qry_system_find_member_candidate_by_email(' MEMBER@example.com ') limit 1),
  '42200000-0000-4000-8000-000000000002'::uuid,
  'system candidate lookup normalizes email case and whitespace'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '42200000-0000-4000-8000-000000000005', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claims', '{"role":"authenticated"}', true);

select is(
  (select id from api.qry_review_find_member_candidate_by_email('member@example.com') limit 1),
  '42200000-0000-4000-8000-000000000002'::uuid,
  'review admin can use the review candidate lookup'
);

select throws_ok(
  $$select * from api.qry_system_find_member_candidate_by_email('member@example.com')$$,
  '42501',
  'SYSTEM_MANAGER_REQUIRED',
  'review admin cannot cross into the system candidate lookup'
);

reset role;
set local role anon;
select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claim.role', 'anon', true);
select set_config('request.jwt.claims', '{"role":"anon"}', true);

select ok(
  not has_function_privilege('anon', 'api.qry_membership_get_mine()', 'EXECUTE'),
  'anon cannot execute actor-derived membership facade'
);

select ok(
  not has_function_privilege('anon', 'api.svc_worker_read_job(uuid,boolean)', 'EXECUTE'),
  'anon cannot execute service worker facade'
);

select lives_ok(
  $$select count(*) from api.search_contacts_latest('__issue422_no_match__', '{}'::jsonb, 1, 1, 'tg', '', null, null)$$,
  'anon can execute the retained contacts simple-search facade'
);
select lives_ok(
  $$select count(*) from api.search_flowproperties_latest('__issue422_no_match__', '{}'::jsonb, 1, 1, 'tg', '', null, null)$$,
  'anon can execute the retained flow-properties simple-search facade'
);
select lives_ok(
  $$select count(*) from api.search_sources_latest('__issue422_no_match__', '{}'::jsonb, 1, 1, 'tg', '', null, null)$$,
  'anon can execute the retained sources simple-search facade'
);
select lives_ok(
  $$select count(*) from api.search_unitgroups_latest('__issue422_no_match__', '{}'::jsonb, 1, 1, 'tg', '', null, null)$$,
  'anon can execute the retained unit-groups simple-search facade'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '42200000-0000-4000-8000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claims', '{"role":"authenticated"}', true);

select ok(
  not has_function_privilege(
    'authenticated',
    'api.svc_lca_read_job_projection(uuid,uuid,uuid,boolean)',
    'EXECUTE'
  ),
  'authenticated cannot execute service LCA facade'
);

select lives_ok(
  $$select count(*) from api.search_contacts_latest('__issue422_no_match__', '{}'::jsonb, 1, 1, 'tg', '', null, null)$$,
  'authenticated can execute the retained contacts simple-search facade'
);
select lives_ok(
  $$select count(*) from api.search_flowproperties_latest('__issue422_no_match__', '{}'::jsonb, 1, 1, 'tg', '', null, null)$$,
  'authenticated can execute the retained flow-properties simple-search facade'
);
select lives_ok(
  $$select count(*) from api.search_sources_latest('__issue422_no_match__', '{}'::jsonb, 1, 1, 'tg', '', null, null)$$,
  'authenticated can execute the retained sources simple-search facade'
);
select lives_ok(
  $$select count(*) from api.search_unitgroups_latest('__issue422_no_match__', '{}'::jsonb, 1, 1, 'tg', '', null, null)$$,
  'authenticated can execute the retained unit-groups simple-search facade'
);

reset role;
set local role service_role;
select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claim.role', 'service_role', true);
select set_config('request.jwt.claims', '{"role":"service_role"}', true);

select is(
  api.svc_worker_read_job('42220000-0000-4000-8000-000000000001', false) ->> 'code',
  'WORKER_JOB_NOT_FOUND'::text,
  'service worker facade traverses the private implementation boundary'
);

select is(
  api.svc_lca_read_result_projection(
    '42200000-0000-4000-8000-000000000001',
    '42230000-0000-4000-8000-000000000001',
    null,
    false
  ) #>> '{data}',
  null::text,
  'service LCA projection returns the stable empty result contract'
);

select is(
  api.svc_schema_contract_status() ->> 'migrationHead',
  '20260926050042'::text,
  'service-only schema readback reports the exact migration head'
);

reset role;

select is(
  (
    select count(*)
    from pg_proc as routine
    join pg_namespace as namespace on namespace.oid = routine.pronamespace
    where namespace.nspname = 'api'
      and routine.proname = any(array[
        'qry_membership_get_mine', 'qry_team_list', 'qry_team_get',
        'qry_identity_get_mine', 'qry_identity_get_visible_users',
        'qry_system_find_member_candidate_by_email',
        'qry_review_find_member_candidate_by_email'
      ])
      and pg_get_functiondef(routine.oid) ~ 'public[.](roles|teams|users|reviews|comments)'
  ),
  0::bigint,
  'new read facades contain no stale public qualification for moved state'
);

select matches(
  pg_get_functiondef('api.cmd_lifecycle_model_bundle_save(jsonb)'::regprocedure),
  'auth[.]uid[(][)].*jsonb_set.*actorUserId',
  'bundle save overwrites actorUserId from auth.uid inside the transaction'
);

select matches(
  pg_get_functiondef('api.cmd_lifecycle_model_bundle_delete(uuid,text)'::regprocedure),
  'for[[:space:]]+update',
  'bundle delete locks the target before authorizing and mutating'
);

select * from finish();

rollback;
