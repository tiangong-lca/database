---
title: database-engine AI Working Guide
docType: contract
scope: repo
status: active
authoritative: true
owner: database-engine
language: en
whenToUse:
  - when a task may change database schema, migrations, seeds, Supabase branch config, or database-side SQL tests
  - when routing work from the workspace root into the database-engine repo
  - when deciding which document owns a rule, command, or path boundary in this repo
  - when defining or changing the anonymous Portal public DTO contract
whenToUpdate:
  - when repo ownership or source-of-truth paths change
  - when branch policy or workspace integration rules change
  - when the current documentation system becomes redundant or ambiguous
checkPaths:
  - AGENTS.md
  - README.md
  - README.zh-CN.md
  - .docpact/**/*.yaml
  - contracts/portal/**
  - docs/agents/**
  - supabase/config.toml
  - supabase/migrations/**
  - supabase/tests/**
  - supabase/templates/**
  - supabase/seed.sql
  - supabase/seeds/**
  - supabase/workspace/**
  - scripts/**
  - docs/agents/**
  - .github/workflows/**
  - .env.supabase*.example
  - .githooks/**
  - scripts/docpact
  - scripts/docpact-gate.sh
  - scripts/install-git-hooks.sh
lastReviewedAt: 2026-09-23
lastReviewedCommit: 15afe29391b0ec3b44602a64bc769b8851583c1f
lastReviewedNote: "Reviewed for Database #670 with workspace #1432: records the guarded owner-draft before-content save facade in the capability facts; repo contract, branch rules and hard boundaries are unchanged. Reviewed for Database #673 (Foundry #60) with workspace #1432: the Time alias v2 RED baseline adds one database test file only; repo contract, architecture map and proof ownership are unchanged. Reviewed for Database #673 (Foundry #60) with workspace #1432: the guarded v2 batch executor is now real behaviour GREEN — closed envelope and source evidence, Product-flow eligibility, the canonical five-key reference derived from the target's own common:name, the functional-unit binding, exact replay with zero writes and write-pass rollback; the repo contract, branch rules and hard boundaries are unchanged. Reviewed for Database #673 (Foundry #60) with workspace #1432: the v2 batch executor now binds the functional unit through the real source-number namespace (TIDAS internal ids versus original EcoSpold source numbers) — the reference exchange is bound by internal id, the functional unit by that exchange's reviewed source number, the leading quantity must equal the exchange's own source quantity, and a claim contradicting the stored reviewed source comment is an evidence mismatch; the real-shape fixture (internal 1/source 730045/quantity 1 plus internal 2/source 730046/1.03E-4) proves different source numbers pass while every mis-binding is refused, 60/60 GREEN. No governed rule, proof bar, branch or capability semantics change. Reviewed for Database #673 (Foundry #60) with workspace #1432: the v2 executors are aligned with the shared CLI cohort contract (claimed canonical digests verified server-side, source_flowproperty, the full five-key reference in the flow mutation, quantitative_reference and four amount fields per exchange entry, the text_actions block as the functional-unit authority, amount_field_count, the source unit-group snapshot) and the new guarded v2 plan executor validates the shared plan envelope, assembles the one batch it executes and keeps a replay-safe whole-plan summary; 75 behaviour assertions GREEN. No governed rule, proof bar, branch or capability semantics change. Reviewed for Database #673 (Foundry #60) with workspace #1432: root's final expected-count and derivative-target semantics are adopted — the plan carries the ten flat v1 expected keys plus the versioned text_action_count, the audit count must match the row+batch+plan audit topology actually written, the six-key derivative targets must be one per changed identity with the exact actor and owner-draft state, and the source unit-group snapshot is documented as the source alias's current declared unit group (the historical hr record is provenance only); 81 behaviour assertions GREEN. No governed rule, proof bar, branch or capability semantics change. Reviewed for Database #673 (Foundry #60) with workspace #1432: the versioned protected lifecycle is added against the current post-cutover surface — api.cmd_dataset_alias_execution_{preflight,gate,admit}_v2_guarded, _read_v2 and the service-only _execute_v2 with its CLI-ALIAS-02 capability rows, the v2 receipt/request/preflight tables in util, the preserved 180-second gate window, five-key admission, single-attempt dispatch and nonce-bound callback, and plan-derived expectations; the historical public.command_audit_log references follow the cutover into private, the frozen contract suite passes fully (14/14) and v1 stays byte-identical. No governed rule, proof bar, branch or capability semantics change beyond the additive versioned surface. Reviewed for Database #673 (Foundry #60) with workspace #1432: the v2 protected preflight and gate are plan-derived end to end after converting the last copied v1 cohort pins (declared target count and per-table split, plan-derived simulation/gate material and responses, the gate's stored-plan reference); a live local preflight plus all three gates now pass on real rows with stored receipts. The protected behaviour matrix suite is parked outside the tree while its admit helper is repaired. No governed rule, proof bar, branch or capability semantics change. Reviewed for Database #673 (Foundry #60) with workspace #1432: the versioned protected boundary now accepts the reviewed CLI's real wire — the plan-request and derivative-set digests follow the producer's own definitions, the expected freeze and approval are the producer's thirteen and fourteen key envelopes, the protected expected block is the versioned eleven-key claim block, the alias identity digest binds the {id, version} tuple, the Flow property collection decodes in either deployed shape, and the executor and read paths carry plan-derived audit and derivative counts instead of the v1 cohort constants; the parked manual fixture is replaced by a conformance suite built from the CLI's own request document that drives preflight, the three gates, admission, the service-only executor and the readback, and pins the refusals around them (61/61). The private-inventory pin learns one more v2 helper (396) and the api contract-closure migration-head pin advances to 20260921190000. No governed rule, proof bar, branch or capability semantics change. Reviewed for Database #673 (Foundry #60) with workspace #1432: the five versioned Time-alias v2 suites (math, decimal parity vectors, frozen contract, batch/plan behaviour, protected lifecycle conformance) are now part of the required local-contract selection in .github/workflows/supabase-dev.yml and of the workflow contract test's pinned tokens, and the generated schema workspace and Data API types were regenerated with the CI-pinned Supabase CLI 2.117.0 and re-generated deterministically. Deployment boundaries, routing, ownership and the branch policy are unchanged; no historical suite was swept into the selection.Reviewed for Database #677 (Foundry #60) with workspace #1432: the official Production CLI class gains the additive CLI-ALIAS-02 capability through a one-time drift-repair migration that selects the unique enabled CLI holding the exact prior five-capability class under the registry lock (zero-match is a no-op, ambiguity fails closed, one exact replace audit event, idempotent rerun); the five protected Time-alias v2 routes keep their exact manifest roles (four authenticated-only actor routes plus the service-role-only executor callback), and the one-shot admission now queues its executor callback with an explicit api content profile so the dispatch cannot fall back to the default public profile. Deployment boundaries, routing, ownership and the branch policy are unchanged.Reviewed again for Database #674 (Foundry #186) with workspace #1432: the closed Length*time kmy-to-m*a profile lands as a second explicit profile over the reviewed protected lifecycle, selected only by the plan's own schema_version through one closed internal discriminator; the Time profile, its factor, its mandatory flow action, its alias-property closure and its ALIAS_V2_* codes are unchanged, no business-data column is added, and the generated schema workspace and Data API types were regenerated deterministically with the CI-pinned Supabase CLI. No governed rule, proof bar, branch, routing or generated-path ownership changes. Reviewed for Database #680 with workspace #1432: the Time-alias v2 fresh closure now re-verifies the plan's bound support (canonical target property and unit group, the source alias flow property and its declared source unit group) and the exact global occurrence set of the changed Flows on every read, so a support or consumer change after the run makes live_closure_proof false and the public read cannot report passed/applied; the Time math, write set, request/receipt shapes, nullable-FU semantics and historical v1 behavior are unchanged. Deployment boundaries, routing, ownership and the branch policy are unchanged. The same exact target identity (id, version and reference kind) is enforced by the pre-write batch executor, so the protected preflight, gate and service-execute simulations reject an invalid relation before admission.Reviewed for Database #686 with workspace #1432: the fresh-run global occurrence closure of the claimed Flows is made candidate-driven in all five statements across the four functions that carried it — private.cmd_dataset_alias_batch_v2_guarded, util.read_dataset_alias_execution_v2_primary_closure, private.cmd_dataset_length_time_v1_guarded and util.read_dataset_length_time_v1_primary_closure — by probing the existing processes_json_ordered_alias_exchange_gin_idx and keeping the unchanged exact occurrence predicate and primary-key readback, so the closure cost follows the plan rather than the Process table; at the observed hosted magnitude (44,477 Processes / 134,609 Flows) the deployed scan costs 3.4 s and 287k shared buffers against a hosted preflight database execution of 40,343 ms under a 55-second gate budget, and the four replacement functions are byte-identical to their deployed definitions apart from that substitution; every rule, count, drift condition, returned material, ACL and timeout is unchanged, one malformed-collection behaviour difference is deliberate and pinned, the existing v2 batch suite learns three occurrence-refusal cases, the generated schema workspace is regenerated deterministically against a clean migration build on the CI-pinned Supabase CLI 2.117.0 with database.types.ts unchanged, and the committed conflict markers in AGENTS.md are removed with the union variant preserved. No governed rule, proof bar, branch, routing or capability semantics change.Reviewed for Database #689 with workspace #1432: the guarded derivative rebuild's dispatch-body predicate now the dispatch-body matcher is left exactly as it was and the bounded batch admission instead builds one candidate cache per batch of at most fifty targets, after every target has been fully validated and locked, so each target's quarantine delete narrows to the cached candidate superset (its matched row ids plus rows absent from the snapshot or with a changed ctid version) while the original matcher still decides every candidate row on its current body; the per-target row set, the 3-arg owner, every lock, audit, count, snapshot re-check and rollback rule are unchanged, and the batch suite pins the matcher's original predicate (verbatim, escaped-id, ordinary-escape, decoy, literal backslash-u prose, NULL-id and missing-record-id NULL semantics) plus the cached delete row effects (single, shared-array, wrong-version, unrelated-URL, new-row, changed-ctid and late-failure rollback). No governed rule, proof bar, branch, routing or capability semantics change. Reviewed for Database #689 with workspace #1432: the generated schema workspace is regenerated against a clean migration-built stack on the CI-pinned Supabase CLI 2.117.0 after the dispatch-body pre-filter migration, a second regeneration is diff-clean, and database.types.ts is byte-identical to a fresh generation.Reviewed for Database #694 with workspace #1432: the canonical JS object-key sort key gains a pure-ASCII fast path written under the explicit C collation, with the published per-character loop kept verbatim as the fallback for every non-ASCII value and for the empty key, so the array-index branch, the UTF-16 and surrogate arithmetic, the two sort-key prefixes, the declared volatility, the pinned search_path and the ACLs are unchanged; the guarded Time v2 batch executor stops recomputing two payload digests for its row audit and its replay proof and instead reuses the producer's before_sha256 and desired_sha256, which the untouched structural parity guard has already proved equal to the server canonical digests of the claimed before payload and of the server-derived payload that is committed, the two verified digests riding only in the internal prepared envelope, which is never hashed, never returned and never shape-validated. No governed rule, proof bar, branch, routing, capability or time budget changes."
related:
  - .docpact/config.yaml
  - docs/agents/repo-validation.md
  - docs/agents/repo-architecture.md
  - docs/agents/supabase-branching.md
---

## Repo Contract

`database-engine` owns the checked-in Supabase database contract for the TianGong LCA workspace: schema truth, versioned public DTO schemas under `contracts/portal/**`, migration history, Auth email template sources, operator branch bindings, database-side tests, the automation that deploys committed migrations to the persistent Supabase `dev` branch, and the production Supabase GitHub integration contract that applies Git `main` migrations.

Start here when the task may change schema truth, branch bindings, generated schema-workspace tooling, repo validation rules, or documentation ownership inside this repo.

## Documentation System Principles

This repository treats documentation as an information system, not as narrative writing.

Required principles:

- single source of truth: one rule has one owning document
- one document, one job: each document solves one problem clearly
- conclusion first: put purpose, rules, steps, and boundaries before background
- no redundant prose: keep facts, rules, commands, exceptions, and validation; remove filler
- no ambiguity: prefer explicit conditions and exact actions over vague guidance
- executable commands: any documented command must run as written
- verifiable rules: readers must be able to tell whether they followed the rule correctly
- rules before explanation: operational content comes before rationale
- stable structure: same document type uses the same section order where practical
- reference instead of duplication: when a rule already has an owner, link to it instead of restating it

## Documentation Roles

| Document | Owns | Does not own |
| --- | --- | --- |
| `AGENTS.md` | repo contract, documentation principles, branch and delivery rules, hard boundaries | deep implementation details or large reference material |
| `.docpact/config.yaml` | machine-readable repo facts, routing intents, lint rules, governed-doc inventory | prose explanations and narrative summaries |
| `docs/agents/repo-validation.md` | minimum proof by change type and PR validation note shape | branch rationale or schema-workspace mental model |
| `docs/agents/repo-architecture.md` | compact repo mental model and stable-versus-generated path map | execution checklist details |
| `docs/agents/supabase-branching.md` and `docs/agents/supabase-branching_CN.md` | branch-specific database operations and branch-binding workflow | repo-wide validation matrix or generated-path map |
| `scripts/README.md` and `scripts/README.zh-CN.md` | helper-script usage and supported migration-generation flows | repo contract or branch-policy truth |
| `supabase/workspace/README.md` and `supabase/workspace/README.zh-CN.md` | generated-workspace contract and refresh warnings | schema source-of-truth ownership |

Additional governed source docs, not part of the default first-load surface:

| Document | Owns | Does not own |
| --- | --- | --- |
| `README.md` and `README.zh-CN.md` | repo landing context and high-level purpose | repo contract, proof bar, or branch-policy truth |

## Load Order

Read in this order:

1. `AGENTS.md`
2. `.docpact/config.yaml`
3. `docs/agents/repo-validation.md` or `docs/agents/repo-architecture.md`
4. `docs/agents/supabase-branching.md`
5. `supabase/workspace/README.md` or `scripts/README.md` only when the task touches schema-workspace tooling

Do not start from generated schema workspace files, long migration history, or GitHub default-branch UI.

## Operational Pointers

- path-level ownership, routing intents, governed-doc inventory, and lint rules live in `.docpact/config.yaml`
- minimum proof and PR validation note shape live in `docs/agents/repo-validation.md`
- stable path ownership and generated-workspace rules live in `docs/agents/repo-architecture.md`
- deeper branch-operation rules live in `docs/agents/supabase-branching.md`
- repo-local documentation maintenance is enforced locally by the pre-push docpact gate; `.github/workflows/ai-doc-lint.yml` is manual-dispatch fallback

## Minimal Execution Facts

Keep these entry-level facts in `AGENTS.md`. Use `docs/agents/repo-validation.md` and the narrow source docs for the full details.

- local baseline: `supabase start`, `supabase db reset`, `supabase migration list`
- schema boundary: `public` contains only `processes`, `flows`, `contacts`, `sources`, `unitgroups`, `flowproperties`, `lciamethods`, `lifecyclemodels`, and `ilcd`; client RPCs live in the exposed `api` schema, internal state and service helpers live in `private`, operational tooling lives in `util`, and retired rollback evidence lives in `archive`
- PostgREST exposes `public` and `api`; entity access keeps `public` as the default profile, while RPC callers must select the `api` profile explicitly
- Supabase Auth owns OAuth client credentials and refresh tokens; the database stores only public `client_id`, enabled/revoked state, capability grants, and audit history. Direct MCP hosts use separate public manual clients per host/environment while Dynamic Client Registration remains disabled; environment UUIDs are provisioned only through the service façade and never migrations. The official Production CLI client keeps the exact capability class `CLI-ALIAS-02`, `CLI-RPC-01`, `DB-CORE-READ-01`, `DB-CORE-WRITE-01`, `NX-CORE-02`, and `EDGE-BUNDLE-01`; changing that environment-specific grant is database-engine-owned and must use `api.svc_oauth_client_configure`, guarded by exact before/after readback and durable audit evidence. The five protected Time-alias v2 endpoints are actor-gated by `CLI-ALIAS-02`: the four actor-facing routes are authenticated-only, and the one-shot service-only executor callback stays service-role-only and is queued with an explicit `api` content profile so the dispatch cannot fall back to the default `public` profile. The v2 batch executor and the fresh closure both require the locked target flow property to reference exactly the declared unit group by id, exact version and reference kind, and the v2 fresh closure re-verifies the plan's bound support and the exact global occurrence set of the changed Flows on every read, so a support or consumer change after the run cannot read back as applied. A one-time drift-repair migration may locate a client only by one unique exact capability-class precondition so it deploys automatically without embedding an environment UUID; zero matches are a no-op and ambiguity fails closed. First-party sessions without `client_id` retain existing `auth.uid()` behavior. OAuth relation reads require `DB-CORE-READ-01`; raw table DML remains ACL-closed, actor create/save/delete uses the existing command RPCs under `DB-CORE-WRITE-01`, the guarded `cmd_dataset_save_draft_guarded` facade reuses that same owner-draft write capability to reject concurrent before-content drift atomically in the save transaction, and the two exact LifecycleModel bundle commands use `EDGE-BUNDLE-01` rather than the broad `CLI-RPC-01`; every relation/RPC route fails closed through restrictive RLS plus the manifest-backed PostgREST pre-request hook
- anonymous Portal numerics come only from immutable publication-bound typed projections; Search, Detail, and Versions derive `lciaVisible` and Detail publication context from the same current finalized non-revoked predicate as the numeric reader; Search and Hybrid add their shared public card context only after ordering and limit by exact `kind/id/version` source lookup through one manifest-guarded allowlist helper, with no second projection or writer hook; the complete Hybrid read/decorate call tree has one bounded 20-second correctness budget, while latency remains measurement-only and Search/LCIA retain their independent bounds; V3 Worker staging and package readiness are service-only and lease-fenced, predictable package/result/projection drift is rejected before insert, every unexpected post-insert validation failure rolls back the insert and temporary job-schema mutation, an immediate exact retry may recover only a fully matching committed package, and a reclaimed Worker may use the current job lease for locator-free readback of the immutable package/old prepared projection without reusing the old projection lease; package publish prepare/command and projection prepare/finalize re-run the same authoritative binding guard before advancement, while raw projection/artifact tables never gain browser access
- empty-query, geography-only Flow Search reuses the synchronized narrow Facet child for latest/filter/cursor/order/limit before hydrating at most 51 parent cards; it adds no index, relation, Trigger, or writer work and every other Search shape retains the general card-facts path
- Portal catalog-summary classification examples require a public code of at least four characters and prefer Process evidence; exact Flow CAS uses the existing expression B-tree under forced RLS, whose row-neutral Portal SELECT policy is safe only because the table has a validated state-100/200 CHECK and the runtime projection assertion pins both facts. One-code-point empty-filter relevance pre-limits on the synchronized narrow character child; multi-code-point, non-UUID, unfiltered Process relevance keeps the existing PGroonga match/latest set but selects exact-name/classification and general rank keys through one manifest-guarded expression GIN before hydrating at most `limit+1` parent cards. Flow, UUID, empty-query, filtered, and alternate-sort shapes retain their prior kernels. Representative benchmarks must prove the exact-rank GIN naturally, include index bytes and writer amplification, preserve byte-identical pages/cursors, and keep the 2-second Search p95 and 8-second hard timeout
- `supabase/seed.sql` must remain an executable SQL batch even when it seeds no rows; retain a data-neutral no-op rather than comments only
- hosted mutation E2E assets under `supabase/tests/preview/**` are exact-Preview, disposable test paths; their complete actor, credential, recovery, and cleanup proof requirements live in `docs/agents/repo-validation.md`
- migration authoring starts from Git `dev`, not GitHub default-branch UI
- preview-branch proof belongs to the repo PR
- PR Preview transport failure logs may expose only the HTTP status and a shape-validated PostgREST or SQLSTATE code; raw response bodies, messages, details, hints, credentials, and request payloads remain unlogged
- PR Preview runtime verification belongs to the pull-request-only job in `.github/workflows/supabase-dev.yml`: forks skip before authority is available; same-repository PRs first check out the exact head and verify the event base/head commits. The classifier compares only deployable Preview inputs: `supabase/config.toml`, `supabase/migrations/`, `supabase/seed.sql`, `supabase/seeds/`, and `supabase/functions/`. Repository-only workspace, test, template, and documentation changes do not create a Preview dependency. An exact zero diff over the deployable set succeeds without Preview authority or hosted mutation and accepts the official Supabase App `skipped` result. Any deployable change fails closed unless the access token, main-parent ref, and persistent-Dev ref all exist; it then requires one successful official `Supabase Preview` check, exact BranchResponse identity, the three-field PostgREST PATCH/readback, enabled public-key selection, and anonymous Hybrid/sitemap probes. The job never links, pushes migrations, deploys Functions itself, or targets persistent Dev or production.
- persistent `dev` migration deployment belongs to `.github/workflows/supabase-dev.yml`; after the local contract passes, it links the configured Dev project, runs exactly one `supabase db push --include-all`, applies only the exact `db_schema`, `db_extra_search_path`, and `max_rows` PostgREST runtime contract through one targeted Management API PATCH, derives the expected head from the checkout, reads the settings back, and probes the default `public`, explicit `api`, rejected `private`, and retired `public` RPC routes; it must never deploy or delete Edge Functions or run a broad project-configuration push
- after the persistent `dev` database workflow succeeds, deploy and validate the intended Dev Functions through `tiangong-lca-edge-functions`; this repo does not own the Function source, function selection, or deploy command
- production `main` proof belongs after `dev -> main` promote and should confirm Supabase GitHub integration applied migrations automatically; when `supabase/config.toml` changes, the operator must also push and verify that configuration against the production project
- production-volume administrative backfills must fit the platform statement timeout or use a bounded session override that is restored immediately after the statement; Preview row counts alone are not sufficient volume proof
- root workspace proof belongs later in `lca-workspace`
- generated workspace helpers are low-risk to inspect with `python scripts/<name>.py --help`

## Ownership Boundaries

The authoritative path-level ownership map lives in `.docpact/config.yaml`.

At a human-readable level, this repo owns:

- `supabase/config.toml`
- `supabase/migrations/**`
- `supabase/seed.sql`
- `supabase/seeds/**`
- `supabase/tests/**`
- database-side API façades, policies, ACL/capability manifests, protected mutation boundaries, review/publication state, worker queue/domain state, and release/scope-closure durable contracts
- `scripts/**` for schema export, workspace refresh, change copying, and migration generation
- `.github/workflows/supabase-dev.yml`
- production Supabase GitHub integration contract for Git `main`
- `.env.supabase.dev.local.example`
- `.env.supabase.main.local.example`
- repo-local governance and branching docs

This repo does not own:

- worker completeness/numerical diagnostic logic or report generation
- frontend runtime env selection or app-side Supabase clients
- Edge Function runtime code
- workspace submodule pointer bumps or delivery completion

Route those tasks to:

- `tiangong-lca-worker` for the combined completeness/numerical diagnostic and its report payload semantics
- `tiangong-lca-next` for frontend envs and app-side Supabase integration
- `tiangong-lca-edge-functions` for Review Admin-only diagnostic orchestration and other Edge Function runtime behavior
- `lca-workspace` for root integration after merge

## Branch And Delivery Facts

- GitHub default branch: `main`
- true daily trunk: `dev`
- routine branch base: `dev`
- routine PR base: `dev`
- promote path: `dev -> main`
- hotfix path: branch from `main`, merge back into `main`, then back-merge `main -> dev`

Do not infer the working trunk from GitHub default-branch UI alone.

## Documentation Update Rules

Use the role table in this file as the update map.

- if a machine-readable repo fact or governed-doc rule changes, update `.docpact/config.yaml` in the same change
- if a human-readable repo contract, branch rule, or hard boundary changes, update `AGENTS.md`
- if proof, architecture, or branch-operation guidance changes, update only the document that owns that subject
- if a document is governed but not in the default first-load surface, route to it on demand instead of duplicating its rules into `AGENTS.md`
- do not copy the same rule into multiple docs just to make it easier to find

## Hard Boundaries

- do not treat `supabase/workspace/remote_schema.sql`, `global/**`, or `schemas/**` as stable edit locations
- do not deploy Edge Functions from this repo; persistent-Dev Function deployment and runtime validation must use the Edge repository's current procedure
- do not move frontend `.env` or app-side client logic into this repo
- do not treat a merged PR here as delivery-complete when the workspace still needs a submodule bump

## Workspace Integration

A merged PR in `database-engine` is repo-complete, not delivery-complete.

If the change must ship through the workspace:

1. merge the child PR into `database-engine`
2. make sure the intended SHA is eligible for root integration
3. update the `lca-workspace` submodule pointer deliberately

For normal root `main` integration, `lca-workspace/main` should point only at commits already promoted onto `database-engine/main`.

## Local Docpact Push Gate

Install the versioned local hook once per checkout:

```bash
./scripts/install-git-hooks.sh
```

The `pre-push` hook runs `scripts/docpact-gate.sh`, which delegates CLI lookup to `scripts/docpact` and performs strict config validation plus enforced lint before the push leaves the machine. The wrapper checks `DOCPACT_BIN`, Cargo install locations, Homebrew install locations, and then `PATH`, so local agent shells should not fail only because bare `docpact` is unavailable. The default comparison base is `origin/dev` for routine branches and `origin/main` for promote or hotfix branches. Override it for unusual stacks with `DOCPACT_BASE_REF=<ref>` or `scripts/docpact-gate.sh --base <ref>`. The gate writes its detailed report to a temporary file so normal pushes do not create `.docpact/runs/` artifacts.
