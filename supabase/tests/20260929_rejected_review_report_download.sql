begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, auth;

select plan(18);

select ok(
  pg_catalog.to_regprocedure(
    'api.qry_review_report_download_descriptor_v1(uuid,text,uuid,text)'
  ) is not null,
  'review report download descriptor RPC exists'
);

select ok(
  not pg_catalog.has_function_privilege(
    'anon',
    'api.qry_review_report_download_descriptor_v1(uuid,text,uuid,text)',
    'EXECUTE'
  ),
  'anonymous callers cannot execute the descriptor RPC'
);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  is_sso_user, is_anonymous
)
values
  ('00000000-0000-0000-0000-000000000000', '19629000-0000-0000-0000-000000000001',
    'authenticated', 'authenticated', 'report-owner@example.com', 'test', now(),
    '{"provider":"email","providers":["email"]}', '{"email":"report-owner@example.com"}',
    now(), now(), false, false),
  ('00000000-0000-0000-0000-000000000000', '19629000-0000-0000-0000-000000000002',
    'authenticated', 'authenticated', 'report-reviewer@example.com', 'test', now(),
    '{"provider":"email","providers":["email"]}', '{"email":"report-reviewer@example.com"}',
    now(), now(), false, false),
  ('00000000-0000-0000-0000-000000000000', '19629000-0000-0000-0000-000000000003',
    'authenticated', 'authenticated', 'report-other@example.com', 'test', now(),
    '{"provider":"email","providers":["email"]}', '{"email":"report-other@example.com"}',
    now(), now(), false, false);

insert into private.users (id, raw_user_meta_data)
values
  ('19629000-0000-0000-0000-000000000001', '{"email":"report-owner@example.com"}'),
  ('19629000-0000-0000-0000-000000000002', '{"email":"report-reviewer@example.com"}'),
  ('19629000-0000-0000-0000-000000000003', '{"email":"report-other@example.com"}')
on conflict (id) do update set raw_user_meta_data = excluded.raw_user_meta_data;

insert into public.sources (
  id, version, json, json_ordered, user_id, state_code, rule_verification
)
values (
  '39629000-0000-0000-0000-000000000001',
  '01.01.000',
  '{"sourceDataSet":{"sourceInformation":{"dataSetInformation":{"referenceToDigitalFile":[{"@uri":"../external_docs/reports/current-report.pdf"},{"@uri":"../external_docs/reports/evidence.xlsx"}]}},"administrativeInformation":{"publicationAndOwnership":{"common:dataSetVersion":"01.01.000"}}}}'::jsonb,
  '{"sourceDataSet":{"sourceInformation":{"dataSetInformation":{"referenceToDigitalFile":[{"@uri":"../external_docs/reports/current-report.pdf"},{"@uri":"../external_docs/reports/evidence.xlsx"}]}},"administrativeInformation":{"publicationAndOwnership":{"common:dataSetVersion":"01.01.000"}}}}'::json,
  '19629000-0000-0000-0000-000000000002',
  0,
  true
);

set local session_replication_role = replica;
insert into public.processes (
  id, version, json, json_ordered, user_id, state_code, rule_verification
)
values (
  '49629000-0000-0000-0000-000000000003',
  '01.01.000',
  '{"processDataSet":{"processInformation":{"dataSetInformation":{"common:UUID":"49629000-0000-0000-0000-000000000003"}},"administrativeInformation":{"publicationAndOwnership":{"common:dataSetVersion":"01.01.000"}}}}'::jsonb,
  '{"processDataSet":{"processInformation":{"dataSetInformation":{"common:UUID":"49629000-0000-0000-0000-000000000003"}},"administrativeInformation":{"publicationAndOwnership":{"common:dataSetVersion":"01.01.000"}}}}'::json,
  '19629000-0000-0000-0000-000000000001',
  0,
  true
);
set local session_replication_role = origin;

select set_config('app.review_legacy_migration', 'on', true);
insert into private.reviews (
  id, data_id, data_version, state_code, reviewer_id, json,
  review_kind, target_table, submitted_revision_checksum, target_owner_id
)
values
  (
    '59629000-0000-0000-0000-000000000001',
    '49629000-0000-0000-0000-000000000001',
    '01.01.000', -1,
    '["19629000-0000-0000-0000-000000000002"]',
    '{"data":{"id":"49629000-0000-0000-0000-000000000001","version":"01.01.000","table":"processes"}}',
    'root', 'processes', pg_catalog.repeat('1', 64),
    '19629000-0000-0000-0000-000000000001'
  ),
  (
    '59629000-0000-0000-0000-000000000002',
    '49629000-0000-0000-0000-000000000002',
    '01.01.000', 1,
    '["19629000-0000-0000-0000-000000000002"]',
    '{"data":{"id":"49629000-0000-0000-0000-000000000002","version":"01.01.000","table":"processes"}}',
    'root', 'processes', pg_catalog.repeat('2', 64),
    '19629000-0000-0000-0000-000000000001'
  ),
  (
    '59629000-0000-0000-0000-000000000003',
    '49629000-0000-0000-0000-000000000003',
    '01.01.000', -1,
    '["19629000-0000-0000-0000-000000000002"]',
    '{"data":{"id":"49629000-0000-0000-0000-000000000003","version":"01.01.000","table":"processes"}}',
    null, null, null, null
  );

