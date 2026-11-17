begin;
create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public;
select plan(10);

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
select * from finish();
rollback;
