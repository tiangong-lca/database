begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, auth;
select no_plan();

create temporary table candidate_webhook_calls (
  edge_function text not null,
  body jsonb not null,
  timeout_milliseconds integer not null
) on commit drop;

create or replace function util.invoke_edge_function(
  name text,
  body jsonb,
  timeout_milliseconds integer default ((5 * 60) * 1000)
) returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into pg_temp.candidate_webhook_calls(
    edge_function,
    body,
    timeout_milliseconds
  ) values (name, body, timeout_milliseconds);
end;
$$;

select is(
  private.lcia_scope_closure_worker_canonical_sha256(
    '{"z":1,"a":[3,{"b":true}]}'::jsonb
  ),
  '95f7be01f2a50d2296efb7eeba30ac587ef545c9501c9d47740490f143f6b593',
  'candidate document hashing matches the Worker canonical JSON golden vector'
);
select is(
  (
    select count(*)
    from private.lcia_scope_closure_reviewed_lcia_methods
  ),
  25::bigint,
  'candidate LCIA allowlist matches the deployed Worker reviewed method count'
);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  is_sso_user, is_anonymous
) values (
  '00000000-0000-0000-0000-000000000000',
  'c7240000-0000-4000-8000-000000000001',
  'authenticated',
  'authenticated',
  'initial-candidate-closure@example.com',
  'x',
  now(),
  '{}',
  '{}',
  now(),
  now(),
  false,
  false
);
insert into private.users(id, raw_user_meta_data, contact)
values ('c7240000-0000-4000-8000-000000000001', '{}', null);
insert into private.teams(id, json, rank, is_public)
values (
  '00000000-0000-0000-0000-000000000000',
  '{"name":"System"}',
  0,
  false
)
on conflict (id) do nothing;
insert into private.roles(user_id, team_id, role)
values (
  'c7240000-0000-4000-8000-000000000001',
  '00000000-0000-0000-0000-000000000000',
  'data_product_manager'
);

insert into public.processes(
  id, version, state_code, json, json_ordered, user_id
) values
(
  'c7240000-0000-4000-8000-000000000010',
  '01.00.000',
  100,
  '{"processDataSet":{"processInformation":{"dataSetInformation":{"common:UUID":"c7240000-0000-4000-8000-000000000010"}},"administrativeInformation":{"publicationAndOwnership":{"common:dataSetVersion":"01.00.000"}}}}',
  '{"processDataSet":{"processInformation":{"dataSetInformation":{"common:UUID":"c7240000-0000-4000-8000-000000000010"}},"administrativeInformation":{"publicationAndOwnership":{"common:dataSetVersion":"01.00.000"}}}}',
  'c7240000-0000-4000-8000-000000000001'
),
(
  'c7240000-0000-4000-8000-000000000010',
  '02.00.000',
  100,
  '{"processDataSet":{"processInformation":{"dataSetInformation":{"common:UUID":"c7240000-0000-4000-8000-000000000010"}},"administrativeInformation":{"publicationAndOwnership":{"common:dataSetVersion":"02.00.000"}},"versionMarker":"latest"}}',
  '{"processDataSet":{"processInformation":{"dataSetInformation":{"common:UUID":"c7240000-0000-4000-8000-000000000010"}},"administrativeInformation":{"publicationAndOwnership":{"common:dataSetVersion":"02.00.000"}},"versionMarker":"latest"}}',
  'c7240000-0000-4000-8000-000000000001'
),
(
  'c7240000-0000-4000-8000-000000000011',
  '01.00.000',
  0,
  '{"processDataSet":{"processInformation":{"dataSetInformation":{"common:UUID":"c7240000-0000-4000-8000-000000000011"}},"administrativeInformation":{"publicationAndOwnership":{"common:dataSetVersion":"01.00.000"}}}}',
  '{"processDataSet":{"processInformation":{"dataSetInformation":{"common:UUID":"c7240000-0000-4000-8000-000000000011"}},"administrativeInformation":{"publicationAndOwnership":{"common:dataSetVersion":"01.00.000"}}}}',
  'c7240000-0000-4000-8000-000000000001'
);

