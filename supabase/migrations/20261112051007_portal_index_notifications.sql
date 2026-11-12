-- Database #972: capture committed Portal search changes and lease provider work.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';
select private.portal_display_assert_contract_v1();

create table private.portal_index_config (
  singleton boolean primary key default true check (singleton),
  origin text,
  allowed_brands text[],
  capture_enabled boolean not null default false,
  dispatch_enabled boolean not null default false,
  maintenance_gap boolean not null default false,
  maintenance_transaction xid8,
  maintenance_resume_transaction xid8,
  indexnow_not_before timestamptz,
  baidu_not_before timestamptz,
  check ((origin is null) = (allowed_brands is null)),
  check (not capture_enabled or origin is not null),
  check (not dispatch_enabled or capture_enabled),
  check (not maintenance_gap or capture_enabled),
  check (maintenance_transaction is null or maintenance_gap),
  check (maintenance_resume_transaction is null or maintenance_transaction is not null)
);

insert into private.portal_index_config default values;

create table private.portal_index_outbox (
  event_id bigint generated always as identity primary key,
  provider text not null check (provider in ('indexnow', 'baidu', 'baidu_withdrawal')),
  source_transaction xid8 not null,
  during_maintenance boolean not null,
  dataset_kind text not null check (dataset_kind in ('process', 'flow')),
  dataset_id uuid not null,
  dataset_version text not null check (dataset_version ~ '^[0-9]{2}\.[0-9]{2}\.[0-9]{3}$'),
  before_brand text,
  after_brand text,
  removed_latest boolean not null default false,
  state text not null default 'pending'
    check (state in ('held', 'pending', 'accepted', 'blocked', 'skipped', 'manifest_ready')),
  available_at timestamptz not null default clock_timestamp(),
  attempt integer not null default 0,
  lease_token uuid,
  lease_expires_at timestamptz,
  lease_candidates jsonb,
  accepted_keys jsonb not null default '[]'::jsonb,
  last_settlement_token uuid,
  last_outcome text,
  last_reason text,
  last_retry_after_seconds integer,
  settled_at timestamptz,
  unique (provider, source_transaction, dataset_kind, dataset_id, dataset_version),
  check ((lease_token is null) = (lease_expires_at is null)),
  check ((lease_token is null) = (lease_candidates is null)),
  check (lease_token is null or state = 'pending'),
  check (state <> 'held' or during_maintenance)
);

create index portal_index_outbox_due_idx
  on private.portal_index_outbox (provider, available_at, event_id)
  where state = 'pending';

create index portal_index_outbox_baidu_withdrawal_idx
  on private.portal_index_outbox (dataset_kind, dataset_id, dataset_version, event_id desc)
  where provider = 'baidu_withdrawal';

create index portal_index_outbox_prune_idx
  on private.portal_index_outbox (settled_at, event_id)
  where state in ('accepted', 'skipped') and provider <> 'baidu_withdrawal';

create index portal_index_outbox_blocked_idx
  on private.portal_index_outbox (provider, last_reason, event_id)
  where state = 'blocked';

create index portal_index_outbox_held_idx
  on private.portal_index_outbox (event_id)
  where state = 'held';

alter table private.portal_index_config enable row level security;
alter table private.portal_index_config force row level security;
alter table private.portal_index_outbox enable row level security;
alter table private.portal_index_outbox force row level security;
revoke all on private.portal_index_config, private.portal_index_outbox
  from public, anon, authenticated, service_role;
revoke all on sequence private.portal_index_outbox_event_id_seq
  from public, anon, authenticated, service_role;

-- Bind v1 to one production origin and its Portal brand scope. Keep that
-- identity fixed so a retained withdrawal can never move to another site.
create function private.portal_index_configure_v1(
  p_origin text, p_allowed_brands text[], p_capture_enabled boolean, p_dispatch_enabled boolean
) returns void
language plpgsql security definer set search_path = '' set lock_timeout = '5s'
as $$
declare
  v_config private.portal_index_config%rowtype;
  v_brands text[] := private.portal_normalize_brand_scope_v1(p_allowed_brands);
begin
  if p_origin is null or length(p_origin) > 253
    or p_origin !~ '^https://[a-z0-9]+([.-][a-z0-9]+)+$'
    or p_capture_enabled is null or p_dispatch_enabled is null
    or (p_dispatch_enabled and not p_capture_enabled) then
    raise invalid_parameter_value using message = 'invalid Portal index configuration';
  end if;

  -- Take the writer fence before the configuration row, in the same order as
  -- display transitions and maintenance reconciliation.
  lock table private.display_catalog_search_rows_v1 in share row exclusive mode;
  select * into strict v_config from private.portal_index_config for update;
  if v_config.origin is not null
    and (v_config.origin, v_config.allowed_brands) is distinct from (p_origin, v_brands) then
    raise invalid_parameter_value using message = 'Portal index destination is already bound';
  end if;
  if (p_capture_enabled and not v_config.capture_enabled)
    or (p_dispatch_enabled and not v_config.dispatch_enabled) then
    if private.portal_display_mode_v1() is distinct from 'display' then
      raise object_not_in_prerequisite_state using message = 'Portal display is unavailable';
    end if;
    perform private.portal_display_assert_contract_v1();
  end if;
  if v_config.capture_enabled and not p_capture_enabled then
    raise object_not_in_prerequisite_state using message = 'Portal index capture cannot be disabled after activation';
  end if;
  update private.portal_index_config
  set origin = p_origin, allowed_brands = v_brands, capture_enabled = p_capture_enabled,
      dispatch_enabled = p_dispatch_enabled
  where singleton;
