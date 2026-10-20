begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, auth;

create or replace function pg_temp.disable_trigger_if_exists(p_table regclass, p_trigger name)
returns void
language plpgsql
as $$
begin
  if exists (
    select 1
    from pg_trigger
    where tgrelid = p_table
      and tgname = p_trigger
      and not tgisinternal
  ) then
    execute format('alter table %s disable trigger %I', p_table, p_trigger);
  end if;
end;
$$;

select plan(19);

select set_config('request.jwt.claim.role', 'authenticated', true);

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
values
  (
    '00000000-0000-0000-0000-000000000000',
    'a1000000-0000-0000-0000-000000000001',
    'authenticated',
    'authenticated',
    'create-version-owner@example.com',
    'test-password-hash',
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{"sub":"a1000000-0000-0000-0000-000000000001","email":"create-version-owner@example.com"}'::jsonb,
    now(),
    now(),
    false,
    false
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    'a1000000-0000-0000-0000-000000000002',
    'authenticated',
    'authenticated',
    'create-version-other@example.com',
    'test-password-hash',
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{"sub":"a1000000-0000-0000-0000-000000000002","email":"create-version-other@example.com"}'::jsonb,
    now(),
    now(),
    false,
    false
  );

insert into private.users (id, raw_user_meta_data, contact)
values
  ('a1000000-0000-0000-0000-000000000001', '{"email":"create-version-owner@example.com"}'::jsonb, null),
  ('a1000000-0000-0000-0000-000000000002', '{"email":"create-version-other@example.com"}'::jsonb, null);

alter table public.processes disable trigger "process_extract_md_trigger_insert";
select pg_temp.disable_trigger_if_exists('public.lifecyclemodels'::regclass, 'lifecyclemodel_extract_md_trigger_insert');

insert into public.processes (id, json_ordered, user_id, state_code, rule_verification)
values
  (
    'a2000000-0000-0000-0000-000000000001',
    '{
      "processDataSet": {
        "administrativeInformation": {
          "publicationAndOwnership": {
            "common:dataSetVersion": "01.01.000",
            "common:permanentDataSetURI": "old"
          }
        }
      }
    }'::json,
    'a1000000-0000-0000-0000-000000000002',
    100,
    true
  ),
  (
    'a2000000-0000-0000-0000-000000000001',
    '{
      "processDataSet": {
        "administrativeInformation": {
          "publicationAndOwnership": {
            "common:dataSetVersion": "01.01.001"
          }
        }
      }
    }'::json,
    -- A different owner's review version still participates in server
    -- allocation; the caller itself must have no draft or in-progress review.
    'a1000000-0000-0000-0000-000000000002',
    20,
    true
  ),
  (
    'a2000000-0000-0000-0000-000000000001',
    '{
      "processDataSet": {
        "administrativeInformation": {
          "publicationAndOwnership": {
            "common:dataSetVersion": "01.01.002"
          }
        }
      }
    }'::json,
    'a1000000-0000-0000-0000-000000000002',
    200,
    true
  ),
  (
    'a2000000-0000-0000-0000-000000000001',
    '{
      "processDataSet": {
        "administrativeInformation": {
          "publicationAndOwnership": {
            "common:dataSetVersion": "bad.ver"
          }
        }
      }
    }'::json,
    'a1000000-0000-0000-0000-000000000002',
    20,
    true
  );

insert into public.contacts (id, json_ordered, user_id, state_code, rule_verification)
values (
  'a3000000-0000-0000-0000-000000000001',
  '{
    "contactDataSet": {
      "administrativeInformation": {
        "publicationAndOwnership": {
          "common:dataSetVersion": "01.99.999"
        }
      }
    }
  }'::json,
  'a1000000-0000-0000-0000-000000000002',
  100,
  true
);

insert into public.lifecyclemodels (id, json_ordered, json_tg, user_id, state_code, rule_verification)
values (
  'a8000000-0000-0000-0000-000000000001',
  '{
    "lifeCycleModelDataSet": {
      "administrativeInformation": {
        "publicationAndOwnership": {
          "common:dataSetVersion": "01.00.000"
        }
      }
    }
  }'::json,
  '{"submodels":[{"id":"a8000000-0000-0000-0000-000000000101","version":"01.00.000"}]}'::jsonb,
  'a1000000-0000-0000-0000-000000000002',
  100,
  true
);

