begin;
create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public;
select plan(22);

-- Publication derivatives are outside these transaction assertions.
alter table public.processes disable trigger process_extract_md_trigger_insert;
alter table public.processes disable trigger process_extract_md_trigger_update;
alter table public.lifecyclemodels disable trigger lifecyclemodel_extract_md_trigger_insert;
alter table public.lifecyclemodels disable trigger lifecyclemodel_extract_md_trigger_update;

insert into auth.users (id,aud,role,email,raw_app_meta_data,raw_user_meta_data)
values ('b9760000-0000-4000-8000-000000000001','authenticated','authenticated','model-976@example.test','{}','{}');
select set_config('request.jwt.claim.sub','b9760000-0000-4000-8000-000000000001',true);

create temporary table bundle_fixture as
select $request$
{
  "protocol": "model-bundle.v1",
  "action": "save",
  "modelId": "b9760000-0000-4000-8000-000000000002",
  "version": "01.00.000",
  "operationId": "b9760000-0000-4000-8000-000000000003",
  "expectedRevision": null,
  "plan": {
    "mode": "create",
    "modelId": "b9760000-0000-4000-8000-000000000002",
    "version": "01.00.000",
    "parent": {
      "jsonOrdered": {
        "lifeCycleModelDataSet": {
          "lifeCycleModelInformation": {
            "dataSetInformation": {
              "common:UUID": "b9760000-0000-4000-8000-000000000002",
              "referenceToResultingProcess": [{
                "@refObjectId": "b9760000-0000-4000-8000-000000000004",
                "@version": "02.00.000"
              }]
            }
          },
          "administrativeInformation": {
            "publicationAndOwnership": {
              "common:dataSetVersion": "01.00.000"
            }
          }
        }
      },
      "jsonTg": {
        "submodels": [
          {
            "id": "b9760000-0000-4000-8000-000000000004",
            "version": "02.00.000",
            "type": "primary"
          }
        ]
      }
    },
    "processMutations": [
      {
        "op": "create",
        "id": "b9760000-0000-4000-8000-000000000004",
        "modelId": "b9760000-0000-4000-8000-000000000002",
        "jsonOrdered": {
          "processDataSet": {
            "processInformation": {
              "dataSetInformation": {
                "common:UUID": "b9760000-0000-4000-8000-000000000004"
              }
            },
            "administrativeInformation": {
              "publicationAndOwnership": {
                "common:dataSetVersion": "02.00.000"
              }
            }
          }
        }
      }
    ]
  }
}
$request$::jsonb as request;
grant select on bundle_fixture to authenticated;
set local role authenticated;

select is(
    (select api.cmd_lifecycle_model_bundle_save(request)->>'status' from bundle_fixture),
    'committed', 'creates the parent and its own-version primary together'
);
select is(
    (select api.cmd_lifecycle_model_bundle_save(request)->'members'->0->>'version' from bundle_fixture),
    '02.00.000', 'same operation replays its original receipt'
);
select throws_ok(
    $$ select api.cmd_lifecycle_model_bundle_save(jsonb_set(request,'{plan,parent,jsonTg,other}','true')) from bundle_fixture $$,
    'P0001','MODEL_OPERATION_CONFLICT','same operation id cannot bind changed input'
);
select is(
    (select api.cmd_lifecycle_model_bundle_save((request - 'plan' - 'expectedRevision') || '{"action":"recover"}')->>'status' from bundle_fixture),
    'committed', 'read-only recovery resolves the original operation'
);

reset role;
create temporary table update_fixture as
select jsonb_set(
    request || jsonb_build_object(
        'operationId','b9760000-0000-4000-8000-000000000005',
        'expectedRevision',api.cmd_lifecycle_model_bundle_save((request - 'plan' - 'expectedRevision' - 'operationId')
            || '{"action":"inspect"}') #>> '{snapshot,revision}'
    ), '{plan,mode}', '"update"'
) #- '{plan,processMutations,0}' as request from bundle_fixture;
grant select on update_fixture to authenticated;
update public.lifecyclemodels set json_tg = json_tg::jsonb || '{"layout":"other-editor"}'
where id = 'b9760000-0000-4000-8000-000000000002' and version = '01.00.000';

