-- Database #880. Rollback-only synthetic fixtures through authenticated bundle APIs.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, api, private, auth;
select no_plan();

-- Keep all database guards active. Only outbound extraction is contained locally.
create or replace function util.invoke_edge_function(
  name text, body jsonb, timeout_milliseconds integer default 300000
) returns void language plpgsql security definer set search_path = '' as $$
begin
  return;
end;
$$;

create function pg_temp.bundle_document(p_kind text, p_version text, p_marker text default 'before')
returns jsonb language sql immutable as $$
  select jsonb_build_object(p_kind, jsonb_build_object(
    'administrativeInformation', jsonb_build_object('publicationAndOwnership',
      jsonb_build_object('common:dataSetVersion', p_version)),
    'bundleMarker', p_marker
  ))
$$;
create function pg_temp.bundle_mutation(p_op text, p_id text, p_version text)
returns jsonb language sql immutable as $$
  select jsonb_build_object('op', p_op, 'id', p_id, 'version', p_version,
    'jsonOrdered', pg_temp.bundle_document('processDataSet', p_version, 'after'))
$$;
create function pg_temp.bundle_plan(p_mutations jsonb, p_id text default '88000000-0000-4000-8000-000000000010')
returns jsonb language sql immutable as $$
  select jsonb_build_object('mode', 'update', 'modelId', p_id, 'version', '01.00.000',
    -- Deliberately forged. The facade must replace it with the authenticated owner.
    'actorUserId', '88000000-0000-4000-8000-000000000002',
    'parent', jsonb_build_object('jsonOrdered',
      pg_temp.bundle_document('lifeCycleModelDataSet', '01.00.000', 'after')),
    'processMutations', p_mutations)
$$;

-- Even an unexpected success must roll back its DML so every negative case
-- starts from the same preimages. Existing command errors propagate unchanged.
create function pg_temp.bundle_reject_save(p_plan jsonb)
returns void language plpgsql as $$
begin
  perform api.cmd_lifecycle_model_bundle_save(p_plan);
  raise exception 'TEST_COMMAND_UNEXPECTED_SUCCESS';
end;
$$;
create function pg_temp.bundle_reject_delete(p_id uuid, p_version text)
returns void language plpgsql as $$
begin
  perform api.cmd_lifecycle_model_bundle_delete(p_id, p_version);
  raise exception 'TEST_COMMAND_UNEXPECTED_SUCCESS';
end;
$$;

grant execute on function
  pg_temp.bundle_document(text, text, text),
  pg_temp.bundle_mutation(text, text, text),
  pg_temp.bundle_plan(jsonb, text),
  pg_temp.bundle_reject_save(jsonb),
  pg_temp.bundle_reject_delete(uuid, text)
to authenticated;

insert into auth.users(id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  is_sso_user, is_anonymous)
select id::uuid, '00000000-0000-0000-0000-000000000000', 'authenticated',
  'authenticated', email, 'x', now(), '{}', '{}', now(), now(), false, false
from (values
  ('88000000-0000-4000-8000-000000000001', 'bundle-owner@example.invalid'),
  ('88000000-0000-4000-8000-000000000002', 'bundle-other@example.invalid'),
  ('88000000-0000-4000-8000-000000000003', 'bundle-team-review-admin@example.invalid')
) u(id,email);
insert into private.users(id, raw_user_meta_data)
values ('88000000-0000-4000-8000-000000000001', '{}'),
       ('88000000-0000-4000-8000-000000000002', '{}'),
       ('88000000-0000-4000-8000-000000000003', '{}')
on conflict (id) do nothing;
insert into private.teams(id, json, rank, is_public)
values ('00000000-0000-0000-0000-000000000000', '{"name":"System"}', 0, false)
on conflict (id) do nothing;
insert into private.roles(user_id, team_id, role)
values ('88000000-0000-4000-8000-000000000002',
  '00000000-0000-0000-0000-000000000000', 'review-admin');
insert into private.teams(id, json, rank, is_public)
values ('88000000-0000-4000-8000-000000000090', '{"name":"Bundle synthetic team"}', 0, false);
insert into private.roles(user_id, team_id, role)
values ('88000000-0000-4000-8000-000000000003',
  '88000000-0000-4000-8000-000000000090', 'review-admin');

