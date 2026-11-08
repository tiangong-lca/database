CREATE OR REPLACE FUNCTION "private"."cmd_lcia_result_build_request_legacy"("p_name" "text", "p_processes" "jsonb" DEFAULT NULL::"jsonb", "p_coverage_mode" "text" DEFAULT 'global_eligible'::"text", "p_default_impact_category" "text" DEFAULT NULL::"text", "p_lcia_method_set" "jsonb" DEFAULT '[]'::"jsonb", "p_idempotency_key" "text" DEFAULT NULL::"text", "p_audit" "jsonb" DEFAULT '{}'::"jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'private', 'api', 'public', 'util', 'extensions', 'pg_temp'
    AS $$
begin
  return private.lcia_result_build_request_envelope(
    p_name, p_processes, p_coverage_mode, p_default_impact_category,
    p_lcia_method_set, p_idempotency_key, p_audit, null
  );
end;
$$;

ALTER FUNCTION "private"."cmd_lcia_result_build_request_legacy"("p_name" "text", "p_processes" "jsonb", "p_coverage_mode" "text", "p_default_impact_category" "text", "p_lcia_method_set" "jsonb", "p_idempotency_key" "text", "p_audit" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."cmd_lcia_result_build_request_legacy"("p_name" "text", "p_processes" "jsonb", "p_coverage_mode" "text", "p_default_impact_category" "text", "p_lcia_method_set" "jsonb", "p_idempotency_key" "text", "p_audit" "jsonb") FROM PUBLIC;

GRANT ALL ON FUNCTION "private"."cmd_lcia_result_build_request_legacy"("p_name" "text", "p_processes" "jsonb", "p_coverage_mode" "text", "p_default_impact_category" "text", "p_lcia_method_set" "jsonb", "p_idempotency_key" "text", "p_audit" "jsonb") TO "api_internal_executor";