insert into public.processes (id, json_ordered, user_id, model_id, state_code, rule_verification)
values (
  'a8000000-0000-0000-0000-000000000101',
  '{
    "processDataSet": {
      "administrativeInformation": {
        "publicationAndOwnership": {
          "common:dataSetVersion": "01.00.000"
        }
      }
    }
  }'::json,
  'a1000000-0000-0000-0000-000000000002',
  'a8000000-0000-0000-0000-000000000001',
  100,
  true
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'a1000000-0000-0000-0000-000000000001', true);

select is(
  api.cmd_dataset_create_version(
    'processes',
    'a2000000-0000-0000-0000-000000000001',
    '01.01.000',
    '{
      "processDataSet": {
        "administrativeInformation": {
          "publicationAndOwnership": {
            "common:dataSetVersion": "01.01.000",
            "common:permanentDataSetURI": "stale"
          }
        },
        "processInformation": {
          "dataSetInformation": {
            "common:UUID": "a2000000-0000-0000-0000-000000000001"
          }
        }
      }
    }'::jsonb,
    null,
    false,
    '{"command":"dataset_create_version","source":"open-data"}'::jsonb
  )->'data'->>'version',
  '01.01.003',
  'cmd_dataset_create_version allocates after visible, commercial, and under-review versions when no owner draft exists'
);

select is(
  (
    select user_id::text
    from public.processes
    where id = 'a2000000-0000-0000-0000-000000000001'
      and version = '01.01.003'
  ),
  'a1000000-0000-0000-0000-000000000001',
  'created version is owned by the current actor'
);

select is(
  (
    select rule_verification::text
    from public.processes
    where id = 'a2000000-0000-0000-0000-000000000001'
      and version = '01.01.003'
  ),
  'false',
  'created version persists rule verification'
);

select is(
  (
    select json_ordered::jsonb
      #>> '{processDataSet,administrativeInformation,publicationAndOwnership,common:dataSetVersion}'
    from public.processes
    where id = 'a2000000-0000-0000-0000-000000000001'
      and version = '01.01.003'
  ),
  '01.01.003',
  'created json_ordered dataSetVersion matches the allocated version'
);

select is(
  (
    select json_ordered::jsonb
      #>> '{processDataSet,administrativeInformation,publicationAndOwnership,common:permanentDataSetURI}'
    from public.processes
    where id = 'a2000000-0000-0000-0000-000000000001'
      and version = '01.01.003'
  ),
  'https://lcdn.tiangong.earth/datasetdetail/process.xhtml?uuid=a2000000-0000-0000-0000-000000000001&version=01.01.003',
  'created json_ordered permanentDataSetURI matches the allocated version'
);

reset role;

select is(
  (
    select target_version
    from private.command_audit_log
    where command = 'cmd_dataset_create_version'
      and target_id = 'a2000000-0000-0000-0000-000000000001'
    order by created_at desc
    limit 1
  ),
  '01.01.003',
  'command audit log records the allocated target version'
);

set local role authenticated;

select is(
  api.cmd_dataset_create_version(
    'contacts',
    'a3000000-0000-0000-0000-000000000001',
    '01.99.999',
    '{
      "contactDataSet": {
        "administrativeInformation": {
          "publicationAndOwnership": {
            "common:dataSetVersion": "01.99.999"
          }
        }
      }
    }'::jsonb,
    null,
    true,
    '{}'::jsonb
  )->'data'->>'version',
  '02.00.000',
  'cmd_dataset_create_version carries version overflow correctly'
);

select is(
  (
    select json_ordered::jsonb
      #>> '{contactDataSet,administrativeInformation,publicationAndOwnership,common:permanentDataSetURI}'
    from public.contacts
    where id = 'a3000000-0000-0000-0000-000000000001'
      and version = '02.00.000'
  ),
  'https://lcdn.tiangong.earth/datasetdetail/contact.xhtml?uuid=a3000000-0000-0000-0000-000000000001&version=02.00.000',
  'contact permanentDataSetURI uses the contact dataset route'
);

select is(
  api.cmd_dataset_create_version(
    'sources',
    'a4000000-0000-0000-0000-000000000001',
    '01.00.000',
    '{}'::jsonb,
    null,
    true,
    '{}'::jsonb
  )->>'code',
  'DATASET_SOURCE_NOT_FOUND',
  'sourceVersion is checked when provided'
);

select is(
  api.cmd_dataset_create_version(
    'sources',
    'a4000000-0000-0000-0000-000000000001',
    null,
    '{}'::jsonb,
    null,
    true,
    '{}'::jsonb
  )->>'code',
  'DATASET_SOURCE_VERSION_REQUIRED',
  'sourceVersion is required for create-version commands'
);

