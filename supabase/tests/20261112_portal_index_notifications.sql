begin;
create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, auth;
select no_plan();

create temporary table index_work (provider text, value jsonb);
create function pg_temp.flow_payload(p_name text) returns jsonb
language sql immutable as $$
  select jsonb_build_object('flowDataSet', jsonb_build_object(
    'flowInformation', jsonb_build_object('dataSetInformation', jsonb_build_object(
      'name', jsonb_build_object('baseName', jsonb_build_array(
        jsonb_build_object('@xml:lang', 'en', '#text', p_name)
      ))
    ))
  ));
$$;

-- Leave the normal publication and projection writers enabled. Suppress the
-- unrelated legacy extraction HTTP wakeup for these rollback-only fixtures.
create or replace function util.invoke_edge_function(
  name text, body jsonb, timeout_milliseconds integer default 300000
) returns void language plpgsql security definer set search_path = '' as $$begin return; end$$;

select ok(not has_table_privilege('service_role', 'private.portal_index_outbox', 'select'),
  'the service role can only use the outbox facades');
select ok(not has_function_privilege('authenticated', 'api.svc_portal_index_status_v1()', 'execute'),
  'authenticated actors cannot inspect delivery state');
select ok(not has_function_privilege('anon', 'api.svc_portal_index_withdrawal_feed_v1(text,text[])', 'execute'),
  'the feed is not an anonymous Database RPC');
select ok(not has_function_privilege('service_role', 'private.portal_index_set_scheduler_v1(boolean)', 'execute'),
  'scheduler activation is Database owner only');
select throws_ok($$select api.svc_portal_index_status_v1()$$, '42501', 'service role required',
  'the service facade also checks the request role');
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select is(api.svc_portal_index_status_v1()->>'captureEnabled', 'false', 'capture defaults off');
select is(api.svc_portal_index_status_v1()->>'dispatchEnabled', 'false', 'dispatch defaults off');
select is((select count(*) from cron.job where jobname = 'dispatch-portal-index-notifications-v1'),
  0::bigint, 'the migration did not create a scheduler');
select throws_ok(
  $$select private.portal_index_configure_v1('https://portal.example', array['tiangong_lca'], true, true)$$,
  '55000', 'Portal display is unavailable', 'capture requires active scoped display');

insert into public.flows(id, version, state_code, json)
select ('97200000-0000-4000-8000-' || lpad(i::text,12,'0'))::uuid,
  '01.00.000', 0, pg_temp.flow_payload('Fixture ' || i)
from generate_series(101,115) as fixture(i) where i <> 110;
insert into public.flows(id, version, state_code, json)
values
  ('97200000-0000-4000-8000-000000000101','02.00.000',0,pg_temp.flow_payload('Fallback test latest')),
  ('97200000-0000-4000-8000-000000000106','02.00.000',0,pg_temp.flow_payload('New latest')),
  ('97200000-0000-4000-8000-000000000115','02.00.000',0,pg_temp.flow_payload('Higher version remains public'));
insert into public.processes(id,version,state_code,json)
values ('97200000-0000-4000-8000-000000000116','01.00.000',0,'{"processDataSet":{}}');

insert into private.dataset_display_settings(dataset_kind,dataset_id,dataset_version,is_visible,brand)
select 'flow', id, version, true, case when id::text like '%108' then 'bafu' else 'tiangong_lca' end
from public.flows where id::text like '97200000-%'
  and right(id::text,3) in ('101','102','103','106','107','108','111','113','115')
  and (right(id::text,3) <> '106' or version = '01.00.000');
select is((select count(*) from private.portal_index_outbox), 0::bigint, 'migration does not backfill visible rows');
select private.portal_display_transition_v1('legacy', 'display');
select private.portal_index_configure_v1('https://portal.example', array['tiangong_lca'], true, true);
select throws_ok(
  $$select private.portal_index_configure_v1('https://other.example', array['tiangong_lca'], true, true)$$,
  '22023', 'Portal index destination is already bound', 'retained history cannot be moved to another origin');
select throws_ok(
  $$select private.portal_index_configure_v1('https://portal.example', array['tiangong_lca'], false, false)$$,
  '55000', 'Portal index capture cannot be disabled after activation', 'active capture cannot introduce an unobserved gap');
