begin;
create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public;
select no_plan();

select ok(
  (select array_agg(pg_catalog.to_regprocedure(routine_identity)::text order by routine_identity) = array[
      'api.cmd_review_submit(text,uuid,text,jsonb)',
      'api.qry_review_get_items(uuid[],uuid,text,integer[])',
      'api.qry_review_submit_receipt(text,text,uuid,text)'
    ] and bool_and(allow_authenticated and not allow_anon and not allow_service_role)
   from private.api_capability_grants where capability_id = 'CLI-REVIEW-AUTHOR-01'),
  'only the exact author submit, read and receipt signatures use the narrow grant'
);

do $fixture$
begin
  perform api.svc_oauth_client_configure(
    'review984-author', 'cli', true,
    array['CLI-REVIEW-AUTHOR-01', 'DB-CORE-READ-01', 'DB-CORE-WRITE-01']
  );
  perform api.svc_oauth_client_configure('review984-disabled', 'cli', false, array['CLI-REVIEW-AUTHOR-01']);
  perform api.svc_oauth_client_configure('review984-reviewer', 'cli', true, array['NX-REV-01', 'NX-CMD-01']);
end;
$fixture$;

set local session_replication_role = replica;
insert into auth.users (id, aud, role, email, raw_app_meta_data, raw_user_meta_data)
values
  ('98400000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'review984-owner@example.invalid', '{}', '{}'),
  ('98400000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'review984-other@example.invalid', '{}', '{}');
insert into private.users (id, raw_user_meta_data)
values ('98400000-0000-4000-8000-000000000001', '{}'), ('98400000-0000-4000-8000-000000000002', '{}');
insert into private.roles (user_id, team_id, role)
values ('98400000-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000', 'review-member');
insert into public.contacts (id, version, json, json_ordered, user_id, state_code, rule_verification)
values
  ('98400000-0000-4000-8000-000000000010', '01.00.000', '{"fixture":"original"}', '{"fixture":"original"}',
    '98400000-0000-4000-8000-000000000001', 0, true),
  ('98400000-0000-4000-8000-000000000011', '01.00.000', '{}', '{}',
    '98400000-0000-4000-8000-000000000002', 0, true);

insert into private.reviews (id, data_id, data_version, state_code, reviewer_id, json, review_kind, target_table, target_owner_id, submitted_revision_checksum)
values
  ('98400000-0000-4000-8000-000000000021', '98400000-0000-4000-8000-000000000010', '00.00.999', -1,
    '["98400000-0000-4000-8000-000000000002"]',
    '{"user":{"id":"98400000-0000-4000-8000-000000000001"},"comment":{"message":"Returned to author"},"logs":[{"private":"opinion"}]}',
    'root', 'contacts', '98400000-0000-4000-8000-000000000001', repeat('a', 64)),
  ('98400000-0000-4000-8000-000000000022', '98400000-0000-4000-8000-000000000011', '01.00.000', 1,
    '["98400000-0000-4000-8000-000000000001"]', '{"user":{"id":"98400000-0000-4000-8000-000000000002"}}',
    'root', 'contacts', '98400000-0000-4000-8000-000000000002', repeat('a', 64)),
  ('98400000-0000-4000-8000-000000000023', '98400000-0000-4000-8000-000000000010', '00.00.999', -1,
    '[]', '{"user":{"id":"98400000-0000-4000-8000-000000000001"}}',
    'reference', 'contacts', '98400000-0000-4000-8000-000000000001', repeat('a', 64)),
  ('98400000-0000-4000-8000-000000000024', '98400000-0000-4000-8000-000000000010', '00.00.998', -1,
    '[]', '{"user":{"id":"98400000-0000-4000-8000-000000000001"}}',
    'reference', 'contacts', '98400000-0000-4000-8000-000000000001', repeat('a', 64)),
  ('98400000-0000-4000-8000-000000000025', '98400000-0000-4000-8000-000000000010', '00.00.997', -1,
    '[]', '{"user":{"id":"98400000-0000-4000-8000-000000000001"}}',
    null, null, null, null);
insert into private.command_audit_log (command, actor_user_id, target_table, target_id, target_version, payload)
values ('cmd_review_submit', '98400000-0000-4000-8000-000000000001', 'contacts',
  '98400000-0000-4000-8000-000000000010', '00.00.998',
  '{"review_id":"98400000-0000-4000-8000-000000000024","submission_mode":"reference_repair"}');
set local session_replication_role = origin;

set local request.jwt.claims = '{"role":"authenticated","sub":"98400000-0000-4000-8000-000000000001","client_id":"review984-author"}';
set local request.method = 'POST';
set local request.headers = '{"content-profile":"api"}';
set local role authenticated;
set local request.path = '/rpc/cmd_review_submit';

select lives_ok('select api.oauth_client_pre_request()', 'author reaches exact submit route');
select is(api.cmd_review_submit('contacts', '98400000-0000-4000-8000-000000000011', '01.00.000')->>'code',
  'ROOT_DATASET_NOT_OWNED', 'the existing command rejects a foreign root');
select is(api.cmd_review_submit('contacts', '98400000-0000-4000-8000-000000000010', '00.00.998')->>'code',
  'DATASET_NOT_FOUND', 'the command requires the exact requested version');

create temporary table submit_receipt as
select api.cmd_review_submit(
  'contacts', '98400000-0000-4000-8000-000000000010', '01.00.000',
  jsonb_build_object('payload', jsonb_build_object('review_operation_key', repeat('a', 64)))
) as value;
select is((select value ->> 'ok' from submit_receipt), 'true', 'the author can submit the owned draft');
select is((select jsonb_array_length(value #> '{data,affectedDatasets}') from submit_receipt), 1,
  'only the exact synthetic root was affected');
select is(api.cmd_review_submit('contacts', '98400000-0000-4000-8000-000000000010', '01.00.000')->>'code',
  'DATA_UNDER_REVIEW', 'the original draft cannot generate a duplicate submission');
select is((select json from public.contacts where id = '98400000-0000-4000-8000-000000000010'),
  '{"fixture":"original"}'::jsonb, 'submission preserves the exact draft content');
select is((select state_code from public.contacts where id = '98400000-0000-4000-8000-000000000010'), 20,
  'only review lifecycle changes on the draft');

set local request.path = '/rpc/qry_review_get_items';
select lives_ok('select api.oauth_client_pre_request()', 'author reaches review item reads');
select is(
  (select count(*) from api.qry_review_get_items(array[(select (value #>> '{data,reviewId}')::uuid from submit_receipt)])),
  1::bigint, 'the accepted review is visible by exact response ID'
);
select is(
  (select array_agg(id order by id) from api.qry_review_get_items(
    null, '98400000-0000-4000-8000-000000000010', null, array[-1])),
  array['98400000-0000-4000-8000-000000000021'::uuid, '98400000-0000-4000-8000-000000000024'::uuid,
    '98400000-0000-4000-8000-000000000025'::uuid],
  'state and dataset filters retain own root, actually submitted reference and legacy history'
);
select is(
  (select count(*) from (select id from api.qry_review_get_items() order by id limit 1 offset 3) as page),
  1::bigint, 'owner filtering precedes page limits and offsets'
);
select is(
  (select count(*) from api.qry_review_get_items(array['98400000-0000-4000-8000-000000000022'::uuid])),
  0::bigint, 'an author OAuth token cannot read foreign records even when the actor is a reviewer'
);
select ok((
  select reviewer_id = '[]'::jsonb and deadline is null and not (json ? 'logs')
    and json #>> '{comment,message}' = 'Returned to author'
  from api.qry_review_get_items(array['98400000-0000-4000-8000-000000000021'::uuid])
), 'the author projection retains the final reason without reviewer IDs or internal logs');

select throws_ok(
  format('select set_config(''request.path'', %L, true); select api.oauth_client_pre_request()', route),
  '42501', 'OAuth client is not authorized for this API route', 'author cannot use ' || route
)
from unnest(array[
  '/rpc/qry_review_get_rejection_details_v1',
  '/rpc/cmd_review_assign_reviewers',
  '/rpc/cmd_review_approve',
  '/rpc/cmd_review_reject',
  '/rpc/cmd_review_submit_v2'
]) as blocked(route);

set local request.path = '/rpc/qry_review_get_items';
set local request.jwt.claims = '{"role":"authenticated","sub":"98400000-0000-4000-8000-000000000001","client_id":"review984-disabled"}';
select throws_ok('select api.oauth_client_pre_request()', '42501', 'OAuth client is not authorized for this API route',
  'disabled client cannot exercise its old grant');
set local request.jwt.claims = '{"role":"authenticated","sub":"98400000-0000-4000-8000-000000000001","client_id":"review984-unknown"}';
select throws_ok('select api.oauth_client_pre_request()', '42501', 'OAuth client is not authorized for this API route',
  'unregistered client cannot use the author RPC');
select is((select count(*) from api.qry_review_get_items()), 0::bigint,
  'the read also fails closed without a route grant inside the function');

set local request.jwt.claims = '{"role":"authenticated","sub":"98400000-0000-4000-8000-000000000001"}';
select ok((select reviewer_id ? '98400000-0000-4000-8000-000000000001'
  from api.qry_review_get_items(array['98400000-0000-4000-8000-000000000022'::uuid])),
  'a first-party reviewer retains their assigned review and participant projection');
set local request.jwt.claims = '{"role":"authenticated","sub":"98400000-0000-4000-8000-000000000001","client_id":"review984-reviewer"}';
select lives_ok('select api.oauth_client_pre_request()', 'an older review-read grant still admits the existing route');
select is((select count(*) from api.qry_review_get_items(array['98400000-0000-4000-8000-000000000022'::uuid])),
  1::bigint, 'an explicitly granted reviewer OAuth client keeps the existing projection');
set local request.path = '/rpc/cmd_review_submit';
select lives_ok('select api.oauth_client_pre_request()', 'an older review-command grant still admits submission');

set local request.method = 'GET';
set local request.path = '/rpc/qry_review_submit_receipt';
set local request.jwt.claims = '{"role":"authenticated","sub":"98400000-0000-4000-8000-000000000001","client_id":"review984-author"}';
select lives_ok('select api.oauth_client_pre_request()', 'author reaches exact receipt read');
select is(api.qry_review_submit_receipt(repeat('a',64), 'contacts', '98400000-0000-4000-8000-000000000010', '01.00.000'),
  (select (value #>> '{data,reviewId}')::uuid from submit_receipt), 'the actual committed audit supplies the original ID');
select is(api.qry_review_submit_receipt(repeat('a',64), 'contacts', '98400000-0000-4000-8000-000000000010', '00.00.999'),
  null::uuid, 'a stale version cannot resolve the receipt');
select is(api.qry_review_submit_receipt(repeat('a',64), 'sources', '98400000-0000-4000-8000-000000000010', '01.00.000'),
  null::uuid, 'a different table cannot resolve the receipt');
select is(api.qry_review_submit_receipt(repeat('b',64), 'contacts', '98400000-0000-4000-8000-000000000010', '01.00.000'),
  null::uuid, 'an unknown request cannot resolve a matching target');
set local request.jwt.claims = '{"role":"authenticated","sub":"98400000-0000-4000-8000-000000000002","client_id":"review984-author"}';
select is(api.qry_review_submit_receipt(repeat('a',64), 'contacts', '98400000-0000-4000-8000-000000000010', '01.00.000'),
  null::uuid, 'another actor cannot read the receipt even with the capability');
set local request.jwt.claims = '{"role":"authenticated","sub":"98400000-0000-4000-8000-000000000001","client_id":"review984-reviewer"}';
select throws_ok('select api.oauth_client_pre_request()', '42501', 'OAuth client is not authorized for this API route',
  'the old reviewer capability does not admit the new receipt route');

reset role;
insert into private.command_audit_log (command, actor_user_id, target_table, target_id, target_version, payload)
  select command, actor_user_id, target_table, target_id, target_version, payload
  from private.command_audit_log
  where command = 'cmd_review_submit'
    and target_id = '98400000-0000-4000-8000-000000000010'
    and payload #>> '{payload,review_operation_key}' = repeat('a', 64);
set local role authenticated;
set local request.jwt.claims = '{"role":"authenticated","sub":"98400000-0000-4000-8000-000000000001","client_id":"review984-author"}';
select is(api.qry_review_submit_receipt(repeat('a',64), 'contacts', '98400000-0000-4000-8000-000000000010', '01.00.000'),
  null::uuid, 'ambiguous audits never select an arbitrary receipt');
reset role;
select * from finish();
rollback;