set local role authenticated;
select throws_ok(
    $$ select api.cmd_lifecycle_model_bundle_save(request) from update_fixture $$,
    'P0001','MODEL_BUNDLE_CONFLICT','a graph-only change rejects a previously prepared update'
);
select is(
    (select api.cmd_lifecycle_model_bundle_save((request - 'plan' - 'expectedRevision') || '{"action":"recover"}')->>'status' from update_fixture),
    'unknown', 'a rolled back operation has no committed receipt'
);
reset role;
select is((
    select count(*) from private.model_bundle_save_receipts
    where actor_id = 'b9760000-0000-4000-8000-000000000001'
), 1::bigint, 'only one receipt committed for the fixture actor');
select is((select count(*) from public.processes where model_id='b9760000-0000-4000-8000-000000000002'), 1::bigint, 'there are no duplicate members');
select is((select json_tg::jsonb->>'layout' from public.lifecyclemodels where id='b9760000-0000-4000-8000-000000000002'),
    'other-editor', 'the newer graph survives');
select set_config('request.jwt.claim.sub','b9760000-0000-4000-8000-000000000006',true);
set local role authenticated;
select is(
    (select api.cmd_lifecycle_model_bundle_save((request - 'plan' - 'expectedRevision') || '{"action":"recover"}')->>'status' from bundle_fixture),
    'unknown', 'another actor cannot distinguish a real receipt from an absent one'
);

reset role;
select set_config('request.jwt.claim.sub','b9760000-0000-4000-8000-000000000001',true);
create temporary table multi_result_fixture as
with base as (
  select request, api.cmd_lifecycle_model_bundle_save(
    (request - 'plan' - 'expectedRevision' - 'operationId') || '{"action":"inspect"}'
  ) #>> '{snapshot,revision}' as revision
  from bundle_fixture
), candidate as (
  select request || jsonb_build_object(
    'operationId','b9760000-0000-4000-8000-000000000007',
    'expectedRevision',revision
  ) as request from base
), members as (
  select jsonb_set(
    jsonb_set(
      jsonb_set(request,'{plan,mode}','"update"'),
      '{plan,parent,jsonTg,submodels,1}',
      '{"id":"b9760000-0000-4000-8000-000000000008","version":"03.00.000","type":"secondary"}'
    ),
    '{plan,parent,jsonOrdered,lifeCycleModelDataSet,lifeCycleModelInformation,dataSetInformation,referenceToResultingProcess,1}',
    '{"@refObjectId":"b9760000-0000-4000-8000-000000000008","@version":"03.00.000"}'
  ) as request from candidate
)
select jsonb_set(request,'{plan,processMutations}',jsonb_build_array(
  (request #> '{plan,processMutations,0}') || jsonb_build_object(
    'id','b9760000-0000-4000-8000-000000000008',
    'jsonOrdered','{"processDataSet":{"processInformation":{"dataSetInformation":{"common:UUID":"b9760000-0000-4000-8000-000000000008"}},"administrativeInformation":{"publicationAndOwnership":{"common:dataSetVersion":"03.00.000"}}}}'::jsonb
  )
)) as request from members;
grant select on multi_result_fixture to authenticated;
set local role authenticated;
select throws_ok(
  $$ select api.cmd_lifecycle_model_bundle_save(jsonb_set(
    request,
    '{plan,parent,jsonOrdered,lifeCycleModelDataSet,lifeCycleModelInformation,dataSetInformation,referenceToResultingProcess,1,@version}',
    '"04.00.000"'
  )) from multi_result_fixture $$,
  'P0001','MODEL_MEMBERSHIP_INVALID','an incorrect canonical secondary reference rolls back its insert'
);
select is(
  (select jsonb_array_length(api.cmd_lifecycle_model_bundle_save(request)->'members') from multi_result_fixture),
  2, 'both correctly linked canonical products commit after the failed attempt'
);

-- Start a new revision from the legacy two-result Model. Use the existing
-- allocation path so all checks see the authoritative rewritten versions.
reset role;
create temporary table single_primary_fixture as
select jsonb_set(request->'plan', '{parent,jsonTg,resultPolicy}', '"single-primary-v1"') ||
    jsonb_build_object('allocateVersion', true, 'sourceVersion', '01.00.000',
                       'actorUserId', 'b9760000-0000-4000-8000-000000000001') as plan