select throws_ok(
  $$select private.portal_index_set_scheduler_v1(true)$$,
  '55000', 'Portal index scheduler transport is unconfigured', 'scheduler requires provisioned transport');
do $$
begin
  perform vault.create_secret('https://abcdefghijklmnopqrst.supabase.co', 'project_url');
  perform vault.create_secret('sb_publishable_portal_index_test_only', 'portal_index_dispatch_publishable_key');
  perform vault.create_secret(repeat('A', 43), 'portal_index_dispatch_secret');
end;
$$;
select lives_ok($$select private.portal_index_set_scheduler_v1(true)$$, 'owner explicitly enables the fixed schedule');
select is(
  (select command from cron.job where jobname='dispatch-portal-index-notifications-v1' and active),
  'select private.portal_index_wake_v1();', 'the scheduler stores only the fixed owner command');
select is(private.portal_index_wake_v1(), null::bigint, 'empty outbox does not wake the Edge worker');
select lives_ok($$select private.portal_index_set_scheduler_v1(false)$$, 'owner explicitly unschedules the job');
select is((select count(*) from cron.job where jobname='dispatch-portal-index-notifications-v1'),
  0::bigint, 'unscheduling removes only the declared job');

update private.dataset_display_settings set is_visible = false
where dataset_id = '97200000-0000-4000-8000-000000000101' and dataset_version = '02.00.000';
update private.dataset_display_settings set brand = 'bafu'
where dataset_id = '97200000-0000-4000-8000-000000000102';
update private.dataset_display_settings set brand = 'worldsteel'
where dataset_id = '97200000-0000-4000-8000-000000000102';
update public.flows set json = pg_temp.flow_payload('Updated public content')
where id = '97200000-0000-4000-8000-000000000103';
update public.flows set json = pg_temp.flow_payload('Updated undisplayed content')
where id = '97200000-0000-4000-8000-000000000104';
insert into public.flows(id, version, state_code, json)
values ('97200000-0000-4000-8000-000000000110','01.00.000',100,pg_temp.flow_payload('Unlisted approved Flow'));

insert into private.dataset_display_settings(dataset_kind,dataset_id,dataset_version,is_visible,brand)
values ('flow','97200000-0000-4000-8000-000000000105','01.00.000',true,'tiangong_lca'),
       ('flow','97200000-0000-4000-8000-000000000106','02.00.000',true,'tiangong_lca'),
       ('process','97200000-0000-4000-8000-000000000116','01.00.000',true,'tiangong_lca');
update public.flows set json = pg_temp.flow_payload('Still-public older version edited')
where id = '97200000-0000-4000-8000-000000000106' and version = '01.00.000';
update private.dataset_display_settings set is_visible = false
where dataset_id = '97200000-0000-4000-8000-000000000115' and dataset_version = '01.00.000';
update private.dataset_display_settings set is_visible = is_visible, brand = brand
where dataset_id = '97200000-0000-4000-8000-000000000111';
update private.dataset_display_settings set is_visible = false
where dataset_id = '97200000-0000-4000-8000-000000000105';
delete from public.flows where id = '97200000-0000-4000-8000-000000000107';
update private.dataset_display_settings set brand = 'tiangong_lca'
where dataset_id = '97200000-0000-4000-8000-000000000108';
update private.dataset_display_settings set brand = 'worldsteel'
where dataset_id = '97200000-0000-4000-8000-000000000108';

savepoint display_write;
insert into private.dataset_display_settings(dataset_kind,dataset_id,dataset_version,is_visible,brand)
values ('flow','97200000-0000-4000-8000-000000000109','01.00.000',true,'tiangong_lca');
rollback to savepoint display_write;

select results_eq(
  $$select right(dataset_id::text,3), before_brand, after_brand
      from private.portal_index_outbox where provider = 'indexnow' order by dataset_id,dataset_version$$,
  $$values ('101','tiangong_lca',null::text), ('102','tiangong_lca',null::text),
           ('103','tiangong_lca','tiangong_lca'), ('106','tiangong_lca','tiangong_lca'),
           ('106',null::text,'tiangong_lca'), ('107','tiangong_lca',null::text),
           ('115','tiangong_lca',null::text), ('116',null::text,'tiangong_lca')$$,
  'only committed-scope changes are retained, coalesced by exact version within a transaction');