insert into public.lciamethods(
  id, version, state_code, json, json_ordered, user_id
) values (
  '9ec743ea-6b00-400d-a53b-61547a3fc03c',
  '01.01.000',
  0,
  '{"LCIAMethodDataSet":{"LCIAMethodInformation":{"dataSetInformation":{"common:UUID":"503699e0-eca9-4089-8bf8-e0f49c93e578"}},"administrativeInformation":{"publicationAndOwnership":{"common:dataSetVersion":"01.01.000"}}}}',
  '{"LCIAMethodDataSet":{"LCIAMethodInformation":{"dataSetInformation":{"common:UUID":"503699e0-eca9-4089-8bf8-e0f49c93e578"}},"administrativeInformation":{"publicationAndOwnership":{"common:dataSetVersion":"01.01.000"}}}}',
  'c7240000-0000-4000-8000-000000000001'
)
on conflict (id, version) do update
set state_code = excluded.state_code,
    json = excluded.json,
    json_ordered = excluded.json_ordered,
    user_id = excluded.user_id;

create temporary table candidate_boundary_normalizations as
select input.label,
  private.lcia_scope_closure_normalize_request(
    jsonb_build_object(
      'coverageMode', 'subset',
      'processes', jsonb_build_array(jsonb_build_object(
        'id', 'c7240000-0000-4000-8000-000000000010',
        'version', '01.00.000'
      )),
      'lciaMethods', jsonb_build_array(jsonb_build_object(
        'id', '503699e0-eca9-4089-8bf8-e0f49c93e578',
        'version', '01.01.000'
      )),
      'linkPolicy', case
        when input.boundary_policy is null then '{}'::jsonb
        else jsonb_build_object(
          'technosphereBoundaryPolicy', input.boundary_policy
        )
      end
    )
  ) as normalized_scope
from (values
  ('omitted', null::text),
  ('closed', 'closed'),
  ('open', 'open'),
  ('cutoff', 'cutoff')
) as input(label, boundary_policy);

select is(
  (
    select count(*)
    from candidate_boundary_normalizations
    where normalized_scope->'linkPolicy'->>'technosphereBoundaryPolicy' = 'cutoff'
  ),
  4::bigint,
  'all supported legacy boundary inputs normalize to cutoff'
);
select is(
  (
    select count(distinct normalized_scope)
    from candidate_boundary_normalizations
  ),
  1::bigint,
  'legacy boundary inputs produce one canonical requested scope and fingerprint input'
);
select throws_ok(
  $sql$
    select private.lcia_scope_closure_normalize_request(
      '{
        "coverageMode":"subset",
        "processes":[{
          "id":"c7240000-0000-4000-8000-000000000010",
          "version":"01.00.000"
        }],
        "lciaMethods":[{
          "id":"503699e0-eca9-4089-8bf8-e0f49c93e578",
          "version":"01.01.000"
        }],
        "linkPolicy":{"technosphereBoundaryPolicy":"unknown"}
      }'::jsonb
    )
  $sql$,
  '22023',
  'invalid_closure_link_policy',
  'unknown boundary policies remain invalid'
);

select is(
  (
    select count(*)
    from private.lcia_scope_closure_candidate_document_hashes
    where dataset_type = 'processes'
      and dataset_id = 'c7240000-0000-4000-8000-000000000010'
  ),
  2::bigint,
  'candidate hash triggers cache every eligible exact process version'
);
select is(
  (
    select count(*)
    from private.lcia_scope_closure_candidate_document_hashes
    where dataset_type = 'lciamethods'
      and dataset_id = '503699e0-eca9-4089-8bf8-e0f49c93e578'
      and source_locator_id = '9ec743ea-6b00-400d-a53b-61547a3fc03c'
  ),
  1::bigint,
  'candidate hash triggers cache reviewed state-code-zero LCIA methods under canonical identity'
);

select ok(
  not exists (
    select 1
    from private.lca_release_publications
    where is_current = true and status = 'current'
  ),
  'fixture has no current formal release'
);

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config(
  'request.jwt.claim.sub',
  'c7240000-0000-4000-8000-000000000001',
  true
);

create temporary table candidate_closure_responses(
  idempotency_token text primary key,
  result jsonb not null
);
insert into candidate_closure_responses values
(
  'candidate-subset-a',
  api.cmd_lcia_scope_closure_check_request_v2(
    '{
      "coverageMode":"subset",
      "processes":[{
        "id":"c7240000-0000-4000-8000-000000000010",
        "version":"01.00.000"
      }],
      "lciaMethods":[{
        "id":"503699e0-eca9-4089-8bf8-e0f49c93e578",
        "version":"01.01.000"
      }]
    }'::jsonb,
    'candidate-subset-a',
    '{}'
  )
),
(
  'candidate-subset-b',
  api.cmd_lcia_scope_closure_check_request_v2(
    '{
      "coverageMode":"subset",
      "processes":[{
        "id":"c7240000-0000-4000-8000-000000000010",
        "version":"01.00.000"
      }],
      "lciaMethods":[{
        "id":"503699e0-eca9-4089-8bf8-e0f49c93e578",
        "version":"01.01.000"
      }]
    }'::jsonb,
    'candidate-subset-b',
    '{}'
  )
);