-- Active approvals use complete metadata; rejected legacy fixtures stay unchanged.
insert into private.comments (review_id, reviewer_id, json, state_code)
values
  (
    '59629000-0000-0000-0000-000000000001',
    '19629000-0000-0000-0000-000000000002',
    '{"modellingAndValidation":{"validation":{"review":{"common:referenceToCompleteReviewReport":{"@refObjectId":"39629000-0000-0000-0000-000000000001","@version":"01.01.000"}}}}}',
    -1
  ),
  (
    '59629000-0000-0000-0000-000000000002',
    '19629000-0000-0000-0000-000000000002',
    '{"modellingAndValidation":{"validation":{"review":[{"@type":"Not reviewed","common:referenceToCompleteReviewReport":[{"@type":"source data set","@refObjectId":"39629000-0000-0000-0000-000000000001","@version":"01.01.000","@uri":"../sources/39629000-0000-0000-0000-000000000001.xml","common:shortDescription":{"@xml:lang":"en","#text":"Synthetic report"}}]}]}}}',
    1
  ),
  (
    '59629000-0000-0000-0000-000000000003',
    '19629000-0000-0000-0000-000000000002',
    '{"modellingAndValidation":{"validation":{"review":{"common:referenceToCompleteReviewReport":{"@refObjectId":"39629000-0000-0000-0000-000000000001","@version":"01.01.000"}}}}}',
    -1
  );
select set_config('app.review_legacy_migration', 'off', true);

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '19629000-0000-0000-0000-000000000001', true);

select is(
  (
    api.qry_review_report_download_descriptor_v1(
      '49629000-0000-0000-0000-000000000001', '01.01.000',
      '39629000-0000-0000-0000-000000000001', '01.01.000'
    ) #>> '{ok}'
  ),
  'true',
  'terminal rejected Process owner is authorized for the exact report reference'
);

select is(
  (
    api.qry_review_report_download_descriptor_v1(
      '49629000-0000-0000-0000-000000000003', '01.01.000',
      '39629000-0000-0000-0000-000000000001', '01.01.000'
    ) #>> '{ok}'
  ),
  'true',
  'legacy rejected Process owner is authorized through the exact Process row'
);

select set_config('request.jwt.claim.sub', '19629000-0000-0000-0000-000000000003', true);
select is(
  (
    api.qry_review_report_download_descriptor_v1(
      '49629000-0000-0000-0000-000000000003', '01.01.000',
      '39629000-0000-0000-0000-000000000001', '01.01.000'
    ) #>> '{code}'
  ),
  'REVIEW_REPORT_DOWNLOAD_NOT_ALLOWED',
  'a non-owner cannot use a legacy rejected review to download the report'
);
select set_config('request.jwt.claim.sub', '19629000-0000-0000-0000-000000000001', true);

select is(
  pg_catalog.jsonb_array_length(
    api.qry_review_report_download_descriptor_v1(
      '49629000-0000-0000-0000-000000000001', '01.01.000',
      '39629000-0000-0000-0000-000000000001', '01.01.000'
    ) #> '{data,attachments}'
  )::text,
  '2',
  'all current report attachments are returned'
);

select is(
  (
    api.qry_review_report_download_descriptor_v1(
      '49629000-0000-0000-0000-000000000001', '01.01.000',
      '39629000-0000-0000-0000-000000000001', '01.01.000'
    ) #>> '{data,attachments,0,bucket}'
  ),
  'external_docs',
  'attachment bucket is fixed server-side'
);

select is(
  (
    api.qry_review_report_download_descriptor_v1(
      '49629000-0000-0000-0000-000000000001', '01.01.000',
      '39629000-0000-0000-0000-000000000001', '01.01.000'
    ) #>> '{data,attachments,0,objectPath}'
  ),
  'reports/current-report.pdf',
  'only the normalized object path is returned internally'
);

select is(
  (select pg_catalog.count(*)::text from public.sources where id = '39629000-0000-0000-0000-000000000001'),
  '0',
  'download authorization does not broaden Source RLS visibility'
);

