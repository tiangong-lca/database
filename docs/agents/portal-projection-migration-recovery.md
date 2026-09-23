---
lastReviewedAt: 2026-09-23
lastReviewedCommit: 15afe29391b0ec3b44602a64bc769b8851583c1f
lastReviewedNote: 'Reviewed for Database #690 / workspace #1464: the role-gated Sample Library extends the shared raw Hybrid search helpers and refreshes their exact fingerprints without changing the immutable Portal projection helper closure, storage, writer, rollout, or recovery procedure; the Portal Hybrid and candidate-first suites pass 64/64 and 83/83 assertions.'
title: Portal Projection Migration Recovery
docType: runbook
scope: repo
status: active
authoritative: false
owner: database-engine
language: en
whenToUse:
  - when an Issue 531 Portal projection migration stops before cutover completes
  - when a concurrent Portal projection index is INVALID or exists without migration history
  - when validating retry safety for the Portal projection rollout
  - when an Issue 533 Portal catalog-summary eligibility index stops before its guard or façade migration completes
  - when an Issue 539 Portal sitemap exact-version child rollout stops before its public façade migration completes
  - when the Issue 563 Process keyword expression GIN is invalid or its cutover is unrecorded
  - when an Issue 603 adaptive Flow facet index is invalid or its semantic cutover is unrecorded
  - when the Issue 616 Flow semantic executor alignment fails or its commit state is uncertain
  - when an Issue 620 adaptive Process facet index is invalid or its semantic cutover or executor alignment is unrecorded
whenToUpdate:
  - when the Portal projection migration sequence or recovery test changes
checkPaths:
  - docs/agents/portal-projection-migration-recovery.md
  - scripts/test_portal_projection_upgrade_recovery.sh
  - scripts/test_portal_facet_projection_populated_upgrade.sh
  - scripts/check_portal_projection_manifest.py
  - supabase/migrations/20260826060422_portal_candidate_first_search.sql
  - supabase/migrations/20260826080257_portal_projection_backfill_0.sql
  - supabase/migrations/20260826080342_portal_projection_backfill_f.sql
  - supabase/migrations/20260826080345_portal_projection_reconcile.sql
  - supabase/migrations/20260826080348_portal_projection_process_pgroonga.sql
  - supabase/migrations/20260826080351_portal_projection_flow_pgroonga.sql
  - supabase/migrations/20260826080400_portal_projection_candidate_cutover.sql
  - supabase/migrations/20260826080403_portal_projection_facets.sql
  - supabase/migrations/20260827010000_portal_flow_embedding_eligibility_index.sql
  - supabase/migrations/20260827010003_portal_flow_embedding_eligibility_guard.sql
  - supabase/migrations/20260827020000_portal_facet_projection_expand.sql
  - supabase/migrations/20260827020001_portal_facet_projection_backfill_00_3f.sql
  - supabase/migrations/20260827020002_portal_facet_projection_backfill_40_7f.sql
  - supabase/migrations/20260827020003_portal_facet_projection_backfill_80_bf.sql
  - supabase/migrations/20260827020004_portal_facet_projection_backfill_c0_ff.sql
  - supabase/migrations/20260827020005_portal_facet_projection_reconcile.sql
  - supabase/migrations/20260827020006_portal_facet_projection_cutover.sql
  - supabase/migrations/20260827021441_portal_card_context_decorator.sql
  - supabase/migrations/20260827134100_optimize_portal_flow_geography_search.sql
  - supabase/migrations/20260827134101_portal_sitemap_latest_projection.sql
  - supabase/migrations/20260827134102_portal_sitemap_shard_contract.sql
  - supabase/migrations/20260827134103_portal_sitemap_concurrency_repair.sql
  - supabase/migrations/20260827050000_portal_catalog_summary_eligibility_index.sql
  - supabase/migrations/20260827050001_portal_catalog_summary_eligibility_guard.sql
  - supabase/migrations/20260827050002_portal_catalog_summary_v1.sql
  - supabase/tests/benchmarks/20260827_portal_catalog_summary_cardinality.sql
  - supabase/tests/20260827_portal_sitemap_shards_v1.sql
  - supabase/tests/upgrade/20260827_portal_sitemap_preview_winner_fixture.sql
  - supabase/tests/benchmarks/20260827_portal_sitemap_shards_cardinality.sql
  - supabase/migrations/20260830134000_portal_process_keyword_rank_helpers.sql
  - supabase/migrations/20260830134001_portal_process_keyword_rank_index.sql
  - supabase/migrations/20260830134002_portal_process_keyword_rank_cutover.sql
  - supabase/migrations/20260903120000_portal_flow_filter_geography_index.sql
  - supabase/migrations/20260903120001_portal_flow_filter_access_level_index.sql
  - supabase/migrations/20260903120002_portal_flow_adaptive_semantic_v2.sql
  - supabase/migrations/20260904144000_portal_flow_semantic_executor_alignment.sql
  - supabase/migrations/20260905134000_portal_process_filter_geography_index.sql
  - supabase/migrations/20260905134001_portal_process_filter_access_level_index.sql
  - supabase/migrations/20260905134002_portal_process_adaptive_semantic_v2.sql
  - supabase/migrations/20260905134003_portal_process_semantic_executor_alignment.sql
  - supabase/tests/20260826_portal_candidate_first_search.sql
  - supabase/tests/20260903_portal_flow_adaptive_semantic_v2.sql
  - supabase/tests/20260904_portal_flow_semantic_executor_alignment.sql
  - supabase/tests/20260905_portal_process_adaptive_semantic_v2.sql
  - supabase/tests/20260905_portal_process_semantic_executor_alignment.sql
  - supabase/tests/benchmarks/20260826_portal_candidate_first_explain.sql
related:
  - ../../AGENTS.md
  - repo-validation.md
  - supabase-branching.md
  - ../../scripts/README.md
---

# Portal Projection Migration Recovery

This runbook covers only the additive Issue 531 Portal projection rollout, the
narrow Issue 533 catalog-summary eligibility index, the Issue 539 sitemap
exact-version child, the Issue 603 query-only adaptive Flow indexes/cutover,
the Issue 616 Flow semantic executor alignment, and the Issue 620 equivalent
Process adaptive indexes/cutover/executor alignment layered on top of the same
synchronized facet projection.
It does not authorize production mutation, migration-history edits, or
deletion of an applied migration. Use the repository's normal tracked-delivery
and Supabase branch controls before any hosted action.

## Safe rollout states

