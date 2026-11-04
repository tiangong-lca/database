CREATE OR REPLACE FUNCTION "private"."study_method_record"("p_id" "uuid") RETURNS "jsonb"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
 select jsonb_build_object('assessmentId',a.id,'studyId',a.study_id,'profileId',a.profile_id,'config',a.config,'configHash',a.config_hash,
 'execution',jsonb_build_object('jobId',a.job_id,'status',j.status),'factsRef',case when j.status='completed' then f.ref else null end)
 from private.study_method_assessments a join private.worker_jobs j on j.id=a.job_id left join private.study_artifacts f on f.id=a.facts_artifact_id where a.id=p_id$$;

ALTER FUNCTION "private"."study_method_record"("p_id" "uuid") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_method_record"("p_id" "uuid") FROM PUBLIC;