select is((select count(*) from private.portal_index_outbox where provider = 'baidu_withdrawal'),
  4::bigint, 'only exact removals create independent dead-link work');
select is((select count(*) from private.portal_index_outbox
  where dataset_id='97200000-0000-4000-8000-000000000111'),0::bigint,
  'a settings UPDATE with identical projected fields creates no work');
select is(api.svc_portal_index_withdrawal_feed_v1('https://portal.example',array['tiangong_lca']), '[]'::jsonb,
  'unverified withdrawal candidates do not enter the feed');
select throws_ok(
  $$select api.svc_portal_index_claim_v1('indexnow','https://portal.example',array['bafu'],25)$$,
  '22023', 'Portal index destination mismatch', 'the consumer cannot widen or change scope');

insert into index_work
select 'indexnow', value from jsonb_array_elements(
  api.svc_portal_index_claim_v1('indexnow','https://portal.example',array['tiangong_lca'],25)
);
insert into index_work
select 'baidu', value from jsonb_array_elements(
  api.svc_portal_index_claim_v1('baidu','https://portal.example',array['tiangong_lca'],25)
);
insert into index_work
select 'baidu_withdrawal', value from jsonb_array_elements(
  api.svc_portal_index_claim_v1('baidu_withdrawal','https://portal.example',array['tiangong_lca'],25)
);
select is((select count(*) from index_work where provider='indexnow'),8::bigint,
  'IndexNow independently leases its eight changes');
select is((select count(*) from index_work where provider='baidu'),8::bigint,
  'ordinary Baidu has an independent lease for the same changes');
