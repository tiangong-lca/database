---
title: LCA Study durable invariants v1
docType: contract
scope: repo
status: active
authoritative: true
owner: database-engine
language: en
whenToUse:
  - defining Study persistence, revisions, authorization or state transitions
  - implementing the later Study schema and cross-repository acceptance tests
whenToUpdate:
  - Study identity, concurrency, freeze, idempotency or authorization changes
  - research review, export or sharing persistence rules change
checkPaths:
  - docs/agents/lca-study-durable-contract.md
  - supabase/tests/lca_study_durable_contract.py
  - supabase/tests/fixtures/lca-study-durable.v1.json
lastReviewedAt: 2026-11-02
lastReviewedCommit: ff306c42cecd3ea25ecc7e4be3b22f5639127904
lastReviewedNote: "Database #885: P0 durable contract and offline examples only; no schema, grants, runtime or deployment is introduced."
related:
  - ../../AGENTS.md
  - ./repo-architecture.md
  - ./repo-validation.md
---

# LCA Study durable invariants v1

`lca.study-durable.v1` owns the required persistent identities, relations,
authorization and transitions for the proposed Study product. P0 accepts this
contract and executable examples. It does **not** create tables, RPCs, grants,
jobs, report exports or shares. P1 and later implementation must prove these
invariants against real database behavior before advertising runtime support.

The workspace design is tracked by workspace #2141/#2146; this contract is
Database #885. Edge #521 owns the public `lca.study-api.v1` requests/responses
under `contracts/lca-study/v1` in **edge-functions**. Worker #353 owns numerical
contracts and the P0 qualification profile. No public wire schema or numerical
algorithm is defined here. Later SQL objects remain private behind reviewed
`api` commands; naming a domain object does not expose a relation or invent an
OAuth capability grant.

## Identities and exact relations

| Domain object | Durable identity and invariants |
| --- | --- |
| Study | Stable `studyId`, server-derived owner/scope, member grants and mutable head. `active`/`archived` is a research lifecycle, never dataset publication state. A personal scope is `{kind:"personal"}`; a team scope is `{kind:"team",teamId}` and requires current team authorization. |
| StudyRevision | `revisionId`, exact `studyId`, nullable exact `parentRevisionId`, draft/frozen content and its content hash. Frozen definition binds goal, scope, functional unit, model and methods. A new frozen definition uses a new identity; no latest alias is persisted. |
| ModelRevision | Exact versioned model reference, content hash and source identity; layout is presentation. Worker owns normalized effective model semantics. Existing LifecycleModel is an input mapping, not a Study or authorization substitute. |
| ScenarioRevision | `scenarioRevisionId` within Study; exact frozen `studyRevisionId`, explicit differences and an effective model reference. A second scenario is a research alternative, not a boundary-product output projection. |
| Run | `runId`, exact frozen Study/Scenario/Model references, immutable input identity, opaque calculation reference, engine/profile and task/result links. A Run is not a renamed `worker_jobs` row. |
| Analysis | Exact input Run identities, analysis profile/configuration and result evidence. Worker defines numerical and comparability semantics; Database preserves the bindings. |
| ReportRevision | `reportRevisionId`, exact Run/AnalysisFacts references, narrative/citation content hash, template/profile identity and draft/frozen content. Finalization and review are separate records/axes. |
| Review | Append-only `reviewId`, decision, actor/time and exact target `{type:"reportRevision",revisionId,contentHash}`. Withdrawal adds a decision; it does not erase history. |
| ReportExport | `exportId`, exact report revision, full serialized projection hash, trusted Edge disclosure decision/policy identity, actor, permission epoch and artifact/receipt. Audit retention does not imply current download permission. |
| ReportShare | `shareId`, exact report revision/export/projection, explicit recipient/audience, expiry, permission epoch and revocation history. Sharing does not grant Study membership or underlying source access. |

Shared reference vocabulary is camelCase with `schemaVersion` on envelopes and
type-tagged `{type,id,contentHash}` domain/artifact references. Public records and
commands follow Edge's published schema. The fixture event names and internal
maps below are **not** public API fields, table names or RPC signatures.

Each mutable target has a positive integer `revision` CAS generation, distinct
from its stable identity and content hash. Commands name the target and its
`expectedRevision`. Draft updates retain the revision ID and advance the CAS
generation; freezing advances it and makes the content immutable. A later
content change creates a new revision ID linked to its exact predecessor.
Updating a Study head is a separate Study-targeted CAS; it cannot implicitly
overwrite a Report/Scenario head using a different object's generation.

