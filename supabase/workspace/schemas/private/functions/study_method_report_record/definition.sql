CREATE OR REPLACE FUNCTION "private"."study_method_report_record"("p_id" "uuid") RETURNS "jsonb"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
 select(private.study_report_record(r.id)-'analysisIds')||jsonb_build_object('methodAssessmentIds',r.method_assessment_ids)
 from private.study_report_revisions r where r.id=p_id and r.template_id='lca.study-method-report.v1'$$;

ALTER FUNCTION "private"."study_method_report_record"("p_id" "uuid") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_method_report_record"("p_id" "uuid") FROM PUBLIC;
