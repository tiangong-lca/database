begin;

create extension if not exists pgtap with schema extensions;

select plan(26);

select is(
  (
    select array_agg(class.relname::text order by class.relname)
    from pg_class class
    join pg_namespace namespace on namespace.oid = class.relnamespace
    where namespace.nspname = 'public'
      and class.relkind in ('r', 'p')
  ),
  array[
    'contacts', 'flowproperties', 'flows', 'ilcd', 'lciamethods',
    'lifecyclemodels', 'processes', 'sources', 'unitgroups'
  ]::text[],
  'public contains exactly the nine core entity tables'
);

select is(
  (
    select count(*)
    from pg_class class
    join pg_namespace namespace on namespace.oid = class.relnamespace
    where namespace.nspname = 'public'
      and class.relkind in ('v', 'm')
  ),
  0::bigint,
  'public contains no views'
);

select is(
  (
    select count(*)
    from pg_proc routine
    join pg_namespace namespace on namespace.oid = routine.pronamespace
    where namespace.nspname = 'public'
  ),
  0::bigint,
  'public contains no routines'
);

select is(
  (
    select count(*)
    from pg_class class
    join pg_namespace namespace on namespace.oid = class.relnamespace
    where namespace.nspname = 'public'
      and class.relkind = 'S'
  ),
  0::bigint,
  'public contains no standalone sequences'
);

select ok(
  to_regtype('public.filtered_row') is null
    and to_regtype('api.filtered_row') is not null,
  'standalone API composite type moved from public to api'
);

select is(
  (
    select count(*)
    from pg_proc routine
    join pg_namespace namespace on namespace.oid = routine.pronamespace
    where namespace.nspname = 'api'
      and routine.prokind = 'f'
  ),
  -- Database #807 adds 14 brand-scoped Portal public facades; legacy inventory remains included.
  -- Database #838 adds five additive filtered catalog/UUID/display/model-Hybrid facades.
  -- Database #846 adds one service-only export facade.
  -- Database #860 adds the versioned organization dashboard facade; v5 stays available.
  -- Database #877 adds four service-only HDF5 query artifact stage/seal/bind/resolve facades.
  -- Database #894 adds two actor, one validation-intent and five fenced producer façades.
  -- Database #895 adds five service seams while preserving two actor façade identities.
  -- Database #904 adds two actor reporting facades and six service analysis/reporting seams.
  -- Database #906 adds two actor V4 and three service review/intent façades.
  -- Database #909 adds four V5 actor façades and thirteen fenced service/configuration seams.
  -- Database #912 adds four V6 actor facades and fifteen fenced method/evidence/report service seams.
  -- Database #961 adds manager-only version/history inspection and explicit draft replacement.
  -- Database #964 adds the stable download facade during the Edge cutover.
  438::bigint,
  'Two demand-specific Portal readers, one additive organization dashboard v6 facade plus four Portal navigation/V3 facades: api contains the active cutover and consumer facades, including the two Open Data catalog readers and three dataset display RPCs, the reviewer Contact status and activation RPCs, eight additive Portal/Next version-search APIs, two V4, two V5 and two V6 review queues plus batch eligibility, the rejection-detail RPC, the actor-bound rejected-review report download descriptor RPC and the reviewer workload drill-down RPC, two partial-import APIs, the three manager-attested Result publication RPCs, the guarded owner-draft before-content save facade, and the five versioned v2 Time-alias protected endpoints (preflight/gate/admit/read plus the service-only execute callback)'
);

