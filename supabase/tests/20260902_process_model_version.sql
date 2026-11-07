begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, auth;

select plan(32);

select has_column(
  'public',
  'processes',
  'model_version',
  'processes exposes the exact LifecycleModel version'
);

select ok(
  (
    select is_nullable = 'YES'
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'processes'
      and column_name = 'model_version'
  ),
  'processes.model_version stays nullable for legacy fallback rows'
);

alter table public.processes disable trigger user;
alter table public.processes enable trigger processes_json_sync_trigger;
alter table public.lifecyclemodels disable trigger user;
alter table public.lifecyclemodels enable trigger lifecyclemodels_json_sync_trigger;

select throws_like(
  $$
    insert into public.processes (
      id,
      version,
      json_ordered,
      model_version
    )
    values (
      'b9000000-0000-0000-0000-000000000001',
      '01.00.000',
      '{"processDataSet":{"administrativeInformation":{"publicationAndOwnership":{"common:dataSetVersion":"01.00.000"}}}}'::json,
      '01.01.021'
    )
  $$,
  '%processes_model_version_requires_model_id_check%',
  'an exact model version cannot exist without a model id'
);

select throws_like(
  $$
    insert into public.processes (
      id,
      version,
      json_ordered,
      model_id,
      model_version
    )
    values (
      'b9000000-0000-0000-0000-000000000002',
      '01.00.000',
      '{"processDataSet":{"administrativeInformation":{"publicationAndOwnership":{"common:dataSetVersion":"01.00.000"}}}}'::json,
      'b9100000-0000-0000-0000-000000000001',
      'invalid'
    )
  $$,
  '%processes_model_version_format_check%',
  'an exact model version must use the ILCD version format'
);