insert into public.lifecyclemodels(id, version, state_code, user_id, json_ordered, json_tg)
select id::uuid, '01.00.000', state_code, owner::uuid,
  pg_temp.bundle_document('lifeCycleModelDataSet', '01.00.000')::json,
  '{"submodels":"stale frontend content"}'
from (values
  ('88000000-0000-4000-8000-000000000010', 0, '88000000-0000-4000-8000-000000000001'),
  ('88000000-0000-4000-8000-000000000011', 20, '88000000-0000-4000-8000-000000000001'),
  ('88000000-0000-4000-8000-000000000012', 100, '88000000-0000-4000-8000-000000000001'),
  ('88000000-0000-4000-8000-000000000013', -1, '88000000-0000-4000-8000-000000000001'),
  ('88000000-0000-4000-8000-000000000014', 0, '88000000-0000-4000-8000-000000000002'),
  ('88000000-0000-4000-8000-000000000015', 0, '88000000-0000-4000-8000-000000000001'),
  ('88000000-0000-4000-8000-000000000016', 0, '88000000-0000-4000-8000-000000000001'),
  ('88000000-0000-4000-8000-000000000017', 0, '88000000-0000-4000-8000-000000000001'),
  ('88000000-0000-4000-8000-000000000019', 0, '88000000-0000-4000-8000-000000000001')
) m(id,state_code,owner);

insert into public.processes(id, version, state_code, user_id, model_id, model_version, json_ordered)
select id::uuid, version, state_code, owner::uuid,
  '88000000-0000-4000-8000-000000000010', model_version,
  pg_temp.bundle_document('processDataSet', version)::json
from (values
  -- Current same-UUID cross-version result plus historical published sibling.
  ('88000000-0000-4000-8000-000000000010', '01.00.000', 100, '88000000-0000-4000-8000-000000000001', '01.00.000'),
  ('88000000-0000-4000-8000-000000000010', '02.00.000', 0, '88000000-0000-4000-8000-000000000001', '01.00.000'),
  ('88000000-0000-4000-8000-000000000021', '01.00.000', 20, '88000000-0000-4000-8000-000000000001', '01.00.000'),
  ('88000000-0000-4000-8000-000000000022', '01.00.000', 200, '88000000-0000-4000-8000-000000000001', '01.00.000'),
  ('88000000-0000-4000-8000-000000000023', '01.00.000', 0, '88000000-0000-4000-8000-000000000002', '01.00.000'),
  ('88000000-0000-4000-8000-000000000024', '01.00.000', 0, '88000000-0000-4000-8000-000000000001', '03.00.000'),
  ('88000000-0000-4000-8000-000000000025', '01.00.000', 0, '88000000-0000-4000-8000-000000000001', null::text),
  ('88000000-0000-4000-8000-000000000026', '01.00.000', 0, '88000000-0000-4000-8000-000000000001', '01.00.000')
) p(id,version,state_code,owner,model_version);
update public.processes set model_id = '88000000-0000-4000-8000-000000000011'
where id = '88000000-0000-4000-8000-000000000026';
-- A valid isolated bundle exercises full deletion, legacy and multiple result rows.
insert into public.processes(id, version, state_code, user_id, model_id, model_version, json_ordered)
select id::uuid, version, 0, '88000000-0000-4000-8000-000000000001',
  '88000000-0000-4000-8000-000000000015', model_version,
  pg_temp.bundle_document('processDataSet', version)::json
from (values
  ('88000000-0000-4000-8000-000000000031', '02.00.000', '01.00.000'),
  ('88000000-0000-4000-8000-000000000032', '01.00.000', null::text),
  ('88000000-0000-4000-8000-000000000033', '03.00.000', '03.00.000')
) p(id,version,model_version);

