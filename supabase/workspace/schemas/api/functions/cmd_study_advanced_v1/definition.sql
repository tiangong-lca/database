CREATE OR REPLACE FUNCTION "api"."cmd_study_advanced_v1"("p_request" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$begin
 perform private.study_advanced_envelope(p_request,true);perform private.study_require(private.study_client_allowed(nullif(auth.jwt()->>'client_id',''),'STUDY-WRITE-01'),'FORBIDDEN');
 case p_request->>'operation' when 'analysis.request' then return private.study_advanced_request(p_request);
 when 'task.cancel' then return private.study_advanced_task(p_request);
 when 'report.create','report.save','report.freeze' then return private.study_report_advanced_command(p_request);
 else return jsonb_build_object('ok',false,'code','CAPABILITY_UNAVAILABLE');end case;
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);end$$;

ALTER FUNCTION "api"."cmd_study_advanced_v1"("p_request" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."cmd_study_advanced_v1"("p_request" "jsonb") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."cmd_study_advanced_v1"("p_request" "jsonb") TO "authenticated";