select is(
  (
    select count(*)
    from pg_proc routine
    join pg_namespace namespace on namespace.oid = routine.pronamespace
    where namespace.nspname = 'private'
      and routine.prokind = 'f'
  ),
  -- Database #793 retires four V1 rank routines; #799 replaces one publication helper with three display helpers.
  -- Database #807 adds 186 isolated display, licensing, projection, manifest and rollout helpers; legacy inventory remains included.
  -- Database #828 adds the owner-only bounded AI deadline expiry helper.
  -- Database #838 adds six pure matcher/validation and private display reader helpers.
  -- Two Model-only invoker kernels preserve the existing raw RLS boundary.
  -- Database #873 adds two opaque calculation-identity helpers.
  -- Database #877 adds one HDF5 query evidence immutability helper.
  -- Database #894 adds nineteen closed Study persistence/authorization/structural helpers.
  -- Database #895 adds eighteen closed task/source/disclosure helpers and two moved core delegates.
  -- Database #900 adds four closed review metadata validation/cleanup helpers.
  -- Database #904 adds thirty-two closed analysis/reporting helpers including the moved v3 analysis delegate.
  -- Database #906 adds seventeen closed review, current-state, receipt and summary helpers.
  -- Database #909 adds twenty-five closed advanced numerical/configuration/family/review helpers.
  -- Database #912 adds thirty-five closed method/evidence/report/binding helpers.
  -- Database #925 adds one closed, exact-scope lexical key bridge.
  -- Database #949 adds one closed, exact-scope native filter-key bridge.
  -- Database #958 adds one owner-only calculation envelope helper.
  -- Database #961 adds two guarded history triggers, version state/error and atomic draft helper.
  -- Database #964 retires the per-support-row archive ACL helper.
  783::bigint,
  'Three demand-specific navigation overloads and twenty-five navigation helpers plus: private contains the active helpers, including the Open Data filter and three dataset display helpers, the reviewer Contact reference-readiness helper, the review rejection-reason extractor, rejected-report exact-reference matcher, submitted-decision sync helper and shared reviewer workload classifier, the twenty-five exact-version, thirteen composite-name and one review-search internals, two partial-import helpers, two whole-package helpers, the example write guard, the two state-120 candidate-cache helpers, the state-120 lifecycle guard, the seven manager-attested Result publication helpers, the nineteen versioned v2 Time-alias helpers (four exact-numeric, ten leaf/derivation helpers, the guarded v2 batch executor, the plan key set, the six-key derivative-target checker, the guarded v2 plan executor and the deterministic derivative-chunk partition), and the eight closed Length*time profile helpers (the closed discriminator, the plan key set, the factor constant, the exact multiply, the instance rewrite, the guarded Length*time executor, the null-safe required-scalar check and the null-safe required-count check), the two Database #689 batch queue-cache helpers (the dispatch-body candidate-id extractor and the per-batch queue cache builder), the Database #703 internal derivative scheduler picker, and the Database #828 owner-only AI deadline expiry helper'
);

select ok(
  to_regclass('private.users') is not null
    and to_regclass('private.reviews') is not null
    and to_regclass('private.worker_jobs') is not null
    and to_regclass('private.lcia_scope_closure_checks') is not null,
  'representative non-core state tables moved to private'
);

select ok(
  to_regclass('api.worker_job_domain_refs') is not null
    and to_regclass('private.worker_domain_traceability_cutoffs') is not null
    and to_regclass('util.worker_domain_traceability_violations') is not null
    and to_regclass('util.worker_legacy_lifecycle_audit') is not null
    and to_regclass('util.worker_legacy_table_retirement_blockers') is not null,
  'all five public views moved to their reviewed schemas'
);

select ok(
  to_regclass('private.lcia_scope_closure_publication_epoch_seq') is not null,
  'standalone publication epoch sequence moved to private'
);

