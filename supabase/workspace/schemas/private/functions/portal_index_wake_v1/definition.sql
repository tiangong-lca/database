CREATE OR REPLACE FUNCTION "private"."portal_index_wake_v1"() RETURNS bigint
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    SET "statement_timeout" TO '5s'
    AS $$
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

ALTER FUNCTION "private"."portal_index_wake_v1"() OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."portal_index_wake_v1"() FROM PUBLIC;