insert into public.processes(id, version, state_code, user_id, model_id, model_version, json_ordered)
values
  ('88000000-0000-4000-8000-000000000034', '01.00.000', 0,
   '88000000-0000-4000-8000-000000000001', '88000000-0000-4000-8000-000000000016',
   '01.00.000', pg_temp.bundle_document('processDataSet', '01.00.000')::json),
  ('88000000-0000-4000-8000-000000000035', '01.00.000', 0,
   '88000000-0000-4000-8000-000000000002', '88000000-0000-4000-8000-000000000017',
   '01.00.000', pg_temp.bundle_document('processDataSet', '01.00.000')::json);
-- Isolate whole-delete state enforcement from child-owner enforcement.
insert into public.processes(id, version, state_code, user_id, model_id, model_version, json_ordered)
values ('88000000-0000-4000-8000-000000000036', '02.00.000', 100,
  '88000000-0000-4000-8000-000000000001', '88000000-0000-4000-8000-000000000019',
  '01.00.000', pg_temp.bundle_document('processDataSet', '02.00.000')::json);

-- Legacy same-document rows can have a column version different from their JSON
-- after a service-side key update. An unchanged document does not resynchronize it.
insert into public.lifecyclemodels(id, version, state_code, user_id, json_ordered)
values ('88000000-0000-4000-8000-000000000018', '09.00.000', 0,
  '88000000-0000-4000-8000-000000000001',
  pg_temp.bundle_document('lifeCycleModelDataSet', '09.00.000')::json);
update public.lifecyclemodels set version = '01.00.000'
where id = '88000000-0000-4000-8000-000000000018';
insert into public.processes(id, version, state_code, user_id, model_id, model_version, json_ordered)
values ('88000000-0000-4000-8000-000000000028', '09.00.000', 0,
  '88000000-0000-4000-8000-000000000001', '88000000-0000-4000-8000-000000000018',
  '01.00.000', pg_temp.bundle_document('processDataSet', '09.00.000')::json);
update public.processes set version = '01.00.000'
where id = '88000000-0000-4000-8000-000000000028';

create temporary table bundle_before on commit drop as
select 'processes'::text as dataset_table, id, version,
  to_jsonb(p) as row_value, json_ordered::text as ordered_value
from public.processes p where p.id::text like '88000000-%'
union all
select 'lifecyclemodels', id, version, to_jsonb(m), json_ordered::text
from public.lifecyclemodels m where m.id::text like '88000000-%';

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '88000000-0000-4000-8000-000000000001', true);

-- Invalid existing targets must fail even after a valid operation in the same group.
-- The first child DELETE proves rollback includes destructive work.
select throws_ok(format('select pg_temp.bundle_reject_save(%L::jsonb)',
  pg_temp.bundle_plan(jsonb_build_array(
    pg_temp.bundle_mutation('delete', '88000000-0000-4000-8000-000000000025', '01.00.000'),
    jsonb_set(pg_temp.bundle_mutation(op, id, version), '{jsonOrdered}',
      pg_temp.bundle_document('processDataSet', version))
  ))), 'P0001', 'PROCESS_NOT_FOUND',
  op || ' rejects ' || label || ' and rolls back earlier child deletion')
from (values
  ('88000000-0000-4000-8000-000000000010', '01.00.000', 'published child'),
  ('88000000-0000-4000-8000-000000000021', '01.00.000', 'pending child'),
  ('88000000-0000-4000-8000-000000000022', '01.00.000', 'reserved-state child'),
  ('88000000-0000-4000-8000-000000000023', '01.00.000', 'foreign child'),
  ('88000000-0000-4000-8000-000000000024', '01.00.000', 'wrong Model version'),
  ('88000000-0000-4000-8000-000000000026', '01.00.000', 'wrong Model identity'),
  ('88000000-0000-4000-8000-000000000025', '09.00.000', 'stale exact version')
) target(id,version,label)
cross join (values ('update'), ('delete')) operation(op);

select throws_ok(format('select pg_temp.bundle_reject_save(%L::jsonb)',
  pg_temp.bundle_plan(jsonb_build_array(
    pg_temp.bundle_mutation('create', '88000000-0000-4000-8000-000000000099', '04.00.000'),
    pg_temp.bundle_mutation('update', '88000000-0000-4000-8000-000000000023', '01.00.000')
  ))), 'P0001', 'PROCESS_NOT_FOUND', 'foreign child rejects and rolls back earlier child creation');