end;
$$;

create function private.portal_display_index_gap_v1() returns trigger
language plpgsql security definer set search_path = ''
as $$
declare v_xid xid8;
begin
  if old.mode = new.mode then return new; end if;
  -- Serialize the mode switch with already-running and future display writes.
  lock table private.display_catalog_search_rows_v1 in share row exclusive mode;
  v_xid := pg_current_xact_id();
  if old.mode = 'display' and new.mode <> 'display' then
    update private.portal_index_config
    set maintenance_gap = true,
        maintenance_transaction = case when maintenance_resume_transaction = v_xid
          then maintenance_transaction else v_xid end,
        maintenance_resume_transaction = null
    where singleton and capture_enabled;
  elsif new.mode = 'display' then
    -- Writes in this transaction still precede externally visible recovery.
    update private.portal_index_config
    set maintenance_resume_transaction = v_xid
    where singleton and maintenance_transaction is not null;
  end if;
  return new;
end;
$$;

create trigger portal_display_index_gap_v1
  before update of mode on private.portal_display_rollout
  for each row execute function private.portal_display_index_gap_v1();

create function private.portal_index_was_latest_v1(
  p_kind text, p_id uuid, p_version text, p_allowed_brands text[], p_xid xid8
) returns boolean
language sql stable set search_path = ''
as $$
  select not exists (
    -- A higher version already changed in the capture group can have been
    -- public before the group even if it is absent from the current projection.
    select 1 from private.portal_index_outbox as older
    where older.provider = 'indexnow' and older.source_transaction = p_xid
      and older.before_brand is not null
      and (older.dataset_kind, older.dataset_id) = (p_kind, p_id)
      and older.dataset_version > p_version
    union all
    select 1 from private.display_sitemap_rows_v1 as s
    join private.dataset_display_settings as d
      on (d.dataset_kind, d.dataset_id, d.dataset_version::text)
        = (s.dataset_kind, s.id, s.version)
    where (s.dataset_kind, s.id) = (p_kind, p_id) and s.version > p_version
      and s.contract_version = 1 and d.is_visible and d.brand = any(p_allowed_brands)
      and not exists (
        select 1 from private.portal_index_outbox as added
        where added.provider = 'indexnow' and added.source_transaction = p_xid
          and added.before_brand is null
          and (added.dataset_kind, added.dataset_id, added.dataset_version)
            = (s.dataset_kind, s.id, s.version)
      )
  );
$$;

create function private.portal_index_enqueue_v1(
  p_kind text, p_id uuid, p_version text, p_before_brand text, p_after_brand text,
  p_maintenance_transaction xid8, p_allowed_brands text[]
) returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_xid xid8;
  v_held boolean := p_maintenance_transaction is not null;
  v_state text := case when v_held then 'held' else 'pending' end;
  v_removed_latest boolean;
begin
  if p_before_brand is null and p_after_brand is null then return; end if;
  v_xid := coalesce(p_maintenance_transaction, pg_current_xact_id());

  insert into private.portal_index_outbox as existing (
    provider, during_maintenance, source_transaction, dataset_kind, dataset_id, dataset_version,
    before_brand, after_brand, state
  )
  select provider, v_held, v_xid, p_kind, p_id, p_version, p_before_brand, p_after_brand, v_state
  from (values ('indexnow'), ('baidu')) as destinations(provider)
  on conflict (provider, source_transaction, dataset_kind, dataset_id, dataset_version)
  do update set after_brand = excluded.after_brand, removed_latest = false,
    during_maintenance = existing.during_maintenance or excluded.during_maintenance,
    state = case when excluded.during_maintenance then 'held' else existing.state end;

  if p_after_brand is null then
    -- This exact URL first appeared and then disappeared before commit or
    -- within one unavailable interval. It never became publicly visible.
    delete from private.portal_index_outbox
    where provider in ('indexnow', 'baidu') and source_transaction = v_xid
      and (dataset_kind, dataset_id, dataset_version) = (p_kind, p_id, p_version)
      and before_brand is null and after_brand is null;

    if exists (
      select 1 from private.portal_index_outbox
      where provider = 'indexnow' and source_transaction = v_xid
        and (dataset_kind, dataset_id, dataset_version) = (p_kind, p_id, p_version)
        and before_brand is not null
    ) then
      v_removed_latest := private.portal_index_was_latest_v1(
        p_kind, p_id, p_version, p_allowed_brands, v_xid
      );
      if v_removed_latest then
        update private.portal_index_outbox set removed_latest = true
        where provider in ('indexnow','baidu') and source_transaction = v_xid
          and (dataset_kind, dataset_id, dataset_version) = (p_kind, p_id, p_version);
      end if;
    end if;

    -- A separate lane can confirm dead links while ordinary Baidu is disabled
    -- or has no submission quota. Inherit the first brand from the same transaction.
    insert into private.portal_index_outbox as existing (
      provider, during_maintenance, source_transaction, dataset_kind, dataset_id, dataset_version,
      before_brand, after_brand, state
    )
    select 'baidu_withdrawal', v_held, v_xid, p_kind, p_id, p_version, before_brand, null, v_state
    from private.portal_index_outbox
    where provider = 'baidu' and source_transaction = v_xid
      and (dataset_kind, dataset_id, dataset_version) = (p_kind, p_id, p_version)
      and before_brand is not null
    on conflict (provider, source_transaction, dataset_kind, dataset_id, dataset_version)
    do update set during_maintenance = existing.during_maintenance or excluded.during_maintenance,
      state = case when excluded.during_maintenance then 'held' else existing.state end;
  else
    delete from private.portal_index_outbox
    where provider = 'baidu_withdrawal' and source_transaction = v_xid
      and (dataset_kind, dataset_id, dataset_version) = (p_kind, p_id, p_version);
  end if;