The rollout has nine observable boundaries:

1. `20260826060422` installs the immutable v1 derivation-contract registry,
   private projection, dormant projection Hybrid kernel, and source-table sync
   triggers in one explicit transaction. Every row binds contract version 1.
2. `20260826080257` through `20260826080342` backfill bounded UUID ranges. Old
   Search, Hybrid, and Facets wrappers remain authoritative throughout this
   state. A failed or paused rollout therefore adds write-only projection work
   but does not expose partial projection reads. Every batch sets an outer
   five-second lock timeout and 120-second statement timeout before invoking
   the private helper; function proconfig alone is not the statement timer.
3. `20260826080345` acquires a five-second source-write fence in one explicit
   transaction, inserts genuinely missing rows, removes stale rows, verifies
   key/state/modified parity, and removes the backfill helper.
4. Two standalone projection `CREATE INDEX CONCURRENTLY` migrations reuse the
   existing Process/Flow source HNSW indexes and precede the
   transactional Search/Hybrid cutover at `20260826080400` and the transactional
   Facets cutover at `20260826080403`.
5. `20260827010000` adds one narrow concurrent Flow source B-tree on
   `state_code`, restricted to state-100/200 rows with a non-null embedding.
   `20260827010003` transactionally verifies its exact table, keys, opclasses,
   predicate, owner, validity, and lack of INCLUDE/expression/options drift.
   This low-selectivity membership index accelerates the exact 0..199
   embedding-universe probe without becoming a covering id/version join path;
   it does not store vectors, rank semantic candidates, or alter API semantics.
6. `20260827020000` creates a separate narrow facet contract/table, adds
   `json_ordered` to both existing source projection trigger event lists, and
   installs one parent-to-facet trigger without changing a read path. Four
   UUID-quarter files through `20260827020004` insert child facts with the old
   Facets implementation still authoritative. `20260827020005` takes a
   five-second parent-first write fence, fills only genuinely missing children,
   and fails unless the validated child-FK subset has exact per-kind cardinality.
   `20260827020006` then dispatches only normalized
   empty-query/empty-filter requests to the 32-MB bounded narrow helper. Every
   query or filter retains the unchanged card implementation.
7. `20260827050000` builds one standalone concurrent combined eligibility
   B-tree over the existing card projection. It keys only dataset kind,
   identity, version, timestamp, and state, and its predicate admits
   regex-shaped Flow CAS or nonempty classifications without storing card or
   example values. `20260827050001` transactionally verifies the exact
   relation, owner, access method, keys, opclasses, predicate, and validity.
   `20260827050002` then adds the bounded anonymous catalog-summary façade and
   its two ACL-closed validation helpers. Counts and latest timestamp continue
   reading the narrow facet projection; no existing card/facet manifest,
   source trigger, table, or index changes.
8. `20260827134101` transactionally creates
   `private.portal_sitemap_rows_v1` with one row per public facet version, the
   primary key `(dataset_kind,id,version)`, and an exact-key FK to the facet
   child with `ON UPDATE RESTRICT` and `ON DELETE CASCADE`. Its sole
   `AFTER INSERT OR UPDATE` trigger upserts only the affected exact version;
   DELETE requires no sitemap trigger because the FK cascade removes that exact
   child. One set-based backfill proves exact row parity. The ordered index
   `(shard_no,contract_version,dataset_kind,id,version DESC,modified_at DESC)`
   supplies both the physical bucket filter and current-version selection.
   `20260827134102` then exposes the constant 64-row opaque manifest and the
   output/timeout-bounded shard reader. The reader uses
   `DISTINCT ON (dataset_kind,id)` in index order, so scan work grows with
   retained version history even though the response remains capped at 4,096
   identities and 2 MiB. The retained `portal_sitemap_entries_v1` function
   remains byte-identical.
9. `20260827134103_portal_sitemap_concurrency_repair.sql` is the atomic forward
   repair for the first PR Preview winner-table shape. It locks the sole facet
   writer, creates and fully backfills an exact-version shadow child, rebinds
   the assertion and public shard reader, then drops the obsolete winner table,
   delete/upsert helpers, and triggers before committing. Fresh databases
   already receive the final exact-version child from `20260827134101` and take
   the no-drift path. The rebound reader also compares cursor bytes with a fresh
   encoding of the exact expected object, rejecting JSONB-equivalent
   numeric-scale variants.

The card expand/reconcile/cutovers and all facet expand/backfill/reconcile/
cutover files are explicit transactions. A statement or guard failure rolls
back the entire file. Each pre-existing concurrent index file contains exactly one
non-transactional `CREATE INDEX CONCURRENTLY` statement. Source vectors,
embedding triggers, and duplicate projection HNSW indexes are intentionally
absent. The sitemap covering index is created normally while its new table is
empty, so it has no INVALID live-index recovery state.

Search, Hybrid, and Facets call the v1 manifest guard once per request. The
guard compares the committed registry SHA-256 with the live definitions,
owners, language, volatility, parallel/security settings, and function config
of the exact eleven-function card/document closure. Contract drift fails closed
before projection rows are read.

Issue #532 does not add another projection rollout or recovery boundary. The
card-context migration preserves every Issue #531 table, index, trigger, stored
card, and Facet fact. After Search or Hybrid has ordered and limited candidates,
one shared exact-key decorator reads at most 50 Process/Flow source rows and
derives only the exhaustive public card context. Its later query-only Flow
geography Search repair reuses the already synchronized facet child for
latest/filter/order/limit before hydrating 51 parent cards; it adds no relation,
index, Trigger, or writer work. Every matching request validates the independent
Facet manifest before reading the child, so helper/trigger drift fails through
the public Search error contract rather than returning stale derived facts. The
decorator has its own live transitive
manifest because it stores no historical rows; drift or an exact source miss
fails closed. There is no backfill, reconcile, concurrent index, COMMIT/history
cleanup, or writer recovery action for either layer.

The query-only geography Search migration accepts only the exact reviewed
pre-image or its exact canonical post-image digest. A database COMMIT followed
by a missing migration-history write may therefore use the unchanged normal
retry; reapplying the same `CREATE OR REPLACE FUNCTION` is byte-idempotent.
Any third definition, owner/config/ACL drift, or manifest failure remains a
hard stop and requires a separately reviewed forward repair.

## Hybrid correctness-timeout forward migration

