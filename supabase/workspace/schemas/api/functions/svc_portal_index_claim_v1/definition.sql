CREATE OR REPLACE FUNCTION "api"."svc_portal_index_claim_v1"("p_provider" "text", "p_origin" "text", "p_allowed_brands" "text"[], "p_limit" integer) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    SET "statement_timeout" TO '5s'
    AS $$
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

ALTER FUNCTION "api"."svc_portal_index_claim_v1"("p_provider" "text", "p_origin" "text", "p_allowed_brands" "text"[], "p_limit" integer) OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."svc_portal_index_claim_v1"("p_provider" "text", "p_origin" "text", "p_allowed_brands" "text"[], "p_limit" integer) FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."svc_portal_index_claim_v1"("p_provider" "text", "p_origin" "text", "p_allowed_brands" "text"[], "p_limit" integer) TO "service_role";