-- Trigger inventory is asserted against the schemas this repository owns, not against a
-- database-global total. A global `not tgisinternal` count also includes triggers created by
-- whichever platform services are enabled for the environment (Realtime, Storage, Cron,
-- pgsodium); those exist in the deployed service set rather than in this repository's migration
-- ledger, so a global pin is not a repository-owned quantity. Two authors in this repository do
-- write outside the four application schemas and are asserted explicitly below. This assertion
-- is one aggregate count across the four schemas, not a per-schema partition.
select is(
  (
    select count(*)
    from pg_trigger trigger_record
    join pg_class class on class.oid = trigger_record.tgrelid
    join pg_namespace namespace on namespace.oid = class.relnamespace
    where not trigger_record.tgisinternal
      and namespace.nspname in ('api', 'private', 'public', 'util')
  ),
  -- Database #807 adds 15 display synchronization triggers; legacy inventory remains included.
  -- Database #877 adds three HDF5 artifact/source/release-binding immutability triggers.
  -- Database #894 adds seven Study immutable binding/evidence guards.
  -- Database #900 adds the private comment metadata admission trigger.
  -- Database #904 adds two Analysis and four report/export immutability triggers.
  -- Database #906 adds append-only comment/review/finalization/V4-export guards.
  -- Database #909 adds immutable advanced-analysis and advanced report-link guards.
  -- Database #912 adds immutable evidence, method assessment and method-report link guards.
  -- Database #961 adds replacement admission and deferred same-version target guards.
  195::bigint,
  'Two private navigation writers and one seed guard plus: all active application triggers and two Process composite-name sync triggers plus seven example write guards remain present, including the review submitted-decision sync trigger, the Result lifecycle guard and the append-only Result guard and seven dataset display source-cleanup triggers'
);

-- Two authored triggers live outside those four schemas: the guarded dataset derivative rebuild
-- fence on the pgmq embedding queue, and the deferrable Auth profile mirror on `auth.users`.
-- Both are pinned by exact identity and by their load-bearing semantics. Only the schemas owned
-- by platform services (`realtime`, `storage`, `cron`, `pgsodium`) are excluded here: their
-- triggers are created by whichever platform service is enabled for the environment, for example
-- `realtime.subscription.tr_check_filters` exists only where the Realtime service runs, so they
-- are outside this repository's application-owned inventory. Every other schema is included, so a
-- new authored trigger in `pgmq`, `auth`, `net` or `supabase_functions` still fails this test. The
-- discriminator is deliberately the schema and not extension ownership: none of those platform
-- triggers is a `pg_depend` extension member.
select is(
  (
    select count(*)::text || '|' || coalesce(string_agg(
             namespace.nspname || '.' || class.relname || '.' || trigger_record.tgname
               || ':constraint=' || (trigger_record.tgconstraint <> 0)::text
               || ':deferrable=' || trigger_record.tgdeferrable::text
               || ':initdeferred=' || trigger_record.tginitdeferred::text,
             ',' order by namespace.nspname, class.relname, trigger_record.tgname
           ), '')
    from pg_trigger trigger_record
    join pg_class class on class.oid = trigger_record.tgrelid
    join pg_namespace namespace on namespace.oid = class.relnamespace
    where not trigger_record.tgisinternal
      and namespace.nspname not in ('api', 'private', 'public', 'util')
      and namespace.nspname not in ('realtime', 'storage', 'cron', 'pgsodium')
  ),
  '2|auth.users.trg_sync_auth_users_to_private_users:constraint=true:deferrable=true:initdeferred=true,'
  || 'pgmq.q_embedding_jobs.dataset_derivative_rebuild_embedding_visibility_fence:constraint=false:deferrable=false:initdeferred=false',
  'the only authored triggers outside the four application schemas are the pgmq embedding-visibility fence and the deferrable Auth profile mirror on auth.users, and the Auth mirror is still a deferred constraint trigger'
);

-- The exact application-owned identity for the two Result guards this change adds. The full
-- tgtype is pinned to 27 = ROW(1) | BEFORE(2) | DELETE(8) | UPDATE(16). Testing membership bits
-- alone would accept a trigger with different timing or a different event set, so timing and
-- events are asserted as one exact value with no statement/truncate/insert bits permitted, and
-- the firing function is bound to its exact schema-qualified identity with no argument vector.
select is(
  (
    select trigger_record.tgtype::integer
    from pg_trigger trigger_record
    join pg_class class on class.oid = trigger_record.tgrelid
    join pg_namespace namespace on namespace.oid = class.relnamespace
    where namespace.nspname = 'public'
      and class.relname = 'processes'
      and trigger_record.tgname = 'zzz_guard_process_result_lifecycle'
      and not trigger_record.tgisinternal
      and trigger_record.tgenabled = 'O'
      and trigger_record.tgdeferrable = false
      and trigger_record.tginitdeferred = false
      and trigger_record.tgattr::text = ''
      and trigger_record.tgfoid =
        'private.zzz_guard_process_result_lifecycle()'::regprocedure
  ),
  27,
  'the Result lifecycle guard on public.processes is an enabled, non-deferred, row-level before-update-or-delete trigger calling private.zzz_guard_process_result_lifecycle()'
);