select is(
  (select value#>>'{upserts,0,version}' from index_work
    where provider='indexnow' and value#>>'{withdrawals,0,id}' like '%101'),
  '01.00.000', 'withdrawing latest submits the still-visible fallback');
select is(
  (select value#>>'{withdrawals,0,version}' from index_work
    where provider='indexnow' and value#>>'{withdrawals,0,id}' like '%101'),
  '02.00.000', 'withdrawal binds the removed exact version');
select is(
  (select value->'withdrawals' from index_work
    where provider='indexnow' and value#>>'{upserts,0,id}' like '%106'
      and value#>>'{upserts,0,version}' = '02.00.000'),
  '[]'::jsonb, 'rollover leaves the old public version untouched');
select ok(exists (
  select 1 from index_work where provider='indexnow' and value#>>'{upserts,0,id}' like '%106'
    and value#>>'{upserts,0,version}' = '01.00.000'
), 'editing a still-visible older version submits its exact URL');
select is((
  select value->'upserts' from index_work
  where provider='indexnow' and value#>>'{withdrawals,0,id}' like '%115'
), '[]'::jsonb, 'withdrawing an older version leaves the higher public version untouched');
select is((
  select value#>>'{upserts,0,kind}' from index_work
  where provider='indexnow' and value#>>'{upserts,0,id}' like '%116'
), 'process', 'Process visibility shares the same capture boundary as Flow');
select is(
  (select value#>>'{upserts,0,id}' from index_work
    where provider='indexnow' and value#>>'{upserts,0,id}' like '%103'),
  '97200000-0000-4000-8000-000000000103', 'public content edits notify the exact URL');

create temporary table index_selected as
select provider, value, value->>'eventId' as event_id, (value->>'leaseToken')::uuid as token
from index_work
where value#>>'{withdrawals,0,id}' like '%101' or value#>>'{upserts,0,id}' like '%103';
select throws_ok(
  $$select api.svc_portal_index_settle_v1('baidu',event_id,token,'accepted','baidu_accepted',null,'[]')
      from index_selected where provider='baidu' and value#>>'{upserts,0,id}' like '%103'$$,
  '22023', 'Portal index outcome leaves work unaccounted for', 'accepted requires all supported exact locales');
select ok((
  select api.svc_portal_index_settle_v1('baidu',event_id,token,'retry','provider_quota_exhausted',60,
    jsonb_build_array(value#>'{upserts,0}' || '{"operation":"upsert","locale":"en"}'))
  from index_selected where provider='baidu' and value#>>'{upserts,0,id}' like '%103'
), 'partial acceptance persists while ordinary quota is exhausted');
select is(api.svc_portal_index_status_v1()->>'indexNowNotBefore', null::text,
  'Baidu quota does not throttle IndexNow');
select ok(api.svc_portal_index_status_v1()->>'baiduNotBefore' is not null,
  'Baidu quota creates a provider-wide durable pause');
select throws_ok(
  $$select api.svc_portal_index_settle_v1('baidu',value->>'eventId',(value->>'leaseToken')::uuid,
    'blocked','baidu_success_unattributed_quota_exhausted',120,
    jsonb_build_array(value#>'{upserts,0}' || '{"operation":"upsert","locale":"en"}'))
  from index_work where provider='baidu' and value#>>'{upserts,0,id}' like '%116'$$,
  '22023', 'invalid Portal index outcome', 'unattributed Baidu success cannot assert an exact receipt');
select ok((
  select api.svc_portal_index_settle_v1('baidu',value->>'eventId',(value->>'leaseToken')::uuid,
    'blocked','baidu_success_unattributed_quota_exhausted',120,'[]')
  from index_work where provider='baidu' and value#>>'{upserts,0,id}' like '%116'
), 'unattributed Baidu success is held for operator resolution instead of a blind retry');

select ok((
  select api.svc_portal_index_settle_v1('baidu_withdrawal',event_id,token,'retry','withdrawal_http_unconfirmed',15,
    jsonb_build_array(value#>'{withdrawals,0}' || '{"operation":"withdrawal","locale":"en"}'))
  from index_selected where provider='baidu_withdrawal'
), 'the dead-link lane records only HTTP-confirmed locale proof even during ordinary quota hold');
select is(
  api.svc_portal_index_withdrawal_feed_v1('https://portal.example',array['tiangong_lca']),
  '[{"kind":"flow","id":"97200000-0000-4000-8000-000000000101","version":"02.00.000","locale":"en"}]'::jsonb,
  'the feed returns only verified public-history keys and omits internal receipt data');
update private.portal_index_outbox set available_at = '-infinity'
where provider='baidu_withdrawal' and dataset_id='97200000-0000-4000-8000-000000000101';
create temporary table withdrawal_retry as
select api.svc_portal_index_claim_v1(
  'baidu_withdrawal','https://portal.example',array['tiangong_lca'],1
) -> 0 as work;
select is((select work#>>'{accepted,0,locale}' from withdrawal_retry), 'en',
  'reclaim preserves the exact proved subset');
select ok((
  select api.svc_portal_index_settle_v1(
    'baidu_withdrawal',work->>'eventId',(work->>'leaseToken')::uuid,
    'manifest_ready','manual_registration_pending',null,(
      select jsonb_agg(work#>'{withdrawals,0}' || jsonb_build_object('operation','withdrawal','locale',locale))
      from (values ('zh-CN'),('de'),('fr')) as pending(locale)
    )
  ) from withdrawal_retry
), 'completed verification remains distinct from provider acceptance');
select is(jsonb_array_length(api.svc_portal_index_withdrawal_feed_v1(
  'https://portal.example',array['tiangong_lca']
)),4,'every verified locale is present in the feed');

-- Force time forward for an exact synthetic lease without wall-clock sleeps.
update private.portal_index_outbox set lease_expires_at = clock_timestamp() - interval '1 second',
  available_at = clock_timestamp() - interval '1 second'
where provider='indexnow' and dataset_id='97200000-0000-4000-8000-000000000103';
select is((
  select api.svc_portal_index_settle_v1('indexnow',event_id,token,'retry','provider_timeout',15,'[]')
  from index_selected where provider='indexnow' and value#>>'{upserts,0,id}' like '%103'
), false, 'an expired lease cannot settle even before another worker reclaims it');
select is((api.svc_portal_index_claim_v1('indexnow','https://portal.example',array['tiangong_lca'],1)
  #>>'{0,attempt}')::integer, 2, 'reclaim issues a new lease and increments attempt');

update private.dataset_display_settings set is_visible = true
where dataset_id = '97200000-0000-4000-8000-000000000101' and dataset_version = '02.00.000';
select is((
  select api.svc_portal_index_recheck_v1('indexnow',event_id,token)->'withdrawals'
  from index_selected where provider='indexnow' and value#>>'{withdrawals,0,id}' like '%101'
), '[]'::jsonb, 'live recheck cancels a stale leased withdrawal');
select is(api.svc_portal_index_withdrawal_feed_v1('https://portal.example',array['tiangong_lca']), '[]'::jsonb,
  'reactivation immediately removes a previously confirmed dead link');
insert into private.dataset_display_settings(dataset_kind,dataset_id,dataset_version,is_visible,brand)
values ('flow','97200000-0000-4000-8000-000000000112','01.00.000',true,'tiangong_lca');
select private.portal_display_transition_v1('display', 'unavailable');
select is(api.svc_portal_index_claim_v1('indexnow','https://portal.example',array['tiangong_lca'],25),
  '[]'::jsonb, 'a catalog outage never leases removals');
select throws_ok(
  $$select api.svc_portal_index_withdrawal_feed_v1('https://portal.example',array['tiangong_lca'])$$,
  '55000', 'Portal display is unavailable', 'a catalog outage fails the feed closed');
select lives_ok(
  $$select private.portal_index_configure_v1('https://portal.example',array['tiangong_lca'],true,false)$$,
  'an owner can disable dispatch while Portal display is unavailable');
select is(private.portal_index_wake_v1(), null::bigint, 'unavailable display never wakes the Edge worker');
select is(api.svc_portal_index_status_v1()->>'maintenanceGap', 'true',
  'leaving display mode durably suspends dispatch and the feed');
select throws_ok($$select private.portal_index_reconcile_maintenance_v1(100)$$,
  '55000', 'Portal display is unavailable', 'the owner can only release held events after display is restored');
update private.dataset_display_settings set is_visible = false
where dataset_id = '97200000-0000-4000-8000-000000000111';
update private.dataset_display_settings set is_visible = false
where dataset_id = '97200000-0000-4000-8000-000000000112';
create temporary table detail_only_projection as
select card,document,modified_at from private.display_catalog_search_rows_v1
where dataset_kind='flow' and id='97200000-0000-4000-8000-000000000113';
update public.flows set json = jsonb_set(json,'{flowDataSet,administrativeInformation}',
  '{"publicationAndOwnership":{"common:dateOfLastRevision":"2026-11-12"}}')
where id = '97200000-0000-4000-8000-000000000113';
select ok((
  select (p.card,p.document,p.modified_at) is not distinct from (old.card,old.document,old.modified_at)
  from private.display_catalog_search_rows_v1 as p cross join detail_only_projection as old
  where p.dataset_kind='flow' and p.id='97200000-0000-4000-8000-000000000113'
), 'a detail-only edit can preserve the complete card, document and timestamp');
select results_eq(
  $$select right(dataset_id::text,3), before_brand, after_brand
      from private.portal_index_outbox where provider='indexnow' and state='held' order by dataset_id$$,
  $$values ('111','tiangong_lca',null::text), ('113','tiangong_lca','tiangong_lca')$$,
  'maintenance holds former public removals and edits without leaking a never-public transient');
insert into private.dataset_display_settings(dataset_kind,dataset_id,dataset_version,is_visible,brand)
values ('flow','97200000-0000-4000-8000-000000000114','01.00.000',true,'tiangong_lca');
select private.portal_display_transition_v1('unavailable', 'display');
update private.dataset_display_settings set is_visible = false
where dataset_id = '97200000-0000-4000-8000-000000000114';
select is((select count(*) from private.portal_index_outbox
  where right(dataset_id::text,3) in ('112','114')),0::bigint,
  'a never-public exact version cannot escape either same-transaction mode boundary');
select private.portal_index_configure_v1('https://portal.example',array['tiangong_lca'],true,true);
select is(api.svc_portal_index_claim_v1('indexnow','https://portal.example',array['tiangong_lca'],25),
  '[]'::jsonb, 'mode restoration alone cannot resume claims');
select throws_ok(
  $$select api.svc_portal_index_withdrawal_feed_v1('https://portal.example',array['tiangong_lca'])$$,
  '55000', 'Portal index maintenance requires reconciliation', 'mode restoration alone cannot reopen the feed');
select throws_ok($$select private.portal_index_reconcile_maintenance_v1(1)$$,
  '55000', 'commit Portal display restoration before reconciliation',
  'the restoration transaction continues to coalesce unavailable writes until commit');

select * from finish();
rollback;