end;
$$;

create function private.portal_index_capture_config_v1()
returns private.portal_index_config
language plpgsql set search_path = ''
as $$
declare v_config private.portal_index_config%rowtype;
begin
  if current_setting('transaction_isolation') in ('repeatable read', 'serializable') then
    -- Reject a stale snapshot that crossed a configuration or rollout fence.
    select * into strict v_config from private.portal_index_config for share;
  else
    select * into strict v_config from private.portal_index_config;
  end if;
  if v_config.maintenance_resume_transaction is not null
    and v_config.maintenance_resume_transaction <> pg_current_xact_id() then
    v_config.maintenance_transaction := null;
  end if;
  return v_config;
end;
$$;

create function private.portal_index_capture_v1() returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  v_config private.portal_index_config%rowtype;
  v_brands text[];
  v_before_brand text;
  v_after_brand text;
  v_identity_changed boolean := false;
begin
  if tg_op = 'UPDATE' and
    (old.dataset_kind, old.id, old.version, old.brand, old.state_code, old.modified_at, old.card, old.document)
    is not distinct from
    (new.dataset_kind, new.id, new.version, new.brand, new.state_code, new.modified_at, new.card, new.document) then
    return null;
  end if;
  v_config := private.portal_index_capture_config_v1();
  if not v_config.capture_enabled then return null; end if;
  v_brands := v_config.allowed_brands;

  if tg_op <> 'INSERT' and old.brand = any(v_brands) then
    v_before_brand := old.brand;
  end if;
  if tg_op <> 'DELETE' and new.brand = any(v_brands) then
    v_after_brand := new.brand;
  end if;
  if tg_op = 'UPDATE' then
    v_identity_changed := (old.dataset_kind, old.id, old.version)
      is distinct from (new.dataset_kind, new.id, new.version);
  end if;
  if tg_op = 'DELETE' or v_identity_changed then
    perform private.portal_index_enqueue_v1(
      old.dataset_kind, old.id, old.version, v_before_brand, null,
      v_config.maintenance_transaction, v_brands
    );
    v_before_brand := null;
  end if;
  if tg_op <> 'DELETE' then
    perform private.portal_index_enqueue_v1(
      new.dataset_kind, new.id, new.version, v_before_brand, v_after_brand,
      v_config.maintenance_transaction, v_brands
    );
  end if;
  return null;
end;
$$;

create trigger portal_index_capture_v1
  after insert or update or delete on private.display_catalog_search_rows_v1
  for each row execute function private.portal_index_capture_v1();

-- A second content edit in one transaction can leave the projected card,
-- document and transaction timestamp unchanged. Compare the source JSON only
-- in that case, after the existing source synchronizer has run.
create function private.portal_display_index_same_timestamp_v1() returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  v_config private.portal_index_config%rowtype := private.portal_index_capture_config_v1();
  v_brand text;
begin
  if not v_config.capture_enabled then return null; end if;
  select brand into v_brand from private.display_catalog_search_rows_v1
  where dataset_kind = tg_argv[0] and id = new.id and version = new.version::text
    and brand = any(v_config.allowed_brands);
  if v_brand is not null then
    perform private.portal_index_enqueue_v1(
      tg_argv[0], new.id, new.version::text, v_brand, v_brand,
      v_config.maintenance_transaction, v_config.allowed_brands
    );
  end if;
  return null;
end;
$$;

create trigger portal_display_z_index_same_timestamp_v1
  after update of json on public.processes for each row
  when (old.id = new.id and old.version = new.version
    and old.modified_at is not distinct from new.modified_at and old.json is distinct from new.json)
  execute function private.portal_display_index_same_timestamp_v1('process');

create trigger portal_display_z_index_same_timestamp_v1
  after update of json on public.flows for each row
  when (old.id = new.id and old.version = new.version
    and old.modified_at is not distinct from new.modified_at and old.json is distinct from new.json)
  execute function private.portal_display_index_same_timestamp_v1('flow');

create function private.portal_index_reconcile_maintenance_v1(p_limit integer)
returns jsonb
language plpgsql security definer set search_path = '' set lock_timeout = '5s' set statement_timeout = '10s'
as $$
declare
  v_config private.portal_index_config%rowtype;
  v_released integer;
  v_complete boolean;
begin
  if p_limit is null or p_limit not between 1 and 1000 then
    raise invalid_parameter_value using message = 'invalid Portal index maintenance batch';
  end if;
  lock table private.display_catalog_search_rows_v1 in share row exclusive mode;
  select * into strict v_config from private.portal_index_config for update;
  if private.portal_display_mode_v1() is distinct from 'display' then
    raise object_not_in_prerequisite_state using message = 'Portal display is unavailable';
  end if;
  if v_config.maintenance_resume_transaction = pg_current_xact_id() then
    raise object_not_in_prerequisite_state using message = 'commit Portal display restoration before reconciliation';
  end if;
  perform private.portal_display_assert_contract_v1();
  with held as (
    select event_id from private.portal_index_outbox
    where state = 'held' order by event_id limit p_limit
  )
  update private.portal_index_outbox as q set state = 'pending'
  from held where q.event_id = held.event_id;
  get diagnostics v_released = row_count;
  select not exists (select 1 from private.portal_index_outbox where state = 'held') into v_complete;
  if v_complete and v_config.maintenance_gap then
    update private.portal_index_config
    set maintenance_gap = false, maintenance_transaction = null, maintenance_resume_transaction = null
    where singleton;
  end if;
  return jsonb_build_object('released', v_released, 'complete', v_complete);
