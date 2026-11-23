begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, auth;

select no_plan();

-- The v2 wire domain is the JavaScript safe-integer subset of JSON.  Keep
-- these primitive tests independent of the 305-row lifecycle fixture so a
-- serialization or privilege regression fails quickly and diagnostically.
select is(
  private.dataset_flow_identity_safe_json_v2('9007199254740991'::jsonb),
  '9007199254740991'::jsonb,
  'safe JSON accepts Number.MAX_SAFE_INTEGER'
);
select is(
  private.dataset_flow_identity_safe_json_v2('-9007199254740991'::jsonb),
  '-9007199254740991'::jsonb,
  'safe JSON accepts Number.MIN_SAFE_INTEGER'
);
select is(
  private.dataset_flow_identity_safe_json_v2('9007199254740992'::jsonb),
  null::jsonb,
  'safe JSON rejects the first positive unsafe integer'
);
select is(
  private.dataset_flow_identity_safe_json_v2('-9007199254740992'::jsonb),
  null::jsonb,
  'safe JSON rejects the first negative unsafe integer'
);
select is(
  private.dataset_flow_identity_safe_json_v2('1.5'::jsonb),
  null::jsonb,
  'safe JSON rejects a non-integer number'
);
select is(
  private.dataset_flow_identity_safe_json_v2('1e-1'::jsonb),
  null::jsonb,
  'safe JSON rejects a fractional exponent form'
);
select is(
  private.dataset_flow_identity_safe_json_v2('-0'::jsonb),
  '0'::jsonb,
  'safe JSON canonicalizes negative zero to zero'
);
select is(
  private.dataset_flow_identity_safe_json_v2('[null,true,1]'::jsonb),
  '[null,true,1]'::jsonb,
  'safe JSON preserves JSON null instead of confusing it with SQL null'
);
select is(
  private.dataset_flow_identity_safe_json_v2(
    '{"outer":[1,{"bad":1.5}]}'::jsonb
  ),
  null::jsonb,
  'one unsafe descendant rejects the entire JSON value'
);
select is(
  private.dataset_flow_identity_safe_json_v2(
    '{"outer":[1,{"ok":2}]}'::jsonb
  ),
  '{"outer":[1,{"ok":2}]}'::jsonb,
  'set-based safe JSON recursion preserves valid array order and object shape'
);

select throws_ok(
  $$select E'"\\u0000"'::jsonb$$,
  '22P05',
  'unsupported Unicode escape sequence',
  'PostgreSQL rejects U+0000 before it can enter the v2 JSON domain'
);
select throws_ok(
  $$select E'"\\uD800"'::jsonb$$,
  '22P02',
  'invalid input syntax for type json',
  'PostgreSQL rejects an unpaired high surrogate'
);
select is(
  private.dataset_flow_identity_safe_json_v2(
    E'"\\uD83D\\uDE00"'::jsonb
  ),
  '"😀"'::jsonb,
  'safe JSON accepts a paired non-BMP surrogate as one scalar value'
);
select is(
  util.dataset_flow_identity_restricted_sha256_v2(
    '{"a":[1,-0,9007199254740991],"é":"值","😀":"emoji"}'::jsonb
  ),
  '3caeab8cb9c331ffeca1801150a074d10e7e8d3e23dc9314eeb1985b4babcdd6',
  'restricted hash matches a fixed independent JSON.stringify/UTF-8 vector'
);
select is(
  util.dataset_flow_identity_restricted_sha256_v2(
    '{"unsafe":9007199254740992}'::jsonb
  ),
  null::text,
  'restricted hash refuses values outside the safe JSON domain'
);
select is(
  (select provolatile::text
   from pg_proc
   where oid =
     'private.dataset_flow_identity_safe_json_v2(jsonb)'::regprocedure),
  's',
  'safe JSON volatility is STABLE because its recursive key sort is STABLE'
);
select is(
  (select provolatile::text
   from pg_proc
   where oid =
     'util.dataset_flow_identity_validate_support_snapshot(uuid,jsonb)'::regprocedure),
  's',
  'support snapshot validation is STABLE so read-only guards stay STABLE'
);

create temporary table mapping_index_contract on commit drop as
select mappings,
  private.dataset_flow_identity_mapping_index_v2(mappings) as index
