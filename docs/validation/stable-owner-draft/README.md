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
| Prior recorded result | 391 SQL assertions across 10 suites; 34 real-overlap concurrency assertions; no recorded failures; cleanup exit `0`; superseded for the additive exact-key follow-up below |

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

The recorded 93-assertion suite covers Contacts, Sources, Product/Waste Flows and standalone Processes: zero owner drafts delegates one successor to the existing version allocator; one reuses its exact identity; historical multiple drafts return the complete conflict set and require explicit selection. The request binds the actor, complete draft census/full before images, and exact public source. New clones set `rule_verification=false`; source flags and reused/selected draft flags remain unchanged. Preparation establishes identity, not scientific verification or save readiness.

Any current-owner version in `20 <= state_code < 100` blocks preparation and legacy creation, including zero-draft cases and prepare replay. Conflicts return the existing review targets. Review entry/exit, draft entry and legacy allocation compete in the same table/UUID family lock domain. Read-only original-request recovery retains the fixed receipt and reports later target changes, including review, model binding or reference-only type transitions; an absent receipt does not authorize another writer. Same-request replay cannot allocate a second version, and changed request content conflicts. Injected delegated failures roll back draft insertion, native audit and stable receipt together. The existing exact-row guarded save remains the content writer.

The populated upgrade suite seeds historical duplicate and mixed families on the canonical base **before** applying the actual migration. All 22 assertions pass, including whole-row preservation, explicit selection without version creation/deletion, and review fencing. The base fixture temporarily disables only the external Process AFTER-insert webhook during synthetic seeding and restores it before commit; it does not disable the new guard to manufacture history.

[concurrency.json](concurrency.json) is the exact concurrency object extracted from the prior aggregate. Its 34 checks cover stable/stable, stable/legacy-create, legacy-create-version/stable, owner-transfer/stable and review-entry/stable races. The runner observes writer A parked on a controller barrier with its transaction uncommitted when B returns; the review-entry case additionally observes the exact family advisory lock in `pg_locks`. It verifies busy/stale-census responses, no losing receipt, lost-response recovery without another writer, idempotency, repeatable-read refusal, final draft counts, three native writes and two successful stable receipts. This is a structured final report; no separate session transcript is claimed.

## Exact-key compatibility follow-up

