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
lastReviewedAt: 2026-09-27
lastReviewedCommit: 37d8ccc54dc5f4f8fb8501b82f233a24f91299a2
lastReviewedNote: "Reviewed Database #735 exact Main-to-Dev backmerge of #733/#734 at 5935527b3564fc519549766cc65375a3eca4fd61. The combined 390-migration history retains all three existing Dev-only migrations byte-for-byte and reaches 20260926143000. Reader definitions and public contracts retain the qualified Main bytes; seven scoped suites pass 188 assertions. Generated schema/types are regenerated from the isolated combined history. CI, official Preview and persistent Dev publication remain separate gates; Root #1570 selects Main only."
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
- The retained V1 empty-query, geography-only Flow Search has its narrow Facet fast path. V2 and V3 query-free Process/Flow Search use the existing navigation and facet projections for filtering and page selection; relevance/date sorts hydrate only the selected page, while name ordering still reads matched names. V2 filtered/text Facets and V3 filtered Facets/navigation counts reuse narrow facts. Legacy V2 text Search keeps authoritative pattern/CAS keys, evaluates only original ranking facts before pagination and derives display reasons from at most the selected page; it preserves public score/cursor semantics and has no new projection/index/writer. Cutover verifies complete, consistent coverage; no index, relation, Trigger, writer or timeout is added. See `docs/agents/repo-architecture.md` and `docs/agents/repo-validation.md` for the read and proof boundaries.
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