insert into auth.users (
  instance_id,
  id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at,
  is_sso_user,
  is_anonymous
)
values (
  '00000000-0000-0000-0000-000000000000',
  'b9200000-0000-0000-0000-000000000001',
  'authenticated',
  'authenticated',
  'process-model-version@example.com',
  'test-password-hash',
  now(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{"sub":"b9200000-0000-0000-0000-000000000001","email":"process-model-version@example.com"}'::jsonb,
  now(),
  now(),
  false,
  false
);

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', 'b9200000-0000-0000-0000-000000000001', true);

select is(
  api.cmd_dataset_create(
    p_table => 'processes',
    p_id => 'b9300000-0000-0000-0000-000000000001',
    p_json_ordered => '{"processDataSet":{"administrativeInformation":{"publicationAndOwnership":{"common:dataSetVersion":"01.00.000"}}}}'::jsonb,
    p_model_id => 'b9100000-0000-0000-0000-000000000001',
    p_audit => '{}'::jsonb,
    p_model_version => '01.01.021'
  )->>'ok',
  'true',
  'dataset create accepts an exact model version for a Process'
);

select is(
  (
    select model_version::text
    from public.processes
    where id = 'b9300000-0000-0000-0000-000000000001'
      and version = '01.00.000'
  ),
  '01.01.021',
  'dataset create persists the exact model version'
);

select is(
  api.cmd_dataset_create(
    p_table => 'processes',
    p_id => 'b9300000-0000-0000-0000-000000000002',
    p_json_ordered => '{"processDataSet":{"administrativeInformation":{"publicationAndOwnership":{"common:dataSetVersion":"01.00.000"}}}}'::jsonb,
    p_audit => '{}'::jsonb,
    p_model_version => '01.01.021'
  )->>'code',
  'MODEL_ID_REQUIRED_FOR_MODEL_VERSION',
  'dataset create rejects a model version without a model id'
);

select is(
  api.cmd_dataset_save_draft(
    p_table => 'processes',
    p_id => 'b9300000-0000-0000-0000-000000000001',
    p_version => '01.00.000',
    p_json_ordered => '{"processDataSet":{"administrativeInformation":{"publicationAndOwnership":{"common:dataSetVersion":"01.00.000"}},"payload":"preserve"}}'::jsonb,
    p_audit => '{}'::jsonb
  )->>'ok',
  'true',
  'legacy draft save remains compatible when model fields are omitted'
);

select is(
  (
    select model_version::text
    from public.processes
    where id = 'b9300000-0000-0000-0000-000000000001'
      and version = '01.00.000'
  ),
  '01.01.021',
  'omitting model fields preserves an existing exact model version'
);

select is(
  api.cmd_dataset_save_draft(
    p_table => 'processes',
    p_id => 'b9300000-0000-0000-0000-000000000001',
    p_version => '01.00.000',
    p_json_ordered => '{"processDataSet":{"administrativeInformation":{"publicationAndOwnership":{"common:dataSetVersion":"01.00.000"}},"payload":"legacy"}}'::jsonb,
    p_model_id => 'b9100000-0000-0000-0000-000000000002',
    p_audit => '{}'::jsonb
  )->>'ok',
  'true',
  'an old writer may still move a Process to legacy model fallback semantics'
);

select ok(
  (
    select model_version is null
    from public.processes
    where id = 'b9300000-0000-0000-0000-000000000001'
      and version = '01.00.000'
  ),
  'changing modelId without modelVersion clears a stale exact version'
);

select is(
  api.cmd_dataset_save_draft(
    p_table => 'processes',
    p_id => 'b9300000-0000-0000-0000-000000000001',
    p_version => '01.00.000',
    p_json_ordered => '{"processDataSet":{"administrativeInformation":{"publicationAndOwnership":{"common:dataSetVersion":"01.00.000"}},"payload":"exact"}}'::jsonb,
    p_model_id => 'b9100000-0000-0000-0000-000000000001',
    p_audit => '{}'::jsonb,
    p_model_version => '01.01.021'
  )->>'ok',
  'true',
  'draft save restores an explicit exact model reference'
);

select is(
  (
    select model_version::text
    from public.processes
    where id = 'b9300000-0000-0000-0000-000000000001'
      and version = '01.00.000'
  ),
  '01.01.021',
  'draft save persists the restored exact model version'
);

select is(
  api.cmd_dataset_create_version(
    p_table => 'processes',
    p_id => 'b9300000-0000-0000-0000-000000000001',
    p_source_version => '01.00.000',
    p_json_ordered => '{"processDataSet":{"administrativeInformation":{"publicationAndOwnership":{"common:dataSetVersion":"01.00.000"}}}}'::jsonb,
    p_model_id => 'b9100000-0000-0000-0000-000000000001',
    p_audit => '{}'::jsonb,
    p_model_version => '01.01.021'
  )->>'ok',
  'true',
  'dataset create-version accepts an exact model version'
);

select is(
  (
    select model_version::text
    from public.processes
    where id = 'b9300000-0000-0000-0000-000000000001'
      and version = '01.00.001'
  ),
  '01.01.021',
  'dataset create-version persists the exact model version'
);

reset role;
set local role service_role;

select is(
  private.save_lifecycle_model_bundle(
    '{
      "mode": "create",
      "modelId": "b9400000-0000-0000-0000-000000000001",
      "actorUserId": "b9200000-0000-0000-0000-000000000001",
      "parent": {
        "jsonOrdered": {
          "lifeCycleModelDataSet": {
            "lifeCycleModelInformation": {
              "dataSetInformation": {
                "referenceToResultingProcess": {
                  "@type": "process data set",
                  "@refObjectId": "b9500000-0000-0000-0000-000000000001",
                  "@version": "01.05.000"
                }
              }
            },
            "administrativeInformation": {
              "publicationAndOwnership": {
                "common:dataSetVersion": "02.00.000"
              }
            }
          }
        },
        "jsonTg": {},
        "ruleVerification": true
      },
      "processMutations": [
        {
          "op": "create",
          "id": "b9500000-0000-0000-0000-000000000001",
          "jsonOrdered": {
            "processDataSet": {
              "administrativeInformation": {
                "publicationAndOwnership": {
                  "common:dataSetVersion": "01.05.000"
                }
              }
            }
          },
          "ruleVerification": true
        }
      ]
    }'::jsonb
  )->>'version',
  '02.00.000',
  'bundle save accepts a Process version that differs from its Model version'
);