select throws_ok(format('select pg_temp.bundle_reject_save(%L::jsonb)',
  pg_temp.bundle_plan('[]', id)), 'P0001', 'MODEL_NOT_FOUND', label)
from (values
  ('88000000-0000-4000-8000-000000000011', 'pending Model cannot save'),
  ('88000000-0000-4000-8000-000000000012', 'published Model cannot save'),
  ('88000000-0000-4000-8000-000000000013', 'example Model cannot save'),
  ('88000000-0000-4000-8000-000000000014', 'foreign Model cannot save')
) target(id,label);

select throws_ok(format('select pg_temp.bundle_reject_save(%L::jsonb)',
  pg_temp.bundle_plan(jsonb_build_array(pg_temp.bundle_mutation(
    'remove', '88000000-0000-4000-8000-000000000025', '01.00.000')))),
  'P0001', 'INVALID_PLAN', 'unsupported remove operation fails atomically');
select throws_ok(format('select pg_temp.bundle_reject_save(%L::jsonb)',
  pg_temp.bundle_plan(jsonb_build_array(jsonb_set(pg_temp.bundle_mutation(
    'update', '88000000-0000-4000-8000-000000000010', '02.00.000'),
    '{jsonOrdered}', pg_temp.bundle_document('processDataSet', '03.00.000'))))),
  'P0001', 'INVALID_PLAN', 'child JSON cannot move the exact requested version');

select throws_ok(format('select pg_temp.bundle_reject_save(%L::jsonb)',
  jsonb_set(pg_temp.bundle_plan('[]'), '{parent,jsonOrdered}',
    pg_temp.bundle_document('lifeCycleModelDataSet', '03.00.000'))),
  'P0001', 'INVALID_PLAN', 'parent JSON cannot move the exact requested Model version');

select throws_ok($$select pg_temp.bundle_reject_delete(
  '88000000-0000-4000-8000-000000000019', '01.00.000')$$,
  'P0001', 'PROCESS_NOT_FOUND',
  'owner cannot delete a draft Model whose only child is same-owner and published');

select throws_ok($$select pg_temp.bundle_reject_delete(
  '88000000-0000-4000-8000-000000000010', '01.00.000')$$,
  'P0001', 'PROCESS_NOT_FOUND', 'whole bundle deletion rejects immutable or foreign members');
select throws_ok(format('select pg_temp.bundle_reject_delete(%L::uuid, %L)',
  id, '01.00.000'), 'P0001', 'MODEL_NOT_FOUND', label)
from (values
  ('88000000-0000-4000-8000-000000000011', 'pending Model cannot be deleted'),
  ('88000000-0000-4000-8000-000000000012', 'published Model cannot be deleted'),
  ('88000000-0000-4000-8000-000000000013', 'example Model cannot be deleted')
) target(id,label);
select throws_ok($$select pg_temp.bundle_reject_delete(
  '88000000-0000-4000-8000-000000000014', '01.00.000')$$,
  '42501', 'FORBIDDEN', 'foreign Model deletion retains the facade authorization');
select set_config('request.jwt.claim.sub', '88000000-0000-4000-8000-000000000002', true);
select throws_ok($$select pg_temp.bundle_reject_delete(
  '88000000-0000-4000-8000-000000000019', '01.00.000')$$,
  'P0001', 'PROCESS_NOT_FOUND',
  'review-admin cannot delete the isolated same-owner published child bundle');
select throws_ok($$select pg_temp.bundle_reject_delete(
  '88000000-0000-4000-8000-000000000017', '01.00.000')$$,
  'P0001', 'PROCESS_NOT_FOUND', 'review-admin cannot delete a draft bundle with a foreign child');
reset role;

select is((select count(*) from public.processes
  where id = '88000000-0000-4000-8000-000000000099'), 0::bigint,
  'rejected group committed no newly created child');