The [corrected CI run](https://github.com/tiangong-lca/database/actions/runs/39480142235/job/118826253553) passed migration reconstruction and schema/type generation, then failed `20260918_tidas_full_package_import.sql:51` after nine passing assertions. The new BEFORE INSERT guard rejected an existing exact draft key before native `ON CONFLICT DO NOTHING` could skip it. This is a compatibility regression for valid equal-version bodies as well as the import fixture's minimal bodies. The unrelated Supabase Preview Edge packaging timeout is not this SQL failure.

The CLI-generated additive migration `20261020191735_stable_owner_draft_exact_key_compatibility.sql` preserves the original migration and its published hashes. It replaces only the guard: after synchronization and the family try-lock, an existing exact final key is pinned with `FOR KEY SHARE NOWAIT`, then native uniqueness/`ON CONFLICT` handling proceeds. `DO UPDATE` still runs UPDATE admission. A pin prevents concurrent deletion/key changes from removing the presumed conflict. Family and row contention keep the explicit nonblocking busy contract, including exact retries; no hidden retry or importer bypass is added. PostgreSQL documents [key-share protection](https://www.postgresql.org/docs/17/explicit-locking.html) and [INSERT/UPDATE trigger ordering](https://www.postgresql.org/docs/17/trigger-definition.html).

The new [exact-key proof](exact-key/evidence.json) records 477 passing SQL assertions across eleven suites and 65 passing actual-overlap concurrency assertions. The final feature suite has 151 assertions, including four-type native duplicate/upsert admission and explicit Process-model/Flow-type crossings; unchanged full/partial import suites pass 31/19 assertions. The recorded RED feature checkpoint has 21 failures out of 150 assertions; the final source adds one Flow-type assertion after that checkpoint, and its separate final GREEN log binds the final source hash. The race cases observe the no-op writer still uncommitted while delete/key-change peers fail safely, reverse the ordering to verify busy insertion, and retry after the competing commit or rollback. Source/type generation uses Database CLI `2.117.0`: two normalized schema dumps are identical (`081225b379dc7a29a788744ee897cb7d27c66476a0c0c3ced81944638ad8a5cc`); API types are unchanged (`f0022a0d45ec7386e0d8eb25e91d1032e1f94f6e049f9e4cd7a2175e0abda027`). The generated function snapshot adds only the exact-key declaration and pin block. The additive migration SHA-256 is `7c04bbdec5e1f0ef865c190acdb6d32cb2e04530a70fc006cd070be99011cc09`.

Earlier evidence in this directory remains immutable historical proof. It does not claim the additive compatibility migration was included in those earlier runs. The prior 22-assertion canonical-base populated-upgrade checkpoint has not been freshly rerun for this follow-up; the retained integration database was not reset. Final native transport acceptance, online checks and deployment status remain separate from this local proof.

## Display hydration fixture follow-up

On `c1663f9ac1f909581969adee2c04d11ffbc90b9c`, [CI passed both import suites and the 151-assertion stable-draft suite](https://github.com/tiangong-lca/database/actions/runs/39495928956/job/118880836762), then stopped during display hydration fixture setup: two distinct versions were both active drafts for one owner. The guard correctly rejected new admission. This follow-up changes only that fixture's state CASE and explanatory comments: odd families have older published state `100` and latest draft state `0`; even families retain state `20`. Every identity, version, name, visibility value and all 797 assertions are unchanged. Production SQL, migrations, generated snapshots and API types remain byte-identical to `c1663f9a`.

The [fixture proof](hydration-fixture/evidence.json) records the original RED setup error (exit `3`, zero assertions) and corrected GREEN (797 assertions), plus unchanged display settings (40), public readers (93), and scoped settings readers (31): **961 assertions pass**. The corrected source SHA-256 is `273481107d0a3f6af54cc6f1a3c94b8b7dd5e2b161cf7a0ea111ea3623216fbe`.

The local database retained synthetic E2E rows, so the local harness injected `TRUNCATE ... CASCADE` for the seven fixture tables immediately after BEGIN and restored everything through suite ROLLBACK or connection exit on RED failure. Cascade inspection found only those seven tables. All 160 local user-table counts matched before and after RED and each GREEN suite. No guard/trigger was disabled and no projection, persistent cleanup or reset was introduced. Clean CI runs the checked-in suite directly, without this harness isolation. The prior accepted 477 SQL/65 concurrency results are reused explicitly; this fixture-only follow-up does not claim they were rerun.

## Alias closure fixture follow-up

[CI on `45d2de4e50169613ecca293e570e6a9e91c22a89`](https://github.com/tiangong-lca/database/actions/runs/39498922952) passed the hydration and subsequent reader checks, then stopped after 25 passing assertions in alias batch case 1.10: its extra same-owner Flow version was another state-0 draft. The alias closure inventories every exact consumer regardless of state (`cmd_dataset_alias_batch_v2_guarded`, lines 694–717), so a published state-100 version remains live. The test now uses that valid fixture state and strengthens its existing diagnostic assertion to require exactly both `(id, version, owner, state)` rows: original `01.00.000` draft and extra `02.00.000` published consumer. The 119-test plan and closure mismatch expectation remain unchanged. The published row also violates draft scope; this preserves exact-version inventory coverage without claiming the earlier all-draft precondition remains unchanged.

The [alias fixture proof](alias-fixture/evidence.json) records RED exit `3` after 25 passing assertions and **490 passing assertions across eleven alias-family suites**: batch 119, math 18, vectors 4, plan 14, protected 75, rollback 10, terminal 29, Length×time 121, current closure 29, canonical key hash 45 and OAuth capability 26. The final batch source SHA-256 is `848a9df905475770bd96064f68bb06aba2e10f61160789ef780beb2a0fb85198`.

The same rollback-only seven-table local isolation preserved all 160 recorded table counts after RED and each GREEN suite. No new guard bypass, production change or persistent cleanup was added. Public logs remove trailing whitespace and redact three rows containing literal placeholder test headers; TAP results are unchanged and raw logs remain private. Prior accepted 477 SQL/65 concurrency results and the 961-assertion hydration follow-up are reused, not claimed as rerun here. The bounded remaining-fixture scan found no further second-draft version in the other alias suites; their complete GREEN runs confirm that family needs no additional fixture edit.

## Reproduce with synthetic local fixtures

From a checkout of the recorded code, start an owned disposable local Supabase stack and apply its migrations using the repository's [local validation procedure](../../agents/repo-validation.md). The ordinary suites can then run as written:

```bash
for suite in \
  20261021_stable_owner_draft.sql \
  20260918_tidas_full_package_import.sql \
  20260909_tidas_partial_import.sql \
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

The separate upgrade proof requires a disposable database initialized from the exact recorded base. Run `supabase/tests/upgrade/20261021_stable_owner_draft_base.sql` there, apply the original migration and the additive exact-key compatibility migration, then run `supabase test db supabase/tests/upgrade/20261021_stable_owner_draft_head.sql` against that same local database. Running the base fixture after migration is deliberately refused. The ordinary SQL suites roll back their test transactions; the populated base fixture commits owned synthetic history and requires disposal/owned cleanup afterward.

The checked-in [concurrency runner](../../../supabase/tests/regression/20261021_stable_owner_draft_concurrency.py) uses only Python's standard library and a Docker CLI. Prepare an owned disposable local project with the applied migrations, the exact running container `supabase_db_cli372-local` labeled `com.supabase.cli.project=cli372-local`, and its sole network `cli372-local` marked internal and labeled `codex.task=cli372`. The runner verifies container/network IDs and membership before fixture access; it never starts or resets the stack. Run it from the checkout, replacing the socket argument with that local Docker daemon's absolute Unix socket:

```bash
python3 supabase/tests/regression/20261021_stable_owner_draft_concurrency.py \
  --docker-host unix:///absolute/path/to/docker.sock \
  --report /tmp/stable-owner-draft-concurrency.json
```

Use `--docker-bin /absolute/path/to/docker` when Docker is not on `PATH`. TCP/SSH endpoints, relative paths and non-socket targets are refused. Every Docker call uses the explicit socket with inherited `DOCKER_*` overrides removed; database access is only `docker exec` into the fixed container with `psql -U postgres -d postgres`. No private runtime wrapper, database URL or production target is accepted. The runner requires its synthetic identities to be absent before seeding and cleans only its exact fixtures and sessions. Before the exact-key follow-up, the public adapter was rerun against the owned local fixture: [34/34 assertions passed](concurrency-public-adapter.json), and [post-run cleanup](concurrency-public-adapter-cleanup.json) confirmed zero owned fixture rows or sessions. This rerun leaves the original 34 proof assertions unchanged. That prior runner SHA-256 is `5fd8282fc011990b7b5fa7251ae6e53b759dbd29d3254fbb628247bc26b7a94e`.

## Generated types and limits

The first [Database PR #856 CI run](https://github.com/tiangong-lca/database/actions/runs/39476889207/job/118815051327) failed its generated-workspace gate: Database CI selected CLI `2.117.0`, while the prior local type snapshot used Edge's CLI `2.121.0`. The failure log contains only a `database.types.ts` diff; schema reconstruction and schema export completed without schema drift. The CLI version selected by the Database workflow is authoritative for this artifact; the CI gate was not relaxed or upgraded.

The correction restores the canonical generator (`stdout.rstrip()` plus one final newline), removes the unnecessary raw-template normalization, and regenerates with CLI `2.117.0`. Two native local generations produced identical SHA-256 `f0022a0d45ec7386e0d8eb25e91d1032e1f94f6e049f9e4cd7a2175e0abda027`. The generated Git blob is `a63b753d330e0bd6658cfd9a531bf0e59b959815`, exactly the replacement printed by the failing CI job. Compared with the canonical base type file, the corrected artifact adds exactly eight lines for `cmd_dataset_prepare_stable_draft` and `get_dataset_stable_draft_request`; all other type text is unchanged. A read-only CLI `2.117.0` schema dump also matches the accepted schema snapshot exactly (SHA-256 `4e69533243616b0e4d4ccc3d7e6ca03d274303c3624931c6e0d809716be1d947`). No migration, RPC, trigger, test behavior or database setting changed in that generation-only correction. Online rerun status remains in the PR, separate from this local checkpoint.

[types-semantic-catalog.json](types-semantic-catalog.json) remains the **prior CLI `2.121.0` comparison**, not the current type-generation artifact. It normalized only verified `ComputedFields: never`/`Omit<Row, never>` and no-argument `never`/`Record<PropertyKey, never>` equivalences. It found the same two added API functions and no removed or other changed catalog entries. Those historical comparison results and hashes are retained without claiming that CLI `2.121.0` was Database's pinned toolchain or that all consumers were compiled.

Initial creation without a public source, LifecycleModels, model-bound Process preparation, Result sources, and Elementary/unknown/missing Flow types are outside the new preparation slice. Native model-bound-only and reference-only Flow-only multiplicity remains excluded from its uniqueness guarantee; crossing into a supported standalone/Product/Waste draft family conflicts. No LCIA or model workflow authority is added.

READ COMMITTED is required for new draft admission and review transitions on all four mutable tables, including otherwise excluded model-only and reference-only Flow-only scopes. REPEATABLE READ/SERIALIZABLE admission is intentionally refused because a stale transaction snapshot cannot establish the fresh family census. Same-identity in-place content saves retain their existing contract. This is a compatibility restriction, not only a test setting.

No remote deployment, Preview/persistent-Dev/production proof, original-data acceptance, consumer runtime adoption or complete CLI #372 closure is established here. Companion [CLI #372](https://github.com/tiangong-lca/cli/issues/372) and [Edge #500](https://github.com/tiangong-lca/edge-functions/issues/500) changes require their own verification. See the [architecture boundary](../../agents/repo-architecture.md) and [validation requirements](../../agents/repo-validation.md).
