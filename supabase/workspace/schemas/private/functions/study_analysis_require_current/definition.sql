CREATE OR REPLACE FUNCTION "private"."study_analysis_require_current"("p_study" "uuid", "p_config" "jsonb") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$begin
 perform private.study_require(not exists(select 1 from jsonb_array_elements_text(p_config->'runIds')e(id)
  left join private.study_runs r on r.study_id=p_study and r.id=e.id::uuid where r.id is null or r.validity<>'current'),'CAPABILITY_UNAVAILABLE');
end $$;

ALTER FUNCTION "private"."study_analysis_require_current"("p_study" "uuid", "p_config" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_analysis_require_current"("p_study" "uuid", "p_config" "jsonb") FROM PUBLIC;