select is((select count(*) from bundle_before b
  join (select 'processes'::text as dataset_table, id, version, to_jsonb(p) as row_value,
          json_ordered::text as ordered_value from public.processes p
        union all select 'lifecyclemodels', id, version, to_jsonb(m), json_ordered::text
          from public.lifecyclemodels m) c using(dataset_table,id,version)
  where b.row_value = c.row_value and b.ordered_value = c.ordered_value),
  (select count(*) from bundle_before),
  'every rejected command preserves all preimages including timestamp and ordered bytes');

set local role authenticated;
-- Edge delegates parent-only saves through the service review-admin predicate,
-- which admits review-admin membership independently of its team.
select set_config('request.jwt.claim.sub', '88000000-0000-4000-8000-000000000002', true);
select lives_ok(format('select api.cmd_lifecycle_model_bundle_save(%L::jsonb)',
  pg_temp.bundle_plan('[]')),
  'system review-admin retains another owner parent-only draft save');
select throws_ok(format('select pg_temp.bundle_reject_save(%L::jsonb)',
  pg_temp.bundle_plan(jsonb_build_array(pg_temp.bundle_mutation(op,
    case when op = 'create' then '88000000-0000-4000-8000-000000000098'
      else '88000000-0000-4000-8000-000000000023' end,
    case when op = 'create' then '04.00.000' else '01.00.000' end)))),
  'P0001', 'MODEL_NOT_FOUND',
  'system review-admin parent delegation rejects nonempty ' || op || ' child plan')
from (values ('create'), ('update'), ('delete')) operation(op);
select set_config('request.jwt.claim.sub', '88000000-0000-4000-8000-000000000003', true);
select lives_ok(format('select api.cmd_lifecycle_model_bundle_save(%L::jsonb)',
  pg_temp.bundle_plan('[]')),
  'non-system review-admin retains Edge-authorized parent-only draft save');
select throws_ok(format('select pg_temp.bundle_reject_save(%L::jsonb)',
  pg_temp.bundle_plan(jsonb_build_array(pg_temp.bundle_mutation(op,
    case when op = 'create' then '88000000-0000-4000-8000-000000000098'
      else '88000000-0000-4000-8000-000000000023' end,
    case when op = 'create' then '04.00.000' else '01.00.000' end)))),
  'P0001', 'MODEL_NOT_FOUND',
  'delegated parent-only authority rejects nonempty ' || op || ' child plan')
from (values ('create'), ('update'), ('delete')) operation(op);
select throws_ok(format('select pg_temp.bundle_reject_save(%L::jsonb)',
  pg_temp.bundle_plan('[]', id)), 'P0001', 'MODEL_NOT_FOUND', label)
from (values
  ('88000000-0000-4000-8000-000000000011', 'review-admin parent-only save rejects pending state'),
  ('88000000-0000-4000-8000-000000000012', 'review-admin parent-only save rejects published state'),
  ('88000000-0000-4000-8000-000000000013', 'review-admin parent-only save rejects read-only example state')
) target(id,label);
select throws_ok($$select pg_temp.bundle_reject_delete(
  '88000000-0000-4000-8000-000000000019', '01.00.000')$$,
  '42501', 'FORBIDDEN', 'non-system parent-save delegation does not expand whole-delete authority');
reset role;
select ok((select user_id = '88000000-0000-4000-8000-000000000001'::uuid
    and state_code = 0
    and json_ordered::jsonb #>> '{lifeCycleModelDataSet,bundleMarker}' = 'after'
  from public.lifecyclemodels where id = '88000000-0000-4000-8000-000000000010'
    and version = '01.00.000'),
  'delegated parent saves preserve the existing owner, state and exact Model key');
select is((select count(*) from public.processes
  where id = '88000000-0000-4000-8000-000000000098'), 0::bigint,
  'delegated parent authority cannot attach a newly created actor child');
select ok(not exists(select 1 from public.processes p join bundle_before b
  on b.dataset_table = 'processes' and b.id = p.id and b.version = p.version
  where p.id::text like '88000000-%'
    and (to_jsonb(p) is distinct from b.row_value or p.json_ordered::text is distinct from b.ordered_value)),
  'parent delegation and rejected child plans leave all existing child preimages unchanged');