select is(
  api.cmd_dataset_create_version(
    'contacts',
    'a3000000-0000-0000-0000-000000000001',
    '01.99.999',
    '{}'::jsonb,
    'a5000000-0000-0000-0000-000000000001',
    true,
    '{}'::jsonb
  )->>'code',
  'MODEL_ID_NOT_ALLOWED',
  'modelId is rejected outside process version creation'
);

select is(
  api.cmd_dataset_create_version(
    'lifecyclemodels',
    'a6000000-0000-0000-0000-000000000001',
    '01.00.000',
    '{}'::jsonb,
    null,
    true,
    '{}'::jsonb
  )->>'code',
  'LIFECYCLEMODEL_BUNDLE_REQUIRED',
  'lifecycle model create-version stays on bundle-specific commands'
);

select is(
  api.cmd_dataset_create_version(
    'unknown',
    'a7000000-0000-0000-0000-000000000001',
    null,
    '{}'::jsonb,
    null,
    true,
    '{}'::jsonb
  )->>'code',
  'INVALID_DATASET_TABLE',
  'unsupported tables are rejected'
);

select is(
  api.cmd_dataset_create_version(
    'contacts',
    'a3000000-0000-0000-0000-000000000001',
    '02.00.000',
    null,
    null,
    true,
    '{}'::jsonb
  )->>'code',
  'JSON_ORDERED_REQUIRED',
  'jsonOrdered is required'
);

reset role;
set local role service_role;

select is(
  private.save_lifecycle_model_bundle(
    '{
      "mode": "create",
      "modelId": "a8000000-0000-0000-0000-000000000001",
      "actorUserId": "a1000000-0000-0000-0000-000000000001",
      "allocateVersion": true,
      "sourceVersion": "01.00.000",
      "parent": {
        "jsonOrdered": {
          "lifeCycleModelDataSet": {
            "lifeCycleModelInformation": {
              "dataSetInformation": {
                "referenceToResultingProcess": [
                  {
                    "@refObjectId": "a8000000-0000-0000-0000-000000000101",
                    "@version": "99.99.999"
                  }
                ]
              }
            },
            "administrativeInformation": {
              "publicationAndOwnership": {
                "common:dataSetVersion": "99.99.999",
                "common:permanentDataSetURI": "stale"
              }
            }
          }
        },
        "jsonTg": {
          "submodels": [
            {
              "id": "a8000000-0000-0000-0000-000000000101",
              "version": "99.99.999"
            }
          ]
        },
        "ruleVerification": false
      },
      "processMutations": [
        {
          "op": "create",
          "id": "a8000000-0000-0000-0000-000000000101",
          "modelId": "a8000000-0000-0000-0000-000000000001",
          "jsonOrdered": {
            "processDataSet": {
              "administrativeInformation": {
                "publicationAndOwnership": {
                  "common:dataSetVersion": "99.99.999",
                  "common:permanentDataSetURI": "stale"
                }
              }
            }
          },
          "ruleVerification": false
        }
      ]
    }'::jsonb
  )->>'version',
  '01.00.001',
  'save_lifecycle_model_bundle allocates the next lifecycle model version when requested'
);

set local role authenticated;

select is(
  (
    select json_ordered::jsonb
      #>> '{lifeCycleModelDataSet,administrativeInformation,publicationAndOwnership,common:dataSetVersion}'
    from public.lifecyclemodels
    where id = 'a8000000-0000-0000-0000-000000000001'
      and version = '01.00.001'
  ),
  '01.00.001',
  'allocated lifecycle model JSON version is persisted'
);

select is(
  (
    select json_tg #>> '{submodels,0,version}'
    from public.lifecyclemodels
    where id = 'a8000000-0000-0000-0000-000000000001'
      and version = '01.00.001'
  ),
  '01.00.001',
  'allocated lifecycle model json_tg submodel version is persisted'
);

select is(
  (
    select json_ordered::jsonb
      #>> '{lifeCycleModelDataSet,lifeCycleModelInformation,dataSetInformation,referenceToResultingProcess,0,@version}'
    from public.lifecyclemodels
    where id = 'a8000000-0000-0000-0000-000000000001'
      and version = '01.00.001'
  ),
  '01.00.001',
  'allocated lifecycle model resulting-process reference version is persisted'
);

select is(
  (
    select json_ordered::jsonb
      #>> '{processDataSet,administrativeInformation,publicationAndOwnership,common:dataSetVersion}'
    from public.processes
    where id = 'a8000000-0000-0000-0000-000000000101'
      and version = '01.00.001'
  ),
  '01.00.001',
  'allocated lifecycle bundle child process JSON version is persisted'
);

select * from finish();

rollback;