from (values (jsonb_build_array(
  jsonb_build_object(
    'ordinal', 1, 'mapping_id', repeat('a', 64),
    'source', jsonb_build_object(
      'id', '10000000-0000-4000-8000-000000000001',
      'version', '01.00.000'
    ),
    'marker', 'first'
  ),
  jsonb_build_object(
    'ordinal', 2, 'mapping_id', repeat('b', 64),
    'source', jsonb_build_object(
      'id', '10000000-0000-4000-8000-000000000002',
      'version', '01.00.000'
    ),
    'marker', 'second'
  )
))) as fixture(mappings);
select is(
  (select jsonb_agg(key order by key)
   from mapping_index_contract
   cross join lateral jsonb_object_keys(index) as key),
  to_jsonb(array[
    'by_id', 'by_ordinal', 'by_source', 'mapping_count',
    'mapping_guard_set_sha256', 'mappings', 'schema_version'
  ]::text[]),
  'mapping index has the exact ordered-array and three lookup domains'
);
select is(
  (select jsonb_build_object(
    'count', index->'mapping_count',
    'hash_matches', index->>'mapping_guard_set_sha256'
      = util.dataset_flow_identity_restricted_sha256_v2(mappings),
    'ordinal', index #>> '{by_ordinal,2,marker}',
    'id', index #>> array['by_id', repeat('a', 64), 'marker'],
    'source', index #>> array[
      'by_source',
      '10000000-0000-4000-8000-000000000002@01.00.000',
      'marker'
    ]
  ) from mapping_index_contract),
  jsonb_build_object(
    'count', 2, 'hash_matches', true,
    'ordinal', 'second', 'id', 'first', 'source', 'second'
  ),
  'mapping index lookups and retained-array hash are exactly consistent'
);
select throws_ok(
  $$select private.dataset_flow_identity_mapping_index_v2(jsonb_build_array(
    jsonb_build_object(
      'ordinal', 1, 'mapping_id', repeat('a', 64),
      'source', jsonb_build_object(
        'id', '10000000-0000-4000-8000-000000000001',
        'version', '01.00.000'
      )
    ),
    jsonb_build_object(
      'ordinal', 2, 'mapping_id', repeat('b', 64),
      'source', jsonb_build_object(
        'id', '10000000-0000-4000-8000-000000000001',
        'version', '01.00.000'
      )
    )
  ))$$,
  '22023',
  'FLOW_IDENTITY_MAPPING_INDEX_IDENTITY_INVALID',
  'mapping index fails closed on a duplicate source identity'
);
select ok(
  pg_get_functiondef(
    'private.dataset_flow_identity_build_process_v2(uuid,jsonb,jsonb,jsonb,jsonb,text)'::regprocedure
  ) not like '%jsonb_array_elements(p_mappings)%'
  and pg_get_functiondef(
    'util.dataset_flow_identity_dry_validate_process(uuid,jsonb,jsonb,jsonb,jsonb)'::regprocedure
  ) like '%v_mapping_by_source ?%',
  'indexed v2 process construction has no per-rewrite mapping-array scan'
);
select is(
  (select provolatile::text
   from pg_proc
   where oid =
     'private.dataset_flow_identity_mapping_index_v2(jsonb)'::regprocedure),
  's',
  'mapping index volatility is STABLE because its restricted hash is STABLE'
);