end;
$$;

-- Match the scoped sitemap's live-settings predicate. A changed exact version
-- can still be public when a higher version is in the sitemap.
create function private.portal_index_candidates_v1(
  p_event private.portal_index_outbox, p_allowed_brands text[]
) returns jsonb
language sql stable set search_path = ''
as $$
  with scoped as materialized (
    select s.version
    from private.display_sitemap_rows_v1 as s
    join private.dataset_display_settings as d
      on (d.dataset_kind, d.dataset_id, d.dataset_version::text)
        = (s.dataset_kind, s.id, s.version)
    where (s.dataset_kind, s.id) = (p_event.dataset_kind, p_event.dataset_id)
      and s.contract_version = 1 and d.is_visible and d.brand = any(p_allowed_brands)
  ), decision as (
    select max(version) as latest, coalesce(bool_or(version = p_event.dataset_version), false) as exact,
      p_event.before_brand is not null and p_event.after_brand is null as removed
    from scoped
  ), upsert as (
    select case
      when exact and p_event.after_brand is not null then p_event.dataset_version
      when not exact and removed and p_event.removed_latest and latest < p_event.dataset_version then latest
    end as version
    from decision
  )
  select jsonb_build_object(
    'upserts', case when p_event.provider <> 'baidu_withdrawal' and upsert.version is not null
      then jsonb_build_array(jsonb_build_object(
      'kind', p_event.dataset_kind, 'id', p_event.dataset_id, 'version', upsert.version
    )) else '[]'::jsonb end,
    'withdrawals', case when not exact and removed and (
      p_event.provider <> 'baidu_withdrawal' or not exists (
        select 1 from private.portal_index_outbox as newer
        where newer.provider = 'baidu_withdrawal'
          and (newer.dataset_kind, newer.dataset_id, newer.dataset_version)
            = (p_event.dataset_kind, p_event.dataset_id, p_event.dataset_version)
          and newer.event_id > p_event.event_id
      ))
      then jsonb_build_array(jsonb_build_object(
        'kind', p_event.dataset_kind, 'id', p_event.dataset_id, 'version', p_event.dataset_version
      )) else '[]'::jsonb end
  )
  from decision cross join upsert;
$$;

create function private.portal_index_receipt_keys_v1(p_candidates jsonb)
returns setof jsonb
language sql immutable set search_path = ''
as $$
  select candidate || jsonb_build_object('operation', operation, 'locale', locale)
  from (
    select 'upsert' as operation, value as candidate from jsonb_array_elements(p_candidates->'upserts')
    union all
    select 'withdrawal', value from jsonb_array_elements(p_candidates->'withdrawals')
  ) as candidates
  cross join (values ('zh-CN'), ('en'), ('de'), ('fr')) as locales(locale);
$$;

create function private.portal_index_work_v1(p_event private.portal_index_outbox)
returns jsonb
language sql immutable set search_path = ''
as $$
  select p_event.lease_candidates || jsonb_build_object(
    'eventId', p_event.event_id::text,
    'leaseToken', p_event.lease_token,
    'attempt', p_event.attempt,
    'accepted', coalesce((
      select jsonb_agg(key order by key)
      from private.portal_index_receipt_keys_v1(p_event.lease_candidates) as keys(key)
      where p_event.accepted_keys @> jsonb_build_array(key)
    ), '[]'::jsonb)
  );
$$;

create function api.svc_portal_index_claim_v1(
  p_provider text, p_origin text, p_allowed_brands text[], p_limit integer
) returns jsonb
language plpgsql security definer set search_path = '' set statement_timeout = '5s'
as $$
declare
  v_config private.portal_index_config%rowtype;
  v_event private.portal_index_outbox%rowtype;
  v_brands text[];
  v_result jsonb := '[]'::jsonb;
  v_now timestamptz := clock_timestamp();
  v_lease_until timestamptz := v_now + interval '120 seconds';
begin
  if not util.is_service_request() then
    raise insufficient_privilege using message = 'service role required';
  end if;
  if p_provider is null or p_provider not in ('indexnow', 'baidu', 'baidu_withdrawal')
    or p_limit is null or p_limit not between 1 and 25 then
    raise invalid_parameter_value using message = 'invalid Portal index claim';
  end if;
  v_brands := private.portal_normalize_brand_scope_v1(p_allowed_brands);
  select * into strict v_config from private.portal_index_config;
  if not v_config.dispatch_enabled or v_config.maintenance_gap
    or private.portal_display_mode_v1() is distinct from 'display'
    or (p_provider = 'indexnow' and v_config.indexnow_not_before > v_now)
    or (p_provider = 'baidu' and v_config.baidu_not_before > v_now) then
    return v_result;
  end if;
  if (p_origin, v_brands) is distinct from (v_config.origin, v_config.allowed_brands) then
    raise invalid_parameter_value using message = 'Portal index destination mismatch';
  end if;
  perform private.portal_display_assert_contract_v1();

  for v_event in
    with due as (
      select event_id from private.portal_index_outbox
      where provider = p_provider and state = 'pending' and available_at <= v_now
      order by available_at, event_id
      limit p_limit
      for update skip locked
    )
    update private.portal_index_outbox as q
    set lease_token = gen_random_uuid(), lease_expires_at = v_lease_until,
        available_at = v_lease_until, attempt = least(q.attempt + 1, 1000000),
        lease_candidates = private.portal_index_candidates_v1(q, v_brands)
    from due where q.event_id = due.event_id
    returning q.*
  loop
    v_result := v_result || jsonb_build_array(private.portal_index_work_v1(v_event));
  end loop;
  return v_result;