from bundle_fixture;
select is((select private.save_lifecycle_model_bundle(plan)->>'version' from single_primary_fixture),
    '01.00.001', 'version allocation creates one exact primary');
select is((select jsonb_array_length(json_tg::jsonb->'submodels') from public.lifecyclemodels
    where id='b9760000-0000-4000-8000-000000000002' and version='01.00.000'),
    2, 'the legacy source retains both members');
create temporary table single_update as
select jsonb_build_object('mode','update','modelId',id,'version',version,'actorUserId',user_id,
    'parent',jsonb_build_object('jsonOrdered',json_ordered,'jsonTg',json_tg),
    'processMutations','[]'::jsonb) as plan
from public.lifecyclemodels where id='b9760000-0000-4000-8000-000000000002' and version='01.00.001';
select is((select private.save_lifecycle_model_bundle(plan)->>'version' from single_update),
    '01.00.001', 'layout-only updates reuse the existing exact group');
select throws_ok($$ select private.save_lifecycle_model_bundle(plan #- '{parent,jsonTg,resultPolicy}') from single_update $$,
    'P0001','INVALID_PLAN','an older writer cannot downgrade a marked version');
select throws_ok($$ select private.save_lifecycle_model_bundle(jsonb_set(plan,
    '{parent,jsonOrdered,lifeCycleModelDataSet,lifeCycleModelInformation,dataSetInformation,referenceToResultingProcess,0,@version}',
    '"01.00.000"')) from single_update $$, 'P0001','INVALID_PLAN','a different result revision is rejected');
select throws_ok($$ select private.save_lifecycle_model_bundle(jsonb_set(plan,
    '{parent,jsonTg,submodels,0,finalId}', '{"allocatedExchangeFlowId":"different-product","allocatedExchangeDirection":"Output"}'))
    from single_update $$, 'P0001','INVALID_PLAN','changing the primary product requires a new Model version');
select is((select count(*) from public.processes where model_id='b9760000-0000-4000-8000-000000000002'
    and model_version='01.00.001'), 1::bigint, 'rejected writes leave exactly the primary');

-- Use the exact stored primary and add one graph-owned allocated dependency.
create temporary table allocated_update as
with extra as (
    select request #> '{plan,processMutations,0}' as mutation from multi_result_fixture
), identity as (
    select mutation, mutation->>'id' as id
    from extra
)
select jsonb_set(jsonb_set(jsonb_set(plan, '{processMutations}', jsonb_build_array(
    jsonb_set(mutation, '{jsonOrdered,processDataSet,administrativeInformation,publicationAndOwnership,common:dataSetVersion}', '"01.00.001"')
)), '{parent,jsonTg,submodels,1}', jsonb_build_object('id', id, 'version', '01.00.001', 'type', 'allocated')),
    '{parent,jsonOrdered,lifeCycleModelDataSet,lifeCycleModelInformation,technology}', jsonb_build_object(
       'processes',jsonb_build_object('processInstance',jsonb_build_object(
           'referenceToProcess', jsonb_build_object('@refObjectId',id,'@version','01.00.001')))
    )) as plan
from single_update, identity;
select throws_ok($$ select private.save_lifecycle_model_bundle(jsonb_set(plan,
    '{parent,jsonOrdered,lifeCycleModelDataSet,lifeCycleModelInformation,technology,processes,processInstance,referenceToProcess,@version}',
    '"03.00.000"')) from allocated_update $$, 'P0001','INVALID_PLAN','a historical revision cannot justify an allocated member');
select is((select private.save_lifecycle_model_bundle(plan)->>'version' from allocated_update),
    '01.00.001','a retry can add a graph dependency with an exact Process reference');
select is((select jsonb_array_length(json_ordered::jsonb #> '{lifeCycleModelDataSet,lifeCycleModelInformation,dataSetInformation,referenceToResultingProcess}')
    from public.lifecyclemodels where id='b9760000-0000-4000-8000-000000000002' and version='01.00.001'),
    1,'adding the allocated Process preserves the single external result');

select * from finish();
rollback;