select is(
  (
    select model_version::text
    from public.processes
    where id = 'b9500000-0000-0000-0000-000000000001'
      and version = '01.05.000'
  ),
  '02.00.000',
  'bundle save records the parent Model version instead of the Process version'
);

insert into public.lifecyclemodels (
  id,
  version,
  json_ordered,
  user_id,
  state_code
)
values (
  'b9400000-0000-0000-0000-000000000001',
  '03.00.000',
  '{"lifeCycleModelDataSet":{"administrativeInformation":{"publicationAndOwnership":{"common:dataSetVersion":"03.00.000"}}}}'::json,
  'b9200000-0000-0000-0000-000000000001',
  100
);

insert into public.processes (
  id,
  version,
  json,
  json_ordered,
  user_id,
  state_code,
  model_id,
  model_version
)
values
  (
    'b9500000-0000-0000-0000-000000000002',
    '09.00.000',
    '{"processDataSet":{"administrativeInformation":{"publicationAndOwnership":{"common:dataSetVersion":"09.00.000"}}}}'::jsonb,
    '{"processDataSet":{"administrativeInformation":{"publicationAndOwnership":{"common:dataSetVersion":"09.00.000"}}}}'::json,
    'b9200000-0000-0000-0000-000000000001',
    100,
    'b9400000-0000-0000-0000-000000000001',
    '03.00.000'
  ),
  (
    'b9500000-0000-0000-0000-000000000003',
    '02.00.000',
    '{"processDataSet":{"administrativeInformation":{"publicationAndOwnership":{"common:dataSetVersion":"02.00.000"}}}}'::jsonb,
    '{"processDataSet":{"administrativeInformation":{"publicationAndOwnership":{"common:dataSetVersion":"02.00.000"}}}}'::json,
    'b9200000-0000-0000-0000-000000000001',
    0,
    'b9400000-0000-0000-0000-000000000001',
    null
  );

select throws_like(
  $$
    select private.save_lifecycle_model_bundle(
      '{
        "mode": "update",
        "modelId": "b9400000-0000-0000-0000-000000000001",
        "version": "02.00.000",
        "actorUserId": "b9200000-0000-0000-0000-000000000001",
        "parent": {
          "jsonOrdered": {
            "lifeCycleModelDataSet": {
              "administrativeInformation": {
                "publicationAndOwnership": {
                  "common:dataSetVersion": "02.00.000"
                }
              }
            }
          }
        },
        "processMutations": [
          {
            "op": "update",
            "id": "b9500000-0000-0000-0000-000000000002",
            "version": "09.00.000",
            "jsonOrdered": {
              "processDataSet": {
                "administrativeInformation": {
                  "publicationAndOwnership": {
                    "common:dataSetVersion": "09.00.000"
                  }
                }
              }
            }
          }
        ]
      }'::jsonb
    )
  $$,
  '%PROCESS_NOT_FOUND%',
  'bundle update cannot mutate a Process owned by another Model version'
);

select throws_like(
  $$
    select private.save_lifecycle_model_bundle(
      '{
        "mode": "update",
        "modelId": "b9400000-0000-0000-0000-000000000001",
        "version": "02.00.000",
        "actorUserId": "b9200000-0000-0000-0000-000000000001",
        "parent": {
          "jsonOrdered": {
            "lifeCycleModelDataSet": {
              "administrativeInformation": {
                "publicationAndOwnership": {
                  "common:dataSetVersion": "02.00.000"
                }
              }
            }
          }
        },
        "processMutations": [
          {
            "op": "delete",
            "id": "b9500000-0000-0000-0000-000000000002",
            "version": "09.00.000"
          }
        ]
      }'::jsonb
    )
  $$,
  '%PROCESS_NOT_FOUND%',
  'bundle delete mutation cannot remove a Process owned by another Model version'
);

reset role;

select is(
  (
    select count(*)::text
    from api.cmd_review_collect_dataset_targets(
      '[{
        "table": "lifecyclemodels",
        "id": "b9400000-0000-0000-0000-000000000001",
        "version": "02.00.000",
        "is_root": true
      }]'::jsonb,
      false
    )
    where table_name = 'processes'
      and dataset_id = 'b9500000-0000-0000-0000-000000000001'
      and dataset_version = '01.05.000'
  ),
  '1',
  'review target collection follows an exact cross-version Process owner reference'
);