select is(
  (
    select trigger_record.tgtype::integer
    from pg_trigger trigger_record
    join pg_class class on class.oid = trigger_record.tgrelid
    join pg_namespace namespace on namespace.oid = class.relnamespace
    where namespace.nspname = 'private'
      and class.relname = 'result_process_publications'
      and trigger_record.tgname = 'result_process_publications_immutable'
      and not trigger_record.tgisinternal
      and trigger_record.tgenabled = 'O'
      and trigger_record.tgdeferrable = false
      and trigger_record.tginitdeferred = false
      and trigger_record.tgattr::text = ''
      and trigger_record.tgfoid =
        'private.result_process_publications_immutable_v1()'::regprocedure
  ),
  27,
  'the Result attestation append-only guard on private.result_process_publications is an enabled, non-deferred, row-level before-update-or-delete trigger calling private.result_process_publications_immutable_v1()'
);

select is(
  (
    select count(*)
    from pg_policy
  ),
  -- Database #807 adds 12 display executor SELECT policies; legacy inventory remains included.
  -- Database #879 adds one closed internal Candidate-member SELECT policy for ZIP authorization.
  -- Database #895 adds one restrictive raw Study artifact Storage policy.
  122::bigint,
  'All RLS guards remain present after six authenticated example companions merge into their same-role SELECT policies; Contacts, OAuth, navigation and restrictive Result guards remain separate; the five unused custom ZIP Storage guards are retired'
);

select is(
  (
    select count(*)
    from pg_constraint constraint_record
    where constraint_record.connamespace in (
      'public'::regnamespace,
      'api'::regnamespace,
      'private'::regnamespace,
      'util'::regnamespace
    )
  ),
  -- Database #807 adds 56 display brand, projection and rollout constraints; legacy inventory remains included.
  -- Database #873 adds ten identity/descriptor/FK constraints.
  -- Database #877 adds fifteen constraints on the three private HDF5 query evidence relations.
  -- Database #879 adds eight identity, 22 final Result query, 21 Candidate storage and 17 publication selection and eight runtime admission constraints, plus twelve readiness evidence and five activation binding constraints.
  -- Database #894 adds 107 exact Study identity/FK/structural/state constraints.
  -- Database #895 adds nine exact runtime-config and artifact-intent constraints.
  -- Database #904 adds fifty-six constraints across eight private analysis/reporting relations.
  -- Database #906 adds 56 constraints across nine private review/share relations.
  -- Database #909 adds five private tables and two explicit intent-family CHECKs: thirty-four constraints.
  -- Database #912 adds six closed method tables and exact method report selection: forty-four constraints.
  -- Database #916 replaces two Result registry FKs with one canonical content CHECK.
  -- Database #961 adds replacement CHECK, self-reference FK and deferred constraint trigger.
  1148::bigint,
  'Twenty-nine navigation constraints plus: all application, OAuth registry and twenty-two composite-name constraints plus ten partial-import and four whole-package constraints, the review submitted-decision constraint, the Result publication attestation and dataset display exact-version and allowlist constraints remain present, and the versioned v2 Time-alias preflight/gate/request tables carry their own reviewed constraints'
);

select is(
  (
    select count(*)
    from pg_constraint constraint_record
    where constraint_record.connamespace in (
      'public'::regnamespace,
      'api'::regnamespace,
      'private'::regnamespace,
      'util'::regnamespace
    )
      and not constraint_record.convalidated
  ),
  3::bigint,
  'migration does not introduce additional unvalidated constraints'
);