`20260901183000_portal_hybrid_correctness_timeout.sql` is a config-only,
transactional read-path change. It requires the exact 8-second predecessor on
thirteen Portal Hybrid wrapper, lexical/semantic, exact-fallback, and selected-
row decorator functions, then sets all thirteen to one bounded 20-second
statement budget. It changes no function body except the card-context runtime
assertion's expected config digest. The stored v1 projection manifest and all
projection rows, derivation helpers, tables, indexes, policies, triggers,
writers, rankings, DTOs, owners, and application-role ACLs remain unchanged.

The selected-row context closure stores no derived rows, but its live manifest
includes function configuration. The migration therefore advances only that
config digest from
`e0516d5f3a641d26221a5c44b92a2e7a87cab125e9145e8141074d9bc2af39fa`
to
`db78336c8604848af1e068352f8a39d9ee740308c44c59c639b986ed2660c47e`.
The static checker permits exactly this reviewed forward file and rejects any
additional body, schema, data, index, or writer mutation.

Because the file is one explicit transaction, an owner-role, schema-CREATE,
predecessor, digest, or postcondition failure rolls back every function config,
temporary role membership, and assertion replacement. If its migration ledger
row is absent after an ordinary SQL failure, fix the file in Git and repeat the
normal migration path. If catalog evidence shows the new 20-second configs or
new context digest committed while the ledger row is absent, do not edit
history or hand-change functions; record exact `pg_proc.proconfig`, assertion
source, context digest, and ledger evidence, then ship a reviewed reconciliation
migration.

## Read-only diagnosis

First identify the exact ledger and object state. Do not infer it from a CLI
error alone.

```sql
select version
from supabase_migrations.schema_migrations
where version between '20260826060422' and '20260827020006'
order by version;

select contract_version,
  manifest_schema,
  function_identities,
  manifest_sha256,
  created_by_migration
from private.portal_catalog_projection_contract_v1;

select private.portal_catalog_projection_manifest_sha256_v1()
  as live_manifest_sha256;

select projection_contract_version,
  count(*)
from private.portal_catalog_search_rows_v1
group by projection_contract_version
order by projection_contract_version;

select private.assert_portal_catalog_projection_contract_v1();

select contract_version,
  manifest_schema,
  function_identities,
  manifest_sha256,
  created_by_migration
from private.portal_catalog_facet_contract_v1;

select private.portal_catalog_facet_manifest_sha256_v1()
  as live_facet_manifest_sha256;

select facet_contract_version,
  count(*)
from private.portal_catalog_facet_rows_v1
group by facet_contract_version
order by facet_contract_version;

select private.assert_portal_catalog_facet_contract_v1();

select index_relation.oid::regclass as index_name,
  index_catalog.indisvalid,
  index_catalog.indisready,
  index_catalog.indislive,
  pg_catalog.pg_get_indexdef(index_relation.oid) as definition
from pg_catalog.pg_class as index_relation
join pg_catalog.pg_namespace as namespace
  on namespace.oid = index_relation.relnamespace
left join pg_catalog.pg_index as index_catalog
  on index_catalog.indexrelid = index_relation.oid
where (
    namespace.nspname = 'private'
    and index_relation.relname in (
      'portal_catalog_search_process_document_v1_pgroonga',
      'portal_catalog_search_flow_document_v1_pgroonga',
      'portal_catalog_facet_rows_v1_pkey',
      'portal_catalog_facet_rows_latest_v1_idx',
      'portal_sitemap_rows_shard_v1_idx'
    )
  ) or (
    namespace.nspname = 'public'
    and index_relation.relname in (
      'processes_embedding_ft_hnsw_idx',
      'flows_embedding_ft_hnsw_idx',
      'flows_portal_embedding_eligible_v1_idx'
    )
  )
order by index_relation.relname;

select trigger.tgrelid::regclass as source_table,
  trigger.tgname,
  trigger.tgenabled,
  trigger.tgtype,
  trigger.tgattr,
  pg_catalog.pg_get_triggerdef(trigger.oid) as definition
from pg_catalog.pg_trigger as trigger
where trigger.tgrelid in (
    'public.processes'::regclass,
    'public.flows'::regclass,
    'private.portal_catalog_search_rows_v1'::regclass,
    'private.portal_catalog_facet_rows_v1'::regclass
  )
  and trigger.tgname in (
    'portal_catalog_projection_content_sync_v1',
    'portal_catalog_facet_sync_v1',
    'portal_sitemap_rows_sync_v1'
  )
order by source_table, trigger.tgname;

select routine.oid::regprocedure as routine_identity,
  owner_role.rolname as owner_name,
  routine.prosecdef,
  routine.proconfig,
  routine.proacl,
  routine.prosrc
from pg_catalog.pg_proc as routine
join pg_catalog.pg_roles as owner_role on owner_role.oid = routine.proowner
where routine.oid in (
  pg_catalog.to_regprocedure(
    'api.portal_hybrid_search_v1(text,text[],text,jsonb,integer)'
  ),
  pg_catalog.to_regprocedure(
    'private.portal_projection_hybrid_search_v1_impl(text,text[],extensions.vector,jsonb,integer,text)'
  ),
  pg_catalog.to_regprocedure(
    'private.portal_public_hybrid_search_v1_impl(text,text[],extensions.vector,jsonb,integer,text)'
  ),
  pg_catalog.to_regprocedure(
    'api.portal_facets_v1(text,text,jsonb)'
  ),
  pg_catalog.to_regprocedure(
    'private.catalog_portal_facets_v1_impl(text,text,uuid,text,jsonb,text)'
  ),
  pg_catalog.to_regprocedure(
    'private.catalog_portal_facets_empty_v1_impl(text,text)'
  ),
  pg_catalog.to_regprocedure(
    'private.portal_catalog_facet_facts_v1(text,jsonb)'
  ),
  pg_catalog.to_regprocedure(
    'private.portal_catalog_facet_manifest_sha256_v1()'
  ),
  pg_catalog.to_regprocedure(
    'private.assert_portal_catalog_facet_contract_v1()'
  ),
  pg_catalog.to_regprocedure(
    'private.sync_portal_catalog_facet_row_v1()'
  )
);

select dependency.classid::regclass,
  dependency.objid,
  dependency.refclassid::regclass,
  dependency.refobjid,
  dependency.deptype
from pg_catalog.pg_depend as dependency
where dependency.objid = any (array_remove(array[
    pg_catalog.to_regprocedure(
      'api.portal_hybrid_search_v1(text,text[],text,jsonb,integer)'
    )::oid,
    pg_catalog.to_regprocedure(
      'private.portal_projection_hybrid_search_v1_impl(text,text[],extensions.vector,jsonb,integer,text)'
    )::oid,
    pg_catalog.to_regprocedure(
      'api.portal_facets_v1(text,text,jsonb)'
    )::oid,
    pg_catalog.to_regprocedure(
      'private.catalog_portal_facets_empty_v1_impl(text,text)'
    )::oid,
    pg_catalog.to_regprocedure(
      'private.catalog_portal_facets_v1_impl(text,text,uuid,text,jsonb,text)'
    )::oid
  ], null))
   or dependency.refobjid = any (array_remove(array[
     pg_catalog.to_regprocedure(
       'api.portal_hybrid_search_v1(text,text[],text,jsonb,integer)'
     )::oid,
     pg_catalog.to_regprocedure(
       'private.portal_projection_hybrid_search_v1_impl(text,text[],extensions.vector,jsonb,integer,text)'
     )::oid,
     pg_catalog.to_regprocedure(
       'api.portal_facets_v1(text,text,jsonb)'
     )::oid,
     pg_catalog.to_regprocedure(
       'private.catalog_portal_facets_empty_v1_impl(text,text)'
     )::oid,
     pg_catalog.to_regprocedure(
       'private.catalog_portal_facets_v1_impl(text,text,uuid,text,jsonb,text)'
     )::oid
   ], null));
```