select is(
  (
    select count(*)
    from candidate_closure_responses
    where result->>'ok' = 'true'
  ),
  2::bigint,
  'zero-release subset preflight requests are accepted'
);

reset role;

select is(
  (
    select count(distinct data_snapshot_token)
    from private.lcia_scope_closure_checks
    where request_idempotency_token in ('candidate-subset-a', 'candidate-subset-b')
  ),
  1::bigint,
  'logically identical candidate requests freeze one deterministic data snapshot'
);
select is(
  (
    select count(distinct scan_execution_id)
    from private.lcia_scope_closure_checks
    where request_idempotency_token in ('candidate-subset-a', 'candidate-subset-b')
  ),
  1::bigint,
  'logically identical candidate requests share one scan execution'
);
select is(
  (
    select requested_scope_manifest->'processes'->0->>'version'
    from private.lcia_scope_closure_checks
    where request_idempotency_token = 'candidate-subset-a'
  ),
  '01.00.000',
  'subset normalization preserves the exact requested process version'
);
select is(
  (
    select requested_scope_manifest->'lciaMethods'->0->>'id'
    from private.lcia_scope_closure_checks
    where request_idempotency_token = 'candidate-subset-a'
  ),
  '503699e0-eca9-4089-8bf8-e0f49c93e578',
  'LCIA normalization preserves canonical method identity rather than its artifact locator'
);
select is(
  (
    select requested_scope_manifest->'linkPolicy'->>'technosphereBoundaryPolicy'
    from private.lcia_scope_closure_checks
    where request_idempotency_token = 'candidate-subset-a'
  ),
  'cutoff',
  'persisted Scope Closure requests freeze the canonical cutoff boundary policy'
);
select is(
  (
    select snapshot.root_manifest->'candidateData'->>'sourceKind'
    from private.lcia_scope_closure_checks closure_check
    join private.lcia_scope_closure_data_snapshots snapshot
      using (data_snapshot_token)
    where closure_check.request_idempotency_token = 'candidate-subset-a'
  ),
  'candidate-public-state',
  'snapshot explicitly identifies candidate public state as its source'
);
select is(
  (
    select snapshot.root_manifest
      ->'currentPublicRelease'->>'releaseRunId'
    from private.lcia_scope_closure_checks closure_check
    join private.lcia_scope_closure_data_snapshots snapshot
      using (data_snapshot_token)
    where closure_check.request_idempotency_token = 'candidate-subset-a'
  ),
  '00000000-0000-0000-0000-000000000000',
  'Worker v2 compatibility projection cannot be mistaken for a real release identity'
);
select is(
  (
    select count(*)
    from private.lcia_scope_closure_checks closure_check
    join private.lcia_scope_closure_data_snapshots snapshot
      using (data_snapshot_token)
    cross join lateral jsonb_array_elements(
      snapshot.root_manifest->'datasets'
    ) dataset(value)
    where closure_check.request_idempotency_token = 'candidate-subset-a'
      and dataset.value->>'datasetType' = 'processes'
      and dataset.value->>'datasetId' =
        'c7240000-0000-4000-8000-000000000010'
      and dataset.value->>'datasetVersion' in ('01.00.000', '02.00.000')
      and dataset.value->>'canonicalContentHash' ~ '^[0-9a-f]{64}$'
  ),
  2::bigint,
  'candidate allowlist freezes every eligible exact process version with Worker hashes'
);
select is(
  (
    select count(*)
    from private.lcia_scope_closure_checks closure_check
    join private.lcia_scope_closure_data_snapshots snapshot
      using (data_snapshot_token)
    cross join lateral jsonb_array_elements(
      snapshot.root_manifest->'datasets'
    ) dataset(value)
    where closure_check.request_idempotency_token = 'candidate-subset-a'
      and dataset.value->>'datasetType' = 'lciamethods'
      and dataset.value->>'datasetId' =
        '503699e0-eca9-4089-8bf8-e0f49c93e578'
      and dataset.value->>'datasetVersion' = '01.01.000'
  ),
  1::bigint,
  'candidate allowlist uses the canonical LCIA identity while hashing the locator document'
);

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config(
  'request.jwt.claim.sub',
  'c7240000-0000-4000-8000-000000000001',
  true
);