select is(
  (
    select count(*)
    from pg_class class
    join pg_namespace namespace on namespace.oid = class.relnamespace
    where namespace.nspname in ('public', 'private')
      and class.relkind in ('r', 'p')
      and class.relrowsecurity
  ),
  -- Database #807 adds 8 isolated display projection and rollout relations; legacy inventory remains included.
  -- Database #873 adds two RLS-protected identity tables.
  -- Database #877 adds three private HDF5 query evidence relations with RLS and no browser policies.
  -- Database #894 adds fourteen private Study relations with forced RLS and no raw policies.
  -- Database #895 adds two private forced-RLS runtime-config/intent relations.
  -- Database #904 adds eight ACL-closed private relations with forced RLS.
  -- Database #906 adds nine FORCE RLS private review/share relations.
  -- Database #909 adds five FORCE-RLS private advanced/configuration/intent/link tables.
  -- Database #912 adds six FORCE-RLS private method/config/evidence/intent/link tables.
  159::bigint,
  'RLS covers the Open Data publication relation, five new private navigation relations and existing tables plus four private composite-name relations and three private import plan/receipt relations'
);

select ok(
  not has_schema_privilege('anon', 'private', 'USAGE')
    and not has_schema_privilege('anon', 'util', 'USAGE')
    and not has_schema_privilege('authenticated', 'util', 'USAGE')
    and not has_schema_privilege('anon', 'archive', 'USAGE')
    and not has_schema_privilege('authenticated', 'archive', 'USAGE'),
  'browser roles cannot enter non-RLS internal schemas'
);

select ok(
  has_schema_privilege('anon', 'api', 'USAGE')
    and has_schema_privilege('authenticated', 'api', 'USAGE')
    and has_schema_privilege('service_role', 'api', 'USAGE'),
  'Data API roles can enter the api schema'
);

select ok(
  has_schema_privilege('authenticated', 'private', 'USAGE')
    and has_table_privilege('authenticated', 'private.roles', 'SELECT')
    and has_table_privilege('authenticated', 'private.reviews', 'SELECT')
    and not has_table_privilege('authenticated', 'private.roles', 'INSERT')
    and not has_table_privilege('authenticated', 'private.reviews', 'UPDATE'),
  'authenticated has only the private reads required by public core-table RLS'
);

select is(
  (
    select count(*)
    from pg_proc routine
    join pg_namespace namespace on namespace.oid = routine.pronamespace
    join pg_roles owner_role on owner_role.oid = routine.proowner
    where namespace.nspname = 'api'
      and routine.prosecdef
      and owner_role.rolname = 'api_internal_executor'
  ),
  -- Database #838 catalog and UUID page readers retain restrictive raw RLS.
  41::bigint,
  'private RLS, canonical Search, filtered catalog/UUID, and opt-in Next version-search facades use the constrained executor'
);

select ok(
  exists (
    select 1
    from pg_roles
    where rolname = 'api_internal_executor'
      and not rolcanlogin
      and rolinherit
      and not rolbypassrls
  ),
  'API internal executor cannot log in or bypass RLS'
);

select is(
  (
    select count(*)
    from pg_proc routine
    join pg_namespace namespace on namespace.oid = routine.pronamespace
    where namespace.nspname in ('api', 'private', 'util')
      and routine.prokind = 'f'
      and pg_get_functiondef(routine.oid) ~
        'public[.](command_audit_log|comments|dataset_review_submit_|identity_center_|lca_|lcia_|notifications|reviews|roles|teams|users|worker_)'
  ),
  0::bigint,
  'stored functions contain no stale explicit references to moved public objects'
);

select ok(
  has_function_privilege(
    'authenticated',
    'api.search_flows_latest(text,jsonb,jsonb,bigint,bigint,text,text,uuid,integer,text[])',
    'EXECUTE'
  ),
  'authenticated retains execute access to an API search facade'
);

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '00000000-0000-0000-0000-000000000001',
  true
);

select lives_ok(
  $sql$
    select *
    from api.search_flows_latest(
      '',
      '{}'::jsonb,
      '{}'::jsonb,
      10,
      1,
      'all',
      null,
      null,
      null,
      array[]::text[]
    )
  $sql$,
  'authenticated API facade can traverse the private helper boundary'
);

reset role;

select * from finish();

rollback;