If the failed migration has no ledger row and its explicit transaction rolled
back, repeat the normal migration command. A reconcile lock timeout is expected
to recover this way after the conflicting writer finishes.

If the registry row, live digest, child version, FK/check, or assertion differs,
do not retry, clean up a concurrent index, edit migration history, update the
registry digest, or rebuild v1 rows in place. Preserve the evidence and repair
the helper change through a new versioned migration path.

```bash
supabase db push --include-all
```

Never delete or rewrite a migration-history row to force a retry.

## Concurrent index recovery

A canceled concurrent build can leave an INVALID same-name relation while its
migration remains absent from history. `CREATE INDEX CONCURRENTLY` then fails
closed on retry. Confirm all of the following before cleanup:

- the exact index migration version is absent from migration history;
- `20260826080400` and `20260826080403` are absent;
- the v1 derivation-contract assertion succeeds;
- the same-name relation is one of the two private projection PGroonga indexes;
- it is INVALID, definition-drifted, or a canonical-valid build whose COMMIT
  preceded its missing migration-history row.

Run only the matching cleanup statement as a standalone database command. Do
not combine it with `CREATE INDEX CONCURRENTLY`, `BEGIN`, a `DO` block, or other
SQL in the same command.

```sql
drop index concurrently if exists
  private.portal_catalog_search_process_document_v1_pgroonga;

drop index concurrently if exists
  private.portal_catalog_search_flow_document_v1_pgroonga;
```

Execute only the one statement for the failed migration, then repeat the normal
migration command. The following cutover guard verifies the exact access
method, indexed column, `extensions` opclass, partial predicate, validity state,
and PGroonga options before any wrapper changes.

The post-cutover Flow eligibility index uses the same controlled pattern, but
its preconditions are different: `20260827010000` and `20260827010003` must both
be absent, while the cutover and Facets migrations must already be recorded and
their runtime probes healthy. Removing an unrecorded invalid, definition-drifted,
or canonical-valid commit-gap copy restores only the pre-hotfix slow sparse
probe; it does not revert API semantics. Run only this standalone cleanup:

```sql
drop index concurrently if exists
  public.flows_portal_embedding_eligible_v1_idx;
```

Then rerun the normal migration command. Never drop the index when either
post-cutover migration is recorded; diagnose or repair that state as separately
tracked work.

The Portal catalog-summary eligibility index has its own three-file boundary.
Cleanup is allowed only when `20260827050000`, `20260827050001`, and
`20260827050002` are all absent from migration history, both immutable Portal
projection assertions succeed, the facet cutover through `20260827020006` is
recorded, and the same-name relation is an INVALID, definition-drifted, or
canonical-valid commit-gap copy on
`private.portal_catalog_search_rows_v1`. Run only this standalone statement:

```sql
drop index concurrently if exists
  private.portal_catalog_summary_eligibility_v1_idx;
```

Then repeat the normal migration command. If the guard or façade migration is
already recorded, do not drop or rename the index and do not edit migration
history. Preserve the exact ledger/index/function evidence and repair through
a separately reviewed forward migration.

The Issue 603 adaptive Flow path has two standalone concurrent-index files and
one transactional cutover. For either
`portal_catalog_facet_flow_geography_v1_idx` or
`portal_catalog_facet_flow_access_level_v1_idx`, cleanup is allowed only when:

- that index's own `20260903120000` or `20260903120001` migration version is
  absent from history;
- `20260903120002` is absent, while the version-aware Portal migration through
  `20260902150000` is recorded and its projection/facet assertions are healthy;
- the same-name relation is INVALID, definition-drifted, or a canonical-valid
  build whose COMMIT preceded its missing migration-history row; and
- the exact index is still on `private.portal_catalog_facet_rows_v1`, not an
  unrelated relation that happens to reuse the name.

Run only the matching statement as a standalone database command, then repeat
the normal migration command:

```sql
drop index concurrently if exists
  private.portal_catalog_facet_flow_geography_v1_idx;

drop index concurrently if exists
  private.portal_catalog_facet_flow_access_level_v1_idx;
```

Execute only one statement for the unrecorded failed migration. A recorded
sibling index is a valid intermediate state and must not be removed. Never drop
an index when its own migration or the `20260903120002` cutover is recorded.

The cutover proves the exact predecessor function SHA, both live index
fingerprints, executor-role invariants, and immutable projection/facet
contracts before replacing only
`private.portal_projection_semantic_flow_v2(vector,jsonb)`. An ordinary failure
rolls the function, comments, and temporary maintenance grants back together;
the two already recorded indexes remain dormant and safe for an unchanged
retry. A COMMIT followed by a missing `20260903120002` ledger row is not
blind-idempotent because the predecessor SHA has changed. Preserve the ledger,
live function SHA/config/ACL, both index definitions and validity flags, and the
projection/facet assertion results, then use a separately reviewed forward
reconciliation. Do not edit migration history, restore function bytes by hand,
or rebuild the facet projection. This rollout changes no facet row, derivation,
Trigger, writer, manifest, public signature, or vector index.

