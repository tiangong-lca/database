CREATE OR REPLACE FUNCTION "private"."portal_index_configure_v1"("p_origin" "text", "p_allowed_brands" "text"[], "p_capture_enabled" boolean, "p_dispatch_enabled" boolean) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    SET "lock_timeout" TO '5s'
    AS $_$
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
$_$;

ALTER FUNCTION "private"."portal_index_configure_v1"("p_origin" "text", "p_allowed_brands" "text"[], "p_capture_enabled" boolean, "p_dispatch_enabled" boolean) OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."portal_index_configure_v1"("p_origin" "text", "p_allowed_brands" "text"[], "p_capture_enabled" boolean, "p_dispatch_enabled" boolean) FROM PUBLIC;
