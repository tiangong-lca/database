CREATE OR REPLACE FUNCTION "private"."study_lock_job"("p_study" "uuid", "p_job" "uuid", "p_token" "uuid", "p_kind" "text", "p_subject" "text", "p_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare j private.worker_jobs%rowtype;
begin
  perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');
  perform 1 from private.studies where id=p_study for update;
  perform private.study_require(found,'REFERENCE_MISMATCH');
  select * into j from private.worker_jobs where id=p_job for update;
  perform private.study_require(found and j.job_kind=p_kind and j.worker_runtime='calculator'
    and j.payload_json->>'studyId'=p_study::text and j.payload_json->>p_subject=p_id::text,'REFERENCE_MISMATCH');
  perform private.study_require(j.status='running' and j.lease_token=p_token and j.lease_expires_at>clock_timestamp(),'FORBIDDEN');
end $$;

ALTER FUNCTION "private"."study_lock_job"("p_study" "uuid", "p_job" "uuid", "p_token" "uuid", "p_kind" "text", "p_subject" "text", "p_id" "uuid") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_lock_job"("p_study" "uuid", "p_job" "uuid", "p_token" "uuid", "p_kind" "text", "p_subject" "text", "p_id" "uuid") FROM PUBLIC;