insert into candidate_closure_responses values
(
  'candidate-global',
  api.cmd_lcia_scope_closure_check_request_v2(
    '{
      "coverageMode":"global_eligible",
      "processes":[],
      "lciaMethods":[{
        "id":"503699e0-eca9-4089-8bf8-e0f49c93e578",
        "version":"01.01.000"
      }]
    }'::jsonb,
    'candidate-global',
    '{}'
  )
);
select is(
  (
    select result->>'ok'
    from candidate_closure_responses
    where idempotency_token = 'candidate-global'
  ),
  'true',
  'zero-release global eligible preflight is accepted'
);
select is(
  api.get_lcia_scope_closure_check(
    (
      select (result->'data'->>'closureCheckId')::uuid
      from candidate_closure_responses
      where idempotency_token = 'candidate-global'
    )
  )->'data'->>'scanCompleteness',
  'unknown',
  'queued zero-release checks project unknown scan completeness'
);
select is(
  api.get_lcia_scope_closure_check(
    (
      select (result->'data'->>'closureCheckId')::uuid
      from candidate_closure_responses
      where idempotency_token = 'candidate-global'
    )
  )->'data'->>'certificateValidity',
  'unavailable',
  'queued zero-release checks hide the internal pending certificate state'
);

reset role;

select is(
  (
    select requested_scope_manifest->'processes'->0->>'version'
    from private.lcia_scope_closure_checks
    where request_idempotency_token = 'candidate-global'
  ),
  '02.00.000',
  'global candidate roots select the latest eligible version per process UUID'
);

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config(
  'request.jwt.claim.sub',
  'c7240000-0000-4000-8000-000000000001',
  true
);

select is(
  api.cmd_lcia_scope_closure_check_request_v2(
    '{
      "coverageMode":"subset",
      "processes":[{
        "id":"c7240000-0000-4000-8000-000000000011",
        "version":"01.00.000"
      }],
      "lciaMethods":[{
        "id":"503699e0-eca9-4089-8bf8-e0f49c93e578",
        "version":"01.01.000"
      }]
    }'::jsonb,
    'candidate-ineligible',
    '{}'
  )->>'code',
  'invalid_closure_scope',
  'non-eligible exact process identities remain rejected'
);
select is(
  api.cmd_lcia_scope_closure_check_request_v2(
    '{
      "coverageMode":"subset",
      "processes":[{
        "id":"c7240000-0000-4000-8000-000000000010",
        "version":"01.00.000"
      }],
      "lciaMethods":[{
        "id":"503699e0-eca9-4089-8bf8-e0f49c93e578",
        "version":"01.01.000"
      }],
      "certificateFreshnessPolicy":"current-membership-required-v1"
    }'::jsonb,
    'candidate-current-membership',
    '{}'
  )->>'code',
  'current_release_required',
  'explicit current-membership freshness still requires a formal release'
);

reset role;

-- A selected Final Result publication must leave candidate calculation inputs usable.
insert into private.lca_release_runs(
  id, release_version, publication_format, scope_mode,
  selection_manifest_hash, input_manifest_hash, calculation_bundle_hash,
  calculation_bundle_ref, profile_lock_hash, publish_plan_hash, publish_plan,
  artifact_set_hash, release_manifest_hash, release_manifest, status,
  idempotency_key, request_hash, created_by
) values (
  'c7240000-0000-4000-8000-000000000090', '2026.11.0',
  'final-result-pair.v2', 'selected_final_results', repeat('a',64), repeat('b',64),
  null, null, repeat('d',64), repeat('e',64), '{}', repeat('f',64),
  repeat('9',64), '{}', 'published', 'candidate-final-release', repeat('1',64),
  'c7240000-0000-4000-8000-000000000001'
);
insert into private.lca_release_approvals(
  id, release_run_id, publish_plan_hash, approval_hash, approved_by, approved_at, expires_at
) values (
  'c7240000-0000-4000-8000-000000000091',
  'c7240000-0000-4000-8000-000000000090', repeat('e',64), repeat('2',64),
  'c7240000-0000-4000-8000-000000000001', now(), now()+interval '1 day'
);
insert into private.lca_release_publications(
  id, release_run_id, release_version, approval_id, approval_hash, publish_plan_hash,
  release_manifest_hash, artifact_set_hash, approved_by, executed_by,
  credential_fingerprint, idempotency_key, published_at
) values (
  'c7240000-0000-4000-8000-000000000092',
  'c7240000-0000-4000-8000-000000000090', '2026.11.0',
  'c7240000-0000-4000-8000-000000000091', repeat('2',64), repeat('e',64),
  repeat('9',64), repeat('f',64), 'c7240000-0000-4000-8000-000000000001',
  'c7240000-0000-4000-8000-000000000001', repeat('3',64), 'candidate-final-publication', now()
);