All relation validation is Study-scoped and exact. Cross-Study parents, Run
inputs, reports or exports are rejected atomically. Display titles, job IDs,
transport keys and timestamps are not semantic content identities. Content hash
production belongs to the relevant content owner; Database stores and verifies
trusted bindings, not an alternative LCA canonicalization algorithm.

## Authorization and concurrency

Authorization combines the current actor, client capability and live resource
grant. A role alone or a capability alone is insufficient. Server/service
identity is a distinct execution authority and never a human review, Study
membership or Final Result publication grant. Public actor/owner fields cannot
choose the authenticated principal. Raw relation access remains closed by
default in the later schema; authenticated commands must check their actual
object rather than trust IDs or layout sent by a client.

The examples use owner/editor/reviewer/viewer grants: owner manages members and
research lifecycle, editor writes research content, reviewer submits review
decisions, viewer reads authorized research content. Their capabilities are an
additional gate. Production client capability names and role-to-action mapping
must be implemented through the existing authorization manifest in P1, not
installed by this contract. Reviewer access to a report does not imply access to
all raw sources. Team scope also rechecks current team membership; synthetic
personal-scope traces do not prove team RLS.

Permission changes advance a durable `grantEpoch`; old export/share receipts
remain immutable but cannot authorize a new read after an epoch mismatch.
The conservative v1 examples fence all earlier Study export/share access on any
grant change. Issuing fresh access requires a fresh authorized projection and
receipt. Every read/download/share page rechecks live authorization and expiry;
a cursor or cached result is not a credential. Historical report review remains
readable to authorized actors, but an approval by a no-longer-authorized reviewer
cannot satisfy a new finalization command.

CAS validation, all related inserts and the resulting receipt must be one
atomic transaction in the later implementation. A rejected stale update,
freeze/update race, bad reference, bad grant or bad idempotency request leaves
no partial domain rows, head movement or new task. The offline sequential
interleavings specify expected outcomes; they do not prove PostgreSQL isolation,
locking or race safety.

## Freeze, Run and independent state axes

| Axis | Required behavior |
| --- | --- |
| Study lifecycle | `active` permits authorized new work; `archived` preserves history and denies new work/share use. Exact recorded command receipts remain recoverable to a still-authorized actor. |
| Content | Study/Scenario/Report content is `draft` or `frozen`; frozen content cannot be patched. `revision` is a CAS generation, not this status. |
| Run execution | Project the canonical `worker_jobs` lifecycle; do not create a competing queue lifecycle. Exact task/lease fencing and retry remain owned by existing Worker/Database job contracts. |
| Artifact availability | `pending`, `ready`, `expired`, `deleted` or `failed` describes accessibility, separately from completed computation. Missing/expired results are never numeric zero. |
| Numerical applicability | `current`, `superseded`, `withdrawn` or `unknown` is an explicit annotation on historical evidence, independent of execution success. Withdrawal never rewrites the original input/result. |
| Finalization/review | Report content freeze, `not_finalized`/`finalized`, exact review decisions and profile requirements are separate. A frozen report is not automatically approved, certified or published. |
| Share access | Durable active/revoked state plus current time yields effective active/revoked/expired access. Expiry does not require a background writer to deny access. |

A Run admission freezes exact revision/input/model/background/method bindings,
resource/profile limits and the numerical identity selected by the trusted
Worker boundary. The shared opaque reference is:

```json
{"kind":"calculation_contract","schema":"lca.calculation-contract.v1","sha256":"<Worker-issued lowercase SHA-256>"}
```

The digest is the existing Worker's fingerprint of its exact descriptor bytes.
Database/Edge do not deserialize numerical policy, reserialize the descriptor,
derive the digest, or invent an `artifactId` for it. `engineId` is
`solver-worker`; `lca.study-deterministic-p0.v1` is a qualification profile,
not a new solver implementation identity or proof of deployed Study support.

Later source/model edits cannot change an admitted Run. Recording completion
requires the exact bound task/input, a current lease and immutable result
evidence. Identical terminal recording is idempotent; conflicting result evidence
is rejected. Service completion also records the actor/operation/Study/key
receipt: reusing a completion key for another Run or result conflicts even when
both task bindings are otherwise valid. Retry retains the original frozen request. Adopting changed data,
methods, parameters or implementation requires an explicit new intent/revision
and new Run. Reusing numerical evidence across Runs requires separately qualified
compatibility and must preserve both Run intents and provenance.