set local role authenticated;
select set_config('request.jwt.claim.sub', '88000000-0000-4000-8000-000000000001', true);
select lives_ok(format('select api.cmd_lifecycle_model_bundle_save(%L::jsonb)',
  jsonb_set(pg_temp.bundle_plan(jsonb_build_array(jsonb_set(
    pg_temp.bundle_mutation('update', '88000000-0000-4000-8000-000000000028', '01.00.000'),
    '{jsonOrdered}', pg_temp.bundle_document('processDataSet', '09.00.000'))),
    '88000000-0000-4000-8000-000000000018'), '{parent,jsonOrdered}',
    pg_temp.bundle_document('lifeCycleModelDataSet', '09.00.000'))),
  'same-document legacy parent and child keep their exact column keys');
select lives_ok(format('select api.cmd_lifecycle_model_bundle_save(%L::jsonb)',
  pg_temp.bundle_plan(jsonb_build_array(
    pg_temp.bundle_mutation('update', '88000000-0000-4000-8000-000000000010', '02.00.000'),
    pg_temp.bundle_mutation('update', '88000000-0000-4000-8000-000000000025', '01.00.000')
  ))), 'owner can update current cross-version result and legacy result together');
reset role;
select is((select json_ordered::jsonb #>> '{processDataSet,bundleMarker}'
  from public.processes where id = '88000000-0000-4000-8000-000000000010'
    and version = '02.00.000'), 'after', 'exact current child content was saved');
select ok((select to_jsonb(p) = b.row_value and p.json_ordered::text = b.ordered_value
  from public.processes p join bundle_before b on b.dataset_table = 'processes'
    and b.id = p.id and b.version = p.version
  where p.id = '88000000-0000-4000-8000-000000000010' and p.version = '01.00.000'),
  'successful current-child save preserves its historical published sibling exactly');

set local role authenticated;
select lives_ok(format('select api.cmd_lifecycle_model_bundle_save(%L::jsonb)',
  pg_temp.bundle_plan(jsonb_build_array(
    pg_temp.bundle_mutation('delete', '88000000-0000-4000-8000-000000000010', '02.00.000'),
    pg_temp.bundle_mutation('delete', '88000000-0000-4000-8000-000000000025', '01.00.000')
  ))), 'owner can remove exact cross-version and legacy draft children together');
select lives_ok($$select api.cmd_lifecycle_model_bundle_delete(
  '88000000-0000-4000-8000-000000000015', '01.00.000')$$,
  'whole draft bundle deletion uses relational members with stale frontend JSON');
select set_config('request.jwt.claim.sub', '88000000-0000-4000-8000-000000000002', true);
select lives_ok($$select api.cmd_lifecycle_model_bundle_delete(
  '88000000-0000-4000-8000-000000000016', '01.00.000')$$,
  'review-admin retains delegated deletion of another owner draft bundle');
reset role;
select is((select count(*) from public.processes where
  (id = '88000000-0000-4000-8000-000000000010' and version = '02.00.000')
  or (id = '88000000-0000-4000-8000-000000000025' and version = '01.00.000')),
  0::bigint, 'exact delete mutations removed both requested draft keys');
select is((select count(*) from public.processes where id in (
  '88000000-0000-4000-8000-000000000031', '88000000-0000-4000-8000-000000000032')),
  0::bigint, 'whole deletion removed cross-version and legacy members');
select is((select count(*) from public.processes
  where id = '88000000-0000-4000-8000-000000000033'), 1::bigint,
  'whole deletion preserved the other Model-version member');
select is((select count(*) from public.lifecyclemodels
  where id = '88000000-0000-4000-8000-000000000015'), 0::bigint,
  'whole deletion removed its exact draft Model');

select ok(has_function_privilege('authenticated', 'api.cmd_lifecycle_model_bundle_save(jsonb)', 'execute')
  and has_function_privilege('authenticated', 'api.cmd_lifecycle_model_bundle_delete(uuid,text)', 'execute')
  and not has_function_privilege('anon', 'api.cmd_lifecycle_model_bundle_save(jsonb)', 'execute')
  and not has_function_privilege('service_role', 'api.cmd_lifecycle_model_bundle_save(jsonb)', 'execute'),
  'bundle command ACLs retain their existing actor-only contract');
select * from finish();
rollback;