`20260904144000_portal_flow_semantic_executor_alignment.sql` is the Issue 616
transactional follow-up. It requires the exact Issue 603 Flow semantic body,
owner, function settings, caller, role attributes, source RLS policy, and
pre-existing column/function privileges. In one transaction it grants only
`flows.embedding_ft` to `portal_public_executor`, transfers only the Flow V2
semantic leaf to that `NOLOGIN NOINHERIT NOBYPASSRLS` owner, restores explicit
execute access to `api_internal_executor`, and verifies the resulting ACL/RLS
boundary. It changes no function body, HNSW setting, index, source row,
projection row, public signature, trigger, or writer.

An ordinary statement, lock, or guard failure rolls back the column grant,
owner transfer, function ACL, comment, and temporary maintenance grants
together, so the unchanged migration may be retried after correcting the
prerequisite. A COMMIT followed by a missing `20260904144000` ledger row is not
blind-idempotent because the expected predecessor owner and column ACL have
changed. Preserve the ledger row, live function SHA/owner/config/ACL, exact
role attributes and memberships, `flows` column privileges, RLS policy, and
table owner; then ship a separately reviewed reconciliation migration. Do not
edit migration history, hand-transfer the function, broaden table SELECT, or
disable/bypass RLS.

The Issue 620 Process rollout repeats this recovery shape without sharing
migration state with Flow. The standalone `20260905134000` and
`20260905134001` files build
`portal_catalog_facet_process_geography_v1_idx` and
`portal_catalog_facet_process_access_level_v1_idx`. Cleanup is allowed only
when the matching index migration and both later Process migrations are absent
from history, the same-name relation is on the reviewed facet table, and it is
either invalid, definition-drifted, or a canonical-valid COMMIT-gap copy. Run
only the matching standalone statement, then retry the normal migration:

```sql
drop index concurrently if exists
  private.portal_catalog_facet_process_geography_v1_idx;

drop index concurrently if exists
  private.portal_catalog_facet_process_access_level_v1_idx;
```

A recorded sibling index is a valid intermediate state. Never remove either
index after its own history row or `20260905134002` is recorded.

`20260905134002_portal_process_adaptive_semantic_v2.sql` transactionally
requires the exact predecessor Process helper and both live index fingerprints,
then replaces only the private Process V2 semantic body. Ordinary failure rolls
back together and leaves recorded indexes safe for retry. If COMMIT succeeds
but the `20260905134002` history row is absent, preserve the ledger, live
function SHA/config/owner/ACL, both index definitions and validity flags, and
projection/facet assertion results; reconcile with a separately reviewed
forward migration. Do not edit history, hand-restore function bytes, or rebuild
the facet projection.

`20260905134003_portal_process_semantic_executor_alignment.sql` is the guarded
transactional follow-up. It grants only `processes.embedding_ft` to
`portal_public_executor`, transfers only the Process V2 semantic leaf, and
restores explicit internal execute access while retaining public-state RLS and
denying browser roles. Ordinary failure is safe to retry after its prerequisite
is corrected. A successful COMMIT with a missing `20260905134003` history row
is not blind-idempotent: preserve the ledger, function SHA/owner/config/ACL,
role membership and attributes, Process column privileges, RLS policy, and
table owner, then ship a reviewed forward reconciliation migration. Do not
hand-transfer the function, broaden table SELECT, or disable/bypass RLS.

The Portal sitemap rollout has a three-file transactional boundary. The expand
file creates the exact-version child, composite primary/FK keys, ordered shard
index, one exact-key `AFTER INSERT OR UPDATE` upsert trigger, full backfill, and
row-parity proof in one transaction. Exact-version DELETE cleanup is owned by
the FK cascade. Ordinary failure rolls all of them back.
A database COMMIT followed by a missing `20260827134101` ledger row is not
blind-idempotent: normal retry must fail on the existing table/function. On a
hosted branch, do not delete a subset or edit history; retain the exact ledger,
table/index/FK, sole trigger/helper, row parity, and public-RPC absence evidence,
then use a separately reviewed forward repair. Only the explicitly disposable
isolated recovery project may reset to `20260827134100` and repeat the unchanged
expand.

The `20260827134102` public cutover is also transactional. A missing or disabled
exact-key trigger, missing/invalid history-order index, PK/FK/helper drift, or an
initial shard above 4,096 fails before exposing either RPC. The shard function
must retain exact canonical cursor re-encoding, `DISTINCT ON` current-version
selection, the 4,096-item and 2-MiB response limits, and its four-second timeout.
Restoring an unrecorded metadata rename inside the isolated recovery fixture and
repeating the unchanged migration is valid; an applied hosted expand with real
definition/data drift requires forward repair. Capacity overflow after cutover
is never migration or index corruption and never authorizes cleanup: facet and
sitemap-child writes continue, only the affected shard remains fail closed, and
expansion requires a separately versioned reshard contract.

`20260827134103_portal_sitemap_concurrency_repair.sql` is that checked-in
Preview forward repair, not permission for manual cleanup. While holding the
sole facet-writer fence, it creates the shadow exact-version child and index,
fully backfills it, installs the sole exact-key upsert trigger, rebinds the
assertion and reader, and drops the obsolete winner table/helpers before one
atomic commit. Preserve and escalate any prerequisite or convergence failure;
do not expose a partially backfilled child, retain an obsolete helper, split the
reader swap from old-object retirement, or edit history to force the repair.

`20260827193451_repair_portal_classification_example.sql` changes only the
existing summary function's optional example selection. It filters broad
classification codes, prefers Process evidence, preserves the function owner,
ACL, RLS and two-second summary budget, and adds no projection row, index,
Trigger, or writer path. An uncertain commit follows the normal unchanged
migration retry: `CREATE OR REPLACE FUNCTION` is idempotent after its strict
prerequisite/definition checks, and no data cleanup or projection recovery is
authorized.

`20260827210000_optimize_portal_flow_cas_search.sql` adds one partial expression
B-tree over valid public Flow CAS card values and one exact-CAS candidate branch.
It preserves the existing PGroonga path for ordinary lexical, UUID, and invalid
CAS-shaped text, rechecks the exact latest version before returning a candidate,
and changes no projection row, Trigger, RLS policy, cursor, or timeout. A failed
index build, function prerequisite, public-example smoke, or contract assertion
rolls back atomically; do not retain a manual index or bypass the forward
migration after an uncertain hosted outcome.

