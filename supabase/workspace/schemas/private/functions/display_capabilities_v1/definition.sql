CREATE OR REPLACE FUNCTION "private"."display_capabilities_v1"("p_kind" "text", "p_state_code" integer, "p_json" "jsonb") RETURNS "jsonb"
    LANGUAGE "sql" STABLE PARALLEL SAFE
    SET "search_path" TO ''
    AS $$
  -- Internal DTO builder, not an admission check. Callers enforce exact settings,
  -- root brand scope and reference integrity; LCIA decorators enforce publication.
  -- License, exclusive access and access restrictions are descriptive metadata.
  select jsonb_build_object(
    'metadataVisible', true,
    'exchangesVisible', true,
    'lciaVisible', false,
    'publicArtifactVisible', false,
    'citationVisible', true,
    'policyVersion', 'portal-display-capability-policy.v2',
    'reasonCodes', jsonb_build_array('display_settings_enabled')
  )
$$;

ALTER FUNCTION "private"."display_capabilities_v1"("p_kind" "text", "p_state_code" integer, "p_json" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."display_capabilities_v1"("p_kind" "text", "p_state_code" integer, "p_json" "jsonb") FROM PUBLIC;

GRANT ALL ON FUNCTION "private"."display_capabilities_v1"("p_kind" "text", "p_state_code" integer, "p_json" "jsonb") TO "portal_display_executor";
