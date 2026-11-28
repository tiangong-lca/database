begin;
create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, auth;
select no_plan();

set local session_replication_role = replica;
insert into auth.users (id, aud, role, email, raw_app_meta_data, raw_user_meta_data)
values
  ('96000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated',
    'scope-owner@example.invalid', '{}', '{}'),
  ('96000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated',
    'scope-other@example.invalid', '{}', '{}');
insert into private.users (id, raw_user_meta_data)
values
  ('96000000-0000-4000-8000-000000000001', '{}'),
  ('96000000-0000-4000-8000-000000000002', '{}')
on conflict do nothing;

-- Isolated root process (no external draft refs) + approved published contact + draft/rejected dependency controls.
insert into public.contacts (id, version, json, json_ordered, user_id, state_code, rule_verification, modified_at)
values
  ('96000000-0000-4000-8000-000000000010', '01.00.000', '{}'::jsonb, '{}'::json,
    '96000000-0000-4000-8000-000000000001', 100, true, '2024-01-01'::timestamptz),
  ('96000000-0000-4000-8000-000000000011', '01.00.000', '{}'::jsonb, '{}'::json,
    '96000000-0000-4000-8000-000000000001', 0, true, '2024-01-01'::timestamptz);

insert into public.flows (id, version, json, json_ordered, user_id, state_code, rule_verification)
values
  ('96000000-0000-4000-8000-000000000020', '01.00.000', '{}'::jsonb, '{}'::json,
    '96000000-0000-4000-8000-000000000001', 0, true),
  ('96000000-0000-4000-8000-000000000021', '01.00.000', '{}'::jsonb, '{}'::json,
    '96000000-0000-4000-8000-000000000001', 0, true);

-- Root 1: Isolated process referencing only approved contact
insert into public.processes (id, version, json, json_ordered, user_id, state_code, rule_verification)
select
  '96000000-0000-4000-8000-000000000030',
  '01.00.000',
  p,
  p::json,
  '96000000-0000-4000-8000-000000000001',
  0,
  true
from (
  select jsonb_build_object(
    'processDataSet', jsonb_build_object(
      'administrativeInformation', jsonb_build_object(
        'common:commissionerAndGoal', jsonb_build_object(
          'common:referenceToCommissioner', jsonb_build_object(
            '@type', 'contact data set',
            '@refObjectId', '96000000-0000-4000-8000-000000000010',
            '@version', '01.00.000'
          )
        )
      )
    )
  ) as p
) s;

-- Root 2: Process referencing approved contact AND draft flow 20
insert into public.processes (id, version, json, json_ordered, user_id, state_code, rule_verification)
select
  '96000000-0000-4000-8000-000000000031',
  '01.00.000',
  p,
  p::json,
  '96000000-0000-4000-8000-000000000001',
  0,
  true
from (
  select jsonb_build_object(
    'processDataSet', jsonb_build_object(
      'administrativeInformation', jsonb_build_object(
        'common:commissionerAndGoal', jsonb_build_object(
          'common:referenceToCommissioner', jsonb_build_object(
            '@type', 'contact data set',
            '@refObjectId', '96000000-0000-4000-8000-000000000010',
            '@version', '01.00.000'
          )
        )
      ),
      'exchanges', jsonb_build_object(
        'exchange', jsonb_build_array(
          jsonb_build_object(
            'referenceToFlowDataSet', jsonb_build_object(
              '@type', 'flow data set',
              '@refObjectId', '96000000-0000-4000-8000-000000000020',
              '@version', '01.00.000'
            )
          )
        )
      )
    )
  ) as p
) s;

-- Root 3: Resubmission candidate (previously rejected root review)
insert into public.processes (id, version, json, json_ordered, user_id, state_code, rule_verification)
values ('96000000-0000-4000-8000-000000000032', '01.00.000', '{}'::jsonb, '{}'::json,
  '96000000-0000-4000-8000-000000000001', 0, true);
insert into private.reviews (id, data_id, data_version, state_code, reviewer_id, json, review_kind, target_table, submitted_revision_checksum, target_owner_id)
values ('96000000-0000-4000-8000-000000000040', '96000000-0000-4000-8000-000000000032', '01.00.000', -1, '[]'::jsonb, '{}'::jsonb, 'root', 'processes', repeat('a', 64), '96000000-0000-4000-8000-000000000001');

set local session_replication_role = origin;

