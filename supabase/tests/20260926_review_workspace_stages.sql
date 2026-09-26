begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, auth;

select plan(17);

select ok(
  pg_catalog.to_regprocedure('api.qry_review_get_admin_queue_items_v5(text,integer,integer,text,text,text,text,text)') is not null,
  'admin workspace queue V5 exists'
);
select ok(
  pg_catalog.to_regprocedure('api.qry_review_get_member_queue_items_v5(text,integer,integer,text,text,text,text,text)') is not null,
  'member workspace queue V5 exists'
);
select ok(
  pg_catalog.to_regprocedure('api.qry_review_batch_eligibility_v1(uuid[],text)') is not null,
  'batch eligibility projection exists'
);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  is_sso_user, is_anonymous
)
values
  (
    '00000000-0000-0000-0000-000000000000',
    '19626000-0000-0000-0000-000000000001',
    'authenticated', 'authenticated', 'workspace-admin@example.com', 'test-password-hash', now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{"email":"workspace-admin@example.com"}'::jsonb,
    now(), now(), false, false
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    '19626000-0000-0000-0000-000000000002',
    'authenticated', 'authenticated', 'workspace-reviewer@example.com', 'test-password-hash', now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{"email":"workspace-reviewer@example.com"}'::jsonb,
    now(), now(), false, false
  );

insert into private.users (id, raw_user_meta_data)
values
  ('19626000-0000-0000-0000-000000000001', '{"email":"workspace-admin@example.com"}'::jsonb),
  ('19626000-0000-0000-0000-000000000002', '{"email":"workspace-reviewer@example.com"}'::jsonb)
on conflict (id) do update set raw_user_meta_data = excluded.raw_user_meta_data;