-- common:STMultiLang/common:shortDescription accepts only the three exact
-- wire shapes supported by the CLI contract.
select ok(
  private.dataset_flow_identity_short_description_v2('"plain"'::jsonb),
  'STMultiLang accepts a plain JSON string'
);
select ok(
  private.dataset_flow_identity_short_description_v2(
    '{"@xml:lang":"en","#text":"Mass"}'::jsonb
  ),
  'STMultiLang accepts one exact language/text object'
);
select ok(
  private.dataset_flow_identity_short_description_v2(
    (
      '[{"@xml:lang":"en","#text":"Mass"},'
        || '{"@xml:lang":"zh","#text":"质量"}]'
    )::jsonb
  ),
  'STMultiLang accepts a non-empty array of exact language/text objects'
);
select ok(
  not private.dataset_flow_identity_short_description_v2(
    '{"@xml:lang":"en","#text":"Mass","extra":true}'::jsonb
  ),
  'STMultiLang rejects an object with an extra key'
);
select ok(
  not private.dataset_flow_identity_short_description_v2(
    '{"@xml:lang":"en"}'::jsonb
  ),
  'STMultiLang rejects an object missing #text'
);
select ok(
  not private.dataset_flow_identity_short_description_v2('[]'::jsonb),
  'STMultiLang rejects an empty array'
);
select ok(
  not private.dataset_flow_identity_short_description_v2(
    '["en","Mass"]'::jsonb
  ),
  'STMultiLang rejects an array of scalar strings'
);
select ok(
  not private.dataset_flow_identity_short_description_v2(
    '{"@xml:lang":1,"#text":"Mass"}'::jsonb
  ),
  'STMultiLang requires string-valued language and text fields'
);
select ok(
  not private.dataset_flow_identity_short_description_v2('null'::jsonb),
  'STMultiLang rejects JSON null'
);

-- The only public v2 entrypoints are authenticated security-definer RPCs
-- with an empty search_path.  Cancel is a zero-primary-write abandon path;
-- its legacy v1 implementation remains private and non-executable.
select hasnt_function(
  'public', 'cmd_dataset_flow_identity_process_rewrite_guarded',
  array['uuid', 'jsonb'],
  'the former two-argument process rewrite surface is no longer public'
);
select hasnt_function(
  'public', 'cmd_dataset_flow_identity_scope_finalize_guarded',
  array['uuid', 'jsonb'],
  'the former two-argument finalize surface is no longer public'
);
select function_privs_are(
  'api', 'cmd_dataset_flow_identity_capture_attest_guarded',
  array['jsonb'], 'authenticated', array['EXECUTE'],
  'capture attestation is executable only through the authenticated role'
);
select function_privs_are(
  'api', 'cmd_dataset_flow_identity_scope_preflight_guarded',
  array['jsonb'], 'authenticated', array['EXECUTE'],
  'v2 preflight is executable through the authenticated role'
);
select function_privs_are(
  'api', 'cmd_dataset_flow_identity_process_rewrite_guarded',
  array['uuid', 'jsonb', 'jsonb'], 'authenticated', array['EXECUTE'],
  'v2 process rewrite is executable through the authenticated role'
);
select function_privs_are(
  'api', 'cmd_dataset_flow_identity_scope_read',
  array['uuid'], 'authenticated', array['EXECUTE'],
  'v2 scope read is executable through the authenticated role'
);
select function_privs_are(
  'api', 'cmd_dataset_flow_identity_scope_finalize_guarded',
  array['uuid', 'jsonb', 'jsonb'], 'authenticated', array['EXECUTE'],
  'v2 finalize is executable through the authenticated role'
);
select function_privs_are(
  'api', 'cmd_dataset_flow_identity_scope_recover_guarded',
  array['uuid', 'jsonb'], 'authenticated', array['EXECUTE'],
  'fresh scope recovery is executable through the authenticated role'
);
select function_privs_are(
  'api', 'cmd_dataset_flow_identity_scope_lookup',
  array['jsonb'], 'authenticated', array['EXECUTE'],
  'lost-response scope lookup is executable through the authenticated role'
);
select function_privs_are(
  'api', 'cmd_dataset_flow_identity_scope_cancel_guarded',
  array['uuid', 'jsonb'], 'authenticated', array['EXECUTE'],
  'v2 zero-write cancel is executable through the authenticated role'
);
select is(
  (
    select count(*)::integer
    from unnest(array[
      'api.cmd_dataset_flow_identity_capture_attest_guarded(jsonb)'::regprocedure,
      'api.cmd_dataset_flow_identity_scope_preflight_guarded(jsonb)'::regprocedure,
      'api.cmd_dataset_flow_identity_process_rewrite_guarded(uuid,jsonb,jsonb)'::regprocedure,
      'api.cmd_dataset_flow_identity_scope_read(uuid)'::regprocedure,
      'api.cmd_dataset_flow_identity_scope_finalize_guarded(uuid,jsonb,jsonb)'::regprocedure,
      'api.cmd_dataset_flow_identity_scope_recover_guarded(uuid,jsonb)'::regprocedure,
      'api.cmd_dataset_flow_identity_scope_lookup(jsonb)'::regprocedure,
      'api.cmd_dataset_flow_identity_scope_cancel_guarded(uuid,jsonb)'::regprocedure
    ]) as function_oid(oid)
    where has_function_privilege('anon', function_oid.oid, 'EXECUTE')
       or has_function_privilege('service_role', function_oid.oid, 'EXECUTE')
  ),
  0,
  'anon and service_role have no direct v2 execution grant'
);
select ok(
  (
    select bool_and(
      function.prosecdef
      and function.proconfig @> array['search_path=""']::text[]
    )
    from pg_proc as function
    where function.oid = any(array[
      'api.cmd_dataset_flow_identity_capture_attest_guarded(jsonb)'::regprocedure,
      'api.cmd_dataset_flow_identity_scope_preflight_guarded(jsonb)'::regprocedure,
      'api.cmd_dataset_flow_identity_process_rewrite_guarded(uuid,jsonb,jsonb)'::regprocedure,
      'api.cmd_dataset_flow_identity_scope_read(uuid)'::regprocedure,
      'api.cmd_dataset_flow_identity_scope_finalize_guarded(uuid,jsonb,jsonb)'::regprocedure,
      'api.cmd_dataset_flow_identity_scope_recover_guarded(uuid,jsonb)'::regprocedure,
      'api.cmd_dataset_flow_identity_scope_lookup(jsonb)'::regprocedure,
      'api.cmd_dataset_flow_identity_scope_cancel_guarded(uuid,jsonb)'::regprocedure
    ]::oid[])
  ),
  'every public v2 RPC is security definer with an empty search_path'
);

