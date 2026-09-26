---
title: Supabase Branching
docType: guide
scope: repo
status: active
authoritative: false
owner: database-engine
language: en
whenToUse:
  - when changing Supabase branch bindings, preview behavior, or persistent dev automation
  - when confirming the branch-specific database workflow for this repo
whenToUpdate:
  - when branch bindings, Vault secret rules, or the persistent dev deployment path change
  - when branch-operation guidance diverges from repo contract or validation guidance
checkPaths:
  - docs/agents/supabase-branching.md
  - AGENTS.md
  - .docpact/config.yaml
  - supabase/config.toml
  - supabase/templates/**
  - scripts/check_auth_email_templates.py
  - .github/workflows/supabase-dev.yml
  - .env.supabase.dev.local.example
  - .env.supabase.main.local.example
lastReviewedAt: 2026-09-27
lastReviewedCommit: 3326a6701763cbf4bbcf4f61298b3f8f54a3fd16
lastReviewedNote: "Reviewed Database #733: the legacy V2 regression joins the unchanged local/ARM64/official-Preview gates; exact Main hotfix, required Dev backmerge, credential isolation and production GitHub publication boundaries remain."
related:
  - ../../AGENTS.md
  - ../../.docpact/config.yaml
  - ./repo-validation.md
  - ./repo-architecture.md
  - ./supabase-branching_CN.md
---

# Supabase Branching

`database-engine` is the single Supabase source-of-truth repository for the TianGong LCA workspace.

This repository owns:

- `supabase/config.toml`
- `supabase/migrations/*.sql`
- `supabase/seed.sql`
- `supabase/seeds/*`
- `supabase/tests/*.sql`
- `supabase/templates/*.html`
- `.env.supabase.dev.local.example`
- `.env.supabase.main.local.example`
- `.github/workflows/supabase-dev.yml`
- branching and operations documentation for database delivery

This repository does **not** own:

- frontend runtime env files such as `.env` or `.env.development`
- app-side Supabase client code
- Edge Function runtime code

Those stay in consumer repositories such as `tiangong-lca-next` and `tiangong-lca-edge-functions`.

## Branch contract

- Git `main` -> production baseline migrated automatically by the Supabase GitHub integration
- Git `dev` -> persistent Supabase `dev` branch migrated and verified by `.github/workflows/supabase-dev.yml`
- PR / feature branches -> preview branches created by the Supabase GitHub integration

Rules:

- GitHub default branch remains `main` as a platform exception.
- Daily trunk is Git `dev`.
- Routine feature and fix branches start from `dev` and PR back into `dev`.
- `dev -> main` is the promotion path.
- Do not infer the working trunk from GitHub default-branch UI alone.

When review changes an already-applied PR migration, add a later migration that reapplies the authoritative final schema/functions for the existing Preview branch. Still retain and run a real populated canonical-base-to-head upgrade test, because the additive Preview repair does not by itself prove first-time production upgrade safety.

## Repository contract

- Keep one shared `supabase/` directory in Git.
- Treat committed files in `supabase/migrations/` as the schema source of truth for production, `dev`, and preview branches.
- Keep branch-specific overrides in `[remotes.<branch>]` inside `supabase/config.toml`.
- Do not create a separate `supabase/` directory per Git branch.
- Keep the pull-request-only Preview runtime job isolated from deployment. Fork PRs skip before authority. A same-repository PR first checks out the exact event head and verifies both event commits. It compares only deployable Preview inputs: `supabase/config.toml`, `supabase/migrations/`, `supabase/seed.sql`, `supabase/seeds/`, and `supabase/functions/`. Generated workspace, tests, Auth templates, and repository documentation are not deployment inputs. If that set has no diff, the job succeeds without secrets, branch resolution, or hosted mutation and accepts the official App's `skipped` result. Any deployable change retains the exact official-check, BranchResponse, PostgREST, key, Hybrid, and sitemap proof and fails closed when authority is missing.
- Keep `.github/workflows/supabase-dev.yml` as the sole persistent-`dev` migration deployer. It may run `supabase link`, exactly one `supabase db push --include-all`, and one Management API PATCH limited to `db_schema`, `db_extra_search_path`, and `max_rows` so the running PostgREST instance matches the checked-in contract; it must not deploy/delete Edge Functions, run `supabase config push`, or mutate any other project setting.
- The separate ARM64 scheduler-profile job rebuilds only a local database and runs both full synthetic performance cohorts, resetting between them. The x64 local-contract job retains the functional and security suites; persistent Dev deployment waits for both jobs. The profile job has no hosted credentials or deployment authority.
- After the database workflow succeeds, deploy and validate the intended persistent-Dev Functions through `tiangong-lca-edge-functions`. Function source, function selection, deployment commands, and runtime validation remain owned by that repository.
- Do not add a checked-in GitHub Actions production deploy for Git `main`; the production project is migrated by the Supabase GitHub integration bound to this repository.
- Do not author normal schema changes by editing the remote database first and reconstructing migrations later.

### Edge Function deployment

- This repository contains no `supabase/functions/` runtime source and does not deploy Functions.
- After the persistent-Dev database workflow succeeds, deploy the intended Dev Functions from `tiangong-lca-edge-functions` and run that repository's current validation procedure.
- Keep the function list, deployment command, authentication settings, and runtime probes in the Edge repository instead of duplicating them here.

## Files to maintain

- `supabase/config.toml`: shared baseline plus `[remotes.dev]`
- `.github/workflows/supabase-dev.yml`: rebuilds the local contract, repairs and verifies the exact PR Preview runtime without schema deployment, deploys committed migrations to persistent `dev`, and verifies the exact hosted result
- `supabase/migrations/*.sql`: committed migration history
- `supabase/seed.sql`: shared seed data
- `supabase/seeds/dev.sql`: optional persistent-dev-only seed data
- `supabase/tests/*.sql`: database assertions and safety checks
- `supabase/templates/recovery.html`: canonical password-recovery email body
- `.env.supabase.dev.local.example`: template for the persistent `dev` branch binding
- `.env.supabase.main.local.example`: template for the `main` branch binding
- `docs/agents/supabase-branching.md`: English branching workflow
- `docs/agents/supabase-branching_CN.md`: Chinese branching workflow

Frontend consumer-repo env files are intentionally **not** maintained here.

## Operator env files

Keep the branch-binding templates at the repository root:

- `.env.supabase.dev.local.example`
- `.env.supabase.main.local.example`

Usage rules:

- Copy them to `.env.supabase.dev.local` or `.env.supabase.main.local` for local-only secrets.
- Do not commit the real `.local` files.
- Use them for operator workflows that need `SUPABASE_PROJECT_REF` or `SUPABASE_DB_URL` for the persistent `dev` or `main` branches.
- Frontend `.env` or `.env.development` files still belong in consumer repos such as `tiangong-lca-next`.

## GitHub integration and secrets

Supabase GitHub integration for the production project must point to:

- repository: `tiangong-lca/database`
- relative path: `supabase`

This integration applies committed migrations to the production project automatically
when Git `main` advances. Absence of a checked-in GitHub Actions workflow for
`main` does not mean production migration is manual-only.

Repository configuration expected by `.github/workflows/supabase-dev.yml`:

- variable `SUPABASE_MAIN_PROJECT_ID`, set to the parent production project ref used by Supabase Branching
- variable `SUPABASE_DEV_PROJECT_ID`
- secret `SUPABASE_ACCESS_TOKEN`
- secret `SUPABASE_DEV_DB_PASSWORD`

The Preview job uses `SUPABASE_MAIN_PROJECT_ID` only as the Branching parent,
`SUPABASE_DEV_PROJECT_ID` only as an exclusion guard, and
`SUPABASE_ACCESS_TOKEN` only in the branch/config/public-key Management steps.
`SUPABASE_DEV_DB_PASSWORD` remains exclusive to the push-only persistent-Dev job.

## PR to Supabase migration path

Committed migration files do not affect any remote database until one of the
deployment paths below runs.

Normal PR path:

1. A feature branch includes new files under `supabase/migrations/`.
2. The PR targets Git `dev`.
3. When the PR changes a deployable config, migration, seed, or Function
   input, Supabase GitHub integration creates or updates the preview branch.
4. That preview is PR-scoped proof only, never persistent `dev`. A PR with an
   exact empty base-to-head deployable-input diff needs no preview branch; the
   repository job ends successfully after allowlist classification.
5. After the exact `Supabase Preview` check succeeds for the current PR head,
   the same-repository Preview runtime job resolves that exact Git branch,
   applies and reads back only `db_schema=public,api,graphql_public`,
   `db_extra_search_path=public,api,extensions`, and `max_rows=1000`, then uses
   only a publishable or legacy anon `apikey`—without `Authorization` or
   `Cookie`—to validate the strict explicit-`api` Portal Hybrid response,
   forged-parameter opacity, rejected `private`/`public` profiles, and the
   fixed sitemap manifest/shard contract. Hybrid and sitemap readiness each
   stop at one 300-second deadline; sitemap still runs after Hybrid failure so
   the hosted evidence is not coupled.
6. After merge, `.github/workflows/supabase-dev.yml` performs a blank local
   rebuild, links the configured persistent Dev project, and runs
   `supabase db push --include-all` after the local contract passes.
7. The workflow derives the expected head from the checked-out migration
   directory and waits until a service-only readback reports that exact head;
   it never carries a manually pinned head.
8. The workflow applies one targeted Management API PATCH containing only
   `db_schema=public,api,graphql_public`,
   `db_extra_search_path=public,api,extensions`, and `max_rows=1000` before
   the first hosted RPC probe. It then reads all three values back and probes
   the hosted Data API boundary; the remaining verification is read-only.
9. After the database workflow succeeds, deploy and validate the intended Dev
   Functions through `tiangong-lca-edge-functions`.

An existing Preview branch applies newly added migration files on later PR
pushes. Editing a migration already recorded in that Preview's migration
history does not reapply it. Ship an additive follow-up migration for forward
changes; use explicit Preview branch reprovision only when the intent is to
discard and rebuild that disposable branch state.

### Pull-request Preview runtime verification

- This job runs only for `pull_request` events from the same repository and
  depends on the local contract. Fork PRs skip before receiving authority. A
  same-repository PR proves its exact event base/head commits and deployable
  input allowlist before any secret or Management API step.
- Missing `SUPABASE_ACCESS_TOKEN`, `SUPABASE_MAIN_PROJECT_ID`, or
  `SUPABASE_DEV_PROJECT_ID` fails a same-repository PR closed instead of
  guessing a project ref or using persistent Dev as fallback.
- Exact no-change across the deployable input allowlist is the only path that does not require a Preview check. For any allowlisted diff, the accepted check must be from official Supabase App id `330661`, slug/owner `supabase`; the job captures the expected ref from its exact dashboard `details_url`, resolves one matching disposable BranchResponse, and requires ref equality plus main/Dev inequality. Failed, cancelled, skipped, stale, neutral, timed-out, ambiguous, or non-official checks fail closed whenever Preview is required.
  `supabase`; the job captures the expected ref from its exact dashboard
  `details_url`. The pinned CLI then uses `branches list --output json` and
  requires exactly one row matching the Git branch, PR number, parent project,
  `is_default=false`, and `persistent=false`; it reads only BranchResponse
  metadata, captures the strict 20-character `.project_ref`, and requires both
  refs to match plus unconditional inequality with main and persistent Dev. It
  does so only after exactly one `Supabase Preview`
  check has succeeded for the event's exact PR-head SHA. A failed, cancelled,
  skipped, stale, neutral, timed-out, or ambiguous check fails closed.
- The resolved ref must differ from both the configured main parent and
  persistent Dev refs. The job performs no `supabase link`, `db push`,
  Functions command, broad `config push`, seed, or migration operation.
- The Management API mutation is exactly one PATCH to that disposable ref and
  contains only the checked-in PostgREST schema, search-path, and row-limit
  fields. A separate GET must read all three values back before transport proof.
- A separate key step performs one no-reveal Management API GET and examines
  the raw `disabled` field. It accepts only a nonempty, shape-valid enabled
  publishable key, falling back only to a shape-valid enabled legacy `anon`;
  the selected public key is masked/exported, then the PAT and raw JSON are
  cleared. The following REST step has no PAT or service credential and uses
  `apikey` only, never `Authorization` or `Cookie`.
- Hybrid and sitemap readiness each use one 300-second wall-clock deadline.
  Once the public-key step succeeds, the sitemap step runs independently even
  if Hybrid fails; the overall job still fails when either required boundary
  fails.
- If the anonymous explicit-`api` probe fails, the job may print only its HTTP
  status and a shape-validated PostgREST or SQLSTATE code. Raw response bodies,
  messages, details, hints, request payloads, and public keys remain unlogged;
  malformed or unexpected error shapes are reported as `unclassified`.

`--include-all` means every committed migration absent from remote history is
eligible for application. It is required when a governed `main -> dev`
backmerge introduces a migration whose timestamp precedes newer migrations
already recorded on persistent `dev`; migrations already present in remote
history are still skipped.

### One-time Issue #474 persistent Dev ledger repair

Persistent Dev previously recorded the comment-draft migration under version
`20260810170000`, while production recorded a different hotfix under that same
version. The reconciled tree keeps the production file at `20260810170000`,
renames the byte-identical Dev migration to `20260810170001`, and adds the
post-cutover private-schema repair at `20260812090000`.

Before the first persistent Dev deployment of the reconciled tree, an operator
must link to the Dev project, confirm the remote `20260810170000` row is the
old comment-draft migration, and repair only the history ledger:

```bash
supabase migration repair 20260810170000 --status reverted
supabase migration repair 20260810170001 --status applied
supabase migration list
supabase db push --include-all
```

`reverted` deletes the old version record; it does not roll back the SQL that
already ran. `applied` records the renamed, byte-identical migration without
running it again. The final push then applies the production hotfix migration
(a deliberate no-op after the private-schema cutover) and the new private-schema
reconciliation migration. Do not run this sequence against production: its
`20260810170000` record already identifies the canonical production hotfix.
Capture the before/after migration list and hosted validation in Issue #474 or
the delivery PR before allowing the normal persistent Dev workflow to proceed.

Promote path:

1. A `dev -> main` promote PR merges into Git `main`.
2. The production project's Supabase GitHub integration reads the checked-in
   `supabase/` directory from Git `main`.
3. Pending checked-in migrations are applied automatically to the production
   project.
4. If `supabase/config.toml` changed, an operator runs
   `supabase config push --project-ref <production-project-ref> --yes` after the
   migration is present, then verifies the PostgREST configuration through the
   Management API.
5. Operators validate production migration state and application behavior after
   the promote merge.

For a schema-boundary cutover, validation on Preview and persistent `dev` must
cover profile-less core entity access through the hosted default `public`
profile, explicit `public` entity access, explicit `api` RPC access, rejection
of `private`, and absence of the former `public` RPC route. Data API consumers
must select `public` for entity tables and `api` for RPCs rather than relying on
local CLI schema ordering. A short maintenance window may be used for the
production migration, but all consumer changes must already be validated
against persistent `dev` before the `dev -> main` promote.

This repository currently has no checked-in `workflow_dispatch` production
deploy for Supabase. That is intentional: Git `main` is handled by the Supabase
GitHub integration. An operator can still run `supabase link` and
`supabase db push --include-all` locally as an explicit fallback or recovery
path, but that manual action must be recorded in validation or incident notes.

## Auth email template contract

`supabase/templates/recovery.html` is the canonical password-recovery email body,
and `[auth.email.template.recovery]` in `supabase/config.toml` owns its subject and
local CLI binding. Run this static contract before delivery:

```bash
python3 scripts/check_auth_email_templates.py
python3 scripts/test_check_auth_email_templates.py
```

The template must use Supabase's complete `{{ .ConfirmationURL }}` for both the
reset button and a visible copyable fallback. Do not rebuild the verification
URL from `.TokenHash`, and do not label a recovery link as `type=magiclink`.

Committing this file, applying migrations, or merging `main` does not by itself
prove that an existing hosted project's Auth email template changed. After the
code PR is reviewed, an explicitly authorized operator must open the exact
target project in **Authentication -> Email Templates -> Reset Password**, copy
the checked-in subject and HTML without editing the URL expression, save it,
and then send a real recovery email. Validate both the button and copied-link
paths through the Next application, and record the target environment, time,
and pass/fail readback in the delivery Issue or PR. Never paste access tokens,
the rendered recovery URL, or raw email contents into logs or GitHub records.

## Vault secret contract

Database-side functions or triggers that call Edge Functions must read branch-specific Vault secrets.

Current standard names:

- `project_url`
- `project_secret_key`
- `project_x_key` only for the legacy `generate_flow_embedding()` compatibility path

Rules:

- Never hardcode branch URLs or service keys in SQL, migrations, or dumped baseline files.
- Treat the values as branch-specific. `main`, persistent `dev`, and any preview branch that needs webhook execution must each have the required secrets.
- If a branch is recreated or relinked, re-check the Vault entries before testing webhook-driven flows.

## Default workflow

### Routine schema change

1. Sync local Git `dev`.
2. Create a feature branch from `dev`.
3. Start local Supabase.
4. Make schema changes locally.
5. Create a migration with `supabase migration new <name>` or `supabase db diff -f <name>`.
6. Validate with `supabase db reset` and the relevant SQL tests.
7. Commit migrations, seeds, tests, and config together.
8. Open the PR into Git `dev`.
9. Let Supabase create or update the preview branch for that PR.
10. After merge, validate the persistent remote `dev` database, then deploy and
    validate the intended Dev Functions through `tiangong-lca-edge-functions`.
11. Promote `dev` to `main` when ready to release.
12. Validate that the production Supabase project was migrated automatically by
    the Supabase GitHub integration.

### Persistent `dev` branch deployment

- Pushes to Git `dev` are deployed by `.github/workflows/supabase-dev.yml`.
- The workflow first rebuilds and verifies the complete migration history
  locally. The hosted job depends on that success, links the configured Dev
  project, and runs exactly one `supabase db push --include-all`.
- It then applies the exact three-field PostgREST runtime PATCH, derives the
  expected head from its checkout, and fails unless the exact-head readback,
  Management API readback, and REST profile probes match the checked-in
  contract.
- The workflow owns database migrations and the narrow PostgREST runtime
  refresh only. It must not run `supabase functions deploy`, `supabase
  functions delete`, `supabase config push`, or any other Management API
  mutation.
- After the database workflow succeeds, use the Edge repository's current Dev
  deployment and validation procedure. Do not reproduce its function inventory
  or deployment flags in this repository.

### Production `main` deployment

- Pushes to Git `main` are handled by the production project's Supabase GitHub integration.
- The integration watches repository `tiangong-lca/database` with relative path `supabase`.
- Checked-in pending migrations are applied automatically to the production project when `main` advances.
- Project configuration is not assumed to follow the migration automatically;
  when `supabase/config.toml` changes, push it explicitly to the production
  project and verify the hosted PostgREST settings.
- Do not treat the missing checked-in GitHub Actions workflow for `main` as a manual-deploy requirement.
- Use local `supabase db push` only as an explicit fallback or recovery path, and record that action.

### Hotfix flow

1. Branch from Git `main`.
2. Fix the issue.
3. Merge back to `main`.
4. Back-merge `main` into `dev`.
5. Keep migration history aligned across both long-lived branches.

The database validation workflow runs for PRs targeting either `dev` or `main`,
including hotfixes. Both targets receive the local contract rebuild and exact
disposable Preview checks. Persistent Dev deployment still requires a push to
`refs/heads/dev`; a Main PR never deploys that persistent environment.

## Consumer repo boundaries

Use `database-engine` for:

- schema, policy, SQL function, trigger, seed, and config changes
- preview / persistent branch behavior
- database-side tests and migration recovery

Use consumer repos for:

- frontend env selection and app-side Supabase clients
- Edge Function runtime implementation
- app-level validation against `dev`, preview, or `main`

If a task changes both database schema and application behavior, the database change still starts here.

## Recovery rules

- If local and remote migration histories diverge, inspect them with `supabase migration list` before changing anything else.
- Use `supabase db pull` only to baseline an existing remote schema or to capture remote-only drift back into Git.
- If a branch reaches `MIGRATIONS_FAILED`, fix the migration in Git and prefer recreating the failed branch over hand-editing remote state.
- If remote history metadata is wrong, use `supabase migration repair` deliberately and then re-verify the result.

## Local commands

Use the Supabase CLI in this repository.

- `supabase start`
- `supabase db diff -f <name>`
- `supabase migration new <name>`
- `supabase db reset`
- `supabase migration list`
- `supabase link --project-ref <ref>`
- `supabase db push`