end;
$$;

create function api.svc_portal_index_recheck_v1(
  p_provider text, p_event_id text, p_lease_token uuid
) returns jsonb
language plpgsql security definer set search_path = '' set statement_timeout = '5s'
as $$
declare
  v_config private.portal_index_config%rowtype;
  v_event private.portal_index_outbox%rowtype;
begin
  if not util.is_service_request() then
    raise insufficient_privilege using message = 'service role required';
  end if;
  if p_provider is null or p_provider not in ('indexnow', 'baidu', 'baidu_withdrawal')
    or p_event_id is null or p_event_id !~ '^[1-9][0-9]{0,18}$'
    or p_lease_token is null then
    raise invalid_parameter_value using message = 'invalid Portal index lease';
  end if;
  select * into strict v_config from private.portal_index_config;
  if not v_config.dispatch_enabled or v_config.maintenance_gap
    or private.portal_display_mode_v1() is distinct from 'display'
    or (p_provider = 'indexnow' and v_config.indexnow_not_before > clock_timestamp())
    or (p_provider = 'baidu' and v_config.baidu_not_before > clock_timestamp()) then
    return null;
  end if;
  perform private.portal_display_assert_contract_v1();

  select * into v_event from private.portal_index_outbox
  where event_id = p_event_id::bigint and provider = p_provider
    and state = 'pending' and lease_token = p_lease_token
  for update;
  if not found or v_event.lease_expires_at <= clock_timestamp() then return null; end if;
  update private.portal_index_outbox as q
  set lease_candidates = private.portal_index_candidates_v1(v_event, v_config.allowed_brands)
  where q.event_id = v_event.event_id returning q.* into v_event;
  return private.portal_index_work_v1(v_event);
end;
$$;

create function api.svc_portal_index_settle_v1(
  p_provider text, p_event_id text, p_lease_token uuid, p_outcome text, p_reason text,
  p_retry_after_seconds integer, p_accepted jsonb
) returns boolean
language plpgsql security definer set search_path = '' set statement_timeout = '5s'
as $$
declare
  v_event private.portal_index_outbox%rowtype;
  v_accepted jsonb;
  v_now timestamptz;
  v_requires_delay boolean;
  v_hold_provider boolean;