## Idempotency, review, export and sharing

Each write receipt is scoped by actor, operation, Study and idempotency key;
the Study-creation scope is resolved before its stable ID is allocated in the
future API implementation. Equal requests recover the original receipt after a
lost acknowledgement. Reusing the key with changed normalized content conflicts.
The request identity includes the exact target/CAS precondition, not a mutable
latest pointer. Live authorization runs before replay. CAS is not re-applied
after a verified replay; a legitimate retry retains its original generation.
History reads and recorded retries cannot create replacement jobs or alter an
earlier terminal result.

Review targets the exact frozen report identity/hash. Changing a report creates
a new target with no inherited approval. A later decision from the same reviewer
supersedes that reviewer's earlier decision for a *new* finalization check, while
both records remain history. Finalization uses a server-resolved versioned
profile; clients cannot lower review requirements by supplying a boolean. The
examples cover no-review and internal-review profiles; `independent` returns
`CAPABILITY_UNAVAILABLE` until independently qualified support exists. Research
finalization does not approve a dataset or create a formal Result publication.
The model resolves requirement and availability from its fixed synthetic
`REPORT_PROFILES` registry. An event may select the profile ID; an independently
supplied requirement is only a consistency assertion and cannot override it.
Unknown profiles and unavailable capabilities fail closed. These test-only IDs
do not install real service policies.
The finalization receipt snapshots the exact profile, accepted review IDs and
server time. Later review withdrawal does not rewrite this historical receipt
or assert that its approval remains current.

Edge authorizes the complete serialized report projection, including embedded
tables, drill-down values and attachments, against current source rights and
the disclosure policy. Database persists the exact approved projection/hash,
policy/actor/permission binding and receipt. It does not interpret legal licenses
or accept an untrusted `disclosureAllowed` field. The fixture's
`trustedDisclosureDecision` is an internal service-event stand-in, not an API
field. Sharing may expose only that exact projection to the authorized recipient
until expiry/revocation. Neither recipient access nor a completed export grants
the entire Study or unpublished source data.

`grantEpoch` covers Study grants only. Exports separately bind `policyId` and
an opaque `disclosureContextHash` from Edge's source-rights evaluation. A new
download/share read must revalidate current source disclosure authority even
when Study grants are unchanged. The model's independent `disclosureEpoch`
and trusted `source.revoke` event simulate this invalidation; they neither
mutate a source dataset nor prescribe a public field, SQL counter or license
evaluator. Restoring a historical export receipt never authorizes disclosure of
its full projection without these live checks.

Revocation prevents subsequent service access; it cannot recall a downloaded
HTML or other copy. Export/share history remains as evidence without an active
access grant. Dataset curation, research review, formal Final Result generation
and publication stay separate; no transition in this contract creates a public
Process, shared source update, release or publication.

## Executable acceptance examples and proof boundary

Run from this repository:

```sh
python3 -B supabase/tests/lca_study_durable_contract.py
```

The standard-library model executes
`supabase/tests/fixtures/lca-study-durable.v1.json` transition traces. Each trace
starts from synthetic personal Study evidence, applies commands in order,
compares expected receipts/errors and selected state, and proves rejected
transitions leave its model unchanged. Cases exercise stale CAS, freeze/update
interleavings, exact idempotent recovery, changed-key rejection, cross-Study
references, role/capability denial, opaque calculation references, immutable Run
bindings, stale completion authority, validity annotations, exact review targets,
withdrawal/finalization, disclosure denial, recipient isolation, expiry and
grant/revocation fences. The JSON records after Edge validation are trusted
fixture events, not actor-supplied requests. The fixture's request digest is only
a deterministic comparison of synthetic JSON; it defines no public wire hash
or numerical/content hash domain.

No database, container, network, environment credentials or clock is used. P0
checks contract examples only. P1 must add real command/RLS/ACL/capability tests,
two-client observed CAS/freeze/idempotency races at supported isolation levels,
transaction rollback/response-loss recovery, team revocation and actual Worker
lease/result binding. Export/share execution additionally needs real source
rights, full serialized projection checks, signed download/readback, expiry and
revocation evidence. Those proofs and production deployment are not implied by
passing this offline model.
