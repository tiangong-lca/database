---
title: database-engine Repo Validation Guide
docType: guide
scope: repo
status: active
authoritative: false
owner: database-engine
language: en
whenToUse:
  - when a database-engine change is ready for local validation
  - when deciding the minimum proof required for migration, config, workflow, script, or docs changes
  - when writing PR validation notes for database-engine work
  - when validating a Portal public DTO, RPC, capability, Hybrid search, Exchange, or LCIA projection
whenToUpdate:
  - when the repo gains a new canonical validation command or wrapper
  - when change categories require different minimum checks
  - when schema-workspace tooling or branch operations change
checkPaths:
  - docs/agents/repo-validation.md
  - .docpact/config.yaml
  - contracts/portal/**
  - supabase/config.toml
  - supabase/migrations/**
  - supabase/tests/**
  - supabase/templates/**
  - supabase/seed.sql
  - supabase/seeds/**
  - scripts/**
  - .github/workflows/supabase-dev.yml
  - .github/workflows/ai-doc-lint.yml
  - .githooks/pre-push
  - scripts/docpact
  - scripts/docpact-gate.sh
  - scripts/install-git-hooks.sh
lastReviewedAt: 2026-09-23
lastReviewedCommit: 15afe29391b0ec3b44602a64bc769b8851583c1f
lastReviewedNote: "Reviewed for Database #670 with workspace #1432: adds the guarded atomic owner-draft before-content save proof row (SQL suite plus the two-session concurrency runner); existing change-type rows and deployment boundaries are unchanged. Reviewed for Database #673 (Foundry #60) with workspace #1432: adds the Time alias v2 wire RED baseline under supabase/tests; it pins the frozen v1 surface and its v2-payload refusal and asserts the not-yet-implemented v2 contract surface, so no rule, proof bar, branch or capability semantics change. Reviewed for Database #673 (Foundry #60) with workspace #1432: the guarded v2 batch executor is now real behaviour GREEN on the isolated stack — closed envelope (counts, target snapshots and source evidence read and bound), Product-flow eligibility, the deployed five-key reference derived from the target's own common:name object, the functional-unit mutation bound to the process's reference-flow exchange, an exact replay that writes nothing, and a write-pass failure that rolls rows and audit back; the private-function inventory pin learns the fourteen v2 helpers. No governed rule, proof bar, branch or capability semantics change. Reviewed for Database #673 (Foundry #60) with workspace #1432: the v2 batch executor now binds the functional unit through the real source-number namespace (TIDAS internal ids versus original EcoSpold source numbers) — the reference exchange is bound by internal id, the functional unit by that exchange's reviewed source number, the leading quantity must equal the exchange's own source quantity, and a claim contradicting the stored reviewed source comment is an evidence mismatch; the real-shape fixture (internal 1/source 730045/quantity 1 plus internal 2/source 730046/1.03E-4) proves different source numbers pass while every mis-binding is refused, 60/60 GREEN. No governed rule, proof bar, branch or capability semantics change. Reviewed for Database #673 (Foundry #60) with workspace #1432: the v2 executors are aligned with the shared CLI cohort contract (claimed canonical digests verified server-side, source_flowproperty, the full five-key reference in the flow mutation, quantitative_reference and four amount fields per exchange entry, the text_actions block as the functional-unit authority, amount_field_count, the source unit-group snapshot) and the new guarded v2 plan executor validates the shared plan envelope, assembles the one batch it executes and keeps a replay-safe whole-plan summary; 75 behaviour assertions GREEN. No governed rule, proof bar, branch or capability semantics change. Reviewed for Database #673 (Foundry #60) with workspace #1432: root's final expected-count and derivative-target semantics are adopted — the plan carries the ten flat v1 expected keys plus the versioned text_action_count, the audit count must match the row+batch+plan audit topology actually written, the six-key derivative targets must be one per changed identity with the exact actor and owner-draft state, and the source unit-group snapshot is documented as the source alias's current declared unit group (the historical hr record is provenance only); 81 behaviour assertions GREEN. No governed rule, proof bar, branch or capability semantics change. Reviewed for Database #673 (Foundry #60) with workspace #1432: the versioned protected lifecycle is added against the current post-cutover surface — api.cmd_dataset_alias_execution_{preflight,gate,admit}_v2_guarded, _read_v2 and the service-only _execute_v2 with its CLI-ALIAS-02 capability rows, the v2 receipt/request/preflight tables in util, the preserved 180-second gate window, five-key admission, single-attempt dispatch and nonce-bound callback, and plan-derived expectations; the historical public.command_audit_log references follow the cutover into private, the frozen contract suite passes fully (14/14) and v1 stays byte-identical. No governed rule, proof bar, branch or capability semantics change beyond the additive versioned surface. Reviewed for Database #673 (Foundry #60) with workspace #1432: the v2 protected preflight and gate are plan-derived end to end after converting the last copied v1 cohort pins (declared target count and per-table split, plan-derived simulation/gate material and responses, the gate's stored-plan reference); a live local preflight plus all three gates now pass on real rows with stored receipts. The protected behaviour matrix suite is parked outside the tree while its admit helper is repaired. No governed rule, proof bar, branch or capability semantics change. Reviewed for Database #673 (Foundry #60) with workspace #1432: the versioned protected boundary now accepts the reviewed CLI's real wire — the plan-request and derivative-set digests follow the producer's own definitions, the expected freeze and approval are the producer's thirteen and fourteen key envelopes, the protected expected block is the versioned eleven-key claim block, the alias identity digest binds the {id, version} tuple, the Flow property collection decodes in either deployed shape, and the executor and read paths carry plan-derived audit and derivative counts instead of the v1 cohort constants; the parked manual fixture is replaced by a conformance suite built from the CLI's own request document that drives preflight, the three gates, admission, the service-only executor and the readback, and pins the refusals around them (61/61). The private-inventory pin learns one more v2 helper (396) and the api contract-closure migration-head pin advances to 20260921190000. No governed rule, proof bar, branch or capability semantics change. Reviewed for Database #673 (Foundry #60) with workspace #1432: the five versioned Time-alias v2 suites (math, decimal parity vectors, frozen contract, batch/plan behaviour, protected lifecycle conformance) are now part of the required local-contract selection in .github/workflows/supabase-dev.yml and of the workflow contract test's pinned tokens, and the generated schema workspace and Data API types were regenerated with the CI-pinned Supabase CLI 2.117.0 and re-generated deterministically. Deployment boundaries, routing, ownership and the branch policy are unchanged; no historical suite was swept into the selection. Reviewed again for Database #673 (Foundry #60) with workspace #1432: the four support reads now enforce the same-owner/public reference boundary under the same lock (a support row is admitted only when it is a published state-100 row or a state-0 row owned by the authenticated plan actor), and the approved derivative target set is orchestrated by the new unpublished v2 coordinator as a deterministic cover of sub-batches of at most fifty, admitted atomically with the primary write and read back as one aggregate with exact membership; the private inventory pin learns the partition helper (397) and the generated schema workspace was regenerated deterministically with the CI-pinned CLI. No governed rule, proof bar, branch or capability semantics change.Reviewed for Database #677 (Foundry #60) with workspace #1432: the OAuth authorization proof row gains the CLI-ALIAS-02 capability suite, the populated Issue #677 grant upgrade harness (zero-match no-op, unique selection, exact before/after, single audit, idempotent rerun, ambiguity rollback, unrelated clients unchanged), and the real PostgREST routing probe that binds the client_id-bearing denial, the application null-request refusal and the explicit api content profile to actual HTTP status codes. Existing change-type rows and deployment boundaries are unchanged.Reviewed again for Database #674 (Foundry #186) with workspace #1432: the closed Length*time kmy-to-m*a profile lands as a second explicit profile over the reviewed protected lifecycle, selected only by the plan's own schema_version through one closed internal discriminator; the Time profile, its factor, its mandatory flow action, its alias-property closure and its ALIAS_V2_* codes are unchanged, no business-data column is added, and the generated schema workspace and Data API types were regenerated deterministically with the CI-pinned Supabase CLI. No governed rule, proof bar, branch, routing or generated-path ownership changes. Reviewed for Database #680 with workspace #1432: adds the Time-alias v2 protected lifecycle/closure proof row naming the focused current-closure suite with its drift, restored-snapshot, unrelated-consumer and public-read boundary expectations; existing change-type rows and deployment boundaries are unchanged. The pre-write batch predicate and the fresh-read predicate carry the same identity guard.Reviewed for Database #686 with workspace #1432: the selected local contract learns the candidate-driven occurrence closure — the v2 batch suite carries extra occurrence-refusal cases for a foreign-owner, another-owner and the actor's own unclaimed occurrence plus the one deliberate malformed-collection difference, the migration-head pin advances to 20260922190000, and no existing validation command, change-type row or deployment boundary changes.Reviewed for Database #689 with workspace #1432: the selected local contract is unchanged; the derivative batch suite gains eight predicate pins for the byte pre-filter (the matcher's original predicate (verbatim, escaped-id, ordinary-escape, decoy, literal backslash-u prose, NULL-id and missing-record-id NULL semantics) and the cached quarantine row effects over real queued dispatch bodies (single, shared-array ordering, wrong version, unrelated URL, post-snapshot insert, ctid rewrite and late-failure rollback)) and the migration-head pin advances to 20260922200000, with no existing validation command, change-type row or deployment boundary changing.Reviewed for Database #694 with workspace #1432: the canonical JS object-key sort key gains a pure-ASCII fast path written under the explicit C collation, with the published per-character loop kept verbatim as the fallback for every non-ASCII value and for the empty key, so the array-index branch, the UTF-16 and surrogate arithmetic, the two sort-key prefixes, the declared volatility, the pinned search_path and the ACLs are unchanged; the guarded Time v2 batch executor stops recomputing two payload digests for its row audit and its replay proof and instead reuses the producer's before_sha256 and desired_sha256, which the untouched structural parity guard has already proved equal to the server canonical digests of the claimed before payload and of the server-derived payload that is committed, the two verified digests riding only in the internal prepared envelope, which is never hashed, never returned and never shape-validated. The selected local contract gains the new canonical key-hash oracle suite and the workflow contract test pins its invocation token; the Time v2 batch suite gains the row audit digest-exactness pins and two well-formed-but-wrong claimed digests that must be refused with zero effect; the migration-head pin advances to 20260922210000, with no existing validation command, change-type row or deployment boundary changing."
related:
  - ../../AGENTS.md
  - ../../.docpact/config.yaml
  - ./repo-architecture.md
  - ./supabase-branching.md
---

## Validation Order

1. identify the change type
2. run the minimum proof for that change type
3. add stronger proof only when the risk actually increases
4. record exact commands, SQL files, and environments in the PR

## Default Baseline

Unless the change is doc-only repo-maintenance work, the baseline local commands are:

```bash
supabase start
supabase db reset
supabase migration list
```

There is no checked-in monolithic database-contract runner. Run the relevant
pgTAP files explicitly after a clean reset, and run the change-specific shell
or Node upgrade/transport harnesses named in the proof matrix. Workflows that
need Git provenance still check out full history (`fetch-depth: 0`).

The local contract job in `supabase-dev.yml` always runs the package capability,
ownership, bulk-refresh, selected-root-refresh, review-queue full-text-search,
TIDAS partial-import, example-dataset-scope, guarded owner-draft
before-content save, result-process-state-120,
result-process-lifecycle-protection, result-process-product-read-isolation, and
manager-attested-result-publication suites before hosted steps.

## Proof Matrix

| Change type | Minimum local proof | Stronger proof when risk is higher | Notes |
| --- | --- | --- | --- |
| `supabase/migrations/**` | `supabase db reset` succeeds | run the relevant SQL assertions under `supabase/tests/**`; inspect affected workspace objects if the migration was authored from workspace files | Record which migration and which SQL test files were exercised. |
| OAuth client registry, capability grants, or PostgREST pre-request authorization | `supabase db reset --no-seed`; run `supabase/tests/20260830_oauth_client_capability_foundation.sql`, `20260831_oauth_actor_command_capabilities.sql`, `20260806_api_contract_closure.sql`, and `20260805_full_schema_cutover.sql`; for an environment grant repair also run its populated upgrade harness, including `bash supabase/tests/upgrade/test_issue_638_oauth_cli_bundle_grant_upgrade.sh`; restart local Supabase before transport proof so the configured `public,api,graphql_public` schema list is active | with a locally signed test JWT containing `client_id`, prove an admitted relation read and representative create/save/delete command RPCs, reject raw table DML, an ungranted RPC, and a read-only-client mutation with SQLSTATE `42501`, then prove disabling the client invalidates prior access; repeat against exact Preview before persistent Dev | Supabase Auth owns OAuth client secrets and refresh tokens. Database state stores only public `client_id`, kind, enabled/revoked state, capability grants, and audit history. First-party sessions without `client_id` preserve existing `auth.uid()` behavior. Nine public relations require the read capability; raw table DML remains ACL-closed. Only the three actor-bound CRUD command RPCs use `DB-CORE-WRITE-01`; other first-party CLI commands use `CLI-RPC-01`. Both exact LifecycleModel bundle signatures must use `EDGE-BUNDLE-01`, and tests must reject any `CLI-RPC-01` fallback before the MCP client is admitted. The official Production CLI grant must be exactly `CLI-RPC-01`, `DB-CORE-READ-01`, `DB-CORE-WRITE-01`, `NX-CORE-02`, and `EDGE-BUNDLE-01`; provision or repair it only through `api.svc_oauth_client_configure` after an exact row lock, before-state check, and two-signature route-manifest check. A one-time automatic repair may select one client by the unique exact pre-change capability class, but must no-op on zero matches, fail closed on ambiguity, and never hardcode an environment client ID. Verify the exact after-state and one append-only audit event, then use the official CLI OAuth flow to create/read/update/read/delete one disposable LifecycleModel bundle without retaining identifiers or payloads in public evidence. The drift-repair migration must make every authenticated API ACL manifest-complete without changing ACLs or creating ambiguous overloads. Unknown routes fail closed, and the service-only configuration facade atomically replaces grants. Do not grant custom database access from OAuth scopes. |
| Auth identity/profile mirror Trigger or registered-user lookup | `supabase db reset --no-seed`; run the dedicated Auth profile synchronization pgTAP file plus the affected API contract and nearby identity-field regressions | rehearse a populated upgrade from the previous migration head with both an Auth-only identity and an existing private profile; prove backfill, metadata reconciliation, contact preservation, helper rename, and exactly one governed Trigger | `auth.users` remains authoritative. Prove insert/update/delete mirroring, an Auth-only lookup by normalized email, review-admin-only authorization, fixed empty helper `search_path`, no direct helper execution by application roles, and preserved RPC ACLs. The deferred Trigger must still synchronize before commit while remaining compatible with explicit same-transaction profile writes. |
| full application Schema cutover | `supabase db reset --no-seed`; run the `20260805`/`20260806` contract pgTAP files plus `20260807_data_product_consumer_facades.sql`; `scripts/test_full_schema_cutover_upgrade.sh` | restart local Supabase after config changes; prove explicit `public` core-table REST access, explicit `api` RPC access, rejection of `private`, and absence of the old `public` RPC route; on hosted Preview/persistent `dev`, also prove profile-less core access resolves to `public` after exact ordered Management API readback; repeat the populated upgrade against a production-shaped disposable copy before hosted deployment | Require the exact nine-table public allowlist, zero public routines/views/sequences, complete target placement, OID and exact-row preservation, trigger/policy/constraint parity, denial of internal Data API exposure, exact equality between external API grants and `private.api_capability_grants`, the exact authenticated `private.roles`/`private.reviews` read-only exception required by core-table RLS, bounded Data Product projections, stable TIDAS DTO/error behavior, a service-only boolean lifecycle review-admin predicate, and real traversal through each constrained façade family. When production has already recorded a later main hotfix, the populated upgrade must reproduce that ledger order, prove any older-version bridge is independently service-valid, and prove the same bridge is a strict no-op after cutover. Local Supabase may normalize custom schemas ahead of `public`, so local profile-less behavior is not hosted default-profile proof. Do not add compatibility views, duplicate tables, or dual-write paths. |
| Root/Reference Review schema, commands, or queue projections | `supabase db reset --no-seed`; run `supabase/tests/20260731_root_reference_review_v2.sql`, `20260802_root_grouped_review_queue.sql`, `20260809_rejected_reference_resubmission.sql`, `20260809_review_metadata_scope_basis.sql`, `20260812_reference_approval_scope_isolation.sql`, and `20260806_api_contract_closure.sql` | compare all six Admin/Member tabs on a production-shaped disposable copy; capture a bounded `EXPLAIN (ANALYZE, BUFFERS)` for representative queue cardinalities before hosted cutover | Review submission has no numerical-stability or upstream-completeness Gate. Prove seven-table state transitions, parallel active versions for the same table/id with exact version/checksum isolation, active/approved checksum reuse, unchanged rejected-revision re-entry, current JSON/submitted-Comment derivation, stale candidate rejection, Reviewer metadata draft/submission addition and revocation, isolated impacted-root lookup and Reference approval when unrelated Roots are incomplete, one-row-per-Root-or-Reference flat pagination/counts, and exact external grants. The v3 queues must apply `all`/model-process/other display modes and exact target-table filters before totals, ordering, and pagination; combined filters use intersection semantics, page size defaults to 50, and unsupported values fail closed. `private.reviews` must not contain scope snapshots or Root/Reference ID arrays; business `reviews[].id` contains Root candidates only; no rebind or history replay contract remains. Comment draft saves (`state_code = 0`) must persist only the editable draft and must not create Reference Reviews or append candidate Root hints; formal Comment submission must create or reuse Reference Reviews and append candidate Root hints for unpublished targets. The retained grouped v2 compatibility queues and child relationship query continue deriving only direct or candidate-hinted Roots; the v3 main queues never derive parent membership. |
| Review queue lexical search | Run the Root/Reference baseline above plus `supabase/tests/20260909_review_queue_full_text_search.sql` and `20260811_search_text_source_switch.sql` after reset | Run rollback-only `supabase/tests/benchmarks/20260909_review_queue_search.sql` on an isolated local database; repeat against a production-shaped disposable copy before hosted cutover | V4 preserves empty-query V3 behavior and exact table/id/version identity. Prove all seven types, six tabs, Root/Reference independence, ACL/manifest closure, UUID, multilingual and per-family lexical parity, missing projection, combined filters and count-before-page. Record natural PGroonga plans and distinguish synthetic warm timings from hosted performance. |
| process/flow hybrid-search query shape, HNSW settings, executor role, or vector indexes | `supabase db reset`; run `supabase/tests/20260727_hybrid_search_staging_plan_governance.sql`, `supabase/tests/20260528_semantic_hybrid_candidate_helpers.sql`, `supabase/tests/20260528_hybrid_semantic_candidate_limit_hotfix.sql`, `supabase/tests/20260903_portal_flow_adaptive_semantic_v2.sql`, `supabase/tests/20260904_portal_flow_semantic_executor_alignment.sql`, `supabase/tests/20260905_portal_process_adaptive_semantic_v2.sql`, `supabase/tests/20260905_portal_process_semantic_executor_alignment.sql`, and `supabase/tests/20260905_next_hybrid_filter_adaptive_v2.sql`; for version-aware Portal changes also run `supabase/tests/20260902_portal_version_search_v2.sql` | Run the rollback-only Next profile with `node scripts/benchmark_next_hybrid_v2.mjs --local-container <isolated-database-624-container>`. After the migration reaches persistent `dev`, run the exact read-only `supabase/tests/benchmarks/20260727_hybrid_search_staging_explain.sql` profile against ref `submidrhbtknjxfympna`; compare process, broad-flow, Product-flow, and full-RPC timings/buffers with Issue #292; for adaptive Process or Flow V2, compare cold and warm buffers/timings for zero, small, cutoff, cutoff-plus-one, and broad candidate sets without changing the session's production-equivalent HNSW settings; rerun performance and security advisors | Use the benchmark's checked-in Edge route lexical parameter profile with its redacted real staging vectors; never synthesize lexical terms from the first Markdown tokens because shared headings create an artificial near-whole-table match. Do not use a seed-only Preview as production-cardinality proof, expose raw text/UUID/vector values, or run production `EXPLAIN ANALYZE`. Empty JSON filters must fold away under a custom plan. General and broad Process/Flow paths retain strict-order iterative HNSW with one 10x semantic bound and a 200-row floor. Version-aware Portal geography/access-level and authenticated Next canonical filters may route to exact distance evaluation only after a bounded 2,001-key probe proves at most 2,000 exact-version candidates; prove zero-match behavior, both sides of the cutoff, complete source-table filter/RLS recheck before output, exact-version identity, deterministic ordering, stable result digests, and no duplicate vector index. A Next public candidate projection may contain only public-state search keys, must have no external grant or embedding, and is never an authorization or hydration source. Executor changes must prove the applicable public executor remains NOLOGIN/NOINHERIT/NOBYPASSRLS under exact public-state policies, the internal caller remains admitted, and external roles remain denied. `my` and `te` stay JWT/team-bound on authenticated RLS. |
| Contact, FlowProperty, Source, or UnitGroup Semantic/Hybrid pipeline, RPC, or HNSW index | `supabase db reset`; run `supabase/tests/20260727_foundation_dataset_semantic_hybrid_search.sql`, `supabase/tests/20260514_embedding_derivative_trigger_scope.sql`, `supabase/tests/20260727_hybrid_search_staging_plan_governance.sql`, `supabase/tests/20260528_semantic_hybrid_candidate_helpers.sql`, and `supabase/tests/20260528_hybrid_semantic_candidate_limit_hotfix.sql` | on the exact Preview branch, run bounded cursor backfill pages and drain both extraction and embedding queues; prove zero terminal failures and full eligible-row derivative counts; smoke `tg`/`co` explicit-team scope, `my` explicit-state scope, `te` explicit-readable-team plus state scope, and missing/foreign-team fail-closed behavior; after merge to persistent `dev`, capture redacted real-parameter `EXPLAIN (ANALYZE, BUFFERS)` for Semantic and Hybrid queries across all four datasets, compare timings/buffers, then rerun performance and security advisors | Never do a synchronous whole-table migration rewrite. Backfill is service-only, capped at 500 rows, idempotent, and uses compact queue payloads. A blank-version row is ineligible because it has no stable worker identity: count it as a data-quality exception and never guess a version or enqueue it. Helpers require exact table/RPC allowlists, `tg`/`co`/`my`/`te` visibility, PGroonga escaping, custom plans, and strict-order HNSW scans; derivative writes must not change authored `modified_at`. Team Data requires an explicit team readable by the authenticated actor. A small table may correctly choose a sequential scan. Do not run production `EXPLAIN ANALYZE` or retain raw vectors, search text, IDs, or private row values in evidence. |
| Database A `search_text` expand, canonical Search RPCs, or bounded replay enqueue | `supabase db reset --no-seed`; run `scripts/test_search_text_array_upgrade.sh`, `supabase/tests/20260810_search_text_expand_and_canonical_search_rpcs.sql`, `supabase/tests/20260810_search_text_array_and_review_guard.sql`, `supabase/tests/20260731_flow_identity_derivative_fence.sql`, `supabase/tests/20260729_extracted_md_lexical_search_contract_v2.sql`, `supabase/tests/20260613_hybrid_search_query_terms_escape.sql`, and `supabase/tests/20260806_api_contract_closure.sql`; run `python scripts/build_schema_workspace.py --environment local --schemas public api private util archive` and `python scripts/build_database_types.py --environment local`, then require `git diff --exit-code -- supabase/workspace` | on the exact Preview branch, confirm the migration applies and the generated-workspace/type-drift CI gate is green; record any service-role ACL change in the Issue and PR | Database A keeps all seven `search_text` columns nullable `text[]` values with no default. The production upgrade requires the additive scalar columns to remain empty and dependency-free, then replaces them without rewriting the seven table heaps; it fails before changing any column when that contract has drifted. The later backfill writes the complete projection. State 20/100 rows permit only `extracted_md`, `search_text`, `embedding_ft`, and `embedding_ft_at` outside the review-controlled command context, while derived updates do not advance authored `modified_at`; existing anon/authenticated table-write revocations remain the boundary. Flow treats the same four fields as guard-neutral, and the canonical RPCs have exact no-overload signatures with manifest-matched ACLs. Formal hybrid filters are `jsonb`; formal `page_size` and `page_current` are `integer`; text/bigint conversion stays at the existing private boundary. Database A provides only bounded enqueue: historical backfill is the workspace#565-coordinated Release 1 operational gate after Edge double-write deployment and is never run by this migration. Database B owns the index/source switch, Database C old-index cleanup, and Database D old-RPC cleanup. |
| Database B `search_text` lexical source switch or PGroonga cutover gate | `supabase db reset`; run `supabase/tests/20260811_search_text_source_switch.sql` plus the adjacent Search/Hybrid regressions; verify all seven new indexes are valid, ready, live, single-column, explicitly opclassed, and configured for TokenBigram/NormalizerAuto; prove the array-boundary and newline counterexamples, multilingual and UUID terms, grant-free gate behavior, and a selective 20,000-row `EXPLAIN (ANALYZE, BUFFERS)` that names the new index; regenerate `supabase/workspace` and `database.types.ts` from the exact local state and prove deterministic no-drift | before any persistent-Dev migration application, deploy Edge array writes, prove 100% eligible-row non-NULL coverage and zero terminal derivative failures, and run remote catalog plus read-only smoke checks; only then may the source switch be considered for cutover | The migration changes only the lexical source from `extracted_md` to `search_text` and preserves permissions, visibility, filters, ordering, pagination, ranking, UUID fast paths, wrappers, and old extracted_md indexes/RPCs. The gate distinguishes an empty fresh database (allowed) from an existing database with any missing projection (SQLSTATE `55006`, blocked). Do not claim performance from `enable_seqscan = off` or a tiny table, and do not use array position as ranking weight. |
| Process Search actor-draft or Hybrid/Search lexical contract | `supabase db reset`; run `supabase/tests/20260730_extracted_text_and_embedding_flag_retirement.sql`, `supabase/tests/20260613_hybrid_search_query_terms_escape.sql`, `supabase/tests/20260727_foundation_dataset_semantic_hybrid_search.sql`, and `supabase/tests/20260729_extracted_md_lexical_search_contract_v2.sql` plus the nearby semantic/HNSW and guarded-rebuild regressions | on the exact Preview branch, smoke all seven v2 Hybrid RPCs and `search_processes_latest_v2`; for `owner_draft_only`, cover actor-owned state-zero rows with null and non-null team/review workflow metadata and prove non-owner/non-zero rows remain excluded | `owner_draft_only` is an actor-plus-state calculation filter: `team_id` and `review_id` are workflow metadata, not ownership gates. Search uses the current `search_text` PGroonga source. A PGroonga index may still appear as `unused_index` with `idx_scan = 0` after use; require a direct `EXPLAIN (ANALYZE, BUFFERS)` naming the index before classifying or dropping it. |
| embedding queue selector or per-scope backpressure | `supabase db reset`; run `supabase/tests/20260728_embedding_queue_selector_plan_governance.sql` and `supabase/tests/20260525_embedding_backpressure_and_deferred_queue.sql` | on persistent `dev`, capture a redacted real-queue `EXPLAIN (ANALYZE, BUFFERS)` before and after the append-only migration; prove the visible queue is scanned once, policy is resolved once per distinct scope, active counts are aggregated once per scope, terminal failures stay zero, and the queue drains under the checked-in policy defaults | Never correlate a full active-queue count with every visible job. Preserve retry ordering, stale-job cleanup, per-scope admission, and the default `max_in_flight` values. Any temporary staging-only policy ramp must be bounded, monitored for HTTP/queue failures, and restored before handoff; do not use higher concurrency to hide selector cost. |
| Performance Advisor index or table-bloat governance | `supabase db reset`; run `supabase/tests/20260608_missing_fk_support_indexes.sql` and any affected domain regression | run `supabase db lint --level warning`; compare the relevant Performance Advisor notices on Preview and persistent `dev`; for physical compaction, follow the hooks maintenance-window procedure below | An unused-index notice alone is not permission to drop HNSW, GIN, PGroonga, FK-supporting, or other workload-sensitive indexes. `VACUUM FULL` is never part of the automatic migration path. |
| guarded atomic owner-draft FP/UG alias primitive | `supabase db reset`; run `supabase/tests/20260711_guarded_dataset_alias_batch.sql` and the legacy `supabase/tests/20260404_dataset_command_rpcs.sql` | prove both the replay-capable whole-plan function and per-dimension executor have no API grants; exercise them only through postgres-owned test wrappers; retain the exact `dataset-alias-plan.v1` envelope, ordered time plus length-time batches, 25-row/20-exchange and 27-row/39-exchange scopes, public/foreign rejection, exact factors, live closure, hashes, and all-or-nothing audit proof | This is an internal mutation primitive after protected cutover. It never publishes or changes `state_code`; direct authenticated and service-role execution remains revoked. |
| protected one-shot owner-draft FP/UG execution | `supabase db reset`; run `supabase/tests/20260715_protected_dataset_alias_execution.sql`, `supabase/tests/20260711_guarded_dataset_alias_batch.sql`, both derivative rebuild suites, and the rollback-only statement-timeout fault assertion under `supabase/tests/preview/**` | on the exact hosted Preview ref, run `node supabase/tests/preview/protected_alias_rest_e2e.mjs --expected-preview-ref <ref>` and prove real authenticated success, atomic business rollback, concurrent duplicate admission, lost response, HTTP timeout, status-only recovery, exact 52 rows/59 exchanges/55 audits plus 23-flow + 27-process child admission, 309 unrelated-exchange preservation, and zero actor-scoped fixture residue; also retain the exact authenticated preflight/gate/admit/read ACLs and service-only executor, trusted server context, canonical plan/freeze/approval binding, immutable live-gate hashes, 180-second window, owner/state fences, zero legacy RPC grants, six unchanged support snapshots, and all-terminal causal aggregate proof | Hosted fixtures must hard-fail outside the exact disposable Preview, use separate Auth actors/UUID namespaces, emit redacted evidence, and clean up only their own rows, ledgers, queue items, failures, audits, and users. If a disposable Preview lacks `project_url` and `project_secret_key`, the fixture may create only two exact scenario-scoped Vault values after ref/URL binding, must refuse every pre-existing same-name value, and must delete them by exact name, description, and decrypted value; cleanup failure revokes but retains the actor identity for recovery. Pure BAFU owner-draft data may use the released tool directly on production only after a fresh production freeze and exact human approval; Preview/Dev validate shared capability and never replay BAFU data. No retry, approval reuse, publication, `state_code` change, raw SQL fallback, broad queue cleanup, or client-supplied desired PostgreSQL hash is allowed. |
| Time-alias v2 protected lifecycle, fresh closure, or terminal read | `supabase db reset --no-seed`; run `supabase/tests/20260922_foundry60_time_alias_v2_protected.sql`, `supabase/tests/20260923_foundry60_time_alias_v2_rollback.sql`, `supabase/tests/20260924_foundry60_time_alias_v2_terminal.sql`, and the focused `supabase/tests/20260926_foundry60_time_alias_v2_current_closure.sql` | prove that the batch executor and the fresh closure bind the target support by exact identity (the locked target flow property must reference the declared unit group by id, exact version and reference kind, with an absent kind as the canonical default) and that the fresh closure re-verifies the plan's bound support (canonical target property and unit group, the source alias flow property and its declared source unit group) and the exact global incoming occurrence set of the changed Flows across all owners and states on every read, so a support or consumer change after the run yields `live_closure_proof = false` and the public read cannot report `passed`/`applied`; a restored snapshot reads back passed, unrelated canonical-Time consumers stay outside the plan, and the diagnostics never carry a foreign row payload | Time's exact math, write set, request/receipt shapes, nullable-FU semantics and historical v1 behavior are unchanged; the executor path re-uses these rules under its own locks, so a legitimately applied wire run keeps passing |
| guarded owner-draft flow/process derivative rebuild | `supabase db reset`; run `supabase/tests/20260714_guarded_dataset_derivative_rebuild.sql` and `supabase/tests/20260715_guarded_dataset_derivative_rebuild_batch.sql` plus nearby webhook, embedding queue, and dataset-command regressions | retain the single-process v1 ACL/envelope/error contract; prove flow/process snapshot, fence, staging, quarantine, dispatch, proposal, commit, and terminal parity; prove the internal admission/read helpers have empty search paths and no anon/authenticated/service-role grants; reject 0, 51, duplicate, foreign, public, non-draft, incomplete, or desired-hash-drift targets before any child/audit/quarantine effect; atomically bind 1..50 children to supplied frozen baselines and actual post-write primary snapshots; and require exact 50/50, 23-flow + 27-process live primary, committed proposal, fresh vector, terminal audit, queue/failure drain, and completed-snapshot proof before aggregate completion | The compatible public v1 admission remains one process. Protected alias execution alone may invoke the private batch primitive in its mutation transaction. The primitive has a five-second lock wait, takes stable table/id/version row locks rather than a broad table write lock, validates every target before effects, never reports replay, and never retries. Nonterminal drain/failure phases retain each target fence. `completed`, `stale`, or `failed` may release it only after request-specific work and pre-existing worker windows are drained. |
| guarded Step 3 owner-draft public-flow identity rewrite | `supabase db reset`; run `supabase/tests/20260716_guarded_dataset_flow_identity_mapping.sql`, `supabase/tests/20260716_guarded_dataset_flow_identity_mapping_v2_contract.sql`, and the two guarded derivative rebuild suites; run both `protected_flow_identity_actor_lifecycle_contract.mjs` and `protected_flow_identity_residue_readback_contract.mjs` with `node --test`, then run the transport contract; before requesting Hosted execution approval, run the exact read-only transport path with `node supabase/tests/preview/protected_flow_identity_rest_e2e.mjs --transport-preflight-only --expected-preview-ref <ref>`; only after that proof passes may an outer-frozen one-shot Hosted E2E run with `node supabase/tests/preview/protected_flow_identity_rest_e2e.mjs --expected-preview-ref <ref> --scenario-namespace <fie2e-hosted-24hex> --request-id <uuid> --private-temp-dir <absolute-0700-empty-dir> --recovery-ipc` | prove authenticated-only preflight/process/read/finalize/recovery/lookup plus zero-write-cancel ACLs; exact actor/environment/policy/artifact and actor-wide request/text/identity hash-domain non-reuse; prove each disposable actor uses outer-frozen deterministic selectors, is registered before create, verifies an acknowledged create by GET-by-ID plus exact metadata, durably checkpoints its exact ID/selectors through outer-owned IPC before sign-in or fixture mutation, recovers a lost/malformed create only by one exact filtered email/fixture/request/namespace/role match, is globally logged out and hard admin-deleted, and is absent only after GET-404 plus a fresh empty exact filtered census; require cleanup to hold the derivative coordinator lock and accept only pre-external-dispatch exact children; require a transaction-external, read-only 39-surface zero-residue census covering Auth, capture children, scope/ledger/permit/invocation rows, derivative request/proposal/permit rows, live and archived queues, failure tables, pg_net, audits, primary/support fixtures, global exact-name Vault rows, fault hooks, and fixture DB sessions; one active wrapper invocation, memory-only raw permit custody, persisted token hash/generation only, atomic success rotation, old-permit rejection, and no permit consumption on malformed/authorization failure; prove the public process/finalize surface is three-argument only, exact replay/read/lookup never returns a permit, lost-preflight-response lookup is exact and read-only, and continuation uses a fresh human-approved recovery bound to observed scope state/whole proof that supersedes the old permit; retain 1-based scope/process/rewrite ordinals with 0-based exchange indexes; source owner-draft and exact non-owner public Elementary target/support guards; quantitative reference FP/UG/reference-unit identity; server-side reconstruction that changes only five reference fields; exact collision and pending/blocker occurrence ledgers; process-atomic audit plus one-target derivative admission; cancel success only for an untouched sealed scope with exact receipt/operation/plan/scope proof and zero ledger/audit/derivative/permit progress; read-only cancel replay plus foreign/anonymous/post-primary rejection; zero approved-source residue; dynamic 1..50 causal derivative proof; failed/stale child output with exact current primary/snapshot hashes; distinct derivative-only compensation-plan lineage; and terminal finalization only after every primary/audit/protected/derivative closure and completed wrapper invocation/generation proof passes. The hosted proof additionally binds the exact non-production ref, runs an authenticated read-only database transport proof through the same selected URL, exact native Supabase CLI, exact regular nested Docker executable, and exact cached `pg_prove` image ID/RepoDigest/platform; missing or mismatched images fail before database transport and are never pulled automatically. Every DB file sets and asserts its exact application name in-connection. The proof binds the child environment and network path before any disposable actor is created, then uses real owner/foreign authenticated JWTs across capture/read/process/finalize fences, proves live-drift fail-closed, full post-primary rollback, a true two-process same-permit race with exactly one winning first mutation, immediately captures recovery selectors after each committed process, rejects a stale permit, completes the second process, and performs one guarded finalize with two exact audits/derivative children before zero-residue cleanup | Do not copy the Step 2 180-second token, three live gates, pg_net one-shot dispatch, or fixed 50/23/27 reader. Credential/ref/hash checks and a connector-side SQL query are not substitutes for the exact runner transport proof; direct and pooler URL evidence are not interchangeable. The offline actor-lifecycle and residue contracts exercise failure/recovery and readback rendering/parsing without Hosted authority; they do not replace or authorize the full Hosted run or its independent Auth/SQL zero-residue execution, which remain deferred until the exact head, outer recovery envelope, and Preview authority are frozen. The read-only transport mode creates zero actors and writes zero primary rows. The full runner repeats the same proof before actor creation, so an operator-network failure cannot leave disposable identities. The outer wrapper creates and owns the exact private temp directory, durably fsyncs every secret-free checkpoint before returning the exact IPC ACK, owns recovery after signal, crash, ambiguous create, or derivative fast-path refusal, independently proves descendant quiescence plus temp removal, and must independently repeat Auth and SQL residue readback without ever relaunching the mutation runner. If inner cleanup cannot globally log out an actor, it retains that actor and performs no hard DELETE. Outer recovery may issue exactly one service-role password reset to a fresh memory-only value, sign in only the exact actor ID, require acknowledged global logout, then hard-delete and prove GET-404 plus a fresh empty census; an ambiguous reset, failed/wrong-ID sign-in, or ambiguous/failed logout retains the actor, performs no DELETE, and cannot be retried under the same authority. The original actor password, JWTs, service key, database URL, and raw permit may never enter checkpoint, journal, evidence, or durable environment files. The Step 3 scope is durable and process-atomic. A scope read resumes from durable evidence; the exact scope lookup resolves a lost preflight response, while exact replay is proof-only and no read/replay mints or discloses a permit. Wrapper loss, ambiguous responses, deterministic domain rejection, and derivative readiness after exit require a separate fresh exact recovery approval; there is no automatic retry or approval reuse. Cancellation is an abandon path only before any primary evidence and never rolls back or releases a partially written scope. A terminal derivative failure remains `derivatives_pending`, never auto-retries or replays primary, and requires a new single-target plan/freeze/exact approval before its request-ID causal proof is eligible. Source/public/support rows, `state_code`, publication, deduplication, merging, and summing are outside this capability. The hosted fixture is one disposable 305-source/two-process universe, creates the two exact branch-local Vault values only when absent, never invokes a revoked RPC as `anon`, keeps raw permits in memory/stdin only, stores rendered credential-bearing SQL only in mode-0600 files inside the outer-owned private temporary directory whose inner and outer removal proofs are terminal, and removes only namespace-bound rows/users. Live BAFU plans/freezes remain post-Step-2/post-dependency artifacts and are never generated by database tests. |
| guarded atomic owner-draft before-content save | `supabase db reset`; run `supabase/tests/20260921_guarded_dataset_save_draft.sql` and the legacy `supabase/tests/20260404_dataset_command_rpcs.sql` | run `bash supabase/tests/regression/20260921_guarded_dataset_save_draft_concurrency.sh` against the task-owned disposable database only; the runner refuses any other container or URL and refuses to start when its exact fixture identities already exist, so cleanup owns only rows it created | `api.cmd_dataset_save_draft_guarded(p_table, p_id, p_version, p_json_ordered, p_expected_json_ordered, p_model_id, p_rule_verification, p_audit, p_model_version)` locks the exact table/id/version row, re-derives the fresh actor, requires owner state-0, compares the complete stored before image with the caller's expected JSON object by JSON value equality, and only then calls the unchanged `api.cmd_dataset_save_draft` writer in the same transaction. It copies no write, trigger, derivative or audit logic, adds no default overload, keeps the legacy signature, ACLs, audit and behavior, and adds one exact-signature manifest row using only the existing `DB-CORE-WRITE-01` capability. The required before argument has no default, so omission cannot resolve the guarded RPC; explicit null/non-object before images are refused with `DATASET_BEFORE_CONTENT_REQUIRED`/400, stale or altered before images with `DATASET_BEFORE_CONTENT_CHANGED`/409 and no payload disclosure, and non-draft owner states with `DATASET_STATE_NOT_DRAFT`/403 after the existing `DATA_ALREADY_PUBLISHED`/`DATA_UNDER_REVIEW` codes; foreign, anon, reviewed, published, example, nonexistent and invalid-table inputs stay closed with no primary change and no write audit. JSON value equality follows PostgreSQL semantics: object key order, whitespace and numeric scale are equal, JSON array order and added or missing keys are not. The concurrency runner must observe the competing writer blocked with `wait_event_type='Lock'` while the first writer's transaction provably holds the row lock behind the task-owned advisory barrier, and it must keep proving that the legacy unguarded command still accepts the stale writer. Cross-language hash equivalence is never invented here; Foundry and CLI bind their own contract hashes to the same complete payloads. |
| approve or direct-publish lifecycle closure | `supabase db reset`; run `supabase/tests/20260728_review_publication_path_roles.sql`, `supabase/tests/20260405_review_workflow_rpcs.sql`, `supabase/tests/20260404_dataset_command_rpcs.sql`, and `supabase/tests/20260902_process_model_version.sql` | inspect the affected function ACLs and fixed search paths; retain lock-order evidence for Process/LifecycleModel composition changes; run `supabase db lint --level warning` and distinguish existing extension/dynamic-temp-table findings from new warnings | Prove Lineage is read-only; RequiredSupport approve/publish linkage remains active; ILCD `processInstance` is authoritative for source Process dependencies; `public.processes.model_id` plus `coalesce(model_version, version)` is authoritative for generated model-result membership; new writers preserve the exact LifecycleModel version even when the Process version differs; null `model_version` retains only the legacy same-version fallback and never resolves to the latest Model; stale, missing, or malformed `json_tg` does not change review closure; private and missing composition dependencies share one safe public error shape; unknown Process/Flow paths fail closed; and approve/direct-publish operations write no dataset, review, comment, or audit state after a failed assertion. These whole-graph assertions do not run during `cmd_review_submit`. A same-id/version paired row is a dependency only when it exists. |
| review submission or Review Admin quality-diagnostic schema/RPCs | `supabase db reset --no-seed`; run `supabase/tests/20260404_review_submit_rpc.sql`, `20260813_review_quality_diagnostic.sql`, `20260819_retire_review_submit_coordinator.sql`, and `20260806_api_contract_closure.sql` | include owner/state/transaction admission, exact role partition, diagnostic active-run reuse, fresh post-terminal execution, service-role claim/result recording, report readback, review-state isolation, and retired coordinator surface assertions | `api.cmd_review_submit(text, uuid, text, jsonb)` is the only review-submission command and never enqueues or waits for a Worker quality result. Only Review Admin may manually start and read the combined completeness/numerical diagnostic. `clear`, `findings`, `not_evaluable`, and execution failure are informational and must not block assignment, approval, or rejection. Legacy request, Gate, and Worker rows remain audit history only; their RPCs, triggers, cron, and production runners are retired. Worker diagnostics and Edge orchestration require separate repository proof. |
| `worker_jobs` lifecycle schema or RPCs | `supabase db reset`; run `supabase/tests/20260531_worker_jobs_foundation.sql` and `supabase/tests/20260829_private_schema_p0_controls.sql` | add any job-family-specific coordinator SQL tests affected by the change | Prove claim/reclaim, lease-token fencing, active and terminal-maintenance idempotency, exact-request negative admission, concurrency keys, status transitions, coalesced heartbeat events, and RLS/direct-access boundaries. Lease-only renewal must report `eventEmitted=false`, must not change business `updated_at`, and must not append events; progress regression updates current state without creating bucket history, and current diagnostics must not be copied into event history. A recorded `completed` result must atomically normalize both the job and terminal event to progress `1`; blocked and failed jobs retain their actual progress. |
| AI worker queue or suggestion service facade | `supabase db reset`; run `supabase/tests/20260825_ai_worker_contract.sql` and `supabase/tests/20260531_worker_jobs_foundation.sql`; run `supabase db lint --level warning` | on disposable Preview/Dev, call enqueue/read through Edge with two real authenticated actors, then run the matching Worker against `worker_queue=ai` and prove claim/heartbeat/complete-partial-failed readback without Process/Flow row mutation | Preserve service-only ACLs, exact requester scoping, v1 payload/result schemas, active-request idempotency, the absolute 16 MiB DB cap, lease fencing, hidden payload/internal diagnostics, and the generic `ai` queue identity. Provider calls and AI result quality belong to Worker/Edge proof, not SQL tests. |
| legacy lifecycle cleanup after `worker_jobs` cutover | `supabase db reset`; run `supabase/tests/20260531_worker_jobs_foundation.sql`, `supabase/tests/20260531_worker_jobs_legacy_lifecycle_cleanup.sql`, and `supabase/tests/20260602_worker_legacy_table_retirement_audit.sql` | verify production queue drain/cutover and archive availability separately before applying the cleanup migration to `main` | The cleanup disables legacy pgmq delivery surfaces, archives `public.lca_jobs`, `public.lca_package_jobs`, and `public.dataset_review_submit_jobs` into `archive.worker_legacy_job_table_rows`, and physically retires those legacy tables with `DROP TABLE ... RESTRICT`. |
| worker-produced domain artifact/state contracts after legacy table retirement | `supabase db reset`; run `supabase/tests/20260603_worker_domain_artifact_contracts.sql` and `supabase/tests/20260829_private_schema_p0_controls.sql`; run `python scripts/check_generated_workspace_legacy_tables.py` after refreshing generated workspace output | inspect `util.worker_domain_traceability_violations` on the target remote after deployment | Prove retained `lca_package_*`, LCA result/cache, and legacy review-submit diagnostic rows are documented as domain or audit history rather than lifecycle authority, new post-cutover rows remain traceable to `private.worker_jobs`, package-domain FKs restrict canonical job deletion, package retention preview remains non-mutating, and database-only apply fails closed in favor of Worker object-first GC. |
| TIDAS package export request-cache or artifact read lifecycle | `supabase db reset`; run `supabase/tests/20260806_lca_package_capability_facades.sql`, `supabase/tests/20260810_issue_448_package_ownership_and_attempt_diagnostics.sql`, `supabase/tests/20260810_issue_455_mutable_export_terminal_refresh.sql`, and `supabase/tests/20260910_selected_export_refresh.sql` | on the exact Preview/Dev revision, create a `current_user` package, mutate the actor-owned dataset, submit again, and verify fresh package/Worker identities plus current ZIP contents | Preserve advisory-lock and active-job idempotency for every scope while refusing completed artifact reuse, including one or multiple `selected_roots`. Prove both ready-cache and completed-Worker fallback paths, old-job artifact readback, and absence of old artifacts on a refreshed pending job. Qualify unchanged-version root edits and dependency-only edits through a non-production Worker/ZIP round trip; SQL completion fixtures alone do not prove ZIP contents. Owner authorization stays canonical-job/cache based, and current diagnostics remain distinct from event history. |
| canonical LCI/LCIA release control plane | `supabase db reset`; run `supabase/tests/20260716_lci_lcia_release_control_plane.sql` and `supabase/tests/20260623_data_product_publication_mvp.sql` | also run `supabase/tests/20260603_worker_domain_artifact_contracts.sql`, `supabase/tests/20260608_missing_fk_support_indexes.sql`, and local `supabase db lint --level warning`; use a disposable Preview for authenticated Edge/REST transport proof | Prove API/publishable key without user session is 401; ordinary session is 403; manager prepare/approve/publish/readback succeeds only for exact hashes; service can finalize four artifacts but cannot write tables, approve, or publish; retries are idempotent; Calculation Bundle projection accepts legacy zero-download packages but requires new semantic sets to contain exactly five unique role/group/filename/media-type bindings with valid hash/size/count refs and returns them separately as `productDownloads`; every source Process has one self-mapped Unit Process plus one LifecycleModel and Result Process; generated datasets stay out of authoring tables; public Process projections expose identities but no object locator; published artifacts are pinned and immutable; unpublish removes current projection without deleting artifacts. |
| Portal public catalog, capability, Hybrid search, Exchange, or LCIA numeric projection | on a uniquely named isolated local project, complete a blank `supabase db reset`; run every `supabase/tests/*portal_*.sql` file plus `20260806_api_contract_closure.sql`, `20260623_data_product_publication_mvp.sql`, and `20260716_lci_lcia_release_control_plane.sql`; compile every `contracts/portal/*.schema.json` in strict Draft 2020-12 mode; run `python3 scripts/build_portal_contract_types.py` twice and `python3 scripts/build_portal_contract_types.py --check`; run the immutable projection-manifest static check and `scripts/test_portal_projection_upgrade_recovery.sh`; filter `supabase db lint --level warning` to the Portal surface and require zero findings; regenerate the five-schema workspace and public/api TypeScript types twice with no drift | run the exact clean local `release`, `sparse-zero`, and `sparse-199` benchmark profiles, including Process/Flow empty and filtered Facets plans, zero spill on the narrow empty path, 12-term Hybrid, broad/selective filters, `name_asc`, cursor page two, raw-ANN branch evidence, parseable shared buffers below 750,000 total/250,000 read blocks, and schema-valid completion under the 20-second Hybrid statement budget; record Hybrid latency and plans for later optimization without a p95 or sub-8-second release gate; on exact Preview, probe the explicit `api` profile with a publishable key and no user JWT, including the exact Portal Hybrid PostgREST body and strict response schema; run a real matching Worker V3 job through begin/batch/status/seal/package-ready, simulate reclaim with a new job lease and job-level package readback, then run the Release package-publish/finalize/visibility-readback workflow; after persistent Dev merge, capture bounded read-only plan evidence plus security/performance advisors for representative production-cardinality catalog, Facets, Hybrid Process/Flow, exchange, and LCIA modes before adding indexes | Prove fixed 100/200 scope, 0/20 opacity, forged actor/team/state/data_source rejection, exact-version identity, one stable keyset order/cursor, recursive internal/locator/credential absence, fail-closed license capabilities, canonical decimal strings, exact Exchange support chains, 500-record/1-MiB lease-fenced projection batches, positional Process/Method axes, and dense grid/hash reconciliation. Portal JSON Schemas remain the only authored TypeScript DTO source; generated modules are exact-pinned, committed output and CI must reject missing, changed, or unexpected files. Portal Search/Facets/Hybrid must bind every row to the immutable v1 projection registry and live transitive manifest. Empty/unfiltered Facets additionally bind the literal narrow-facet manifest, preserve exact JSON equality with the retained card implementation, and use the narrow path only for normalized `query=''` plus `filters={}`; every query or filter remains on the unchanged card fallback. Any current v1 helper drift fails closed, and future card semantics require a shadow v2 expand/backfill/reconcile/index/cutover rather than in-place rebuild. The supported safety model excludes out-of-band privileged/dynamic DDL: if change/write/restore may have occurred, current digest parity is not historical row provenance and v1 must remain operationally disabled until shadow-v2 recovery. Hybrid must additionally prove one to twelve normalized bounded unique terms, one exact finite 1024-dimensional embedding, strict normalized filters, fixed 1..20 limit, exact latest-visible identity with zero false positives, filled-pool ANN recall@20/@200 at least 0.95, exact underfill parity, deterministic `portal-hybrid-rank-v1` threshold/RRF/tie-breaks over the retrieved pool, actual-only lexical/semantic evidence including the zero-query-vector lexical-only case, a normalized 0..1 score, a 512-KiB response cap, authoritative LCIA decoration, and byte/owner/config/ACL-stable legacy raw Hybrid routines without calling them. Exact helpers must remain API-internal, single-worker, JIT-off, hash-join-on, nested/merge-join-off, and bounded by a 32-MB per-node workspace; caller settings restore through function proconfig. Package readiness must validate authoritative job/result/latest refs, packageResultHash, projection hashes, and deterministic default Impact before mutation. A deliberately late post-insert validation failure must roll back the package, trigger side effects, Worker resultRef, and temporary request-v2 schema switch before returning stable `projection_package_binding_invalid`; exact committed replay alone returns the strict locator-free receipt with `reused=true`, creates no duplicate, and conflicting replay stays `package_conflict`. A reclaimed Worker must recover the same receipt through the current V3 job lease while resolving the manifest-bound old prepared projection without requiring its old lease; no package returns stable `projection_package_not_found`, and package/result/projection drift remains conflict with zero package/projection mutation. Package publish prepare and command plus projection prepare and finalize must invoke the same authoritative binding validator, keep their retained implementations private/owner-only, and create no publication, pin, or projection binding when authoritative result evidence drifts. Also prove exact `publishPlanHash` confirmation and response-loss retry, immutable package/projection/publication binding, and manager readback parity with anonymous `isPubliclyVisible`. Search, Detail, Versions, and Hybrid must reuse that same current finalized non-revoked predicate: exact open projected Processes expose `lciaVisible=true`, Detail adds locator-free publication/Method context, while Flow, state 200, unrelated, unfinalized, unpublished, or revoked evidence remains false/null. Preserve item order/cursor, prove revocation synchronously and within 60 seconds, and measure the bounded 50-item decorator path before any index decision. Also prove supersede/unpublish/revoke fences, unavailable-not-zero semantics, exact manifest/ACL parity, NOLOGIN/NOBYPASSRLS executor, and byte/owner/config/ACL-stable legacy functions. Raw tables gain no anon policy and private artifacts remain private. Never reset or stop the shared `project_id=database-engine` stack for isolated proof. |
| Portal catalog-summary and literal-Search executability | blank reset plus `supabase/tests/20260825_portal_public_catalog_v1.sql` and `20260826_portal_candidate_first_search.sql`; run summary and full release benchmarks with 20 samples | after Dev/Main deployment, resolve examples dynamically through the anonymous summary, execute each declared Search RPC, and probe one-code-point Process/Flow literals; capture sanitized forced-RLS/CAS and narrow-character plans and log only kind/status/latency/count | Classification examples require a trimmed public code of at least four characters and prefer Process. CAS selection keeps at most 64 history-unique values and rechecks latest identity. The row-neutral Portal policy is valid only with forced RLS, the exact validated state-100/200 CHECK, and the live assertion; CAS equality must be an exact `Index Cond`. Multi-code-point and escaped literal Search retains PGroonga. The common one-code-point empty-filter relevance path must pre-limit on the RLS-forced, exact-FK synchronized narrow character child before joining at most `limit+1` parent cards; other one-code-point shapes retain the correctness fallback. Summary p95 stays <=250 ms under 10,000 duplicate CAS rows; CAS/classification and one-code-point Process/Flow p95 stay <2 seconds. Hybrid latency is recorded separately and is not a release gate; its bounded correctness timeout must never become unbounded. Do not log queries, infer substitutes, or add a text index without writer/storage evidence. |
| manager-attested Result publication | `supabase db reset`; run `supabase/tests/20260915_result_process_publication.sql` | run `supabase/tests/regression/20260915_result_process_publication_concurrency.sh` against the task-owned disposable database only, alone; the runner refuses any other container or URL, refuses to start when any exact fixture identity already exists, and requires the Result lifecycle guard already enabled before arming teardown | Prove the manager publishes directly at 120 from an absent row with no intermediate state; retries resolve the receipt before any recomputation so a lost response is reusable; a different key against an existing identity conflicts; the same key against a different identity is a replay mismatch **before any insert**; revocation blocks prepare, execute and readback while leaving recorded receipts intact; raw 120 without a receipt is never adopted; legacy 100 is never auto-upgraded; the content hash is the stored-byte hash and unknown, mistyped or duplicated-key requests are refused; the receipt is append-only with no browser read and no service write; and a late failure raises so the row, receipt and audit roll back together. Two-client proof must show exactly one publication from two simultaneous first writers, an observed in-flight invisibility window, a non-cooperating duplicate insert rejected by the primary key, and a generic reader still unable to see the Result. This row does not prove cross-repository delivery, and the broader export and cache dependency remains Worker-owned. |
| Process numeric eligibility or candidate cache maintenance | `supabase db reset`; run `supabase/tests/20260915_result_process_state_120.sql` plus `supabase/tests/20260623_data_product_publication_mvp.sql`, `20260722_data_product_scope_closure_and_task_feed.sql`, `20260722_scope_closure_release_binding_e2e.sql`, `20260724_initial_candidate_scope_closure_e2e.sql`, and `20260801_scope_closure_cutoff_main_hotfix.sql` | run `supabase/tests/regression/20260915_result_process_state_120_concurrency.sh` against the task-owned disposable database only; the runner refuses any other container or URL, refuses to start when any of its exact fixture identities already exists so cleanup owns only rows it created, and refuses any egress-trigger state other than the plain enabled `O` before mutating. The pgTAP suite alone is not concurrent proof. Overlap must be evidenced: cases that require maintenance to wait poll `pg_stat_activity.wait_event_type='Lock'` on the maintenance session, and cases that require contention use a lock timeout shorter than the writer's hold so only the fail-closed result is possible. A writer is eligible to race only after it holds a granted `RowExclusiveLock` on `public.processes`. Run it alone; do not run other database tests concurrently. | Prove `public.processes` accepts exactly `-1, 0, 20, 100, 120, 200`; no-current-release global/subset Process eligibility is exactly `state_code=100` with predicate `candidate-public-state-code-100:v2`; the eligible input manifest is `published-state-code-100:latest-per-id:v2` with `{"state_code":{"eq":100}}` and a hash reproducible from the emitted list and its literal; the processes branch of the candidate document-hash cache is exact 100 while every other dataset type keeps its prior support predicate, `100 -> 120` removes the exact candidate, and a `120` insert never enters; a current release keeps its exact `unit_process` axis and refuses Result and LifecycleModel roles as subset members; and the guarded `api.cmd_lcia_result_package_publish` rejects a package whose recorded binding belongs to the retired 100..199 predicate while accepting an equivalent current-bound package. The fail-closed manifest gate must block serving while an invalid cache row exists. The concurrency runner must prove an orphan cache row whose source is concurrently inserted is retained, an ineligible to 100 update is not evicted, a legitimate 100 to 120 eviction still removes the exact candidate, a bounded drain preserves unrelated eligible and support entries, a contended fence reports `lock_timeout` with zero deletions and a clean retry, and the caller `lock_timeout` is preserved on the success, lock-timeout, and error paths. Process numeric eligibility is deliberately narrower than public read permission, and this row does not prove Worker, Edge, provider, or Portal exclusion. |
| data-product scope-closure snapshot source or preflight RPC | `supabase db reset`; run `supabase/tests/20260801_scope_closure_cutoff_main_hotfix.sql`, `supabase/tests/20260724_initial_candidate_scope_closure_e2e.sql`, `supabase/tests/20260722_scope_closure_release_binding_e2e.sql`, and `supabase/tests/20260722_data_product_scope_closure_and_task_feed.sql` | run `supabase migration list` and `supabase db lint --level warning`; when a migration hashes or rewrites the candidate universe, prove its production-volume statement fits the platform timeout or declares a bounded session override and restores the default immediately afterward; for an interactive timeout exception, assert the exact RPC `pg_proc.proconfig`, confirm role-level query budgets are unchanged, and run a rollback-only production-volume request; after production deployment, submit one real zero-release completeness check and inspect Worker completion plus the downloadable report | Prove zero-release subset/global requests, exact versions, canonical LCIA locator mapping, Worker-compatible canonical hashes, deterministic snapshot/scan reuse, explicit current-membership rejection, unchanged formal-release binding, ACLs, and task-center projection. A complete blocked source must reuse and finalize without a source snapshot even though its execution owns a preallocated snapshot UUID; passed reuse must retain exact snapshot equality. A scanner revision change must produce a distinct request fingerprint and scan execution. Boundary normalization must prove omitted, `closed`, `open`, and `cutoff` inputs all freeze canonical `cutoff` and produce one canonical requested-scope hash/fingerprint input, while unknown values fail. Preview data volume alone is not production-scale backfill evidence. |
| scope-closure artifact publication, certificate expiry, download, or GC lifecycle | `scripts/test_scope_closure_base_to_head_upgrade.sh`; `supabase db reset`; run `scripts/test_scope_closure_staged_write_set_v2_fixture.sh`, `node supabase/tests/20260730_scope_closure_staged_write_set_v2_rest_contract.mjs`, `supabase/tests/20260730_scope_closure_staged_write_set_v2.sql`, `supabase/tests/20260729_scope_closure_publication_staging_and_gc_control.sql`, `supabase/tests/20260729_scope_closure_owner_artifact_projection.sql`, `supabase/tests/20260729_scope_closure_artifact_retention.sql`, `supabase/tests/20260722_scope_closure_release_binding_e2e.sql`, `supabase/tests/20260722_data_product_scope_closure_and_task_feed.sql`, `supabase/tests/20260531_worker_jobs_foundation.sql`, and `supabase/tests/20260608_missing_fk_support_indexes.sql` | run `supabase migration list` and `supabase db lint --level warning`; on the exact Preview branch, confirm the additive migration appears in remote history, prove both public selectors and the temporary one-argument XLSX overload through actor RPC transport, then exercise DB-first staging and Worker GC RPC transport when the matching Worker consumer is available | Prove the shared Worker/database fixture has one exact canonical digest and request/response shape. Exercise 0/1/500/501/596/1500+ descriptors, multiple batch sizes, duplicate/reordered/missing/out-of-range ordinals, wrong count/digest, role/locator conflict, stale/foreign fences, exact and conflicting replay, ambiguous-response status, concurrent register/seal, rollback, post-seal mutation, and one-shot compatibility. For 596 and at least 1500 descriptors, record request count, batch size, wall time, maximum registration statement time, row count, and seal time; no request may contain more than 500 descriptors. Also prove a populated canonical-base fixture upgrades atomically; fresh publication resolves bundle clientKey to manifest UUID in one finalize; reused publication uploads only the current XLSX and preserves source manifest/bundle lineage; crash recovery sees every locator and no partial ready set. A passed reused certificate must complete Calculation Bundle request admission, after-lease Worker binding, and package-ready publication with a target-owned report and exact direct-source Bundle/Snapshot; foreign, forged, recursive, stale, revoked, expired, or mismatched evidence remains fail-closed. Prove the owner check returns exactly two fixed-order locator-free summaries and exact selector DTO/opacity semantics, plus certificate deadlines, non-mutating preview, renewable `SKIP LOCKED` leases with old-token rejection, fresh detail-cleanup reclaim without object re-delete, repeated completion, and compact audit residue. SQL coordinates object I/O but never performs it. |
| Flow identity actor-fence trigger boundary | `supabase db reset`; run `supabase/tests/20260731_flow_identity_derivative_fence.sql`, both `20260716_guarded_dataset_flow_identity_mapping*.sql` suites, and the two guarded derivative rebuild suites | also run the nearby JSON/webhook regression and local security/performance advisors | Prove a separately held owner advisory lock does not block updates limited to `extracted_md`, `embedding_ft`, or `embedding_ft_at`; every other current or future Flow-column change plus every INSERT/DELETE remains fail-closed behind the existing v2 fence. |
| `supabase/tests/**` only | run the relevant SQL assertion files against a reset local DB | add a nearby migration or policy smoke check if the new assertions expose a gap | This repo stores PGTAP-style SQL assertions, not a single canonical runner wrapper. |
| `supabase/seed.sql` or `supabase/seeds/dev.sql` | `supabase db reset` succeeds with expected seed behavior | rerun targeted SQL assertions that depend on the seeded rows; for shared-seed changes, confirm the hosted Preview seed stage completes | Keep shared seed and dev-only seed expectations separate. A shared seed with no data must still contain an executable no-op statement; a comments-only batch is not deployment-safe. |
| `supabase/config.toml` or `supabase/templates/**` | `supabase start` and `supabase db reset` still work locally; for Auth recovery template changes, run `python3 scripts/check_auth_email_templates.py` and `python3 scripts/test_check_auth_email_templates.py` | verify the changed branch-binding or auth assumption against `docs/agents/supabase-branching.md`; for exposed-schema changes, prove the Supabase GitHub integration applies the configuration or record the explicit operator gate, then read back exact ordered hosted PostgREST schema/search-path lists; for hosted Auth templates, require the documented authorized Dashboard apply and end-to-end email validation | Config changes affect preview, persistent dev, and local behavior together; neither local CLI order nor a checked-in email template proves the hosted project state. |
| `.github/workflows/supabase-dev.yml` | inspect and parse YAML; run `python3 scripts/test_resolve_migration_head.py` and `python3 scripts/test_supabase_dev_workflow_contract.py`; prove the Preview classifier validates exact base/head commits and compares exactly `supabase/config.toml`, `supabase/migrations/`, `supabase/seed.sql`, `supabase/seeds/`, and `supabase/functions/`; prove repository-only workspace/tests/templates/docs are excluded; retain the persistent-Dev one-push/one-PATCH and Preview one-PATCH/no-deployment contracts | on a PR changing only repository-owned nondeployable files, prove the official Supabase App `skipped` result does not fail the job and no authority or hosted mutation step runs. On any deployable-input change, require all authority, exact successful official check, disposable BranchResponse, PostgREST readback, public-key selection, and anonymous Hybrid/sitemap probes | Missing commits or diff errors fail. The explicit allowlist mirrors the Supabase GitHub integration's configuration, migration, seeding, and Function inputs; Auth templates remain separately manual. Every deployable change retains fail-closed App identity, branch equality, main/Dev exclusion, credential isolation, and no Functions/config/schema deployment from the verifier. |
| `scripts/**` | run the touched script with `--help` when possible, or execute the narrowest safe non-destructive path | if a script changes generated workspace behavior, refresh the workspace in a safe environment and inspect git diff | Avoid remote-destructive script runs unless the task explicitly requires them. |
| `supabase/workspace/**` | prove whether the touched file is generated or stable | if stable manual overlay files changed, explain how they feed migration generation | Generated files alone are not sufficient evidence of a durable schema change. |
| repo docs only | `scripts/docpact lint --root . --files "<csv>" --mode enforce` | `scripts/docpact validate-config --root . --strict` when `.docpact/config.yaml` changes | Refresh review metadata even when prose stays unchanged. |

The Issue #532 Search/Hybrid card context is not a stored v1 card/document
semantic replacement. It must run only after the existing ordering and 50/20
limit, use exact source keys, share one independently manifest-guarded
decorator, and preserve the #531 projection/index/Facet/writer graph
byte-for-byte. Run `supabase/tests/20260827_portal_card_context_v1.sql`, require
Search and Hybrid schemas/types to share the exact exhaustive context, and add
Process/Flow Search-50 plus Hybrid-20 context latency/buffer samples to each named
Portal performance profile. Search remains <= 2 seconds; Hybrid must return a
schema-valid page within its bounded 20-second statement budget, while latency
is recorded for optimization and is not a release gate. Preview must validate the strict response
schemas with a publishable key. Any later change to the stored v1 card/document
still requires the shadow-v2 rollout described above.

The Issue #563 Process keyword acceleration is a query-only consumer of the
immutable v1 card/document projection, not a stored-card replacement. It may
route only multi-code-point, non-UUID, empty-filter `relevance` Process Search.
The PGroonga pattern helper and exact latest-visible key set remain
authoritative; one partial expression GIN supplies exact name/classification
rank probes, then the kernel orders and limits keys before hydrating at most
`limit+1` wide cards. Flow, UUID, empty-query, one-code-point, filtered, and
alternate-sort requests must stay byte-identical on their predecessor paths.
Run `supabase/tests/20260826_portal_candidate_first_search.sql` after a blank
reset and the representative candidate benchmark. Require exact/general/no-hit
and page-2 byte equality, a natural `portal_catalog_search_process_exact_rank_v1_gin`
plan at 17,299 Process rows, recorded index bytes, successful Process writer
and `ANALYZE` maintenance through only `api_internal_executor` and `postgres`,
and the existing 2-second Search p95 / 8-second hard timeout. Hosted promotion
must repeat the common-term Search p95 and buffer profile before the Portal
performance task closes.

The named benchmark fixture must exercise the complete expensive path rather
than context shape alone: every Process card carries a real quantitative
reference Exchange to an exact public Flow, complete FlowProperty/UnitGroup
support, technology, source/database identity, and dataset-authored review
status; every Flow card resolves the same public FlowProperty and source
identity while retaining explicit Process-only nulls. Require exactly 50/20
items for the four dedicated wrapper labels, capture full
`EXPLAIN (ANALYZE, BUFFERS)` for each wrapper, record any temp-buffer evidence,
keep each plan below 750,000 total and 250,000 read shared blocks. Apply the
2-second Search budget normally; record Hybrid plan and 20-sample timing while
gating only schema-valid completion under the bounded 20-second statement budget.
The Flow empty-query `geography=cn` Search-50 path must have its own full plan
artifact because it is the representative filtered worst case.
Its timing label must return exactly 50 complete cards, and its repair must
prove latest-version and relevance-cursor equality against the synchronized
facet child, fail closed on live Facet-manifest drift, preserve the general path
for every other filter, and add no index or writer work.

When the anonymous PR Preview probe fails, CI may log only the HTTP status and
a response-shape-validated PostgREST or SQLSTATE code. It must not print the
raw response body, `message`, `details`, `hint`, request payload, or public key.
An `unclassified` code preserves that boundary when the response is malformed
or carries unexpected fields.

For the narrow Portal facet projection, run both
`scripts/test_portal_projection_upgrade_recovery.sh` and
`scripts/test_portal_facet_projection_populated_upgrade.sh`. The latter must
exercise 126,246 pre-existing parent cards, retain 2x per-statement timeout
headroom with each shard file below 120 seconds, and prove a sub-five-second
successful reconcile plus exact key coverage, sampled facts, and DTO counts.

For the Portal Flow embedding-eligibility hotfix, sparse-zero and sparse-199
profiles must naturally name `flows_portal_embedding_eligible_v1_idx` for the
exact `state_code IN (100,200) AND embedding_ft IS NOT NULL LIMIT 200` universe
probe, expose parseable buffers/execution, and show no Flow heap Seq Scan or
temp/disk spill. The release profile records the natural full-vector plan and
keeps existing writer/ANN/exact budgets. After persistent Dev deploy, a
zero-embedding Flow probe plus at least five anonymous Hybrid samples must show
p95 <= 6 seconds, every call < 8 seconds, and no `portal hybrid unavailable`;
record index validity/size, database size before/after when available, and both
advisor classes. Process remains index-free unless separate hosted evidence
justifies shared write amplification.

For the Portal catalog summary, run
`supabase/tests/benchmarks/20260827_portal_catalog_summary_cardinality.sql`
only against a uniquely named isolated local project with
`benchmark_target=local`, exactly 17,299 Process rows, 108,947 Flow rows, and
20 samples per profile. `normal`, `tail-evidence`, and
`no-cas-classification-evidence` must each keep p95 at or below 250 ms and the
response below 16 KiB. The CAS and classification plans must naturally name
`portal_catalog_summary_eligibility_v1_idx`, with no sequential card scan or
temp spill under the façade's 32-MB workspace; the exact-CAS index must not be
eligible for that unconstrained selector. Record the index bytes and build
time. Dynamically execute both emitted classification and CAS examples for 20
samples: each must return at least one item, keep p95 below two seconds, and
keep every sample below eight seconds. The exact CAS candidate plan must name
`portal_catalog_search_flow_cas_v1_idx` and the retained latest-version index;
under forced RLS its CAS equality must be an `Index Cond`, with no CAS JSON
filter or parent-wide index scan, and it must not enter the PGroonga pattern
path. The table's forced-RLS flags, `postgres` owner, validated state-100/200
CHECK, unique row-neutral Portal SELECT policy, and live assertion are one
indivisible security/performance contract. The benchmark's temporary writer
probe compares 50 four-update samples with no added index, the combined summary
eligibility index, and both eligibility plus Flow CAS indexes. Record both
build times and bytes, and do not drop, rebuild, truncate, or rewrite the real
Portal projection while collecting incremental writer evidence.

The complete release benchmark must also record `process_single_character`
and `flow_single_character` for 20 samples. The fixed pattern helpers retain
their PGroonga-backed literal-LIKE template for every multi-code-point or
escaped pattern; only the exact `%` + one unescaped code point + `%` shape may
use the synchronized narrow character pre-limit for empty-filter relevance.
The child must retain exact parent key/state/time parity, deterministic sampled
character facts, one INSERT/UPDATE upsert Trigger, and FK-cascade DELETE. Both
labels keep p95 below two seconds,
and the candidate pgTAP suite must prove Process and Flow exact identities plus
the existing percent, underscore, backslash, punctuation, CJK, and cross-field
cases. Do not change the public minimum query length to hide an index false
negative.

For the bounded Portal sitemap shards, run
`supabase/tests/20260827_portal_sitemap_shards_v1.sql` and the existing
`20260825_portal_public_catalog_v1.sql` after a blank reset. The manifest must
return exactly 64 byte-stable, unique opaque cursors with a fixed 4,096-item
limit. Calling every descriptor must produce a globally disjoint union equal
to the retained latest-visible sitemap set; the legacy façade remains
byte-identical. A 4,097th latest identity must still commit to the synchronized
exact-version child while only that shard read fails closed, and removing it
must restore the page immediately. Prove the child has one row per public facet
version, primary key `(dataset_kind,id,version)`, an exact-key FK with
`ON UPDATE RESTRICT`/`ON DELETE CASCADE`, one `AFTER INSERT OR UPDATE` exact-key
upsert trigger, and no DELETE-side sitemap helper.

Run `supabase/tests/benchmarks/20260827_portal_sitemap_shards_cardinality.sql`
only on a uniquely named isolated local project with exactly 17,299 Process
rows, 108,947 Flow rows, and 20 samples. Require all 126,246 identities exactly
once, every shard at or below 4,096, manifest p95 at or below 250 ms, largest
shard p95 at or below 2 seconds, each call below the function's four-second
timeout, response JSON below 2 MiB, and a conservative rendered-XML estimate
below 6 MiB. The base 126,246-row single-version fixture must retain a largest
shard of 2,066 identities; the recorded shard-read p95 is approximately 11 ms.
The production-shape plan must naturally name
`portal_sitemap_rows_shard_v1_idx`, avoid a full child-table sequential scan,
and spill no temp data. Record index build time/bytes plus 20-sample writer p95
before/after the physical index and sole exact-version upsert trigger.

Add the history-density proof with exactly 2,048 identities and 64 versions per
identity (131,072 rows). Its natural `DISTINCT ON (dataset_kind,id)` plan must
use the exact history-order index as an index-only path, contain no `Sort` or
`Incremental Sort`, spill no temp data, and finish below four seconds. The
reader's output and timeout remain bounded, but the plan evidence must state
that scanned rows grow with retained version history.

The `20260827134103` recovery proof must show one atomic facet-writer fence,
shadow creation, full backfill, assertion/reader replacement, and retirement of
the obsolete winner table/helpers. The checked-in SHA-pinned old-Preview fixture
must prove an already-recorded populated `134101`/`134102` shape advances by
applying only `134103`. Real same-identity exact-version concurrency
must leave exact facet/child parity with every writer committed and no writer
retry. Preview then uses only the enabled publishable or legacy anon `apikey`,
polls no longer than 300 seconds, strictly validates both new JSON Schemas, and
passes one manifest cursor back byte-for-byte; Portal #12 owns final Next/CDN
XML and five-minute visibility proof. Canonical-cursor tests must also reject
JSONB-equivalent alternate numeric
scales (`1.0`, `64.0`) by comparing input with the freshly encoded expected
object, not JSONB equality alone.

### Direct MCP OAuth operational proof

For each Dev or Production direct MCP client class, record:

1. Supabase Dynamic Client Registration remains disabled and the client is a separate public manual registration with an exact loopback callback.
2. Authorization Code uses S256 PKCE, the exact MCP resource, and only standard identity/offline scopes; OAuth scopes never grant database capabilities.
3. The service-only configuration façade stores the environment `client_id` as `mcp_client` with exactly `DB-CORE-READ-01`, `DB-CORE-WRITE-01`, and `EDGE-BUNDLE-01`; no migration contains that UUID and no MCP client receives `CLI-RPC-01`.
4. A fresh host session completes one actor-bound relation read and representative command/Edge paths while an unknown or disabled client fails with SQLSTATE `42501`.
5. Disabling the same client's registry row denies an already-issued session, and restoring the exact capability set returns the row to enabled state without broadening grants.
6. User grant revocation leaves the consent revoked and zero active Auth sessions/refresh tokens for that client. A JWT already accepted by local signature verification may remain usable until `exp`; do not claim immediate access-token revocation without a separate live session check or denylist.

Keep client UUIDs in the environment-specific Issue/deployment evidence and
service configuration only. Checked-in docs and migrations describe client
classes and capability sets, never environment IDs.

## SQL And Offline Node Contract Notes

### Version-aware search proof

For the additive Portal V2/Next matched-version APIs, use a uniquely named
isolated local stack, a clean migration reset, all Portal suites plus the
nearby Hybrid/ACL/OAuth suites, and `20260902_next_hybrid_versions_v1.sql` plus
`20260902_portal_version_search_v2.sql`. When changing either adaptive V2
semantic path, also run `20260903_portal_flow_adaptive_semantic_v2.sql`,
`20260904_portal_flow_semantic_executor_alignment.sql`,
`20260905_portal_process_adaptive_semantic_v2.sql`,
`20260905_portal_process_semantic_executor_alignment.sql`, and the three
adjacent semantic/HNSW governance suites from the proof matrix. Prove
positive 100/200 scope and exclusion of other synthetic states, 0/6/199/200
cardinalities, pre-limit filters, independent historical matches, best-member
group ranking, complete bounded member expansion and keyset continuation.
Geography-only, access-level-only, and combined filters must exercise the exact
route at or below 2,000 projected exact-version keys; a 2,001st key must retain
the predecessor HNSW route. The exact branch must reapply the complete canonical
filter, preserve both versions of one ID, rank by exact cosine distance with
deterministic ID/version ties, and return no row for an empty candidate set.
### Navigation and V3 proof

For administrative parent revisions, first run `python3 scripts/test_portal_china_navigation_upgrade.py --local-container supabase_db_database-engine-662-isolated` against an empty disposable project at the pre-revision base. Then replay the complete migrations and run `supabase/tests/20260920_portal_china_administrative_navigation.sql` alongside the original navigation suite. Prove existing historical versions gain exactly one ancestor, direct placements and raw codes remain unchanged, TW/HK/MO and Tibet remain reachable at zero matches, anonymous V3 counts agree, withdrawals remove ancestors, and the seed guard and private ACLs remain intact. Regenerated five-schema workspace and Data API types must have no diff for this data-only revision.

For the versioned navigation RPC, the Chinese-administrative alias layer and the
V3 node filters, use the same isolated local stack, a clean reset, and
`supabase/tests/20260919_portal_navigation_v1.sql`. Prove:

- the closure projection materialises one row per authored placement and every
  ancestor of it, that only the authored placement of a branch is `direct`, and
  that a version with no usable classification still lands in a bucket;
- an authored archive code (`SD-CN`, `AQ-AH-CN`) resolves through its alias to
  the canonical `CN-*` node instead of creating a second tree, and that the
  canonical tree's own parent links are asserted by each row's name;
- the page carries `countBasis`, per-kind `totals` that keep measuring the other
  kind, a complete `parent` node with its own `count`/`directCount`, identity-only
  `ancestors`, subtree and direct child counts, and a keyset cursor that pages a
  branch instead of truncating it;
- V3 `classificationNodeId`/`geographyNodeId` with `subtree` (default) and
  `direct` scopes reach the pre-filter, and a scope without its node, a node from
  the other dimension, or a node outside the vocabulary is refused with
  `22023`;
- the v1 and v2 facades keep their exact signatures, grants and behaviour, the
  navigation internals stay closed to browser roles, and every new `api.*`
  routine is registered in `private.api_capability_grants`.

The generated vocabulary is not hand-edited: change it by re-running
`scripts/generate_portal_navigation_vocabulary.py` against the pinned platform
commit and the receipted `tiangong-lca/data` snapshot, then confirm the committed
`contracts/portal/navigation-vocabulary.json` and its receipt are byte-identical.

### Bounded catalog summary

The anonymous summary facade keeps a 2-second statement budget and must never
raise it to hide cost. Proof for a change to it is a synthetic
production-volume projection fixture on the isolated stack plus an assertion that
`api.portal_catalog_summary_v1()` returns its published shape and that its body
reads the narrow projection tables rather than the
`portal_catalog_search_current_v2` union view. A performance fix must return
byte-identical JSON: record `md5()` of the response before and after, and record
representative timings. Do not run `EXPLAIN ANALYZE` against production.

Existing V1 definitions and immutable projection/context/facet manifests must
remain unchanged. Compile all Portal JSON Schemas in strict
Draft 2020-12 mode and regenerate contracts and the five-schema workspace twice
without drift.

`node scripts/benchmark_hybrid_versions.mjs --local-container
supabase_db_database-engine-600-<isolated-suffix>` compares V1/V2 top-10/20
identities, historical-version coverage, 20-sample timings and the natural
V2 semantic plan over synthetic fixtures. Reset only that isolated stack
before and after. The report is labelled `isolated-synthetic`: it is query
shape/identity evidence, not real-world relevance or promotion-scale proof.
Record eligible HNSW or small-universe plans and buffers without globally
forcing planner indexes. For adaptive Process and Flow V2 paths, record cold and warm
timings plus shared reads/hits at zero, small, 2,000, 2,001, and broad candidate
cardinalities. The exact branch may use ordinary B-tree facet/source indexes but
must not be satisfied by the global HNSW ordering; the broad branch must retain
strict-order HNSW and the existing `ef_search=200`, `max_scan_tuples=20000`, and
`scan_mem_multiplier=2` settings. Capture both broad plans as
`portal_public_executor`, verify each naturally names its source HNSW index,
and retain the exact public-state RLS policies; do not use BYPASSRLS or a
globally forced planner setting as proof. Real public-data relevance and deployed
readback remain separate evidence; production `EXPLAIN ANALYZE` and fixture
writes are forbidden.
The historical 299-file projection-rollout runners attest their frozen V1
rollout, not this additive query-only V2 contract.

The repo stores SQL assertions and narrow offline Node contracts under `supabase/tests/**`.

Facts that matter:

- database semantics use PGTAP-style SQL assertions
- offline Node contracts may mock transport to prove runner control flow such as deterministic selector binding, exact filtered actor recovery, global logout, hard DELETE acknowledgement, GET-404 plus empty-census absence confirmation, and fail-closed 39-surface residue rendering/parsing
- offline contracts do not replace exact-head Hosted execution or independent post-run Auth/SQL readback
- no single checked-in wrapper defines the only valid invocation
- PR validation notes should therefore record the exact command or SQL runner used

If you add or change SQL assertions:

1. reset the local DB first
2. run the relevant assertion files against that reset state
3. record the exact invocation in the PR

If you add or change an offline Node contract, run its exact file with `node --test` and record that command separately from any deferred Hosted proof.

## Supabase Functions Hooks Compaction

`util.purge_supabase_functions_hooks` enforces logical retention, but ordinary
deletes and autovacuum do not return the table files to the operating system.
Treat physical compaction as an explicit production maintenance action.

Before the maintenance window:

1. confirm a current backup or point-in-time recovery window
2. run the retention preview and bounded purge until `eligible_rows` is zero
3. capture row count and heap, index, and total bytes with the query below
4. confirm no long-running session or queued lock is using the hooks relation
5. stop if the application cannot tolerate an `ACCESS EXCLUSIVE` lock

```sql
select *
from util.preview_supabase_functions_hooks_retention(
  interval '14 days',
  pg_catalog.now()
);

select
  count(*) as row_count,
  pg_catalog.pg_relation_size('supabase_functions.hooks') as heap_bytes,
  pg_catalog.pg_indexes_size('supabase_functions.hooks') as index_bytes,
  pg_catalog.pg_total_relation_size('supabase_functions.hooks') as total_bytes
from supabase_functions.hooks;

select
  activity.pid,
  activity.usename,
  activity.state,
  activity.wait_event_type,
  activity.wait_event,
  lock.mode,
  lock.granted,
  activity.query_start
from pg_catalog.pg_locks as lock
join pg_catalog.pg_stat_activity as activity
  on activity.pid = lock.pid
where lock.relation = 'supabase_functions.hooks'::regclass
order by lock.granted, activity.query_start;
```

Run compaction from a direct database session during the approved window. The
timeouts make lock contention fail closed instead of queueing indefinitely:

```sql
set lock_timeout = '5s';
set statement_timeout = '15min';
vacuum (full, analyze) supabase_functions.hooks;
reset statement_timeout;
reset lock_timeout;
```

If the lock timeout fires, reschedule; do not increase it while traffic is
active. After success, rerun the storage query and the retention SQL test,
record before/after bytes in the delivery Issue, and verify webhook execution.
`VACUUM FULL` cannot be rolled back, so do not repeat it merely because the
remaining live rows still require disk space.

## Schema Workspace Tooling Checks

If the task touches `scripts/**` or `supabase/workspace/**`, first decide whether you changed:

- stable documentation or overlay paths
- generated inspection output
- helper scripts that transform one into the other

Useful low-risk checks:

```bash
python scripts/build_schema_workspace.py --help
python scripts/copy_workspace_file_to_changes.py --help
python scripts/new_migration.py --help
python scripts/export_remote_schema.py --help
python scripts/check_generated_workspace_legacy_tables.py --help
```

If you actually refresh the workspace, make the validation note explicit about which generated paths changed and whether the change is intended to be committed.

The canonical refresh target remains remote `dev`. For an exact local migration-state reconstruction, omit `--db-url` so the helper uses the Supabase CLI local connection path:

```bash
python scripts/build_schema_workspace.py --environment local
```

For a schema-changing PR, an exact-local reconstruction may be committed as a review snapshot after a blank migration rebuild, targeted contract tests, and a second deterministic regeneration show no drift. Record those proofs in the PR. After merge, require the database-only Dev deployment to reach the exact head, hosted catalog checks, and a remote-Dev refresh comparison; commit any resulting drift as a follow-up.

## Preview, Persistent Dev, and Root Integration

For branch-oriented changes:

- preview-branch proof usually happens on the repo PR
- persistent remote `dev` proof happens after merge into Git `dev`: first record the database workflow result, then the Edge-owned Function deployment and runtime validation
- production `main` proof happens after `dev -> main` promote and should confirm the Supabase GitHub integration applied migrations automatically
- root workspace proof happens later in `lca-workspace`

Do not collapse those phases into one validation note.

## Composite Process names

For the composite-name projection, run a blank reset, all `*portal*.sql` suites,
`20260805_full_schema_cutover.sql`, `20260806_api_contract_closure.sql`, adjacent
OAuth/Hybrid contracts, and the isolated concurrency runner documented in
`portal-projection-migration-recovery.md`. Keep both Process projection triggers and the sole Flow V1 trigger enabled
in synthetic fixtures that disable unrelated authoring triggers. Prove no Flow
shadow rows or second writer and exact invoker-view routing/security. Preserve
V1 latest-only and V2 matched-version expectations. Record populated shard timing,
replay/concurrency results, long multilingual page/cursor bounds, strict consumer
DTO validation, and the exact local regeneration comparison. Production source
readback and deployed cache-expiry verification remain separate evidence.

## Minimum PR Validation Note

Every PR note for this repo should state:

1. exact commands run
2. exact SQL assertion files or migration paths exercised
3. whether any proof is deferred to preview branch, persistent `dev`, production `main`, or root integration

## Local Docpact Push Gate

Install the versioned local hook once per checkout:

```bash
./scripts/install-git-hooks.sh
```

The `pre-push` hook runs `scripts/docpact-gate.sh`, which delegates CLI lookup to `scripts/docpact` and performs strict config validation plus enforced lint before the push leaves the machine. The wrapper checks `DOCPACT_BIN`, Cargo install locations, Homebrew install locations, and then `PATH`, so local agent shells should not fail only because bare `docpact` is unavailable. The default comparison base is `origin/dev` for routine branches and `origin/main` for promote or hotfix branches. Override it for unusual stacks with `DOCPACT_BASE_REF=<ref>` or `scripts/docpact-gate.sh --base <ref>`. The gate writes its detailed report to a temporary file so normal pushes do not create `.docpact/runs/` artifacts.

TIDAS partial import requires `supabase/tests/20260909_tidas_partial_import.sql`, including insert/skip, rollback isolation, replay counts, caller ownership, lease rejection and v2 admission. Preserve actual database triggers; tests may record calls at the external webhook boundary. Also qualify concurrent identity collisions and failure-after-commit recovery. Generated schema/ACL snapshots must follow the existing generation workflow after migration replay.

For authenticated example scope changes, run `supabase/tests/20260910_example_dataset_scope.sql` after a blank reset. It covers seven-table cross-owner reads, state/version/page isolation, lexical and semantic search, UUID references, matched Process/Flow versions, original-write denial, selected-root export admission, and anonymous exclusion. Keep `20260805_full_schema_cutover.sql` object counts and the `20260806_api_contract_closure.sql` migration-head expectation aligned with the actual migration.

The trigger inventory in `20260805_full_schema_cutover.sql` is asserted over the schemas this repository owns, never as a database-global `not tgisinternal` total. A global total also counts the triggers created by whichever platform services are enabled for the environment — `realtime.subscription.tr_check_filters` exists only where the Realtime service runs, and `storage`, `cron`, and `pgsodium` add their own — so a global total is a property of the deployed service set, not of this repository. The discriminator is the schema, not extension ownership: those platform triggers are not `pg_depend` extension members, so `deptype='e'` cannot separate them. The suite pins one aggregate non-internal count across `api`, `private`, `public`, and `util`, plus the exact identity and semantics of every authored trigger in the remaining schemas except the platform-service-owned `realtime`, `storage`, `cron`, and `pgsodium`. It does not pin per-schema counts for the four application schemas, so a redistribution of the same total would pass; extending the inventory means adding an explicit assertion, not raising the aggregate. The two Result guards are pinned by exact trigger name, enabled state, non-deferred state, empty column list, and exact `tgtype` 27 (`ROW|BEFORE|DELETE|UPDATE`), so a trigger with different timing or events fails, and their firing functions are bound to `private.zzz_guard_process_result_lifecycle()` and `private.result_process_publications_immutable_v1()`.

The example-scope migration intentionally changes four private raw Hybrid/semantic definitions. Update only their definition fingerprints in the two `20260826` Portal Hybrid/candidate suites and run both (64 and 83 assertions respectively); all eight routine owners, security modes, configs and ACLs remain pinned. This baseline refresh does not modify the immutable Portal projection helper closure or authorize Portal visibility changes.

For Database #654, run `supabase/tests/20260918_tidas_full_package_import.sql` and existing partial-import/API/full-schema suites after clean migration replay. Prove orphan/rootless and all-existing packages, per-record skips, cross-type identity, cross-chunk rollback, exact replay, missing chunks, expiry and lease loss during inserts, and receipt ACLs. Regenerate the five-schema workspace and Data API types from the qualified migration state.

## Portal hierarchical navigation and summary

After a blank local migration reset, run all `*portal*.sql` suites plus full-schema, API closure, adjacent matched-version Hybrid/OAuth and FK-index tests. `20260919_portal_navigation_v1.sql` retains both Process projection writers and the Flow writer in rollback-only source fixtures; it checks historical versions, duplicate paths, type disambiguation, aliases, direct/subtree and combined filtering, byte bounds, more than 100 regions, cursor scope, source updates, withdrawals and derivation drift. `20260919_portal_catalog_summary_bounded.sql` checks dataset totals, executable examples and unchanged public capabilities/timeouts.

Use `python3 scripts/benchmark_portal_summary_bounded.py --container <explicit-local-container> --direct-projection-fixture --process-datasets 20000 --flow-datasets 30000 --samples 5 --report <new-json-file>` only on an empty local Docker fixture. This is a rollback-only 100,000-version read-scale benchmark, not production p95 or bulk-write qualification. It compares the exact September predecessor with the replacement on identical data, restores selected raw support rows for context decorators and leaves every change rolled back. The separate source-writer SQL suite proves transactional maintenance.

Run the offline vocabulary generator with `--check`, generate Portal types twice without drift, compile all schemas in strict Draft 2020-12 mode with `python3 scripts/check_portal_json_schemas.py` (the checker preloads sibling references rather than relying on filename order), and regenerate the five-schema workspace plus Data API types from the same clean local state. The pinned Supabase CLI in the workflow owns the generation version. Hosted Preview, persistent Dev, production promote and root integration remain distinct proofs.

Run `python3 scripts/test_portal_navigation_backfill.py --container supabase_db_database-engine --report /tmp/portal-navigation-backfill.json` on the empty local stack before other committed fixtures. It replays all four populated shards twice and uses a two-connection advisory barrier to prove that concurrent withdrawal and update win after the cursor snapshot. It touches only fixture projection parents, cleans them up, and never accepts hosted URLs. The backfill makes only its two parent FKs immediate so per-version savepoints catch withdrawal before commit.

The local qualification at `e6c536f63a4afcc167c70bb95767b79f210f4f03` passed all 16 Portal suites and three adjacent schema/API/Hybrid suites, including 48 navigation and ten summary assertions. The exact four-shard replay and withdrawal/update barrier tests passed. Two regenerated five-schema snapshots matched across 1,705 SQL files. The 100,000-version synthetic benchmark returned identical old/new summary JSON, with new reads 43.6–58.3 ms versus 2,136–2,197 ms; a world navigation page was 40,014 bytes and 1,483–1,552 ms. These are local receipts only. Full `db lint` still reports 12 untouched historical/temp-table routines; none belong to this navigation, V3 or summary increment. Hosted Preview and subsequent Dev/Main checks remain release gates.
