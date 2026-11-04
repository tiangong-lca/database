CREATE OR REPLACE FUNCTION "private"."study_advanced_lock_job"("p_study" "uuid", "p_job" "uuid", "p_token" "uuid", "p_analysis" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$begin
 perform private.study_lock_job(p_study,p_job,p_token,'study.analysis_advanced','analysisId',p_analysis);
 perform private.study_require(exists(select 1 from private.worker_jobs j join private.study_advanced_analyses a on a.job_id=j.id
 where a.id=p_analysis and a.study_id=p_study and j.id=p_job and j.subject_type='study' and j.subject_id=p_analysis and j.worker_queue='solver'
 and j.payload_schema_version='study.analysis_advanced.request.v1' and j.requested_by=a.requested_by
 and j.payload_json=jsonb_build_object('schemaVersion','study.analysis_advanced.request.v1','studyId',p_study,'analysisId',p_analysis)),'REFERENCE_MISMATCH');
end$$;

ALTER FUNCTION "private"."study_advanced_lock_job"("p_study" "uuid", "p_job" "uuid", "p_token" "uuid", "p_analysis" "uuid") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_advanced_lock_job"("p_study" "uuid", "p_job" "uuid", "p_token" "uuid", "p_analysis" "uuid") FROM PUBLIC;