-- Moving the v1 implementations out of public must not leave a second
-- callable name behind.  The public names above are the v2 wrappers; these
-- core names exist only in private.
select hasnt_function(
  'public', 'dataset_flow_identity_scope_preflight_core_v1', array['jsonb'],
  'the v1 preflight core has no public-schema alias'
);
select hasnt_function(
  'public', 'dataset_flow_identity_process_rewrite_core_v1',
  array['uuid', 'jsonb'],
  'the v1 process core has no public-schema alias'
);
select hasnt_function(
  'public', 'dataset_flow_identity_scope_read_core_v1', array['uuid'],
  'the v1 scope-read core has no public-schema alias'
);
select hasnt_function(
  'public', 'dataset_flow_identity_scope_finalize_core_v1',
  array['uuid', 'jsonb'],
  'the v1 finalize core has no public-schema alias'
);
select hasnt_function(
  'public', 'dataset_flow_identity_scope_cancel_core_v1',
  array['uuid', 'jsonb'],
  'the v1 cancel core has no public-schema alias'
);

-- Every v1 materializer and every bearer-permit primitive is a postgres-only
-- implementation capability.  Use exact empty privilege sets for each API
-- role so a future grant on any one function cannot hide inside a combined
-- boolean assertion.
select function_privs_are(
  'private', function_contract.name, function_contract.arguments,
  api_role.name, array[]::text[],
  format(
    '%s has no EXECUTE privilege on private.%s(%s)',
    api_role.name, function_contract.name,
    array_to_string(function_contract.arguments, ',')
  )
)
from (values
  ('dataset_flow_identity_scope_preflight_core_v1', array['jsonb']::text[]),
  ('dataset_flow_identity_process_rewrite_core_v1',
    array['uuid', 'jsonb']::text[]),
  ('dataset_flow_identity_scope_read_core_v1', array['uuid']::text[]),
  ('dataset_flow_identity_scope_finalize_core_v1',
    array['uuid', 'jsonb']::text[]),
  ('dataset_flow_identity_scope_cancel_core_v1',
    array['uuid', 'jsonb']::text[]),
  ('dataset_flow_identity_permit_token_sha256_v1', array['text']::text[]),
  ('dataset_flow_identity_validate_wrapper_permit_v1',
    array['uuid', 'uuid', 'jsonb', 'text']::text[]),
  ('dataset_flow_identity_rotate_wrapper_permit_v1',
    array['uuid', 'text', 'boolean']::text[]),
  ('dataset_flow_identity_invalidate_wrapper_permit_v1',
    array['uuid']::text[])
) as function_contract(name, arguments)
cross join (values ('anon'), ('authenticated'), ('service_role'))
  as api_role(name);

