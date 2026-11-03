---
title: Study durable runtime and task admission v1
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
lastReviewedCommit: 2b8959360fe39205b4ab11d0d40acf32df3e66ac
lastReviewedNote: "Database #895: reviewed default-off canonical Study admission, exact RLS source capture/history rights, opaque disclosure intents and scoped cancellation/reconciliation; local runtime evidence and owned reconstruction are distinct from hosted activation."
related:
  - ./lca-study-durable-contract.md
  - ./repo-validation.md
  - ../../AGENTS.md
---

# Study durable runtime and task admission v1

Database #894 implements W03 persistence and Database #895 adds the separately gated W06 task/disclosure adapter under the retained
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

W03 alone advertises no source or numerical producer. W06 adds closed
`model.source.resolve`, `model.prepare`, `run.submit`, `run.cancel`, `task.read`,
`task.cancel` and `artifact.read` paths. Installation leaves source, compute and
disclosure flags off in `private.study_runtime_config` and grants no OAuth
client a capability. Unavailable submissions create no placeholder work.
Only the service-only CAS façade `svc_study_runtime_configure_v1` can select the
exact registered calculation descriptor, ordered method references and bounded
`lca.study-explicit-v1` profile with a qualification-evidence reference. An
installed profile or descriptor does not qualify a deployment; actual
actor/API/queue/Worker/storage evidence and independently owned runtime limits
are required before enabling its scope. Local test activation qualifies only
that explicitly owned environment.
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

## W06 canonical task admission and recovery

Source acquisition, preparation and Run admission atomically bind their domain
identity to the existing `worker_jobs` arbiter. Commands derive the actual actor,
current client and Study/team rights before receipt replay; an exact-key retry
returns its original task. A changed normalized request conflicts. Generic
queue enqueue/read/cancel/retry/result routes reject Study jobs, and generic
lists, latest-job and TaskHub feeds exclude them before pagination. Public
`task.read`/`task.cancel` take the same Study and typed domain resource identity;
resource IDs and requester ownership alone do not confer permission.

Cancellation uses the canonical state/lease arbiter and clears lease authority
atomically. A late producer cannot complete or fail that canceled task. Fixed
phase/error-code allowlists exclude raw Worker messages, details, source bytes
and storage locators. Source, model and Run callbacks keep the existing exact
job/kind/resource/current-lease/expiry and immutable terminal receipt fences.
The source completion façade is `svc_study_source_record_v1`; callers must not
infer a symmetric RPC name from the source-acquisition read endpoint.

`svc_study_task_fail_v1` accepts only the twelve documented diagnostic codes.
`svc_study_task_reconcile_v1` requires the exact current or recorded historical
claimed lease, Study/resource/job and idempotency binding. It reports committed
receipts and referenced artifacts conservatively. `unreferenced` requires a
terminal task with no lease and no artifact metadata; active, expired,
reclaimed or ambiguous tasks remain pending. Time or object age never grants
cleanup authority. Worker owns exact storage-byte readback and deletion receipts.

## W06 actual source capture and historical disclosure

The source exporter resolves exact UUID/version references from current
RLS-governed `json_ordered::text` rows, through the existing NOBYPASSRLS executor
with the captured actor/client context. It requires both current Study rights
and `DB-CORE-READ-01`, admitting published100 or the actor's own draft0 only.
Withdrawn, state120/200, missing, foreign-private or RLS-invisible rows fail.
The bounded closure covers at most512 documents,64 instances and4MiB; it follows
exact Model→Process→Flow→reference FlowProperty→UnitGroup references without a
latest-version fallback. The first leased read stores its packet once; retries
retain that exact byte observation and time.

Per-document SHA256 binds the exact PostgreSQL JSON-text UTF8 string. Snapshot
packet/artifact bytes, Worker semantic model/input identities and the
calculation descriptor have separate hash domains. `licenseEvidence` is a
captured descriptive record; access-policy metadata is not an open-license or
redistribution assertion. Base preparation stores explicit ordered methods and
cutoffs; empty cutoffs mean no exclusions. Scenario preparation uses the selected
frozen StudyRevision's base preparation and complete current override layer,
including captured factors, rather than latest data or implicit parent layers.

Current row visibility never retroactively publishes historical draft bytes.
Captured private bytes remain bound to their captured owner and current
ownership/read eligibility. A different actor may receive captured public bytes
only while the exact captured SHA is still public100 now. A captured owner may
retain historical bytes only while current ownership and read eligibility
remain. These checks apply to leased source use, model/Run input reads,
completion and every artifact disclosure; a newer published row is not silently
substituted for the frozen source.

## W06 opaque artifact disclosure intents

The `study-artifacts` bucket is private, limited to4MiB per artifact, and a
restrictive Storage policy closes direct anon/authenticated object access
independently of permissive policies. Raw `modelSource` packets are never
publicly disclosed. Only qualified `modelInput` and `runResult` projections have
an actor read path, with both current Study rights and the complete current
source/history disclosure scope.

Actor `artifact.read` returns an opaque two-minute intent containing only the
exact typed reference, Study and intent identity/expiry. It returns no storage
locator or captured actor/client metadata. The service-only resolver rechecks
that original actor/client, current rights, expiry and exact binding before
returning an internal capability; Edge resolves again after bounded download
and hash/size verification before releasing bytes. A host wall clock cannot
replace the database expiry check. There are at most64 outstanding intents per
actor, serialized by a transaction advisory lock. Each authorized read removes
at most256 expired rows with `SKIP LOCKED`, then checks the live budget; an
excess request returns `CAPABILITY_UNAVAILABLE` without extra authority.

## Direct-input parity and concurrent capture

Source identifiers retain their public string types. Scenario preparation
generations must be numeric safe integers and are stored as canonical integers;
string coercion must not create a record rejected by typed consumers. Generic
job-kind routing uses the canonical enqueuer's lower/trim normalization before
deciding whether a scoped Study route is required.

Source input reads acquire Study and job locks in the existing order, then reload
the acquisition before inspecting its captured packet. Under PostgreSQL17 Read
Committed, a waiting same-lease caller therefore reuses the first committed
packet instead of recapturing from a stale pre-lock row. Transaction and
source-right checks remain in force; higher-isolation serialization failures
require normal caller recovery, not a stale overwrite.