select ok(
  (
    select bool_and(
      strpos(
        pg_get_functiondef(signature),
        'coalesce(model_process.model_version, model_process.version)'
      ) > 0
    )
    from unnest(array[
      'api.cmd_review_collect_dataset_targets(jsonb,boolean)'::regprocedure,
      'private.review_resolve_current_reference_targets_v1(uuid[])'::regprocedure,
      'private.cmd_review_assert_lifecycle_closure(jsonb,text,uuid)'::regprocedure,
      'private.cmd_review_approve_issue304_legacy(text,uuid,jsonb)'::regprocedure
    ]) as signatures(signature)
  ),
  'all current review ownership paths use exact Model version semantics'
);

set local role service_role;

select is(
  private.delete_lifecycle_model_bundle(
    'b9400000-0000-0000-0000-000000000001',
    '02.00.000'
  )->>'version',
  '02.00.000',
  'bundle delete resolves both exact and legacy ownership semantics'
);

select is(
  (
    select count(*)::text
    from public.processes
    where id = 'b9500000-0000-0000-0000-000000000001'
  ),
  '0',
  'bundle delete removes an exact cross-version Process owner reference'
);

select is(
  (
    select count(*)::text
    from public.processes
    where id = 'b9500000-0000-0000-0000-000000000003'
  ),
  '0',
  'bundle delete keeps legacy fallback behavior for null model_version'
);

select is(
  (
    select count(*)::text
    from public.processes
    where id = 'b9500000-0000-0000-0000-000000000002'
      and model_version = '03.00.000'
  ),
  '1',
  'bundle delete preserves Processes owned by another Model version'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', 'b9200000-0000-0000-0000-000000000001', true);

select is(
  (
    select model_version::text
    from api.get_latest_process_versions(10, 1, 'tg')
    where id = 'b9500000-0000-0000-0000-000000000002'
  ),
  '03.00.000',
  'latest Process list returns model_version'
);

select is(
  (
    select model_version::text
    from api.search_processes(
      query_text => 'b9500000-0000-0000-0000-000000000002',
      data_source => 'tg'
    )
    where id = 'b9500000-0000-0000-0000-000000000002'
  ),
  '03.00.000',
  'Process search returns model_version from the selected Process revision'
);

reset role;

select lives_ok(
  $$
    select *
    from api.pgroonga_search_processes_latest(
      query_text => '',
      page_size => 100,
      page_current => 1,
      data_source => 'tg'
    )
  $$,
  'legacy PGroonga Process search keeps its established result shape'
);

reset role;

select is(
  (
    select capability_id
    from private.api_capability_grants
    where routine_identity = 'api.cmd_dataset_create(text, uuid, jsonb, uuid, boolean, jsonb, text)'
  ),
  'DB-CORE-WRITE-01',
  'dataset create capability follows the new exact signature'
);

select is(
  (
    select capability_id
    from private.api_capability_grants
    where routine_identity = 'api.cmd_dataset_save_draft(text, uuid, text, jsonb, uuid, boolean, jsonb, text)'
  ),
  'DB-CORE-WRITE-01',
  'dataset save-draft capability follows the new exact signature'
);

select is(
  (
    select capability_id
    from private.api_capability_grants
    where routine_identity = 'api.cmd_dataset_create_version(text, uuid, text, jsonb, uuid, boolean, jsonb, text)'
  ),
  'CLI-RPC-01',
  'dataset create-version capability follows the new exact signature'
);

select is(
  (
    select count(*)::text
    from private.api_capability_grants
    where routine_identity in (
      'api.cmd_dataset_create(text, uuid, jsonb, uuid, boolean, jsonb)',
      'api.cmd_dataset_save_draft(text, uuid, text, jsonb, uuid, boolean, jsonb)',
      'api.cmd_dataset_create_version(text, uuid, text, jsonb, uuid, boolean, jsonb)'
    )
  ),
  '0',
  'retired command signatures do not remain in the capability manifest'
);

select * from finish();
rollback;
