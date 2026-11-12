CREATE OR REPLACE FUNCTION "api"."svc_portal_index_status_v1"() RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    SET "statement_timeout" TO '5s'
    AS $$
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

ALTER FUNCTION "api"."svc_portal_index_status_v1"() OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."svc_portal_index_status_v1"() FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."svc_portal_index_status_v1"() TO "service_role";
