CREATE OR REPLACE FUNCTION "private"."study_method_report_validation_check"("p_validation" "jsonb", "p_report" "uuid", "p_hash" "text", "p_count" integer, "p_binding" "text", "p_assessment" "uuid", "p_config_hash" "text") RETURNS "void"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$begin
 perform private.study_require(private.study_keys(p_validation,array['schemaVersion','profileId','reportRevisionId','contentHash','claimCount','factsBindingHash','methodAssessmentId','configHash','requirementCount','categoryCount','factCount'])
 and p_validation->>'schemaVersion'='lca.study-method-report-validation.v1'and p_validation->>'profileId'='lca.study-method-report-claims.v1'
 and p_validation->>'reportRevisionId'=p_report::text and p_validation->>'contentHash'=p_hash and private.study_method_uint(p_validation->'claimCount',1,256)and(p_validation->>'claimCount')::integer=p_count
 and p_validation->>'factsBindingHash'=p_binding and p_validation->>'methodAssessmentId'=p_assessment::text and p_validation->>'configHash'=p_config_hash
 and private.study_method_uint(p_validation->'requirementCount',20,20)and private.study_method_uint(p_validation->'categoryCount',25,25)and private.study_method_uint(p_validation->'factCount',58,58),'REFERENCE_MISMATCH');
end$$;

ALTER FUNCTION "private"."study_method_report_validation_check"("p_validation" "jsonb", "p_report" "uuid", "p_hash" "text", "p_count" integer, "p_binding" "text", "p_assessment" "uuid", "p_config_hash" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_method_report_validation_check"("p_validation" "jsonb", "p_report" "uuid", "p_hash" "text", "p_count" integer, "p_binding" "text", "p_assessment" "uuid", "p_config_hash" "text") FROM PUBLIC;
