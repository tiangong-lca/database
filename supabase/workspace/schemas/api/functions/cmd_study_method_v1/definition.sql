CREATE OR REPLACE FUNCTION "api"."cmd_study_method_v1"("p_request" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$begin
 perform private.study_method_envelope(p_request,true);perform private.study_require(private.study_client_allowed(nullif(auth.jwt()->>'client_id',''),'STUDY-WRITE-01'),'FORBIDDEN');
 case p_request->>'operation'
 when 'method.assessment.request' then return private.study_method_request(p_request);
 when 'method.evidence.create' then return private.study_method_evidence_create(p_request);
 when 'task.cancel' then return private.study_method_task(p_request);
 when 'report.create','report.save','report.freeze' then return private.study_method_report_command(p_request);
 else return jsonb_build_object('ok',false,'code','CAPABILITY_UNAVAILABLE');end case;
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);end$$;

ALTER FUNCTION "api"."cmd_study_method_v1"("p_request" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."cmd_study_method_v1"("p_request" "jsonb") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."cmd_study_method_v1"("p_request" "jsonb") TO "authenticated";