begin
  if not util.is_service_request() then
    raise insufficient_privilege using message = 'service role required';
  end if;
  if p_provider is null or p_provider not in ('indexnow', 'baidu', 'baidu_withdrawal')
    or p_event_id is null or p_event_id !~ '^[1-9][0-9]{0,18}$'
    or p_lease_token is null or p_outcome is null or p_reason is null
    or p_accepted is null or jsonb_typeof(p_accepted) <> 'array'
    or octet_length(p_accepted::text) > 2048 then
    raise invalid_parameter_value using message = 'invalid Portal index settlement';
  end if;
  v_hold_provider := p_provider <> 'baidu_withdrawal' and p_reason in (
    'provider_rate_limited', 'provider_quota_exhausted', 'baidu_accepted_quota_exhausted',
    'provider_rejected_urls_quota_exhausted', 'baidu_success_unattributed_quota_exhausted'
  );
  v_requires_delay := p_outcome = 'retry' or v_hold_provider;
  if jsonb_array_length(p_accepted) > 8
    or (p_reason in ('baidu_success_unattributed', 'baidu_success_unattributed_quota_exhausted')
      and p_accepted <> '[]'::jsonb)
    or not coalesce(case p_outcome
      when 'accepted' then case p_provider
        when 'indexnow' then p_reason in ('indexnow_accepted', 'indexnow_validation_pending')
        when 'baidu' then p_reason in ('baidu_accepted', 'baidu_accepted_quota_exhausted')
      end
      when 'retry' then case when p_provider = 'baidu_withdrawal'
        then p_reason = 'withdrawal_http_unconfirmed'
        else p_reason in (
        'provider_rate_limited', 'provider_temporary_failure', 'provider_timeout',
        'provider_response_unconfirmed', 'provider_quota_exhausted'
      ) end
      when 'blocked' then p_provider <> 'baidu_withdrawal' and (p_reason in (
        'provider_invalid_request', 'provider_auth_failed', 'provider_endpoint_invalid',
        'provider_rejected_urls', 'provider_disabled', 'provider_endpoint_unverified'
      ) or (p_provider = 'baidu' and p_reason in (
        'provider_rejected_urls_quota_exhausted', 'baidu_success_unattributed',
        'baidu_success_unattributed_quota_exhausted'
      )))
      when 'skipped' then p_reason = 'no_current_urls'
        or (p_provider = 'baidu' and p_reason = 'withdrawal_unsupported')
      when 'manifest_ready' then p_provider = 'baidu_withdrawal' and p_reason = 'manual_registration_pending'
      else false
    end, false)
    or (not v_requires_delay and p_retry_after_seconds is not null)
    or (v_requires_delay and (p_retry_after_seconds is null
      or p_retry_after_seconds not between 15 and 86400)) then
    raise invalid_parameter_value using message = 'invalid Portal index outcome';
  end if;

  select * into v_event from private.portal_index_outbox
  where event_id = p_event_id::bigint and provider = p_provider for update;
  if not found then return false; end if;
  if v_event.lease_token is null and v_event.last_settlement_token = p_lease_token then
    return (v_event.last_outcome, v_event.last_reason, v_event.last_retry_after_seconds)
        is not distinct from (p_outcome, p_reason, p_retry_after_seconds)
      and v_event.accepted_keys @> p_accepted;
  end if;
  v_now := clock_timestamp();
  if v_event.lease_token is distinct from p_lease_token or v_event.lease_expires_at <= v_now then
    return false;
  end if;

  if exists (
    select 1 from jsonb_array_elements(p_accepted) as accepted(key)
    where (p_provider = 'baidu' and accepted.key->>'operation' = 'withdrawal')
      or not exists (
        select 1 from private.portal_index_receipt_keys_v1(v_event.lease_candidates) as candidate(key)
        where candidate.key = accepted.key
      )
  ) then
    raise invalid_parameter_value using message = 'Portal index receipt is outside the lease';
  end if;
  select coalesce(jsonb_agg(key order by key), '[]'::jsonb) into v_accepted
  from private.portal_index_receipt_keys_v1(v_event.lease_candidates) as candidates(key)
  where (v_event.accepted_keys || p_accepted) @> jsonb_build_array(key);

  if (p_outcome in ('accepted', 'manifest_ready') and exists (
    select 1 from private.portal_index_receipt_keys_v1(v_event.lease_candidates) as candidates(key)
    where (p_provider <> 'baidu' or key->>'operation' = 'upsert')
      and not (v_accepted @> jsonb_build_array(key))
  )) or (p_outcome = 'manifest_ready' and v_event.lease_candidates->'withdrawals' = '[]'::jsonb)
  or (p_outcome = 'accepted' and v_event.lease_candidates->'upserts' = '[]'::jsonb
    and (p_provider = 'baidu' or v_event.lease_candidates->'withdrawals' = '[]'::jsonb))
  or (p_outcome = 'skipped' and (
    v_event.lease_candidates->'upserts' <> '[]'::jsonb
    or (p_reason = 'no_current_urls' and v_event.lease_candidates->'withdrawals' <> '[]'::jsonb)
    or (p_reason = 'withdrawal_unsupported' and v_event.lease_candidates->'withdrawals' = '[]'::jsonb)
  )) then
    raise invalid_parameter_value using message = 'Portal index outcome leaves work unaccounted for';
  end if;

  update private.portal_index_outbox
  set state = case when p_outcome = 'retry' then 'pending' else p_outcome end,
      available_at = case when p_outcome = 'retry'
        then v_now + make_interval(secs => p_retry_after_seconds) else available_at end,
      lease_token = null, lease_expires_at = null, lease_candidates = null,
      accepted_keys = v_accepted, last_settlement_token = p_lease_token,
      last_outcome = p_outcome, last_reason = p_reason,
      last_retry_after_seconds = p_retry_after_seconds, settled_at = v_now
  where event_id = v_event.event_id;
  if v_hold_provider then
    update private.portal_index_config
    set indexnow_not_before = case when p_provider = 'indexnow'
          then greatest(indexnow_not_before, v_now + make_interval(secs => p_retry_after_seconds))
          else indexnow_not_before end,
        baidu_not_before = case when p_provider = 'baidu'
          then greatest(baidu_not_before, v_now + make_interval(secs => p_retry_after_seconds))
          else baidu_not_before end
    where singleton;
  end if;
  return true;
end;
$$;

create function api.svc_portal_index_status_v1()
returns jsonb
language plpgsql security definer set search_path = '' set statement_timeout = '5s'
as $$
declare
  v_config private.portal_index_config%rowtype;
  v_counts jsonb;
begin
  if not util.is_service_request() then
    raise insufficient_privilege using message = 'service role required';
  end if;
  select * into strict v_config from private.portal_index_config;
  select jsonb_object_agg(provider, counts) into v_counts
  from (
    select provider, jsonb_object_agg(state, n) as counts
    from (values ('indexnow'), ('baidu'), ('baidu_withdrawal')) as providers(provider)
    cross join (values ('held'), ('pending'), ('blocked'), ('manifest_ready')) as states(state)
    cross join lateral (
      select count(*) as n from (
        select 1 from private.portal_index_outbox as q
        where (q.provider, q.state) = (providers.provider, states.state)
        limit 1001
      ) as bounded
    ) as counted
    group by provider
  ) as provider_counts;
  return jsonb_build_object(
    'origin', v_config.origin, 'allowedBrands', v_config.allowed_brands,
    'captureEnabled', v_config.capture_enabled, 'dispatchEnabled', v_config.dispatch_enabled,
    'displayReady', private.portal_display_mode_v1() = 'display',
    'maintenanceGap', v_config.maintenance_gap,
    'indexNowNotBefore', v_config.indexnow_not_before, 'baiduNotBefore', v_config.baidu_not_before,
    'queueCountsCappedAt', 1001, 'queue', v_counts
  );
end;
$$;

-- A feed contains only exact locale proofs from the latest committed
-- withdrawal, with a fresh exclusion for reactivated exact versions.
create function api.svc_portal_index_withdrawal_feed_v1(p_origin text, p_allowed_brands text[])
returns jsonb
language plpgsql stable security definer set search_path = '' set statement_timeout = '10s'
as $$
declare
  v_config private.portal_index_config%rowtype;
  v_brands text[];
  v_result jsonb;
  v_exact_count bigint;
