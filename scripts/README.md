---
title: Scripts
docType: guide
scope: repo
status: active
authoritative: false
owner: database-engine
language: en
whenToUse:
  - when the task touches schema-workspace helper scripts
  - when you need the supported command surface for workspace refresh or migration generation
whenToUpdate:
  - when script entrypoints, supported source shapes, or workspace refresh behavior changes
checkPaths:
  - scripts/README.md
  - scripts/**
  - supabase/workspace/**
  - docs/agents/repo-architecture.md
  - .githooks/pre-push
  - scripts/docpact
  - scripts/docpact-gate.sh
  - scripts/install-git-hooks.sh
lastReviewedAt: 2026-09-26
lastReviewedCommit: 5b6a2508dcfbe7c602f8cce848d1430a9796ddfa
lastReviewedNote: "Reviewed Database #723 main-hotfix narrow Portal readers, coverage cutover, real-writer/equivalence/concurrency proof and isolated fixture disposition. Public DTOs, writer/ACL contracts, 8-second budgets and main-to-dev/root delivery boundaries remain; local schema snapshots require exact reconstruction and deterministic regeneration."
related:
  - ../AGENTS.md
  - ../.docpact/config.yaml
  - ../docs/agents/repo-architecture.md
  - ../docs/agents/repo-validation.md
  - README.zh-CN.md
---

# Scripts

This directory contains the command-line helpers used for remote schema export, workspace refresh, change-copying, migration generation, and controlled data migrations.

## Layout

Durable helper entry points remain at the top level of this directory.
One-off or dated data remediation runners live under:

- `scripts/data_migrations/<topic>_<yyyymm>/`

Those runners should keep their own `README.md` with dry-run, apply, and validation examples.
Local migration outputs and audit JSONL files should be written under `_artifacts/`, which is intentionally ignored by Git.

## Script List

### `configure_derivative_scheduler.py`

Installs no schema and writes no dataset. It changes only the protected derivative
cron command between five and 25 request visits after the #703 migration has
been deployed. The one-minute cadence, active flag, owner and all other job
fields must match the reviewed snapshot and remain identical. Five combined
external transitions remain the coordinator's independent upper bound.

Use the repository-pinned, already authenticated Supabase CLI. Set
`SCHEDULER_PROJECT_REF`, `SCHEDULER_COORDINATOR_SHA256` and
`SCHEDULER_SELECTOR_SHA256` from the intended project and the independently
qualified clean migration build, not by accepting arbitrary remote definitions.
`SCHEDULER_EVIDENCE` must name a new directory whose parent already exists.

```bash
python3 scripts/configure_derivative_scheduler.py plan \
  --project-ref "$SCHEDULER_PROJECT_REF" --operation enable25 \
  --expected-coordinator-sha256 "$SCHEDULER_COORDINATOR_SHA256" \
  --expected-selector-sha256 "$SCHEDULER_SELECTOR_SHA256" \
  --out-dir "$SCHEDULER_EVIDENCE"
```

Review `plan.json`, the complete before job and `review.sql`; store the returned
`approve_sha256` as `SCHEDULER_PLAN_SHA256`. The default exact migration head is
`20260923053141`; a later qualified deployment must supply its exact head using
`--expected-migration-version`.

```bash
python3 scripts/configure_derivative_scheduler.py apply \
  --project-ref "$SCHEDULER_PROJECT_REF" \
  --plan "$SCHEDULER_EVIDENCE/plan.json" \
  --approve-sha256 "$SCHEDULER_PLAN_SHA256"
```

The SQL template uses REPEATABLE READ and `cron.alter_job`, with complete source,
project, schema and before/after checks. Concurrent admin edits cause refusal or
SQLSTATE 40001, never a retry. A create-only, fsynced attempt file is recorded
before dispatch; a copied plan or an existing attempt cannot be used again.
Credentials and raw command failures are not printed. Keep the private evidence
directory through closeout. Every command accepts `--supabase-cli /path/to/supabase`.

After a timeout or uncertain response, use a NEW readback directory:

```bash
python3 scripts/configure_derivative_scheduler.py verify \
  --project-ref "$SCHEDULER_PROJECT_REF" \
  --plan "$SCHEDULER_EVIDENCE/plan.json" \
  --out-dir "$SCHEDULER_READBACK"
```

This reports current `desired`, `before` or `changed` state, not attribution of
an uncertain commit. Do not replay or replace the uncertain plan to force a
write. For rollback, first create and review a fresh `rollback5` plan against
the current 25-visit job, then apply it once. Rollback restores the default `()`
command (five visits), including when the old source used explicit `(5)`, and
must precede any schema/code rollback. Qualify enable/rollback/enable on the
exact Preview, then activate production and use a new native test-account
request with actual worker completion proof.

Offline transport tests: `python3 scripts/test_configure_derivative_scheduler.py`.
The dedicated local concurrency and populated-upgrade harnesses live under
`supabase/tests/regression/20260923_derivative_scheduler_*.py`; their hardcoded
isolated container and black-hole endpoint guards must not be relaxed to target
shared or hosted data. Release the task-owned stack after preserving evidence.

### `benchmark_hybrid_versions.mjs`

Runs rollback-only, explicitly isolated Database #600 synthetic comparison
fixtures, 20-sample V1/V2 timings, top-10/20 identity overlap, restored
historical-version coverage, Process zero/selective/2,000/2,001/broad/unfiltered
route timings, and natural broad/unfiltered V2 semantic plans. Both Process and
Flow HNSW plans must run under `portal_public_executor` and naturally name
their respective `processes_embedding_ft_hnsw_idx` and
`flows_embedding_ft_hnsw_idx`. It
accepts only a named local Docker container; there is no remote URL or
credential option.
Output contains summary counts/timings/index names, not queries or vectors.
Reset that isolated stack before and after. This diagnostic is not hosted
relevance or production-cardinality release evidence.

`node scripts/benchmark_hybrid_versions.mjs --help`

### `benchmark_next_hybrid_v2.mjs`

Runs the rollback-only Database #624 Next Process/Flow segmented benchmark
against an explicitly named isolated local Docker database. It proves the
zero/one/2,000/2,001/broad/unfiltered route boundary, stable ordered-result
digests, exact-filter and public-institution team indexes, existing PGroonga
indexes, and the eligible broad semantic plan. The runner accepts no database
URL or credential and rejects every container outside its fixed local naming
contract. Synthetic timings are local route evidence; persistent Dev remains
the production-cardinality release gate.

`node scripts/benchmark_next_hybrid_v2.mjs --help`

### `check_auth_email_templates.py`

Validates the password-recovery email contract without contacting Supabase. It
requires the exact `supabase/config.toml` binding, a non-empty subject, and both
a button and visible copyable link targeting the same complete
`{{ .ConfirmationURL }}`. It rejects hand-built token-hash magic links.

```bash
python3 scripts/check_auth_email_templates.py
python3 scripts/test_check_auth_email_templates.py
```

### `test_full_schema_cutover_upgrade.sh`

Rebuilds the local database to the migration immediately before the full
Schema cutover, adds a representative business row, snapshots relation and
routine identities plus trigger, RLS-policy, constraint, and exact row-count
state, reproduces the production ledger where the later reuse-binding hotfix
was already applied, runs the fail-closed bridge, applies the cutover and
contract-closure migrations, and verifies
complete preservation, capability-manifest installation, idempotency-index
creation, Data Product consumer-facade installation, and removal of PostgreSQL
`PUBLIC` execution from the API surface. It also applies the Issue #422 runtime
ACL repair and verifies the exact authenticated RLS-helper and Edge release
façade grants after a populated upgrade, then proves the bridge is a strict
no-op on an already-cut-over database.

Usage:

```bash
scripts/test_full_schema_cutover_upgrade.sh
```

This script is local-only and resets the local Supabase database.

### `test_search_text_array_upgrade.sh`

Rebuilds the local database to `20260810200000`, exercises the exact
production `search_text` migration, and proves that all seven table OIDs and
heap relfilenodes remain stable while an unrelated business row is preserved.
It then rebuilds the pre-migration state with one populated scalar and proves
the migration fails before changing any column or discarding the value. The
script finishes with a clean reset to the checked-out migration head.

```bash
scripts/test_search_text_array_upgrade.sh
```

### `test_portal_projection_upgrade_recovery.sh`

Exercises the Issue 531/532/539/543/551/563 Portal projection rollout against an explicitly
attested, isolated local Supabase project. It uses live concurrent connections
to prove valid-update, delete, state-invalidation, key-change, and
embedding-only races; forces card/facet reconcile lock-timeout and cutover-guard
failures; verifies facet expand COMMIT/history failure, four-shard idempotent
retry, controlled same-name concurrent-index cleanup, post-cutover Flow
eligibility guard rollback, transactional sitemap expand COMMIT-gap/reset and
public-cutover/forward-repair rollback and retry, the exact-version child
PK/FK/index, the sole exact-key upsert trigger, and retirement of every obsolete
winner object. Real same-identity exact-version inserts, updates, and deletes
must all commit without a writer-side retry while child rows remain exactly
equal to the committed public facet-version set. The runner also proves a no-op
repeat does not rebuild eight indexes and rejects noncanonical cursor numeric
scales. A SHA-pinned exact old-Preview fixture additionally proves a populated,
recorded `134101`/`134102` state converges by applying only `134103`.
See
`docs/agents/portal-projection-migration-recovery.md` for the required
environment and recovery boundaries. Formal evidence additionally requires
clean HEAD, Supabase CLI `2.109.1`, and byte equality plus aggregate SHA-256 for
the complete 299-file migration tree.

### `test_portal_facet_projection_populated_upgrade.sh`

Rehearses the seven facet migrations verbatim over 126,246 pre-existing parent
cards in the same explicitly isolated Issue-531/532/539/543/551/563 project. It requires every
backfill statement to retain at least 2x headroom under its 120-second timeout,
each complete UUID-quarter file to stay below 120 seconds, the successful
reconcile fence to finish within five seconds, plus exact key coverage,
deterministic sampled facts, and aggregate DTO counts.
It then times the three sitemap migrations over all 126,246 rows against exact
60/15/15-second evidence budgets (120/30/30-second outer timeouts) and requires
facet/sitemap exact-version row parity, composite PK/FK parity, the ordered
history index, the sole exact-key trigger, shard capacity, and exact public-RPC
parity.
The runner always resets the isolated project to full HEAD on exit.

### `run_portal_projection_benchmark.sh`

Runs the Issue 531 representative Process/Flow Search, Hybrid, Facets, writer,
fence, plan, and ANN-recall benchmark only against an explicitly attested
Issue-531/532/539/543/551/563 local Supabase project. The runner byte-compares the complete
299-file migration tree with the repository, writes into a new operator-selected private
directory, and resets the isolated database before and after the run so rolled
back HNSW pages cannot accumulate. Its environment contract mirrors the
recovery runner and additionally requires
`PORTAL_PROJECTION_BENCHMARK_OUTPUT_DIR`.

The separate catalog-summary cardinality SQL also measures the dynamically
selected classification and Flow CAS examples for 20 samples. Its temporary
writer clone records the combined eligibility index and exact Flow CAS index
independently, including build time, bytes, and incremental four-update p95;
the real projection and its indexes are never dropped or rebuilt by that probe.
Its `cas-pressure` profile assigns one CAS to 10,000 current Flow cards while
retaining one unique CAS, then requires the bounded selector to keep summary
p95 below 250 ms and the emitted CAS to return exactly one item. The same
representative fixture captures the natural forced-RLS exact-CAS plan and fails
unless the CAS equality is in `portal_catalog_search_flow_cas_v1_idx`'s
`Index Cond` with no CAS JSON filter.

The full candidate benchmark also records 20-sample
`process_single_character` and `flow_single_character` labels. They exercise
the synchronized narrow character pre-limit for one unescaped code point and
must keep Search
p95 below two seconds; all multi-code-point and escaped literal labels retain
the existing PGroonga-backed template. Writer evidence includes the sole child
upsert Trigger, and populated/recovery runners prove child/parent parity.

`PORTAL_PROJECTION_BENCHMARK_PROFILE` selects a fail-closed named profile:

- `release` uses representative rows/vectors plus the 21,000-old-Flow pressure,
  records the natural raw-ANN branch, directly gates both full-cardinality
  exact helpers, and captures the production 5,000-to-200 ANN phase;
- `sparse-zero` uses representative rows with zero embeddings;
- `sparse-199` uses representative rows with 199 embeddings per dataset;
- `diagnostic` permits explicitly supplied smaller counts and is not release
  evidence; `auto` recognizes an exact named profile from its counts.

All named gates require a clean exact HEAD. They cover the complete public
request shapes and retain Search/Facets p95 <= 2 seconds. Hybrid samples must
complete with the exact public schema under the bounded 20-second statement
budget; their latency is recorded for optimization but is not a release gate.
Formal semantic plans must include parseable shared-buffer evidence, remain
below 750,000 total and 250,000 read blocks, and show no temp/disk spill. Use a new
mode-0700 output directory for every run. Formal lexical plans use the exact
Process/Flow pattern-helper leaf with every normal planner path enabled. The
representative Flow cardinality must naturally select its PGroonga scan node;
the smaller Process cardinality records its natural-cost plan without forcing
one index, while the migration catalog guard proves its PGroonga index and the
named timings independently cover Process performance, ordering, and cursors.
Both lexical probes require the exact needle fixture identity and no spill.
Every profile with at least 10,000 Process rows also requires the exact-name/
classification probe to naturally name
`portal_catalog_search_process_exact_rank_v1_gin`, records its bytes, and
keeps the existing Process writer delta/ratio gate so the query gain cannot
hide unsafe projection-write amplification.
The benchmark also captures anonymous Process/Flow empty and filtered Facets
plans, requires the independent empty path to use its 32-MB workspace without
temp/disk spill, measures the parent-first facet reconcile fence, and includes
the facet child upsert in the existing writer delta/ratio gate.
Every profile also records the exact Flow embedding-universe probe. Sparse
profiles must naturally use the narrow partial eligibility B-tree and may not
scan the wide Flow heap; release records the natural full-vector plan without
forcing that index. Only release must name both source HNSW indexes; sparse
source probes may choose an eligibility/empty-set plan but still require
buffers, execution time, and no temp/disk spill.

All named profiles build evidence-complete card context: each Process resolves
an exact public reference Flow plus the real FlowProperty/UnitGroup functional
unit chain, while Process/Flow rows carry the public source/database and
Process review/technology fields. Four dedicated Search-50/Hybrid-20 labels
must each produce exactly 50/20 complete items, 20 timing samples, and a full
wrapper `EXPLAIN (ANALYZE, BUFFERS)`. The runner rejects missing evidence,
records temp-buffer use, rejects more than 750,000 total or 250,000 read shared
blocks, and applies the existing
2-second Search / 6-second Hybrid budgets.
The evidence file also carries a dedicated full plan for empty-query,
`geography=cn` Flow Search-50, the representative filtered worst case; its
timing label must also return exactly 50 complete cards so an empty or narrowed
result cannot make the performance gate pass.

The sitemap profile keeps the 126,246-row single-version fixture at a maximum
2,066 identities in one shard and records roughly 11 ms shard-read p95. A
separate history-density probe expands 2,048 identities to 64 versions each
(131,072 rows). Its natural `DISTINCT ON` plan must use the exact history-order
index as an index-only path, contain no `Sort` or `Incremental Sort`, spill no
temp data, and finish below four seconds. Response cardinality, bytes, and
timeout remain bounded even though scanned rows grow with retained versions.

### `check_portal_projection_manifest.py`

Checks the committed Portal digests: the exact eleven-function stored-card
closure, the exact two-function narrow-facet closure, and the independent
selected-row context/decorator closure. It rejects later mutation of any
closure/control set, validates the four facet shards plus reconcile/cutover,
requires the context migration to add no table/index/trigger, and retains the
Flow eligibility index catalog guard without changing either #531 digest. It
also requires the Flow geography Search follow-up to remain a single
query-only kernel replacement with no table/index/trigger/writer rewrite. The
runtime path independently validates the Facet manifest before reading that
child projection.

The checker also freezes the Issue #563 three-step sequence: dormant immutable
rank helpers, one standalone concurrent partial expression GIN, and an atomic
coordinator cutover limited to multi-code-point, non-UUID, unfiltered Process
relevance. It requires the internal writer and `postgres` maintenance ACLs,
rejects any public wrapper/trigger/table rewrite, and protects the helper
closure from later mutation.

It also freezes the Issue #539 64-bucket exact-version child: table/PK, exact
facet FK with `ON UPDATE RESTRICT`/`ON DELETE CASCADE`, history-order index, and
sole `AFTER INSERT OR UPDATE` same-key upsert trigger. The public shard reader
must retain its index-ordered `DISTINCT ON (dataset_kind,id)` selection,
4,096-item/2-MiB/four-second bounds, and explicit history-density plan gate.
The `134103` forward repair must atomically lock the facet writer, build and
fully backfill the shadow child, replace the assertion/reader, and retire the
obsolete winner table/helpers. Shard cursor bytes must equal a fresh encoding
of the exact expected object, so JSONB-equivalent numeric scales such as `1.0`
and `64.0` are rejected. The retained sitemap façade remains byte-identical.

```bash
python3 scripts/check_portal_projection_manifest.py
```

### `check_portal_card_schema_parity.py`

Fails unless lexical Search and Hybrid candidate items have byte-identical,
exhaustive card properties outside their versioned `match` objects and both
reference the exact five-field `PublicCardContext` definition.

```bash
python3 scripts/check_portal_card_schema_parity.py
```

### `resolve_migration_head.py`

Prints the latest valid migration version from the checked-out
`supabase/migrations` directory. It rejects an empty directory, malformed SQL
migration names, and duplicate 14-digit versions so hosted verification cannot
silently select an ambiguous head.

```bash
python scripts/resolve_migration_head.py
```

Run its regression suite with:

```bash
python scripts/test_resolve_migration_head.py
```

### `test_supabase_dev_workflow_contract.py`

Fails closed unless `.github/workflows/supabase-dev.yml` keeps two isolated
hosted paths. The push-only persistent-Dev job must link the configured Dev
project, run exactly one `supabase db push --include-all`, derive its migration
head, and apply exactly one three-field PostgREST PATCH. The pull-request-only
Preview job skips forks and first validates the event base/head commits plus
the exact deployable-input allowlist: config, migrations, root/extra seeds,
and Functions. Workspace, tests, Auth templates, and docs are excluded. A
zero-diff PR emits `required=false` and performs no hosted Preview work. Any
allowlisted change still fails when its access token, main-parent ref, or
persistent-Dev ref is absent, then binds one
successful check from the exact official Supabase App/head to a unique
non-default, non-persistent `branches list` row for the same Git branch, PR
number, and parent. The check ref and BranchResponse ref must match and differ
from both main and Dev before the Preview's one identical PATCH/readback.

The contract also requires one separate no-reveal Management API key read using
the raw `disabled` state and exact public-key shape. Only a masked enabled
publishable or legacy anon key crosses into the next step; raw JSON and PAT are
cleared first. The anonymous Hybrid step itself may contain no PAT,
`Authorization`, `Cookie`, or service credential. Across the workflow, the only
Management API mutations are the one persistent-Dev and one Preview PostgREST
PATCH; Functions commands, broad `config push`, pinned migration heads, and any
other mutation remain rejected.

The contract also requires failure diagnostics to emit only the HTTP status
and a shape-validated PostgREST/SQLSTATE code. It rejects raw response-body
printing; malformed or unexpected error envelopes must become `unclassified`.

The same anonymous credential boundary polls the sitemap manifest for no more
than 300 seconds, validates exactly 64 opaque descriptors, passes one cursor
byte-for-byte into the shard RPC, validates both exhaustive JSON Schemas, and
requires a forged cursor to return only the bounded `22023` envelope.

```bash
python scripts/test_supabase_dev_workflow_contract.py
```

### `data_migrations/tidas_schema_202606/runner.py`

Plans, applies, and validates the TIDAS schema 2026-06 JSON data remediation for remote database rows.

Usage:

```bash
python scripts/data_migrations/tidas_schema_202606/runner.py plan --environment dev --run-id tidas-schema-202606-dev --out _artifacts/tidas-schema-202606/dev-plan.jsonl --dry-run
```

See `scripts/data_migrations/tidas_schema_202606/README.md` for the complete command surface and safety notes.

### `data_migrations/root_reference_review_v2_local.sh`

Creates the local encrypted backup and performs the operator-controlled legacy
review migration for the Root/Reference Review v2 cutover.

The backup includes a full custom-format dump, a review-table dump, and only
affected rows from the seven business tables. It must be stored outside the Git
worktree. `apply` remains locked until the operator has completed an independent
restore check, verified a second local copy, and generated the dry-run manifest.

Usage:

```bash
DATABASE_URL='postgresql://...' \
REVIEW_BACKUP_PASSWORD_FILE='<absolute-path-to-local-password-file>' \
scripts/data_migrations/root_reference_review_v2_local.sh backup \
  '/absolute/path/review-v2-backup'

DATABASE_URL='postgresql://...' \
scripts/data_migrations/root_reference_review_v2_local.sh dry-run \
  '/absolute/path/review-v2-backup'

DATABASE_URL='postgresql://...' \
scripts/data_migrations/root_reference_review_v2_local.sh verify \
  '/absolute/path/review-v2-backup'

DATABASE_URL='postgresql://...' \
scripts/data_migrations/root_reference_review_v2_local.sh apply \
  '/absolute/path/review-v2-backup'
```

The operator must create `RESTORE_VERIFIED` and
`SECOND_LOCAL_COPY_VERIFIED` only after those checks actually pass. Never
commit the password file, encrypted backup, markers, or migration manifest.

### `export_remote_schema.py`

Exports the target remote database schema to:

- `supabase/workspace/remote_schema.sql`

Usage:

```bash
python scripts/export_remote_schema.py --environment dev
```

Notes:

- Default environment: `dev`
- Default schema list: `public`
- You can override the destination with `--schema-file`
- `--environment local` without `--db-url` uses Supabase CLI `db dump --local`; an explicit `--db-url` still uses that URL

### `build_schema_workspace.py`

Refreshes the human-readable schema workspace under:

- `supabase/workspace/remote_schema.sql`
- `supabase/workspace/global/`
- `supabase/workspace/schemas/`

Usage:

```bash
python scripts/build_schema_workspace.py --environment dev
```

For an exact local migration-state reconstruction:

```bash
python scripts/build_schema_workspace.py --environment local
```

Behavior:

- Exports the latest remote schema first
- Canonicalizes trailing whitespace in the generated SQL view for deterministic review diffs
- Rebuilds `global/` and `schemas/`
- Preserves `supabase/workspace/README.md`
- Preserves `supabase/workspace/README.zh-CN.md`
- Preserves `supabase/workspace/changes/`

Warnings:

- Manual edits inside `remote_schema.sql`, `global/`, and `schemas/` are not stable
- Refresh can overwrite uncommitted Git changes in generated workspace files
- If you want `--git-changes` to reflect only later hand edits, commit the refreshed `supabase/workspace/schemas` to Git after syncing the remote database and before editing files.
- Remote `dev` remains the canonical generated-schema target. A schema-changing PR may commit an exact-local review snapshot after a blank migration rebuild, targeted contract tests, and a second deterministic regeneration show no drift. After merge, the database-only Dev deployment must reach the exact head, hosted catalog checks must pass, and a remote-Dev refresh must be compared with the review snapshot; commit any resulting drift as a follow-up.

### `build_database_types.py`

Generates the checked-in TypeScript contract for the two schemas exposed through the Data API: `public` and `api`.

```bash
python scripts/build_database_types.py --environment local
```

Use `--environment linked` only when the linked Supabase target is intentionally the source. CI regenerates the local contract and fails when `supabase/workspace/database.types.ts` drifts.

This script resolves the repository's own Supabase target and accepts no workdir or database-URL
override. To regenerate the same contract from an isolated task workdir, use the equivalent CLI
form and install its output mechanically, preserving the generator's `rstrip()` + trailing
newline handling:

```bash
supabase gen types typescript --local --workdir <isolated-workdir> --schema public --schema api
```

### `build_portal_contract_types.py`

Generates one committed TypeScript module per exhaustive Portal JSON Schema.
The repository has no Node package manifest, so the script follows the existing
CI dependency policy and invokes exact-pinned
`json-schema-to-typescript@15.0.4` through `npx`.

```bash
python3 scripts/build_portal_contract_types.py
python3 scripts/build_portal_contract_types.py --check
```

Normal generation synchronizes `contracts/portal/generated/*.d.ts` with the
sorted `contracts/portal/*.schema.json` source set. `--check` renders into a
temporary directory and fails on missing, changed, or unexpected generated
modules without modifying the checkout. CI uses the read-only check.

### `check_generated_workspace_legacy_tables.py`

Checks that generated schema workspace output no longer advertises retired public legacy job tables:

- `public.lca_jobs`
- `public.lca_package_jobs`
- `public.dataset_review_submit_jobs`

Usage:

```bash
python scripts/check_generated_workspace_legacy_tables.py
```

Use this after refreshing `supabase/workspace/**` from a remote branch where the `worker_jobs` cutover and legacy table retirement migrations have applied.

### `copy_workspace_file_to_changes.py`

Copies files from generated workspace content into the stable manual-edit area:

- from `supabase/workspace/schemas/...`
- to `supabase/workspace/changes/...`

Usage:

```bash
python scripts/copy_workspace_file_to_changes.py --source-path "supabase/workspace/schemas/public/tables/comments/table.sql"
```

```bash
python scripts/copy_workspace_file_to_changes.py --source-path "supabase/workspace/schemas/public/tables/comments"
```

```bash
python scripts/copy_workspace_file_to_changes.py --git-changes
```

Behavior:

- Preserves relative paths
- Supports a single file or a directory
- `--git-changes` copies every uncommitted file currently detected under `supabase/workspace/schemas`
- Recommended workflow: refresh the workspace, commit the generated `supabase/workspace/schemas` state to Git, then edit files and use `--git-changes`

### `new_migration.py`

Generates a migration SQL file from a supported schema object file under:

- `supabase/model/schemas/...`
- `supabase/workspace/changes/...`

Usage:

```bash
python scripts/new_migration.py --name "update policy roles update" --source-path "supabase/workspace/changes/public/functions/policy_roles_update/definition.sql"
```

Output:

- `supabase/migrations/<timestamp>_<slug>.sql`

Currently supported source path shapes:

- `functions/<name>/definition.sql`
- `views/<name>/definition.sql`
- `materialized_views/<name>/definition.sql`
- `tables/<table>/policies/<name>.sql`
- `tables/<table>/triggers/<name>.sql`

Not currently supported:

- `table.sql`
- indexes
- sequences
- schema-level SQL
- other generated workspace files

### `_db_workflow.py`

Internal shared module used by the scripts above.

It is not intended to be the primary entry point for routine command-line use.

### `test_scope_closure_staged_write_set_v2_fixture.sh`

Validates the byte-shared Worker/database staged write-set v2 fixture, including
canonical JSON, descriptor-set SHA-256, bounded batch limits, status-field
opacity, state transitions, and the retained one-shot compatibility window.

Usage:

```bash
scripts/test_scope_closure_staged_write_set_v2_fixture.sh
```

This is a read-only local contract check. It does not refresh generated schema
workspace files or connect to a remote database.

### Scope-closure provider qualification adapters

`run_scope_closure_database_qualification.sh` and
`run_scope_closure_storage_qualification.sh` emit the exact
`lcia.scope-closure-provider-owned-result.v1` records consumed by the Worker
provider aggregator. Both adapters require a Worker-supplied `--run-id`, bind
`componentSha` to the checked-out database-engine commit, accept either
loopback targets or positively allowlisted non-production target fingerprints,
reject production or ambiguous targets, and emit `productionMutation=false`.

The database adapter runs the #308/#316 pgTAP contracts against the explicit
`QUALIFICATION_DATABASE_URL`. The storage adapter uses an explicit
S3-compatible endpoint, bounded generated files, live and expired signed
HEAD/range requests, multipart boundaries, retries, and exact-prefix garbage
collection.
Neither adapter writes credentials, object locators, signed URLs, or payload
contents to its result.

Under exact Worker commit `e5a7f769`, loopback execution is protocol,
fault-injection, and adapter evidence only. It is not the final
provider-specific non-production qualification. Run that later with the same
owner adapters after Worker #188 supplies verified non-production target
classification; ambiguous or production targets must still fail closed.

Usage:

```bash
scripts/run_scope_closure_database_qualification.sh \
  --output <new-result-path> \
  --run-id <worker-supplied-uuid>

scripts/run_scope_closure_storage_qualification.sh \
  --output <new-result-path> \
  --run-id <same-worker-supplied-uuid>
```

Required environment variables are intentionally qualification-scoped:

- both adapters: `QUALIFICATION_NON_PRODUCTION_CONFIRMATION`
- database: `QUALIFICATION_DATABASE_URL`, `QUALIFICATION_SUPABASE_URL`,
  `QUALIFICATION_SUPABASE_SERVICE_ROLE_KEY`
- storage: `QUALIFICATION_DATABASE_URL`, `QUALIFICATION_S3_ENDPOINT`,
  `QUALIFICATION_S3_ACCESS_KEY_ID`,
  `QUALIFICATION_S3_SECRET_ACCESS_KEY`, `QUALIFICATION_S3_BUCKET`, and optional
  `QUALIFICATION_S3_REGION`
- non-loopback targets: `QUALIFICATION_VERIFIED_NON_PRODUCTION_FINGERPRINTS`,
  containing the exact comma-separated SHA-256 target identities approved by
  the qualification coordinator; remote database and provider endpoints must
  use TLS

Feed both records to the exact Worker compatibility verifier without adapting
their schema:

```bash
scripts/verify_scope_closure_worker_aggregator.py \
  --worker-repo <worker-checkout-containing-e5a7f769> \
  <database-result> <storage-result>
```

Run the offline control-flow and safety regressions with:

```bash
python3 -m unittest scripts/test_scope_closure_provider_qualification.py
```

## Local Docpact Push Gate

The repository now includes a local pre-push docpact gate in `scripts/docpact-gate.sh`. The gate resolves the CLI through `scripts/docpact`. It is documentation-governance tooling and does not change database schema workspace behavior.

## Portal navigation tooling

`python3 scripts/generate_portal_navigation_vocabulary.py --check` verifies the offline, receipted vocabulary without modifying generated artifacts. Omit `--check` and pass `--seed-dir supabase/migrations` to regenerate an intentionally reviewed source change. `--vendor --platform-root <path> --archive-locations <path>` refreshes source copies only after exact platform-commit verification; this is separate from ordinary builds. Source receipts, schemas, types and seed migrations must be reviewed together.

Later hierarchy changes must use `data/portal-navigation-revisions.json`; generation verifies the original seed bytes and emits only the new CLI-created revision. `python3 scripts/test_portal_navigation_revisions.py` checks the source-backed bindings and revision boundary. `python3 scripts/test_portal_china_navigation_upgrade.py --local-container supabase_db_database-engine-662-isolated` requires an empty, uniquely named local project initialized from the pre-revision base. It creates 160 synthetic public versions, applies the revision to committed old memberships, proves exact counts and unchanged source rows, then removes its fixtures. It rejects hosted Docker contexts and nonempty sources; reset that disposable project to the full migration history afterwards.

`python3 scripts/benchmark_portal_summary_bounded.py --help` describes the explicitly local, rollback-only performance fixture. It refuses remote Docker contexts and nonempty public projections. Read-scale results do not qualify production latency or source-writer throughput.

`python3 scripts/check_portal_json_schemas.py` compiles every Portal schema in strict Draft 2020-12 mode with all sibling references registered. It uses the pinned existing AJV CLI/format versions and excludes each root from its own reference list, avoiding both filename-order dependency and duplicate IDs. It changes no schemas.

### `benchmark_portal_catalog_bounded.py`

Runs a rollback-only, same-fixture comparison of retained and candidate Portal
readers. It rejects hosted Docker contexts, nonempty projections and names outside
`supabase_db_database-engine-723-*`. The fixture has two versions per dataset and
configurable summary width; direct projection seeding is read-scale evidence,
while the SQL suite independently exercises real writers. Reports include exact
response hashes, predecessor-issued continuation, cutover guard fault injection,
timings and aggregate buffer/temporary-I/O plans. Name sorting remains a measured
matched-name read, not a bounded-card-access claim.

```bash
python3 scripts/benchmark_portal_catalog_bounded.py \
  --container supabase_db_database-engine-723-isolated \
  --process-datasets 9000 --flow-datasets 55000 --card-padding 2048 \
  --samples 5 --report /tmp/portal-catalog-serial.json
```

### `profile_portal_catalog_concurrency.py`

Uses the exact candidate/fixture bound by a successful serial report. It requires
an empty explicitly isolated local database. Rebuild that owned project after
the serial profile so rollback-created physical pages do not affect the next
fixture. The command commits only synthetic fixture rows
so separate connections can share them, and runs the predecessor and candidate
at the requested bounded concurrency. It restores candidate readers even on
failure and writes a disposition receipt. Unlike the serial benchmark, rows are
retained for inspection: reset that owned project after recording the result.

```bash
python3 scripts/profile_portal_catalog_concurrency.py \
  --container supabase_db_database-engine-723-isolated \
  --reference-report /tmp/portal-catalog-serial.json \
  --concurrency 4 --requests 24 --report /tmp/portal-catalog-concurrent.json
```

Neither command accepts a hosted URL or raises public execution budgets. See
`docs/agents/repo-validation.md` for required semantic and release proof.
