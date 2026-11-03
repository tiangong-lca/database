CREATE OR REPLACE FUNCTION "api"."cmd_study_reporting_v1"("p_request" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$begin
 if p_request->>'operation'='analysis.request' then return private.study_analysis_request(p_request);end if;
 if p_request->>'operation'='task.cancel' then return private.study_reporting_task(p_request);end if;
 if p_request->>'operation' in ('report.create','report.save','report.freeze','export.request') then return private.study_report_command(p_request);end if;
 return jsonb_build_object('ok',false,'code','CAPABILITY_UNAVAILABLE');
exception when invalid_text_representation or invalid_parameter_value or numeric_value_out_of_range then return jsonb_build_object('ok',false,'code','INVALID_REQUEST');
end$$;

ALTER FUNCTION "api"."cmd_study_reporting_v1"("p_request" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."cmd_study_reporting_v1"("p_request" "jsonb") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."cmd_study_reporting_v1"("p_request" "jsonb") TO "authenticated";
