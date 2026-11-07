begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, auth;

select plan(10);

alter table public.lifecyclemodels disable trigger user;
alter table public.processes disable trigger user;

insert into public.lifecyclemodels (
  id,
  version,
  json,
  json_ordered,
  json_tg,
  user_id,
  state_code,
  rule_verification,
  reviews
)
values (
  '96800000-0000-0000-0000-000000000001',
  '01.00.000',
  '{
    "lifeCycleModelDataSet": {
      "lifeCycleModelInformation": {
        "dataSetInformation": {"referenceToResultingProcess": {"@type":"process data set","@refObjectId":"96800000-0000-0000-0000-000000000004","@version":"01.00.000"}},
        "technology": {
          "processes": {
            "processInstance": [{
              "referenceToProcess": {
                "@type": "process data set",
                "@refObjectId": "96800000-0000-0000-0000-000000000002",
                "@version": "01.00.000"
              }
            }]
          }
        }
      }
    }
  }'::jsonb,
  '{
    "lifeCycleModelDataSet": {
      "lifeCycleModelInformation": {
        "dataSetInformation": {"referenceToResultingProcess": {"@type":"process data set","@refObjectId":"96800000-0000-0000-0000-000000000004","@version":"01.00.000"}},
        "technology": {
          "processes": {
            "processInstance": [{
              "referenceToProcess": {
                "@type": "process data set",
                "@refObjectId": "96800000-0000-0000-0000-000000000002",
                "@version": "01.00.000"
              }
            }]
          }
        }
      }
    }
  }'::json,
  '{"submodels":"malformed stale frontend state","selected":"96800000-0000-0000-0000-000000000003"}'::jsonb,
  '96800000-0000-0000-0000-0000000000aa',
  0,
  true,
  '[]'::jsonb
);

insert into public.processes (
  id,
  version,
  json,
  json_ordered,
  user_id,
  state_code,
  model_id,
  rule_verification,
  reviews
)
values
  (
    '96800000-0000-0000-0000-000000000002',
    '01.00.000',
    '{}'::jsonb,
    '{}'::json,
    '96800000-0000-0000-0000-0000000000aa',
    0,
    null,
    true,
    '[]'::jsonb
  ),
  (
    '96800000-0000-0000-0000-000000000003',
    '01.00.000',
    '{}'::jsonb,
    '{}'::json,
    '96800000-0000-0000-0000-0000000000aa',
    0,
    null,
    true,
    '[]'::jsonb
  ),
  (
    '96800000-0000-0000-0000-000000000004',
    '01.00.000',
    '{}'::jsonb,
    '{}'::json,
    '96800000-0000-0000-0000-0000000000aa',
    0,
    '96800000-0000-0000-0000-000000000001',
    true,
    '[]'::jsonb
  ),
  (
    '96800000-0000-0000-0000-000000000005',
    '02.00.000',
    '{}'::jsonb,
    '{}'::json,
    '96800000-0000-0000-0000-0000000000aa',
    0,
    '96800000-0000-0000-0000-000000000001',
    true,
    '[]'::jsonb
  );

select is(
  private.cmd_review_assert_lifecycle_closure(
    '[{"table":"lifecyclemodels","id":"96800000-0000-0000-0000-000000000001","version":"01.00.000"}]'::jsonb,
    'submit',
    '96800000-0000-0000-0000-0000000000aa'
  ),
  null::jsonb,
  'malformed stale json_tg does not block lifecycle review closure'
);

create temporary table issue471_targets on commit drop as
select *
from api.cmd_review_collect_dataset_targets(
  '[{"table":"lifecyclemodels","id":"96800000-0000-0000-0000-000000000001","version":"01.00.000","is_root":true}]'::jsonb,
  false
);

select is(
  (select count(*)::text from issue471_targets),
  '3',
  'review target closure contains only the model, ILCD source, and exact-version relational result'
);

select ok(
  exists (
    select 1 from issue471_targets
    where table_name = 'processes'
      and dataset_id = '96800000-0000-0000-0000-000000000002'
      and dataset_version = '01.00.000'
  ),
  'ILCD processInstance remains an authoritative source dependency'
);

select ok(
  exists (
    select 1 from issue471_targets
    where table_name = 'processes'
      and dataset_id = '96800000-0000-0000-0000-000000000004'
      and dataset_version = '01.00.000'
  ),
  'current standard result reference plus exact owner version identifies generated membership'
);

select ok(
  not exists (
    select 1 from issue471_targets
    where dataset_id = '96800000-0000-0000-0000-000000000003'
  ),
  'a process mentioned only by json_tg is excluded from review targets'
);

select ok(
  not exists (
    select 1 from issue471_targets
    where dataset_id = '96800000-0000-0000-0000-000000000005'
  ),
  'a different-version relational process is excluded from review targets'
);

insert into private.reviews (
  id,
  data_id,
  data_version,
  state_code,
  reviewer_id,
  json,
  review_kind,
  target_table,
  submitted_revision_checksum,
  target_owner_id
)
values (
  '96800000-0000-0000-0000-000000000010',
  '96800000-0000-0000-0000-000000000001',
  '01.00.000',
  0,
  '[]'::jsonb,
  '{"logs":[]}'::jsonb,
  'root',
  'lifecyclemodels',
  pg_catalog.repeat('a', 64),
  '96800000-0000-0000-0000-0000000000aa'
);

create temporary table issue471_current_targets on commit drop as
select *
from private.review_resolve_current_reference_targets_v1(
  array['96800000-0000-0000-0000-000000000010'::uuid]
);

select is(
  (select count(*)::text from issue471_current_targets),
  '2',
  'current Root Review relationships contain the ILCD source and exact-version relational result'
);

select ok(
  exists (
    select 1 from issue471_current_targets
    where target_table = 'processes'
      and data_id = '96800000-0000-0000-0000-000000000002'
  ),
  'current review relationship derivation includes the ILCD source'
);

select ok(
  exists (
    select 1 from issue471_current_targets
    where target_table = 'processes'
      and data_id = '96800000-0000-0000-0000-000000000004'
  ),
  'current review relationship derivation includes the relational model result'
);

select ok(
  not exists (
    select 1 from issue471_current_targets
    where data_id in (
      '96800000-0000-0000-0000-000000000003',
      '96800000-0000-0000-0000-000000000005'
    )
  ),
  'current review relationships ignore json_tg-only and different-version processes'
);

select * from finish();
rollback;