`20260827223000_isolate_portal_flow_cas_index.sql` is the forward repair for a
cold persistent-Dev summary timeout discovered after `210000`. It atomically
recreates the same index with an explicit 7..12 CAS-length predicate and adds
the identical predicate to the exact candidate branch. That discriminator is
redundant for valid CAS values but deliberately prevents the unconstrained
summary selector from choosing the CAS-leading index; summary selection
returns to the retained id-ordered eligibility index. The migration must prove
the exact `210000` function/index predecessor, run the real summary smoke inside
its two-second budget, preserve exact-CAS/latest behavior, and roll back both
index and function on any failure.

`20260828003000_select_selective_portal_cas_example.sql` changes only summary
example selection after a strict Dev probe showed that exhaustive context
hydration for a 13-match CAS could still consume the public eight-second
budget. The summary performs one ordered GroupAggregate over the exact CAS
index, retains at most 64 CAS values that occur exactly once across all stored
projection history, and then joins the chosen row to the shared latest CTE.
This conservative condition guarantees one current match after the latest
recheck without repeated helper calls; Search itself remains complete and
unchanged. If valid public CAS evidence exists but the bounded unique-value
probe cannot produce a current example, the migration fails instead of silently
removing the homepage CAS.
The summary's two-second timeout, three-example order, and 16-KiB cap remain
unchanged, and migration verification runs as the constrained Portal executor.

`20260829130000_make_portal_flow_cas_rls_indexable.sql` changes only the
Portal SELECT policy on the purpose-built card projection and the live
projection assertion. The table remains `postgres`-owned with forced RLS and a
validated CHECK that admits only states 100/200; the row-neutral policy is safe
only while the assertion pins all of those facts and its unique role binding.
This lets the existing non-leakproof JSON CAS equality remain an exact index
condition instead of a parent-wide filter. The migration adds or removes no
relation, index, Trigger, row, writer branch, timeout, or public contract. Any
policy, CHECK, owner, RLS-flag, assertion-hash, candidate-function, or summary-
function prerequisite drift aborts atomically. Recovery is the unchanged
migration retry; do not hand-edit the policy or weaken the table constraint.

`20260829131000_repair_portal_single_character_literal_search.sql` preserves
the fixed `%L` multi-code-point templates and establishes a correctness-only
`strpos` fallback after TokenBigram LIKE demonstrated a one-code-point false
negative. It changes no public wrapper, index, relation, or writer and is a safe
intermediate state if later rollout files have not committed.

`20260829131001_portal_character_projection_expand.sql` creates the narrow
exact-version character child, derivation helpers, latest-key B-tree, exact
parent FK, and sole parent INSERT/UPDATE upsert Trigger. It contains no initial
rows. `131002` through `131005` backfill four UUID quarters under independent
120-second statements while the Trigger covers concurrent parent writes.
`20260829131006_portal_character_projection_cutover.sql` takes one short parent
writer fence, inserts any missing rows, removes impossible extras, proves exact
key/state/time parity plus deterministic sampled facts, installs the runtime
schema assertion and bounded pre-limit kernel, then routes only validated
one-code-point empty-filter relevance through it. Any interruption before
cutover leaves the retained correctness fallback authoritative. After cutover,
the child is rebuildable from the immutable parent: never hand-edit rows,
disable the Trigger, rebuild PGroonga, or add a unigram index. A missing shard
is repaired by replaying only its unrecorded migration; an uncertain recorded
cutover requires catalog/ledger inspection before any retry.

`20260830134000_portal_process_keyword_rank_helpers.sql` installs a dormant,
manifest-guarded Process key selector and bounded hydration kernel. It changes
no reader, row, relation, trigger, or public wrapper. The two immutable index
expressions grant execution only to the internal projection writer and
`postgres`, because ordinary Process projection maintenance and database
`ANALYZE` must both evaluate them.

`20260830134001_portal_process_keyword_rank_index.sql` contains one standalone
`CREATE INDEX CONCURRENTLY` for
`portal_catalog_search_process_exact_rank_v1_gin`. If it fails and the ledger
row is absent, inspect `pg_index.indisvalid/indisready/indislive` and the exact
`pg_get_indexdef`. Drop only that exact invalid/unrecorded index, then retry the
unchanged migration; never drop a valid recorded index or rebuild the parent
projection. The helper migration is a safe dormant state while the index is
absent.

`20260830134002_portal_process_keyword_rank_cutover.sql` first proves the
helper digest, exact live index, maintenance ACLs, and predecessor coordinator
hash, then atomically replaces only `private.portal_search_v1`. It dispatches
only multi-code-point, non-UUID, empty-filter Process relevance requests and
preserves the one-code-point and general branches verbatim. A guard or DDL
failure rolls back the coordinator replacement. If the function bytes changed
but the ledger row is absent, do not guess whether COMMIT occurred: record the
live function SHA, helper assertion, index catalog/ACLs, and migration ledger,
then escalate for reviewed reconciliation. Do not hand-edit the digest,
function, grants, or migration history.

## Uncertain expand commit

The expand migration is transactional, so ordinary SQL failure leaves no Issue
531 object. A process crash after database `COMMIT` but before migration-history
recording is different: the ledger can omit `20260826060422` while its objects
exist, and a blind retry will fail on `CREATE TABLE` or `CREATE TRIGGER`.

Stop and obtain operator review. Cleanup is permitted only when read-only checks
prove that `20260826060422` and every later Issue 531 migration are absent, the
old external wrappers are still installed, and no application reads the private
projection. Under those conditions the projection is fully rebuildable from
the source tables:

```sql
begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';
lock table public.processes, public.flows in share row exclusive mode;

drop trigger if exists portal_catalog_projection_content_sync_v1
  on public.processes;
drop trigger if exists portal_catalog_projection_content_sync_v1
  on public.flows;

drop function if exists
  private.portal_projection_hybrid_search_v1_impl(
    text, text[], extensions.vector, jsonb, integer, text
  );
drop function if exists
  private.portal_projection_semantic_candidates_v1(
    text, extensions.vector
  );
drop function if exists
  private.portal_projection_semantic_process_v1(extensions.vector);
drop function if exists
  private.portal_projection_semantic_flow_v1(extensions.vector);
drop function if exists
  private.portal_projection_semantic_process_exact_v1(extensions.vector);
drop function if exists
  private.portal_projection_semantic_flow_exact_v1(extensions.vector);
drop function if exists private.assert_portal_catalog_projection_contract_v1();
drop function if exists
  private.portal_catalog_projection_manifest_sha256_v1();
drop function if exists
  private.backfill_portal_catalog_search_range_v1(uuid, uuid);
drop function if exists private.sync_portal_catalog_search_row_v1();
drop table if exists private.portal_catalog_search_rows_v1;
drop table if exists private.portal_catalog_projection_contract_v1;
drop function if exists
  private.catalog_portal_projection_payload_v1(text, integer, jsonb);
commit;
```