-- Reuse the exact pre-publication scopes to prove publication does not change inputs.
create temporary table final_publication_scopes as
select request_idempotency_token as original_token,
  case when requested_scope_manifest->>'coverageMode' = 'global_eligible'
    then requested_scope_manifest - 'processes'
    else requested_scope_manifest end as scope
from private.lcia_scope_closure_checks
where request_idempotency_token in ('candidate-subset-a', 'candidate-global');
grant select on final_publication_scopes to authenticated;
set local role authenticated;
create temporary table final_publication_result_set as
select api.cmd_lcia_result_set_create('Final publication candidate regression') as result;
create temporary table final_publication_responses as
select original_token, api.cmd_lcia_scope_closure_check_request_v3(
  (select (result->'data'->>'resultSetId')::uuid from final_publication_result_set),
  scope, 'final-' || original_token, '{}'
) as result from final_publication_scopes;
select is((select count(*) from final_publication_responses where result->>'ok'='true'),
  2::bigint, 'Final Result current publication admits subset and global through ResultSet RPC');
select is(
  api.cmd_lcia_scope_closure_check_request_v2(
    (select scope || '{"certificateFreshnessPolicy":"current-membership-required-v1"}'
     from final_publication_scopes where original_token='candidate-global'),
    'final-current-membership', '{}'
  )->>'code', 'current_release_required',
  'Final Result publication does not satisfy calculation current-membership freshness'
);
select is(
  api.cmd_lcia_scope_closure_check_request_v2(
    (select scope || '{"lciaMethods":[{"id":"c7240000-0000-4000-8000-000000000099","version":"01.00.000"}]}'
     from final_publication_scopes where original_token='candidate-global'),
    'final-invalid-method', '{}'
  )->>'code', 'invalid_closure_scope', 'Final Result path retains reviewed method validation'
);
reset role;
select is((select count(*) from private.lcia_scope_closure_checks after_check
  join private.lcia_scope_closure_checks before_check
    on after_check.request_idempotency_token='final-' || before_check.request_idempotency_token
  where before_check.request_idempotency_token in ('candidate-subset-a','candidate-global')
    and after_check.requested_scope_hash=before_check.requested_scope_hash
    and after_check.data_snapshot_token=before_check.data_snapshot_token
    and after_check.scan_execution_id=before_check.scan_execution_id
    and after_check.result_set_id is not null),
  2::bigint, 'Final Result publication preserves candidate scope, frozen snapshot and reusable scan');
select ok(exists(select 1 from pg_locks where pid=pg_backend_pid()
  and relation='private.lca_release_publications'::regclass and mode='ShareLock' and granted),
  'admission holds the publication selector stable until transaction completion');
select is((select count(*) from private.lca_release_dataset_versions
  where release_run_id='c7240000-0000-4000-8000-000000000090'),
  0::bigint, 'candidate checks do not fabricate legacy release membership');

-- Even a newer derived Result version must not replace its eligible Unit root.
insert into public.processes(id,version,state_code,json,json_ordered,user_id)
select id,'03.00.000',120,
  jsonb_set(json, '{processDataSet,administrativeInformation,publicationAndOwnership,common:dataSetVersion}', '"03.00.000"'),
  jsonb_set(json_ordered::jsonb, '{processDataSet,administrativeInformation,publicationAndOwnership,common:dataSetVersion}', '"03.00.000"')::json,
  user_id from public.processes
where id='c7240000-0000-4000-8000-000000000010' and version='02.00.000';
select is(private.lcia_scope_closure_normalize_request(
  (select scope from final_publication_scopes where original_token='candidate-global')
)->'processes'->0->>'version', '02.00.000', 'Final Result path excludes state 120 from calculation roots');
select throws_ok($query$select private.lcia_scope_closure_normalize_request(
  '{"coverageMode":"subset","processes":[{"id":"c7240000-0000-4000-8000-000000000010","version":"03.00.000"}],"lciaMethods":[]}'
)$query$, '22023', 'invalid_or_ineligible_process_selection', 'derived Results cannot be selected as calculation roots');

select * from finish();
rollback;
