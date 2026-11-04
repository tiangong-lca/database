CREATE OR REPLACE FUNCTION "private"."study_method_report_artifact_authorize"("p_study" "uuid", "p_ref" "jsonb", "p_actor" "uuid", "p_client" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$declare r private.study_report_revisions%rowtype;begin
 select * into r from private.study_report_revisions where study_id=p_study and template_id='lca.study-method-report.v1' and content_artifact_id=(p_ref->>'id')::uuid;
 perform private.study_require(found,'DISCLOSURE_DENIED');perform private.study_method_report_rights(p_study,r.run_ids,r.method_assessment_ids,p_actor,p_client);
end$$;

ALTER FUNCTION "private"."study_method_report_artifact_authorize"("p_study" "uuid", "p_ref" "jsonb", "p_actor" "uuid", "p_client" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_method_report_artifact_authorize"("p_study" "uuid", "p_ref" "jsonb", "p_actor" "uuid", "p_client" "text") FROM PUBLIC;