If any precondition is false, do not run cleanup. Escalate with the exact ledger,
index, trigger, and wrapper evidence.

## Facet projection recovery

The facet expand is transactional but intentionally not blind-idempotent. If
its database COMMIT succeeds before the migration ledger is recorded, normal
retry fails on the existing function/table. Stop and obtain operator review;
do not edit history or drop any subset of the contract. This runbook authorizes
only a full reset of the explicitly disposable isolated recovery project. It
does not authorize cleanup on Preview, persistent Dev, or production. For any
hosted COMMIT/history gap, retain the ledger/object/wrapper evidence and
escalate for a separately reviewed forward-repair migration.

Each of the four facet backfills is idempotent. It uses `ON CONFLICT DO NOTHING`
and verifies exact per-kind/range cardinality before recording history. The
validated composite child FK proves the child key set is a subset of the parent
key set, so equal cardinality proves exact key coverage. A COMMIT/history gap
may therefore use the normal unchanged migration retry. The shard files never
update or delete `private.portal_catalog_search_rows_v1`.

The reconcile migration locks the parent before the child with a five-second
timeout. Lock failure leaves both ledger and API unchanged; retry only after the
conflicting writer finishes. It inserts missing children only and treats any
existing mismatch as contract drift. The cutover separately rechecks full
parity before replacing the wrapper. A cutover guard failure must leave
`20260827020006` absent and the old wrapper byte-identical. Do not repair drift
by editing the literal facet digest or silently updating child facts.

The migration-time guards deliberately do not detoast every wide parent card or
repeat state/timestamp comparisons while holding deployment transactions or the
reconcile fence. The immutable helper, validated FK/checks, and only two
governed writers establish row provenance; the pgTAP suite and populated-upgrade
runner perform the complete key/state/timestamp/five-fact comparison outside
the short migration fence.

## Local recovery regression

The checked-in recovery regression requires an explicitly attested, isolated
Issue 531 Supabase project. It resets that local project and must never target a
shared checkout, Preview, persistent Dev, or production.

Formal recovery evidence requires clean HEAD, the reviewed Supabase CLI
`2.109.1`, and byte equality plus one aggregate SHA-256 across all 299 migration
files in the repository and isolated project. Comparing only Issue 531 files is
not sufficient because an earlier baseline change can alter recovery behavior.

```bash
PORTAL_PROJECTION_RECOVERY_TARGET=local-isolated \
PORTAL_PROJECTION_SUPABASE_WORKDIR=/absolute/path/to/database-engine-531-project \
SUPABASE_CLI=/absolute/path/to/supabase \
scripts/test_portal_projection_upgrade_recovery.sh
```

The regression uses two live database connections to cover valid-update,
delete, state `100 -> 20`, id/version key-change, and embedding-only/missing-row
races. Embedding-only changes remain source-HNSW owned and the final fence fills
any independently missing card row. The regression also proves reconcile
lock-timeout rollback, reconcile COMMIT/history retry, wrong and canonical-valid
same-name index cleanup without history edits, cutover guard rollback,
post-cutover Flow eligibility build/guard recovery, facet expand COMMIT/history
failure, facet shard idempotent retry, facet reconcile lock rollback, facet
cutover parity rollback, parent-trigger/FK-cascade convergence, successful
retry, and no-op repeat without rebuilding the eight recorded indexes.

The same runner also resets to `20260827134100` and proves the sitemap expand
COMMIT/history gap requires an explicit disposable-project reset. It then
renames the recorded covering index to force public-cutover rollback, proves
both RPCs remain absent, restores the unrecorded metadata name, applies the
unchanged cutover plus `20260827134103` forward repair, and validates the exact
exact-version child PK/FK/index, sole trigger/helper, absence of obsolete winner
objects, and final 64-descriptor manifest. It then exercises exact concurrent
inserts, updates, and deletes across versions of the same identity. Every writer
must commit through the parent/facet transaction and FK cascade without a
writer-side retry, while the sitemap child remains exactly equal to the
committed public facet-version set. Its no-op pass includes the history index
OID so a recorded retry cannot rebuild it. Canonical cursor evidence also
rejects alternate numeric scales such as `1.0` and `64.0`.
It separately loads the SHA-pinned exact `343b7a1` two-migration Preview fixture
over a populated v1/v2 identity, records only those two isolated ledger rows,
and proves `20260827134103` alone preserves both exact versions while switching
the public reader to v2 and retiring every old winner object.

The separate populated-upgrade runner resets the same kind of isolated project
to `20260827010003`, inserts 17,299 Process plus 108,947 Flow parent cards, and
executes the seven facet files verbatim. Every statement in a UUID-quarter file
must finish within 60 seconds, preserving at least 2x headroom under its
authored 120-second statement timeout, and each complete file must finish
within 120 seconds. Reconcile must complete within five seconds, and final
key coverage, deterministic sampled fact parity, and aggregate DTO counts must
be exact. The runner then applies `20260827134101`, `20260827134102`, and
`20260827134103` over all 126,246 rows with 60/15/15-second evidence budgets and
120/30/30-second outer timeouts. It requires exact facet/sitemap version-row
parity, the composite PK and exact `ON UPDATE RESTRICT`/`ON DELETE CASCADE` FK,
the ordered history index, the sole exact-key trigger, the 4,096-identity shard
cap, and both public sitemap RPCs. The pgTAP suite remains the exhaustive
semantic equality oracle.

The representative single-version benchmark retains 126,246 exact rows, a
largest shard of 2,066 identities, and roughly 11 ms shard-read p95. Its
history-density probe materializes 2,048 identities with 64 versions each
(131,072 rows). The natural `DISTINCT ON` plan must use the history-order index
as an index-only path, contain no `Sort` or `Incremental Sort`, spill no temp
data, and finish below four seconds. These gates make the retained-history scan
cost explicit rather than describing the reader as constant-cost.

```bash
PORTAL_FACET_UPGRADE_TARGET=local-isolated \
PORTAL_FACET_UPGRADE_SUPABASE_WORKDIR=/absolute/path/to/database-engine-531-project \
SUPABASE_CLI=/absolute/path/to/supabase \
scripts/test_portal_facet_projection_populated_upgrade.sh
```