insert into private.roles (user_id, team_id, role)
values
  ('19626000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'review-admin'),
  ('19626000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'review-member');

insert into private.reviews (
  id, data_id, data_version, state_code, reviewer_id, json,
  review_kind, target_table, submitted_revision_checksum, target_owner_id
)
values
  (
    '59626000-0000-0000-0000-000000000001',
    '49626000-0000-0000-0000-000000000001', '01.00.000', 0, '[]'::jsonb,
    '{"data":{"id":"49626000-0000-0000-0000-000000000001","version":"01.00.000","table":"processes"},"logs":[]}'::jsonb,
    'root', 'processes', pg_catalog.repeat('1', 64), '19626000-0000-0000-0000-000000000001'
  ),
  (
    '59626000-0000-0000-0000-000000000002',
    '49626000-0000-0000-0000-000000000002', '01.00.000', 1,
    '["19626000-0000-0000-0000-000000000002"]'::jsonb,
    '{"data":{"id":"49626000-0000-0000-0000-000000000002","version":"01.00.000","table":"processes"},"logs":[]}'::jsonb,
    'root', 'processes', pg_catalog.repeat('2', 64), '19626000-0000-0000-0000-000000000001'
  ),
  (
    '59626000-0000-0000-0000-000000000003',
    '49626000-0000-0000-0000-000000000003', '01.00.000', 1,
    '["19626000-0000-0000-0000-000000000002"]'::jsonb,
    '{"data":{"id":"49626000-0000-0000-0000-000000000003","version":"01.00.000","table":"processes"},"logs":[]}'::jsonb,
    'root', 'processes', pg_catalog.repeat('3', 64), '19626000-0000-0000-0000-000000000001'
  ),
  (
    '59626000-0000-0000-0000-000000000004',
    '49626000-0000-0000-0000-000000000004', '01.00.000', 2,
    '["19626000-0000-0000-0000-000000000002"]'::jsonb,
    '{"data":{"id":"49626000-0000-0000-0000-000000000004","version":"01.00.000","table":"processes"},"logs":[]}'::jsonb,
    'root', 'processes', pg_catalog.repeat('4', 64), '19626000-0000-0000-0000-000000000001'
  ),
  (
    '59626000-0000-0000-0000-000000000005',
    '49626000-0000-0000-0000-000000000005', '01.00.000', -1,
    '["19626000-0000-0000-0000-000000000002"]'::jsonb,
    '{"data":{"id":"49626000-0000-0000-0000-000000000005","version":"01.00.000","table":"processes"},"logs":[]}'::jsonb,
    'root', 'processes', pg_catalog.repeat('5', 64), '19626000-0000-0000-0000-000000000001'
  );

insert into private.comments (review_id, reviewer_id, json, state_code)
values
  ('59626000-0000-0000-0000-000000000002', '19626000-0000-0000-0000-000000000002', '{"draft":true}'::json, 0),
  ('59626000-0000-0000-0000-000000000003', '19626000-0000-0000-0000-000000000002', '{"decision":"approve"}'::json, 1),
  ('59626000-0000-0000-0000-000000000004', '19626000-0000-0000-0000-000000000002', '{"decision":"approve"}'::json, 2),
  ('59626000-0000-0000-0000-000000000005', '19626000-0000-0000-0000-000000000002', '{"decision":"reject"}'::json, -1);

select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '19626000-0000-0000-0000-000000000001', true);

select is(
  (select count(*)::text from api.qry_review_get_admin_queue_items_v5('unassigned', 1, 50, 'modified_at', 'desc')),
  '1',
  'admin unassigned stage contains only state-zero reviews'
);
select is(
  (select count(*)::text from api.qry_review_get_admin_queue_items_v5('in-progress', 1, 50, 'modified_at', 'desc')),
  '2',
  'admin in-progress stage contains active assigned reviews'
);
select is(
  (select count(*)::text from api.qry_review_get_admin_queue_items_v5('completed', 1, 50, 'modified_at', 'desc')),
  '2',
  'admin completed stage contains approved and returned reviews'
);
select is(
  (select completed_reviewer_count::text from api.qry_review_get_admin_queue_items_v5('in-progress', 1, 50, 'modified_at', 'desc') where id = '59626000-0000-0000-0000-000000000003'),
  '1',
  'admin queue exposes submitted reviewer progress'
);
select is(
  (select eligible::text from api.qry_review_batch_eligibility_v1(array['59626000-0000-0000-0000-000000000003'::uuid], 'admin-approve')),
  'true',
  'admin approval preflight accepts a fully submitted review'
);
select is(
  (select reason_code from api.qry_review_batch_eligibility_v1(array['59626000-0000-0000-0000-000000000002'::uuid], 'admin-approve')),
  'REVIEWER_OPINIONS_PENDING',
  'admin approval preflight explains pending opinions'
);

select set_config('request.jwt.claim.sub', '19626000-0000-0000-0000-000000000002', true);

select is(
  (select count(*)::text from api.qry_review_get_member_queue_items_v5('pending', 1, 50, 'modified_at', 'desc')),
  '1',
  'member pending stage contains the editable draft'
);
select is(
  (select count(*)::text from api.qry_review_get_member_queue_items_v5('submitted', 1, 50, 'modified_at', 'desc')),
  '1',
  'member submitted stage contains active submitted opinions'
);
select is(
  (select count(*)::text from api.qry_review_get_member_queue_items_v5('completed', 1, 50, 'modified_at', 'desc')),
  '2',
  'member completed stage contains both terminal outcomes'
);
select is(
  api.cmd_review_save_comment_draft(
    '59626000-0000-0000-0000-000000000003', '{"edited":true}'::jsonb, '{}'::jsonb
  )->>'ok',
  'true',
  'submitted opinion can be reopened as a draft before finalization'
);
select is(
  (select state_code::text from private.comments where review_id = '59626000-0000-0000-0000-000000000003' and reviewer_id = '19626000-0000-0000-0000-000000000002'),
  '0',
  'saving an edited submitted opinion resets it to pending'
);
select is(
  (select count(*)::text from api.qry_review_get_member_queue_items_v5('submitted', 1, 50, 'modified_at', 'desc')),
  '0',
  'reopened opinion leaves the submitted stage'
);
select is(
  (select count(*)::text from api.qry_review_get_member_queue_items_v5('pending', 1, 50, 'modified_at', 'desc')),
  '2',
  'reopened opinion returns to the pending stage'
);
select is(
  api.cmd_review_save_comment_draft(
    '59626000-0000-0000-0000-000000000004', '{"edited":true}'::jsonb, '{}'::jsonb
  )->>'code',
  'INVALID_REVIEW_STATE',
  'completed reviews remain read-only'
);

select * from finish();
rollback;