-- Retain the narrower v2 primitive ACL coverage alongside the exhaustive v1
-- core/permit matrix above.
select function_privs_are(
  'private', function_contract.name, function_contract.arguments,
  api_role.name, array[]::text[],
  format(
    '%s has no EXECUTE privilege on private.%s(%s)',
    api_role.name, function_contract.name,
    array_to_string(function_contract.arguments, ',')
  )
)
from (values
  ('dataset_flow_identity_safe_json_v2', array['jsonb']::text[]),
  ('dataset_flow_identity_short_description_v2', array['jsonb']::text[])
) as function_contract(name, arguments)
cross join (values ('anon'), ('authenticated'), ('service_role'))
  as api_role(name);
select ok(
  (select provolatile = 's'
   from pg_proc
   where oid =
     'api.cmd_dataset_flow_identity_scope_lookup(jsonb)'::regprocedure)
  and pg_get_functiondef(
    'api.cmd_dataset_flow_identity_scope_lookup(jsonb)'::regprocedure
  ) not ilike '%insert into%'
  and pg_get_functiondef(
    'api.cmd_dataset_flow_identity_scope_lookup(jsonb)'::regprocedure
  ) not ilike '%update %'
  and pg_get_functiondef(
    'api.cmd_dataset_flow_identity_scope_lookup(jsonb)'::regprocedure
  ) ilike '%''execution_permit'', null%',
  'scope lookup is STABLE, write-free, and always returns a null permit'
);
select ok(
  pg_get_functiondef(
    'api.cmd_dataset_flow_identity_scope_cancel_guarded(uuid,jsonb)'::regprocedure
  ) like '%v_scope.status <> ''sealed''%'
  and pg_get_functiondef(
    'api.cmd_dataset_flow_identity_scope_cancel_guarded(uuid,jsonb)'::regprocedure
  ) like '%v_completed_count <> 0%'
  and pg_get_functiondef(
    'api.cmd_dataset_flow_identity_scope_cancel_guarded(uuid,jsonb)'::regprocedure
  ) like '%v_scope.status = ''cancelled''%'
  and pg_get_functiondef(
    'api.cmd_dataset_flow_identity_scope_cancel_guarded(uuid,jsonb)'::regprocedure
  ) like '%v_audit_count <> 1%',
  'v2 cancel is sealed-zero-write-only and exact replay verifies one audit'
);

