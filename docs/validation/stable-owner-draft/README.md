# Stable owner-draft local validation

Database [#855](https://github.com/tiangong-lca/database/issues/855) adds source-based preparation of a stable owner draft and read-only recovery of its original request. This directory records synthetic local database evidence, not deployment or original-data acceptance.

| Binding | Recorded value |
| --- | --- |
| Canonical repository / routine base | `tiangong-lca/database` / `dev` |
| Fetched base | `96d042679810e8df0427d4d4ecd34e2c1b6a5d61` |
| Implementation commit | `21a32bcf1af8c2011181c60cf8a3768670d6ca02` |
| Code/evidence HEAD before publication/test-adapter changes | `69d7f9892fcf778c619b26e68c19c92a83648f73` |
| Migration | `supabase/migrations/20261020164514_stable_owner_draft.sql` |
| Migration SHA-256 | `e328f5ff68145abbff246ab9de0db80382c2d8750806b1698d3865b99301cbec` |
| Recorded SQL/concurrency runtime | PostgreSQL `17.11`; Supabase CLI `2.121.0`; owned disposable local database; retained historical proof |
| Corrected generation toolchain | Database CI-pinned Supabase CLI `2.117.0`; canonical generator behavior restored |
| Final recorded result | 391 SQL assertions across 10 suites; 34 real-overlap concurrency assertions; no recorded failures; cleanup exit `0` |

## Evidence and interpretation

[evidence.json](evidence.json) preserves the recorded aggregate, including suite hashes, process exits, empty failure lists and runtime versions. Its CLI `2.121.0` type-generation checks are **prior, superseded generation evidence**; the correction below records the current Database-pinned artifact without overwriting those historical hashes. [sql/](sql/) contains the complete final SQL output with trailing whitespace and final blank lines removed for Git; all result lines and values are retained. Fixtures use deliberately synthetic identities already present in the checked-in tests. A final submission rerun on the retained integration fixture exposed one test-isolation issue: assertion 31 counted every stable receipt, including a previously retained integration receipt. The test now limits that count to its exact synthetic actor; expected writes and all 93 assertions remain unchanged. The historical output and source hash below still describe the recorded checkpoint; the final PR gate separately records the current-test rerun.

These logs contain no original operational cases, credentials, real account identifiers or local filesystem paths. [artifact-sha256.json](artifact-sha256.json) hashes the published result artifacts.

| SQL suite under `supabase/tests/` | Assertions |
| --- | ---: |
| `upgrade/20261021_stable_owner_draft_head.sql` | 22 |
| `20261021_stable_owner_draft.sql` | 93 |
| `20260921_guarded_dataset_save_draft.sql` | 53 |
| `20260404_dataset_command_rpcs.sql` | 15 |
| `20260611_dataset_create_version_rpc.sql` | 19 |
| `20260902_process_model_version.sql` | 32 |
| `20261009_model_bundle_process_references.sql` | 16 |
| `20260915_result_process_lifecycle_protection.sql` | 69 |
| `20260805_full_schema_cutover.sql` | 26 |
| `20260806_api_contract_closure.sql` | 46 |

The 93-assertion suite covers Contacts, Sources, Product/Waste Flows and standalone Processes: zero owner drafts delegates one successor to the existing version allocator; one reuses its exact identity; historical multiple drafts return the complete conflict set and require explicit selection. The request binds the actor, complete draft census/full before images, and exact public source. New clones set `rule_verification=false`; source flags and reused/selected draft flags remain unchanged. Preparation establishes identity, not scientific verification or save readiness.

Any current-owner version in `20 <= state_code < 100` blocks preparation and legacy creation, including zero-draft cases and prepare replay. Conflicts return the existing review targets. Review entry/exit, draft entry and legacy allocation compete in the same table/UUID family lock domain. Read-only original-request recovery retains the fixed receipt and reports later target changes, including review, model binding or reference-only type transitions; an absent receipt does not authorize another writer. Same-request replay cannot allocate a second version, and changed request content conflicts. Injected delegated failures roll back draft insertion, native audit and stable receipt together. The existing exact-row guarded save remains the content writer.

The populated upgrade suite seeds historical duplicate and mixed families on the canonical base **before** applying the actual migration. All 22 assertions pass, including whole-row preservation, explicit selection without version creation/deletion, and review fencing. The base fixture temporarily disables only the external Process AFTER-insert webhook during synthetic seeding and restores it before commit; it does not disable the new guard to manufacture history.

[concurrency.json](concurrency.json) is the exact concurrency object extracted from the final aggregate. Its 34 checks cover stable/stable, stable/legacy-create, legacy-create-version/stable, owner-transfer/stable and review-entry/stable races. The runner observes writer A parked on a controller barrier with its transaction uncommitted when B returns; the review-entry case additionally observes the exact family advisory lock in `pg_locks`. It verifies busy/stale-census responses, no losing receipt, lost-response recovery without another writer, idempotency, repeatable-read refusal, final draft counts, three native writes and two successful stable receipts. This is a structured final report; no separate session transcript is claimed.

## Reproduce with synthetic local fixtures

From a checkout of the recorded code, start an owned disposable local Supabase stack and apply its migrations using the repository's [local validation procedure](../../agents/repo-validation.md). The nine ordinary suites can then run as written:

```bash
for suite in \
  20261021_stable_owner_draft.sql \
  20260921_guarded_dataset_save_draft.sql \
  20260404_dataset_command_rpcs.sql \
  20260611_dataset_create_version_rpc.sql \
  20260902_process_model_version.sql \
  20261009_model_bundle_process_references.sql \
  20260915_result_process_lifecycle_protection.sql \
  20260805_full_schema_cutover.sql \
  20260806_api_contract_closure.sql
do
  supabase test db "supabase/tests/$suite" || exit
done
```

The separate upgrade proof requires a disposable database initialized from the exact recorded base. Run `supabase/tests/upgrade/20261021_stable_owner_draft_base.sql` there, apply the actual migration, then run `supabase test db supabase/tests/upgrade/20261021_stable_owner_draft_head.sql` against that same local database. Running the base fixture after migration is deliberately refused. The ordinary SQL suites roll back their test transactions; the populated base fixture commits owned synthetic history and requires disposal/owned cleanup afterward.

The checked-in [concurrency runner](../../../supabase/tests/regression/20261021_stable_owner_draft_concurrency.py) uses only Python's standard library and a Docker CLI. Prepare an owned disposable local project with the applied migrations, the exact running container `supabase_db_cli372-local` labeled `com.supabase.cli.project=cli372-local`, and its sole network `cli372-local` marked internal and labeled `codex.task=cli372`. The runner verifies container/network IDs and membership before fixture access; it never starts or resets the stack. Run it from the checkout, replacing the socket argument with that local Docker daemon's absolute Unix socket:

```bash
python3 supabase/tests/regression/20261021_stable_owner_draft_concurrency.py \
  --docker-host unix:///absolute/path/to/docker.sock \
  --report /tmp/stable-owner-draft-concurrency.json
```

Use `--docker-bin /absolute/path/to/docker` when Docker is not on `PATH`. TCP/SSH endpoints, relative paths and non-socket targets are refused. Every Docker call uses the explicit socket with inherited `DOCKER_*` overrides removed; database access is only `docker exec` into the fixed container with `psql -U postgres -d postgres`. No private runtime wrapper, database URL or production target is accepted. The runner requires its synthetic identities to be absent before seeding and cleans only its exact fixtures and sessions. The public adapter was rerun against the owned local fixture: [34/34 assertions passed](concurrency-public-adapter.json), and [post-run cleanup](concurrency-public-adapter-cleanup.json) confirmed zero owned fixture rows or sessions. This rerun leaves the original 34 proof assertions unchanged. The final runner SHA-256 is `5fd8282fc011990b7b5fa7251ae6e53b759dbd29d3254fbb628247bc26b7a94e`.

## Generated types and limits

The first [Database PR #856 CI run](https://github.com/tiangong-lca/database/actions/runs/39476889207/job/118815051327) failed its generated-workspace gate: Database CI selected CLI `2.117.0`, while the prior local type snapshot used Edge's CLI `2.121.0`. The failure log contains only a `database.types.ts` diff; schema reconstruction and schema export completed without schema drift. The CLI version selected by the Database workflow is authoritative for this artifact; the CI gate was not relaxed or upgraded.

The correction restores the canonical generator (`stdout.rstrip()` plus one final newline), removes the unnecessary raw-template normalization, and regenerates with CLI `2.117.0`. Two native local generations produced identical SHA-256 `f0022a0d45ec7386e0d8eb25e91d1032e1f94f6e049f9e4cd7a2175e0abda027`. The generated Git blob is `a63b753d330e0bd6658cfd9a531bf0e59b959815`, exactly the replacement printed by the failing CI job. Compared with the canonical base type file, the corrected artifact adds exactly eight lines for `cmd_dataset_prepare_stable_draft` and `get_dataset_stable_draft_request`; all other type text is unchanged. A read-only CLI `2.117.0` schema dump also matches the accepted schema snapshot exactly (SHA-256 `4e69533243616b0e4d4ccc3d7e6ca03d274303c3624931c6e0d809716be1d947`). No migration, RPC, trigger, test behavior or database setting changed in this correction. Online rerun status remains in the PR, separate from this local checkpoint.

[types-semantic-catalog.json](types-semantic-catalog.json) remains the **prior CLI `2.121.0` comparison**, not the current type-generation artifact. It normalized only verified `ComputedFields: never`/`Omit<Row, never>` and no-argument `never`/`Record<PropertyKey, never>` equivalences. It found the same two added API functions and no removed or other changed catalog entries. Those historical comparison results and hashes are retained without claiming that CLI `2.121.0` was Database's pinned toolchain or that all consumers were compiled.

Initial creation without a public source, LifecycleModels, model-bound Process preparation, Result sources, and Elementary/unknown/missing Flow types are outside the new preparation slice. Native model-bound-only and reference-only Flow-only multiplicity remains excluded from its uniqueness guarantee; crossing into a supported standalone/Product/Waste draft family conflicts. No LCIA or model workflow authority is added.

READ COMMITTED is required for new draft admission and review transitions on all four mutable tables, including otherwise excluded model-only and reference-only Flow-only scopes. REPEATABLE READ/SERIALIZABLE admission is intentionally refused because a stale transaction snapshot cannot establish the fresh family census. Same-identity in-place content saves retain their existing contract. This is a compatibility restriction, not only a test setting.

No remote deployment, Preview/persistent-Dev/production proof, original-data acceptance, consumer runtime adoption or complete CLI #372 closure is established here. Companion [CLI #372](https://github.com/tiangong-lca/cli/issues/372) and [Edge #500](https://github.com/tiangong-lca/edge-functions/issues/500) changes require their own verification. See the [architecture boundary](../../agents/repo-architecture.md) and [validation requirements](../../agents/repo-validation.md).