select set_config('request.jwt.claim.sub', '19629000-0000-0000-0000-000000000003', true);
select is(
  (
    api.qry_review_report_download_descriptor_v1(
      '49629000-0000-0000-0000-000000000001', '01.01.000',
      '39629000-0000-0000-0000-000000000001', '01.01.000'
    ) #>> '{code}'
  ),
  'REVIEW_REPORT_DOWNLOAD_NOT_ALLOWED',
  'another user cannot download the report'
);

select set_config('request.jwt.claim.sub', '19629000-0000-0000-0000-000000000001', true);
select is(
  (
    api.qry_review_report_download_descriptor_v1(
      '49629000-0000-0000-0000-000000000002', '01.01.000',
      '39629000-0000-0000-0000-000000000001', '01.01.000'
    ) #>> '{code}'
  ),
  'REVIEW_REPORT_DOWNLOAD_NOT_ALLOWED',
  'a non-rejected review does not authorize download'
);

select is(
  (
    api.qry_review_report_download_descriptor_v1(
      '49629000-0000-0000-0000-000000000001', '01.01.000',
      '39629000-0000-0000-0000-000000000001', '02.01.000'
    ) #>> '{code}'
  ),
  'REVIEW_REPORT_DOWNLOAD_NOT_ALLOWED',
  'a different report version does not authorize download'
);

select is(
  (
    api.qry_review_report_download_descriptor_v1(
      '49629000-0000-0000-0000-000000000009', '01.01.000',
      '39629000-0000-0000-0000-000000000001', '01.01.000'
    ) #>> '{code}'
  ),
  'REVIEW_REPORT_DOWNLOAD_NOT_ALLOWED',
  'a different Process does not authorize download'
);

reset role;
update public.sources
set json = '{"sourceDataSet":{"sourceInformation":{"dataSetInformation":{"referenceToDigitalFile":{"@uri":"../external_docs/reports/replaced.pdf"}}},"administrativeInformation":{"publicationAndOwnership":{"common:dataSetVersion":"01.01.000"}}}}'::jsonb
where id = '39629000-0000-0000-0000-000000000001';
set local role authenticated;

select is(
  (
    api.qry_review_report_download_descriptor_v1(
      '49629000-0000-0000-0000-000000000001', '01.01.000',
      '39629000-0000-0000-0000-000000000001', '01.01.000'
    ) #>> '{data,attachments,0,objectPath}'
  ),
  'reports/replaced.pdf',
  'each call reflects the Source current attachment without freezing'
);

reset role;
update public.sources
set json = '{"sourceDataSet":{"sourceInformation":{"dataSetInformation":{}},"administrativeInformation":{"publicationAndOwnership":{"common:dataSetVersion":"01.01.000"}}}}'::jsonb
where id = '39629000-0000-0000-0000-000000000001';
set local role authenticated;

select is(
  pg_catalog.jsonb_array_length(
    api.qry_review_report_download_descriptor_v1(
      '49629000-0000-0000-0000-000000000001', '01.01.000',
      '39629000-0000-0000-0000-000000000001', '01.01.000'
    ) #> '{data,attachments}'
  )::text,
  '0',
  'a report with no current attachments returns an empty descriptor list'
);

reset role;
update public.sources
set json = '{"sourceDataSet":{"sourceInformation":{"dataSetInformation":{"referenceToDigitalFile":{"@uri":"../external_docs/../secret.pdf"}}},"administrativeInformation":{"publicationAndOwnership":{"common:dataSetVersion":"01.01.000"}}}}'::jsonb
where id = '39629000-0000-0000-0000-000000000001';
set local role authenticated;

select is(
  (
    api.qry_review_report_download_descriptor_v1(
      '49629000-0000-0000-0000-000000000001', '01.01.000',
      '39629000-0000-0000-0000-000000000001', '01.01.000'
    ) #>> '{code}'
  ),
  'REVIEW_REPORT_ATTACHMENT_INVALID',
  'path traversal in current attachment metadata fails closed'
);

select set_config('request.jwt.claim.sub', '', true);
select is(
  (
    api.qry_review_report_download_descriptor_v1(
      '49629000-0000-0000-0000-000000000001', '01.01.000',
      '39629000-0000-0000-0000-000000000001', '01.01.000'
    ) #>> '{code}'
  ),
  'AUTH_REQUIRED',
  'missing actor identity is rejected'
);

reset role;
select is(
  (
    select capability_id
    from private.api_capability_grants
    where routine_identity = 'api.qry_review_report_download_descriptor_v1(uuid, text, uuid, text)'
  ),
  'NX-REV-01',
  'descriptor RPC is registered under the review capability'
);

select * from finish();
rollback;