-- Receipt rows and their relation-shaped children are immutable, and the
-- active-row fence authorizes primary writes only by consuming a private
-- transaction-bound nonce row.  Caller-forged custom GUCs are not consulted.
select is(
  (
    select count(*)::integer
    from pg_trigger as trigger
    where not trigger.tgisinternal
      and trigger.tgname = any(array[
        'dataset_flow_identity_capture_receipts_immutable',
        'dataset_flow_identity_capture_sources_immutable',
        'dataset_flow_identity_capture_targets_immutable',
        'dataset_flow_identity_capture_support_immutable',
        'dataset_flow_identity_capture_mappings_immutable',
        'dataset_flow_identity_capture_processes_immutable'
      ])
      and trigger.tgenabled = 'O'
      and trigger.tgfoid =
        'private.dataset_flow_identity_receipt_immutable_v2()'::regprocedure
  ),
  6,
  'all six capture receipt relations have enabled immutable triggers'
);
select ok(
  pg_get_functiondef(
    'private.dataset_flow_identity_receipt_immutable_v2()'::regprocedure
  ) like '%FLOW_IDENTITY_CAPTURE_RECEIPT_IMMUTABLE%',
  'receipt immutability trigger always raises the dedicated fail-closed code'
);
select is(
  (
    select count(*)::integer
    from pg_trigger as trigger
    where not trigger.tgisinternal
      and trigger.tgname = any(array[
        'dataset_flow_identity_process_active_fence',
        'flows_z_identity_active_fence',
        'dataset_flow_identity_flowproperty_active_fence',
        'dataset_flow_identity_unitgroup_active_fence'
      ])
      and trigger.tgenabled = 'O'
      and trigger.tgfoid =
        'private.dataset_flow_identity_active_fence()'::regprocedure
  ),
  4,
  'all four primary/support tables have the enabled canonical active fence'
);
select ok(
  pg_get_functiondef(
    'private.dataset_flow_identity_active_fence()'::regprocedure
  ) like '%pg_try_advisory_xact_lock%'
  and pg_get_functiondef(
    'private.dataset_flow_identity_active_fence()'::regprocedure
  ) like '%FLOW_IDENTITY_ACTIVE_SCOPE_ACTOR_FENCE_BUSY%'
  and pg_get_functiondef(
    'private.dataset_flow_identity_active_fence()'::regprocedure
  ) not like '%perform pg_advisory_xact_lock(%',
  'row triggers use non-blocking actor locks and fail closed instead of waiting'
);
select ok(
  pg_get_functiondef(
    'private.dataset_flow_identity_active_fence()'::regprocedure
  ) like '%delete from util.dataset_flow_identity_mutation_permits%'
  and pg_get_functiondef(
    'private.dataset_flow_identity_active_fence()'::regprocedure
  ) not like '%current_setting%'
  and pg_get_functiondef(
    'private.dataset_flow_identity_active_fence()'::regprocedure
  ) not like '%app.dataset_flow_identity_v2_process_request_sha256%',
  'active fence consumes a private permit and has no forged-GUC bypass path'
);
select is(
  set_config(
    'app.dataset_flow_identity_v2_process_request_sha256', repeat('f', 64), true
  ),
  repeat('f', 64),
  'a caller can forge the custom GUC value, so it cannot be an authority'
);
select is(
  (
    select count(*)::integer
    from util.dataset_flow_identity_mutation_permits as permit
    where permit.transaction_id = txid_current()
  ),
  0,
  'forging the legacy GUC does not mint a transaction-bound mutation permit'
);

-- Pin the full relation inventory as well as its ACLs.  The catalog assertion
-- fails if a later migration adds another dataset_flow_identity table, forcing
-- the expected list and privilege matrix to be extended together.
select is(
  (
    select array_agg(class.relname::text order by class.relname)
    from pg_class as class
    join pg_namespace as namespace on namespace.oid = class.relnamespace
    where namespace.nspname = 'util'
      and class.relkind in ('r', 'p')
      and class.relname like 'dataset_flow_identity_%'
  ),
  array[
    'dataset_flow_identity_capture_mapping_guards',
    'dataset_flow_identity_capture_process_intents',
    'dataset_flow_identity_capture_receipts',
    'dataset_flow_identity_capture_source_guards',
    'dataset_flow_identity_capture_support_guards',
    'dataset_flow_identity_capture_target_guards',
    'dataset_flow_identity_mappings',
    'dataset_flow_identity_mutation_permits',
    'dataset_flow_identity_process_ledger',
    'dataset_flow_identity_scopes',
    'dataset_flow_identity_wrapper_invocations'
  ]::text[],
  'the v2 migration owns the exact eleven private util relations'
);
select table_privs_are(
  'util', relation.name, api_role.name, array[]::text[],
  format(
    '%s has no table privilege on util.%s', api_role.name, relation.name
  )
)
from (values
  ('dataset_flow_identity_capture_mapping_guards'),
  ('dataset_flow_identity_capture_process_intents'),
  ('dataset_flow_identity_capture_receipts'),
  ('dataset_flow_identity_capture_source_guards'),
  ('dataset_flow_identity_capture_support_guards'),
  ('dataset_flow_identity_capture_target_guards'),
  ('dataset_flow_identity_mappings'),
  ('dataset_flow_identity_mutation_permits'),
  ('dataset_flow_identity_process_ledger'),
  ('dataset_flow_identity_scopes'),
  ('dataset_flow_identity_wrapper_invocations')
) as relation(name)
cross join (values ('anon'), ('authenticated'), ('service_role'))
  as api_role(name);

-- This fixture-free contract suite can prove anonymous rejection at the ACL
-- boundary.  Foreign-actor semantics require a sealed owner scope and are
-- exercised by 20260716_guarded_dataset_flow_identity_mapping.sql; real
-- PostgREST/JWT behavior remains hosted Preview E2E evidence.  Snapshot every
-- private relation plus command audits here so each rejected anonymous call
-- is also proved state-neutral.
create function pg_temp.dataset_flow_identity_acl_state()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_relation text;
  v_rows jsonb;
  v_state jsonb := '{}'::jsonb;