The pre-cutover raw-source
`private.portal_public_hybrid_search_v1_impl(...)` is a rollback asset only
until `20260826080400` replaces the API wrapper. The same cutover transaction
drops it with `IF EXISTS`; a failed transaction restores it, while a committed
or commit/history-gap retry leaves it absent. The final guard requires the API
wrapper to call only `private.portal_projection_hybrid_search_v1_impl(...)`.

## Derived-semantics changes

The registry row, its digest, the eleven-function v1 closure, and every v1 row
label are immutable. A card/document semantic change must create a new helper
closure and shadow projection, then use bounded backfill, a short source-write
reconcile fence, concurrent lexical indexes, and an atomic read cutover. Never
update the v1 registry row or perform a long in-place mixed-semantics backfill.

The two-function facet manifest is independently immutable. Its v1 facts are
derived only from the already public-safe card, and its storage is a child
projection rather than a rewrite of card/document rows. A facet-fact semantic
change requires a new literal facet contract and an additive child rollout;
never modify the v1 digest or mix fact versions in the current child table.

Even a claimed output-equivalent bug fix requires full source-card byte
equivalence proof. Without that proof, treat it as v2. The static manifest check
rejects later migrations that replace a v1 closure member; the runtime guard is
the fail-closed defense if live catalog definitions drift.

The supported safety model assumes privileged DDL runs only through governed
migrations and CI. The live digest has no historical memory: an out-of-band
change followed by source writes/backfill and restoration of the old definition
can leave mixed rows while the current digest matches. If that sequence may
have occurred, do not re-enable or retry v1, even after restoring identical
function bytes. Treat the full v1 projection as untrusted and recover through a
shadow v2 rebuild and cutover.

The recovery harness holds the conflicting writer lock for 60 seconds so CLI
startup cannot let it expire before the migration reaches `LOCK`. After the
expected five-second lock timeout is captured, the harness terminates exactly
that application-name-bound backend and verifies a 5–30 second wall window,
unchanged migration ledger/helper state, and successful retry. Formal evidence
uses Supabase CLI `2.109.1`.

## Composite-name projection rollout

Ten migrations implement the Process-only change:

1. `20260908090000` installs the immutable composite-name helpers, Process-only
   card/character tables and a Process dual writer. V1 Flow storage, indexes and
   writer remain untouched. Two zero-storage invoker-security views combine
   Process V2 with Flow V1 for shared readers; the live guard pins their exact
   definitions, owner and invoker security as well as the frozen V1 contract.
2. `20260908090100..103` backfill four Process UUID quarters, each bounded to
   5,000 eligible records and 120 seconds with a five-second lock wait. Source rows are locked
   in key order with `FOR SHARE`; concurrent source updates and deletions serialize
   with the writer. `ON CONFLICT DO NOTHING` cannot overwrite newer committed
   cards. One audit row per quarter records successful coverage. If the preflight count exceeds
   the reviewed bound, fail and split the unrecorded backfill in a reviewed change.
3. `20260908090202..205` build four Process lexical/rank/latest/summary indexes
   concurrently, one top-level statement per migration. No Flow index is copied.
4. `20260908090300` validates exact index readiness, manifests, completed backfill,
   source-derived V1/V2 Process key/state/time parity and character coverage under
   a short Process write fence. It atomically updates existing mutable readers
   and public wrappers. Only immutable generations coexist; there is no duplicate
   general Search/Hybrid/Facet reader graph.

The original source JSON, version and modified_at remain unchanged. Both Process
writers commit together, keeping the existing facet/sitemap chain synchronized.
Each bounded Process quarter must demonstrate at least 2x statement-timeout
headroom on the representative populated upgrade. Preview counts alone are not
production-volume proof. A wrong or invalid concurrent index fails cutover; inspect
only that exact unrecorded index before the normal reviewed recovery. Ordinary
transaction failures roll back the file. Never edit persistent migration history.

PR #629's earlier 24-file sequence was applied only to its disposable Preview.
The revised ten-file canonical sequence requires explicit discard/reprovision of
that exact PR Preview before fresh proof. Do not apply the shortened sequence over
the earlier Preview ledger, and do not discard persistent Dev or Main state.

Validate a blank isolated stack and a populated canonical-base-to-head upgrade:

```bash
python3 scripts/test_portal_composite_names_upgrade.py \
  --local-container supabase_db_database-engine-628
supabase test db supabase/tests/20260908_portal_composite_names.sql
python3 scripts/test_portal_composite_names_graph.py \
  --local-container supabase_db_database-engine-628
python3 scripts/benchmark_portal_composite_names.py \
  --local-container supabase_db_database-engine-628
```

The volume runner requires empty isolated Process/Flow sources. It seeds 17,299
Process and 108,947 Flow records, measures the Process-only rollout, verifies no
Flow shadow rows or second writer, and checks unchanged unrelated fields plus
representative query plans. All timings and storage sizes are synthetic evidence.
Keep deployed exact-source readback, migration/index readiness, DTO agreement and
cache-expiry evidence in the delivery Issue. Installing helpers alone does not
complete deployment.

## Navigation projection rollout

Database #656 adds an independent navigation vocabulary, narrow version facts and ancestor memberships. The expand migration attaches writers to the existing public-safe Flow V1 and Process V2 projections, leaving the raw source writers and frozen manifests intact. Four UUID-quarter backfills claim only missing versions; a concurrent writer wins its existing claim, and foreign keys prevent withdrawn parents from surviving as navigation rows. A failed quarter rolls back and can be replayed; it must not be marked applied manually. The read cutover refuses incomplete version coverage. The capability manifest and literal derivation guard complete exposure.

Do not delete or rewrite existing public projections to recover this child. Inspect the exact failed migration, its source/child coverage and constraint evidence, correct the owning forward migration and resume through the supported migration workflow. Temporary local fixture rollback does not prove a hosted populated upgrade. Runtime unknown nodes must disappear from public navigation when their last public member is withdrawn; their retained private identities are not permission to disclose retired codes.

The navigation shard migrations set both version-parent constraints to immediate for the backfill transaction. A withdrawal after the cursor snapshot is caught and skipped inside the per-version savepoint; the FK cannot defer that error until the whole quarter commits. `scripts/test_portal_navigation_backfill.py` proves populated replay and deterministic concurrent withdrawal/update against the exact migration text. Runtime source writers retain the original deferred constraints.