begin
  if not util.is_service_request() then
    raise insufficient_privilege using message = 'service role required';
  end if;
  v_brands := private.portal_normalize_brand_scope_v1(p_allowed_brands);
  select * into strict v_config from private.portal_index_config;
  if v_config.origin is null
    or (p_origin, v_brands) is distinct from (v_config.origin, v_config.allowed_brands) then
    raise invalid_parameter_value using message = 'Portal index destination mismatch';
  end if;
  if private.portal_display_mode_v1() is distinct from 'display' then
    raise object_not_in_prerequisite_state using message = 'Portal display is unavailable';
  end if;
  if v_config.maintenance_gap then
    raise object_not_in_prerequisite_state using message = 'Portal index maintenance requires reconciliation';
  end if;
  perform private.portal_display_assert_contract_v1();

  with latest as (
    select distinct on (q.dataset_kind, q.dataset_id, q.dataset_version)
      q.dataset_kind, q.dataset_id, q.dataset_version, q.accepted_keys
    from private.portal_index_outbox as q
    where q.provider = 'baidu_withdrawal'
      and not exists (
        select 1
        from private.display_sitemap_rows_v1 as s
        join private.dataset_display_settings as d
          on (d.dataset_kind, d.dataset_id, d.dataset_version::text)
            = (s.dataset_kind, s.id, s.version)
        where (s.dataset_kind, s.id, s.version) = (q.dataset_kind, q.dataset_id, q.dataset_version)
          and s.contract_version = 1 and d.is_visible and d.brand = any(v_brands)
      )
    order by q.dataset_kind, q.dataset_id, q.dataset_version, q.event_id desc
  ), proved as materialized (
    select * from latest where accepted_keys <> '[]'::jsonb limit 12501
  )
  select (select count(*) from proved), coalesce(jsonb_agg(
    proof.key - 'operation' order by dataset_kind, dataset_id, dataset_version, proof.key->>'locale'
  ), '[]'::jsonb)
  into v_exact_count, v_result
  from proved cross join lateral jsonb_array_elements(accepted_keys) as proof(key);

  if v_exact_count > 12500 or jsonb_array_length(v_result) > 50000
    or octet_length(v_result::text) >= 10000000 then
    raise program_limit_exceeded using message = 'Portal withdrawal export exceeds its bound';
  end if;
  return v_result;
end;
$$;

create function private.portal_index_requeue_v1(p_provider text, p_reason text, p_limit integer)
returns integer
language plpgsql security definer set search_path = '' set statement_timeout = '5s'
as $$
declare v_count integer;
begin
  if p_provider is null or p_provider not in ('indexnow', 'baidu')
    or p_reason is null or p_limit is null or p_limit not between 1 and 500 then
    raise invalid_parameter_value using message = 'invalid Portal index requeue';
  end if;
  with blocked as (
    select event_id from private.portal_index_outbox
    where provider = p_provider and state = 'blocked' and last_reason = p_reason
    order by event_id limit p_limit for update skip locked
  )
  update private.portal_index_outbox as q
  set state = 'pending', available_at = clock_timestamp(), last_settlement_token = null
  from blocked where q.event_id = blocked.event_id;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

create function private.portal_index_prune_v1(p_limit integer)
returns integer
language plpgsql security definer set search_path = '' set statement_timeout = '5s'
as $$
declare v_count integer;
begin
  if p_limit is null or p_limit not between 1 and 1000 then
    raise invalid_parameter_value using message = 'invalid Portal index prune';
  end if;
  with expired as (
    select event_id from private.portal_index_outbox
    where state in ('accepted', 'skipped') and settled_at < clock_timestamp() - interval '30 days'
      and provider <> 'baidu_withdrawal'
    order by settled_at, event_id limit p_limit for update skip locked
  )
  delete from private.portal_index_outbox as q
  using expired where q.event_id = expired.event_id;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

create function private.portal_index_scheduler_transport_v1()
returns table (project_url text, publishable_key text, dispatch_secret text)
language plpgsql stable security definer set search_path = ''
as $$
begin
  select min(decrypted_secret) filter (where name = 'project_url'),
    min(decrypted_secret) filter (where name = 'portal_index_dispatch_publishable_key'),
    min(decrypted_secret) filter (where name = 'portal_index_dispatch_secret')
  into project_url, publishable_key, dispatch_secret
  from vault.decrypted_secrets
  where name in ('project_url', 'portal_index_dispatch_publishable_key', 'portal_index_dispatch_secret')
  having count(*) = 3 and count(distinct name) = 3;
  if project_url is null or project_url !~ '^https://[a-z0-9]{20}\.supabase\.co$'
    or publishable_key is null or publishable_key !~ '^sb_publishable_[A-Za-z0-9_-]{15,128}$'
    or dispatch_secret is null or dispatch_secret !~ '^[A-Za-z0-9_-]{42}[AEIMQUYcgkosw048]$' then
    raise object_not_in_prerequisite_state using message = 'Portal index scheduler transport is unconfigured';
  end if;
  return next;
end;
$$;

create function private.portal_index_wake_v1()
returns bigint
language plpgsql security definer set search_path = '' set statement_timeout = '5s'
as $$
declare
  v_config private.portal_index_config%rowtype;
  v_transport record;
  v_request_id bigint;
  v_now timestamptz := clock_timestamp();
