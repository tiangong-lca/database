CREATE OR REPLACE FUNCTION "private"."study_report_record"("p_id" "uuid") RETURNS "jsonb"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
 select jsonb_build_object('reportRevisionId',r.id,'studyId',r.study_id,'parentReportRevisionId',r.parent_report_id,'authorId',r.author_id,'revision',r.revision,'status',r.status,
 'contentHash',r.content_hash,'runIds',r.run_ids,'analysisIds',r.analysis_ids,'factsRefs',r.facts_refs,'contentRef',a.ref,'templateId',r.template_id,
 'finalization',jsonb_build_object('status','not_finalized','profileId','lca.study-report-unreviewed.v1','reviewRequirement','none','finalizedAt',null,'reviewIds','[]'::jsonb),'validitySnapshot',private.study_report_validity_snapshot(r.study_id,r.run_ids,(r.validity_snapshot->>'checkedAt')::timestamptz))
 from private.study_report_revisions r join private.study_artifacts a on a.id=r.content_artifact_id where r.id=p_id
$$;

ALTER FUNCTION "private"."study_report_record"("p_id" "uuid") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_report_record"("p_id" "uuid") FROM PUBLIC;
