CREATE OR REPLACE FUNCTION "private"."study_report_validation_check"("p_validation" "jsonb", "p_report" "uuid", "p_hash" "text", "p_count" integer, "p_refs" "jsonb") RETURNS "void"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$begin
 perform private.study_require(private.study_keys(p_validation,array['schemaVersion','profileId','reportRevisionId','contentHash','claimCount','factsBindingHash'])
 and p_validation->>'schemaVersion'='lca.study-report-validation.v1' and p_validation->>'profileId'='lca.study-report-claims.v1'
 and p_validation->>'reportRevisionId'=p_report::text and p_validation->>'contentHash'=p_hash
 and jsonb_typeof(p_validation->'claimCount')='number' and (p_validation->>'claimCount')::numeric=p_count
 and p_validation->>'factsBindingHash'=private.study_reporting_digest('lca.study-report-facts-binding.v1',p_refs),'REFERENCE_MISMATCH');
end$$;

ALTER FUNCTION "private"."study_report_validation_check"("p_validation" "jsonb", "p_report" "uuid", "p_hash" "text", "p_count" integer, "p_refs" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_report_validation_check"("p_validation" "jsonb", "p_report" "uuid", "p_hash" "text", "p_count" integer, "p_refs" "jsonb") FROM PUBLIC;
