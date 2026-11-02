---
title: Study durable runtime v1
docType: contract
scope: repo
status: active
authoritative: true
owner: database-engine
language: en
whenToUse:
  - implementing or consuming the persistent Study actor and service RPCs
whenToUpdate:
  - Study schema, authorization, command, producer or validation intent behavior changes
checkPaths:
  - supabase/migrations/*study*.sql
  - supabase/tests/*study*.sql
  - supabase/tests/fixtures/study894_runtime_fixture.sql
  - supabase/tests/fixtures/study894_definition_vectors.sql
  - supabase/tests/regression/*study*.py
  - scripts/*study_runtime*.py
  - docs/agents/lca-study-runtime-contract.md
lastReviewedAt: 2026-11-03
lastReviewedCommit: 5ed1cd2cd487ff147695b76762c65e2c8e8100aa
lastReviewedNote: "Database #894: additive W03 persistence and fenced service seams; queue admission, actual producers and disclosure remain W06."
related:
  - ./lca-study-durable-contract.md
  - ./repo-validation.md
  - ../../AGENTS.md
---

# Study durable runtime v1

Database #894 implements W03 persistence under the retained
[durable invariants](lca-study-durable-contract.md). Edge owns public
`lca.study-api.v2`; Worker owns source compilation and numerical/artifact
identities. Internal RPC suffix `v1` does not change the public wire version.

## Available boundary

`api.cmd_study_v1(p_request jsonb)` accepts the closed v2 operations
`study.create`, `member.set`, `study.archive`, `study.select_revision`,
`revision.create/save/freeze`, and `scenario.create/save/freeze`.
`api.qry_study_v1(p_request jsonb)` reads capabilities, Studies, bounded lists,
revisions, scenarios, source acquisitions, preparations and Runs. Replies are
`{ok:true,data:<Edge-owned variant>}` or `{ok:false,code:<fixed Study code>}`.
Direct raw relation access is closed, including ordinary service-role DML.
Ordinary RPCs validate closed nested targets, scopes, definitions and overrides
before persistence. These structural guards mirror Edge's qualified v2 records,
including code-point and UTF8 byte bounds; committed parity vectors are checked
against the Edge-owned schema. Direct PostgREST callers cannot bypass the Edge
parser to persist an unprojectable functional unit, method or assumption record.

W03 does not advertise `model.source.resolve`, `model.prepare`, `run.submit`,
`run.cancel` or `artifact.read`. They return `CAPABILITY_UNAVAILABLE` and create
no placeholder work. The additive W06 task adapter must qualify real admission,
source/export/compilation, cancellation, current disclosure and transport before
enabling those operations. Profile registration is empty on migration; no
algorithm is activated and the P0 qualification profile is never enabled as a
runtime solver. The initial supported profile identity is
`lca.study-explicit-v1`; activation remains a separately verified operation.
Report/review/export/share production structures belong to W09/W13 additive
delivery; the P0 rules remain authoritative for those later structures.

## Actor and team authorization

Actor façades derive `auth.uid()` and current OAuth `client_id`; actor/owner,
producer, lease or validation fields supplied by clients grant no authority.
The manifest has separate `STUDY-READ-01` and `STUDY-WRITE-01` classes. No
existing client receives a grant through this migration. Both SQL bodies and
the existing pre-request manifest guard enforce admission. Read-only OAuth
capability responses exclude writes. First-party sessions without `client_id`
retain the existing actor-based admission convention.

Personal Studies initially have only their owner. Team creation requires a
current existing team `owner` or `admin`. Every team Study access additionally
requires both an explicit Study grant and current team role `owner`, `admin` or
`member`. `is_invited`, `rejected`, `review-admin`, `review-member` and
`data_product_manager` are not research membership mappings. Team roles never
implicitly confer Study grants. Study owner alone manages members/archive;
editor writes; viewer reads. P1 `member.set` permits only editor/viewer/null,
requires Study CAS and current eligible recipient membership, and cannot change
the owner. Revocation can remove an already departed recipient. Personal member
grants and reviewer grants are unavailable in W03.

Demotion among eligible team roles preserves only the explicit Study grant;
demotion to an ineligible role or removal immediately denies access. Regranting
team membership does not create a new Study grant, though an explicit retained
grant becomes usable again. Membership changes increment the Study grant epoch.
This research ACL is independent of source rights and later ReportShare.

## Transactions, hashes and pagination

Actor mutations serialize current capability admission, Study state, team
membership and the actual mutable target. The shared order is OAuth registry
then capability row, Study, eligible team-role rows, target/intent, and any
Worker job. Team-role `FOR SHARE` locks fence non-key role demotions; key-share
alone would not do so. Every Study-targeted mutation locks the same Study row.
Receipts, generation changes, graph validation and domain writes commit together.
Creation serializes the actor/key scope before allocating its stable Study ID.

Receipts are keyed by actor, operation, Study scope and idempotency key. Request
comparison excludes transport `requestId` and schema/key envelope fields but
retains exact operation, target/CAS and command content. Authorization precedes
replay; exact replay precedes fresh CAS, so response loss never replaces work.
An archived Study permits authorized receipt recovery while rejecting new work.
For two-phase freeze, the initial intent acknowledgement redirects to its stored
committed frozen response on actor replay, after current caller authorization.
That terminal recovery survives the intent TTL. An expired unconsumed intent
instead returns `CAPABILITY_UNAVAILABLE`, creates no replacement intent/receipt,
and leaves the draft unchanged.

Database-issued research document hashes use SHA-256 of the versioned domain,
newline and PostgreSQL17 normalized JSONB text. Revision domain is
`lca.study-definition.v1` over definition/preparation/model; Scenario domain is
`lca.study-scenario.v1` over exact StudyRevision/overrides. Arrays retain order.
Clients consume these identities from server readback. This is not a Worker
model semantic hash, frozen Run input hash, artifact-byte hash or calculation
descriptor fingerprint, and must never be substituted for one.
Run applicability annotation time is persisted at the qualified binding event;
reading a Run never invents a new applicability check or rewrites this time.

Parents are distinct frozen same-Study identities.
Scenario creation with a parent allocates a new scenarioRevisionId and retains
that parent's scenarioId. A null parent allocates a new alternative/scenarioId.
Overrides are the complete explicit layer relative to the selected StudyRevision;
parent layers are not implicitly merged. Cloning a new alternative uses a null
parent with copied/edited overrides. Callers cannot supply scenarioId.

The provenance DAG includes
parent edges and captured draft-source preparation dependencies. Source
dependencies exclude the later frozen Scenario's own preparation to avoid a
false self-cycle. Frozen revisions/scenarios and issued artifacts/snapshots are
immutable; prepared bindings and issued results cannot be replaced.

Pagination uses random server-stored opaque cursor identities, bound to actor,
client, schema/operation/Study/kind/limit selection, access epoch and five-minute
expiry. Every continuation rechecks current authorization. Cursors and cached
results are not credentials. A changed selection, actor/client, epoch or expired
cursor is rejected. Initial request size is bounded at 256KiB normalized JSON.

## Synchronous validation intent

`revision.freeze` records a two-minute internal intent without changing draft
status, generation or `not_checked`. Its reply has
`kind:revisionValidationIntent`, intentId, expiresAt, exact revision and
preparation (including ordered methodRefs). The intent stores the original
actor/client, exact target/CAS/content hash, model/preparation and full definition.
Edge validates the captured material synchronously; the public request cannot
carry trusted validation evidence.
Edge validates expiry timestamp shape and uses a monotonic handler deadline;
the database clock alone decides intent expiry. A host/VM wall-clock difference
cannot veto a fresh intent or prevent recovery of an already committed freeze.

Only service-role
`api.svc_study_revision_freeze_consume_v1(p_intent_id,p_outcome,p_error_code)`
can consume it. Consumption rechecks original live client/resource/team rights,
expiry, CAS and all captured bindings. Only passed with no error atomically
records evidence, `passed`, `frozen` and one generation increment. Failed,
unavailable, stale or unauthorized attempts leave no ghost state. Exact passed
replay returns the historical receipt after live authorization; it never
revalidates scientific applicability or creates numerical/publication authority.

## Producer seams and disclosure obligation

W06 must create domain/job bindings atomically in canonical `worker_jobs`.
W03 service callbacks require exact job kind, payload Study/domain ID, current
running lease token and real-time expiry. No `leaseCurrent` boolean is accepted.
The read-input endpoints for model preparation and Run take domain ID, job ID
and lease token. Preparation input includes captured `sourceDocument` and ordered
methodRefs; Run input returns its frozen revision/scenario/preparation bindings.

The complete callbacks are `svc_study_source_record_v1`,
`svc_study_model_preparation_complete_v1`, and `svc_study_run_complete_v1`.
Their parameters are domain ID, job ID, lease token, completion JSON and
idempotency key. Completion installs immutable evidence and canonical job result
in one transaction. Scoped service receipts recover the identical terminal
acknowledgement using its original lease; changed content/job/lease conflicts.
The canonical job's shared result projection contains only a locator-free
Study/resource identity receipt. Full completion evidence stays in closed domain
records; generic requester-only job reads never receive source scope, model or
storage metadata from this result. W06 must additionally fence Study job
read/cancel routes by live Study rights rather than generic requester ownership.
Preparation completion must match its stored profile/calculation reference and
requires a semantic inputHash for Scenario sources. Source completion binds the
exact origin, source artifact, issuer/license/time and captured
`lca.study-source-authorization.v1` metadata. That metadata binds the requested
actor, origin and sourceScope and is historical evidence, never current permission.

Artifact references use full Edge typed byte identities; internal storage binds
private bucket `study-artifacts`, prefix `study/<Study>/<artifact-id>/` and a
simple JSON/ZIP/HTML filename. W03 admits metadata only up to 4MiB and never
fetches, signs or returns object locators. Larger artifacts require a separately
qualified bounded protocol; truncation is forbidden.

Study/team grants do not authorize raw private Process/Flow material. Before
enabling source/model artifact reads W06 must bind capture evidence from actual
database row state/ownership and current actor source rights, then recheck the
entire captured source/disclosure scope at every byte/link disclosure. Numerical
resolver evidence is independently Worker-owned. Derived Run/report projections
need explicit qualified disclosure policy too. Synthetic service/job fixture
tests prove SQL fencing only; they do not fetch exports, compile, verify licenses,
upload bytes or qualify the source/solver pipeline.