-- 1. Preview for isolated root + approved contact (exercised as authenticated)
set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '96000000-0000-4000-8000-000000000001', true);
create temp table preview1 as
select api.qry_review_submit_scope('processes', '96000000-0000-4000-8000-000000000030', '01.00.000') as res;
select ok((select (res->>'ok')::boolean from preview1), 'preview succeeds for isolated root');
select is((select res #>> '{data,submissionMode}' from preview1), 'root', 'preview identifies root mode');
select is((select jsonb_array_length(res #> '{data,targets}') from preview1), 2, 'preview returns root + approved dependency');
reset role;
select is(
  (select count(*)::integer from private.reviews where data_id::text like '96000000-%' and state_code <> -1),
  0,
  'preview creates zero review rows'
);

-- 2. Preview + submit with stale digest MUST fail cleanly with 409 REVIEW_SCOPE_DRIFT and zero mutations
set local role authenticated;
create temp table drift_digest as
select api.cmd_review_submit(
  'processes',
  '96000000-0000-4000-8000-000000000030',
  '01.00.000',
  jsonb_build_object('payload', jsonb_build_object('expected_scope_digest', repeat('0', 64)))
) as res;
select is((select res->>'code' from drift_digest), 'REVIEW_SCOPE_DRIFT', 'mismatched digest returns REVIEW_SCOPE_DRIFT');
select is((select (res->>'status')::integer from drift_digest), 409, 'mismatched digest returns status 409');
select is((select state_code from public.processes where id = '96000000-0000-4000-8000-000000000030'), 0, 'mismatched digest leaves root draft');

-- 3. Bound isolated root submission succeeds & preserves published dependency untouched
create temp table submit1 as
select api.cmd_review_submit(
  'processes',
  '96000000-0000-4000-8000-000000000030',
  '01.00.000',
  jsonb_build_object('payload', jsonb_build_object(
    'expected_scope_digest', (select res #>> '{data,scopeDigest}' from preview1),
    'expected_scope_targets', (select res #> '{data,targets}' from preview1)
  ))
) as res;
select is((select res->>'ok' from submit1), 'true', 'bound isolated root submission succeeds');
select is((select state_code from public.processes where id = '96000000-0000-4000-8000-000000000030'), 20, 'bound root freezes to state 20');
select is((select modified_at from public.contacts where id = '96000000-0000-4000-8000-000000000010'), '2024-01-01'::timestamptz, 'approved contact stays untouched');

-- 4. Preview Root 2, then mutate Root 2 to add unexpected draft flow 21 -> commit using stale preview MUST fail with ZERO state transitions
create temp table preview2 as
select api.qry_review_submit_scope('processes', '96000000-0000-4000-8000-000000000031', '01.00.000') as res;

-- First test allow-set excluding related draft flow 20 -> rejected cleanly
create temp table unexpected_draft as
select api.cmd_review_submit(
  'processes',
  '96000000-0000-4000-8000-000000000031',
  '01.00.000',
  jsonb_build_object('payload', jsonb_build_object(
    'expected_scope_targets', jsonb_build_array(
      jsonb_build_object('table', 'processes', 'id', '96000000-0000-4000-8000-000000000031', 'version', '01.00.000')
    )
  ))
) as res;
select is((select res->>'code' from unexpected_draft), 'REVIEW_SCOPE_DRIFT', 'allow-set omitting draft ref rejects unexpected draft');
select is((select state_code from public.processes where id = '96000000-0000-4000-8000-000000000031'), 0, 'root stays draft on unexpected draft refusal');
select is((select state_code from public.flows where id = '96000000-0000-4000-8000-000000000020'), 0, 'draft ref stays draft on unexpected draft refusal');

-- Mutate Root 2 dependency between preview and commit
reset role;
set local session_replication_role = replica;
update public.processes
set json = jsonb_set(
      json,
      '{processDataSet,exchanges,exchange}',
      (json #> '{processDataSet,exchanges,exchange}') || jsonb_build_array(
        jsonb_build_object(
          'referenceToFlowDataSet', jsonb_build_object(
            '@type', 'flow data set',
            '@refObjectId', '96000000-0000-4000-8000-000000000021',
            '@version', '01.00.000'
          )
        )
      )
    ),
    json_ordered = jsonb_set(
      json::jsonb,
      '{processDataSet,exchanges,exchange}',
      (json #> '{processDataSet,exchanges,exchange}') || jsonb_build_array(
        jsonb_build_object(
          'referenceToFlowDataSet', jsonb_build_object(
            '@type', 'flow data set',
            '@refObjectId', '96000000-0000-4000-8000-000000000021',
            '@version', '01.00.000'
          )
        )
      )
    )::json
where id = '96000000-0000-4000-8000-000000000031';
set local session_replication_role = origin;
set local role authenticated;

create temp table changed_dep as
select api.cmd_review_submit(
  'processes',
  '96000000-0000-4000-8000-000000000031',
  '01.00.000',
  jsonb_build_object('payload', jsonb_build_object(
    'expected_scope_digest', (select res #>> '{data,scopeDigest}' from preview2)
  ))
) as res;
select is((select res->>'code' from changed_dep), 'REVIEW_SCOPE_DRIFT', 'dependency drift between preview and commit fails closed');
select is((select state_code from public.flows where id = '96000000-0000-4000-8000-000000000021'), 0, 'newly linked draft stays untouched on drift');
select is((select state_code from public.processes where id = '96000000-0000-4000-8000-000000000031'), 0, 'root stays untouched on dependency drift');

-- 5. Fresh preview after drift succeeds when committed with new digest
create temp table preview2_fresh as
select api.qry_review_submit_scope('processes', '96000000-0000-4000-8000-000000000031', '01.00.000') as res;
create temp table submit2 as
select api.cmd_review_submit(
  'processes',
  '96000000-0000-4000-8000-000000000031',
  '01.00.000',
  jsonb_build_object('payload', jsonb_build_object(
    'expected_scope_digest', (select res #>> '{data,scopeDigest}' from preview2_fresh)
  ))
) as res;
select is((select res->>'ok' from submit2), 'true', 'commit succeeds with refreshed preview digest');
select is((select state_code from public.flows where id = '96000000-0000-4000-8000-000000000021'), 20, 'newly linked draft transitions cleanly when authorized');

-- 6. Resubmission after rejection (Root 3) works with scope preview + bound submit
create temp table preview3 as
select api.qry_review_submit_scope('processes', '96000000-0000-4000-8000-000000000032', '01.00.000') as res;
create temp table submit3 as
select api.cmd_review_submit(
  'processes',
  '96000000-0000-4000-8000-000000000032',
  '01.00.000',
  jsonb_build_object('payload', jsonb_build_object(
    'expected_scope_digest', (select res #>> '{data,scopeDigest}' from preview3)
  ))
) as res;
select is((select res->>'ok' from submit3), 'true', 'resubmission after rejected review succeeds with bound digest');
select is((select state_code from public.processes where id = '96000000-0000-4000-8000-000000000032'), 20, 'resubmitted root freezes to state 20');
reset role;

select * from finish();
rollback;
