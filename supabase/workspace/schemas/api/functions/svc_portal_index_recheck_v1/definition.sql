CREATE OR REPLACE FUNCTION "api"."svc_portal_index_recheck_v1"("p_provider" "text", "p_event_id" "text", "p_lease_token" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    SET "statement_timeout" TO '5s'
    AS $_$
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
$_$;

ALTER FUNCTION "api"."svc_portal_index_recheck_v1"("p_provider" "text", "p_event_id" "text", "p_lease_token" "uuid") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."svc_portal_index_recheck_v1"("p_provider" "text", "p_event_id" "text", "p_lease_token" "uuid") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."svc_portal_index_recheck_v1"("p_provider" "text", "p_event_id" "text", "p_lease_token" "uuid") TO "service_role";
