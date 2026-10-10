CREATE OR REPLACE FUNCTION "private"."display_support_capabilities_v1"("p_kind" "text", "p_state_code" integer) RETURNS "jsonb"
    LANGUAGE "sql" IMMUTABLE PARALLEL SAFE
    SET "search_path" TO ''
    AS $$
  select jsonb_build_object(
    'exchangesVisible', p_kind in ('flow', 'flowproperty', 'unitgroup'),
    'policyVersion', 'portal-display-capability-policy.v2',
    'reasonCodes', jsonb_build_array('display_settings_enabled')
  )
$$;

ALTER FUNCTION "private"."display_support_capabilities_v1"("p_kind" "text", "p_state_code" integer) OWNER TO "portal_display_executor";

REVOKE ALL ON FUNCTION "private"."display_support_capabilities_v1"("p_kind" "text", "p_state_code" integer) FROM PUBLIC;

GRANT ALL ON FUNCTION "private"."display_support_capabilities_v1"("p_kind" "text", "p_state_code" integer) TO "postgres";
