CREATE OR REPLACE FUNCTION "api"."svc_study_run_read_input_v1"("p_run_id" "uuid", "p_job_id" "uuid", "p_lease_token" "uuid") RETURNS "jsonb"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$ select private.study_read_worker_input('run',p_run_id,p_job_id,p_lease_token) $$;

ALTER FUNCTION "api"."svc_study_run_read_input_v1"("p_run_id" "uuid", "p_job_id" "uuid", "p_lease_token" "uuid") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."svc_study_run_read_input_v1"("p_run_id" "uuid", "p_job_id" "uuid", "p_lease_token" "uuid") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."svc_study_run_read_input_v1"("p_run_id" "uuid", "p_job_id" "uuid", "p_lease_token" "uuid") TO "service_role";