begin
  for v_relation in
    select unnest(array[
      'dataset_flow_identity_capture_mapping_guards',
      'dataset_flow_identity_capture_process_intents',
      'dataset_flow_identity_capture_receipts',
      'dataset_flow_identity_capture_source_guards',
      'dataset_flow_identity_capture_support_guards',
      'dataset_flow_identity_capture_target_guards',
      'dataset_flow_identity_mappings',
      'dataset_flow_identity_mutation_permits',
      'dataset_flow_identity_process_ledger',
      'dataset_flow_identity_scopes',
      'dataset_flow_identity_wrapper_invocations'
    ]::text[])
  loop
    execute format(
      'select coalesce('
        || 'jsonb_agg(to_jsonb(snapshot) order by to_jsonb(snapshot)::text),'
        || '''[]''::jsonb) from util.%I as snapshot',
      v_relation
    ) into v_rows;
    v_state := v_state || jsonb_build_object(v_relation, v_rows);
  end loop;
  select coalesce(
    jsonb_agg(to_jsonb(audit) order by audit.id), '[]'::jsonb
  ) into v_rows
  from private.command_audit_log as audit
  where audit.command like 'cmd_dataset_flow_identity_%';
  return v_state || jsonb_build_object('command_audit_log', v_rows);
end;
$$;

create temporary table flow_identity_anon_acl_before on commit drop as
select pg_temp.dataset_flow_identity_acl_state() as state;

set local role anon;
-- Supabase Postgres image 17.6.1.106 crashes in supautils while formatting
-- permission hints for reserved roles (supabase/postgres#2112).  Prove the
-- anonymous boundary from the privilege catalog instead of invoking a revoked
-- function; authenticated transport behavior is covered by Hosted Preview E2E.
select ok(
  not has_function_privilege(
    current_user,
    'api.cmd_dataset_flow_identity_capture_attest_guarded(jsonb)'::regprocedure,
    'EXECUTE'
  ),
  'anon cannot execute capture attestation'
);
select ok(
  not has_function_privilege(
    current_user,
    'api.cmd_dataset_flow_identity_scope_preflight_guarded(jsonb)'::regprocedure,
    'EXECUTE'
  ),
  'anon cannot execute scope preflight'
);
select ok(
  not has_function_privilege(
    current_user,
    'api.cmd_dataset_flow_identity_process_rewrite_guarded(uuid,jsonb,jsonb)'::regprocedure,
    'EXECUTE'
  ),
  'anon cannot execute a process rewrite'
);
select ok(
  not has_function_privilege(
    current_user,
    'api.cmd_dataset_flow_identity_scope_read(uuid)'::regprocedure,
    'EXECUTE'
  ),
  'anon cannot read a scope'
);
select ok(
  not has_function_privilege(
    current_user,
    'api.cmd_dataset_flow_identity_scope_finalize_guarded(uuid,jsonb,jsonb)'::regprocedure,
    'EXECUTE'
  ),
  'anon cannot finalize a scope'
);
select ok(
  not has_function_privilege(
    current_user,
    'api.cmd_dataset_flow_identity_scope_recover_guarded(uuid,jsonb)'::regprocedure,
    'EXECUTE'
  ),
  'anon cannot recover a scope'
);
select ok(
  not has_function_privilege(
    current_user,
    'api.cmd_dataset_flow_identity_scope_lookup(jsonb)'::regprocedure,
    'EXECUTE'
  ),
  'anon cannot look up a scope'
);
select ok(
  not has_function_privilege(
    current_user,
    'api.cmd_dataset_flow_identity_scope_cancel_guarded(uuid,jsonb)'::regprocedure,
    'EXECUTE'
  ),
  'anon cannot cancel a scope'
);
reset role;

select is(
  pg_temp.dataset_flow_identity_acl_state(),
  (select state from flow_identity_anon_acl_before),
  'all eight anonymous privilege checks leave private and audit state byte-identical'
);

select * from finish();
rollback;