begin
  select * into strict v_config from private.portal_index_config;
  if not v_config.dispatch_enabled or v_config.maintenance_gap
    or private.portal_display_mode_v1() is distinct from 'display' then
    return null;
  end if;
  perform private.portal_index_prune_v1(1000);
  if not exists (
    select 1 from private.portal_index_outbox as q
    where state = 'pending' and available_at <= v_now
      and (
        (provider = 'indexnow' and coalesce(v_config.indexnow_not_before, v_now) <= v_now)
        or (provider = 'baidu' and coalesce(v_config.baidu_not_before, v_now) <= v_now)
        or provider = 'baidu_withdrawal'
      )
  ) then
    return null;
  end if;
  perform private.portal_display_assert_contract_v1();
  select * into strict v_transport from private.portal_index_scheduler_transport_v1();
  select net.http_post(
    url => v_transport.project_url || '/functions/v1/dispatch_portal_index_notifications',
    headers => jsonb_build_object(
      'Content-Type', 'application/json',
      'apikey', v_transport.publishable_key,
      'x-portal-index-dispatch-secret', v_transport.dispatch_secret
    ),
    body => '{}'::jsonb, timeout_milliseconds => 90000
  ) into v_request_id;
  return v_request_id;
end;
$$;

-- Operator opt-in only. The migration installs no scheduler and uses no Vault data.
create function private.portal_index_set_scheduler_v1(p_enabled boolean)
returns bigint
language plpgsql security definer set search_path = '' set lock_timeout = '5s'
as $$
declare
  v_config private.portal_index_config%rowtype;
  v_job record;
  v_job_name constant text := 'dispatch-portal-index-notifications-v1';
  v_schedule constant text := '* * * * *';
  v_command constant text := 'select private.portal_index_wake_v1();';
begin
  if p_enabled is null then
    raise invalid_parameter_value using message = 'invalid Portal index scheduler state';
  end if;
  select * into strict v_config from private.portal_index_config for update;
  select jobid, schedule, command, database, username, active into v_job
  from cron.job where jobname = v_job_name;
  if found and (v_job.schedule, v_job.command, v_job.database, v_job.username)
    is distinct from (v_schedule, v_command, current_database(), current_user::text) then
    raise object_not_in_prerequisite_state using message = 'Portal index scheduler job does not match';
  end if;
  if not p_enabled then
    if v_job.jobid is not null then perform cron.unschedule(v_job.jobid); end if;
    return v_job.jobid;
  end if;
  if not v_config.dispatch_enabled or v_config.maintenance_gap
    or private.portal_display_mode_v1() is distinct from 'display' then
    raise object_not_in_prerequisite_state using message = 'Portal index dispatch is disabled';
  end if;
  perform private.portal_display_assert_contract_v1();
  perform private.portal_index_scheduler_transport_v1();
  if v_job.jobid is null then
    return cron.schedule(v_job_name, v_schedule, v_command);
  end if;
  if not v_job.active then
    perform cron.alter_job(v_job.jobid, active => true);
  end if;
  return v_job.jobid;
end;
$$;

revoke all on function
  private.portal_index_configure_v1(text, text[], boolean, boolean),
  private.portal_display_index_gap_v1(),
  private.portal_display_index_same_timestamp_v1(),
  private.portal_index_was_latest_v1(text, uuid, text, text[], xid8),
  private.portal_index_enqueue_v1(text, uuid, text, text, text, xid8, text[]),
  private.portal_index_capture_config_v1(),
  private.portal_index_capture_v1(),
  private.portal_index_reconcile_maintenance_v1(integer),
  private.portal_index_candidates_v1(private.portal_index_outbox, text[]),
  private.portal_index_receipt_keys_v1(jsonb),
  private.portal_index_work_v1(private.portal_index_outbox),
  private.portal_index_requeue_v1(text, text, integer),
  private.portal_index_prune_v1(integer),
  private.portal_index_scheduler_transport_v1(),
  private.portal_index_wake_v1(),
  private.portal_index_set_scheduler_v1(boolean)
  from public, anon, authenticated, service_role;

revoke all on function
  api.svc_portal_index_claim_v1(text, text, text[], integer),
  api.svc_portal_index_recheck_v1(text, text, uuid),
  api.svc_portal_index_settle_v1(text, text, uuid, text, text, integer, jsonb),
  api.svc_portal_index_status_v1(),
  api.svc_portal_index_withdrawal_feed_v1(text, text[])
  from public, anon, authenticated, service_role;

grant execute on function
  api.svc_portal_index_claim_v1(text, text, text[], integer),
  api.svc_portal_index_recheck_v1(text, text, uuid),
  api.svc_portal_index_settle_v1(text, text, uuid, text, text, integer, jsonb),
  api.svc_portal_index_status_v1(),
  api.svc_portal_index_withdrawal_feed_v1(text, text[])
  to service_role;

insert into private.api_capability_grants
  (routine_identity, capability_id, allow_anon, allow_authenticated, allow_service_role)
values
  ('api.svc_portal_index_claim_v1(text, text, text[], integer)', 'PORTAL-INDEX-SVC-01', false, false, true),
  ('api.svc_portal_index_recheck_v1(text, text, uuid)', 'PORTAL-INDEX-SVC-01', false, false, true),
  ('api.svc_portal_index_settle_v1(text, text, uuid, text, text, integer, jsonb)', 'PORTAL-INDEX-SVC-01', false, false, true),
  ('api.svc_portal_index_status_v1()', 'PORTAL-INDEX-SVC-01', false, false, true),
  ('api.svc_portal_index_withdrawal_feed_v1(text, text[])', 'PORTAL-INDEX-SVC-01', false, false, true);

update private.portal_display_contract_manifest
set identity = private.portal_display_contract_identity_v1() where singleton;
select private.portal_display_assert_contract_v1();
notify pgrst, 'reload schema';
commit;
