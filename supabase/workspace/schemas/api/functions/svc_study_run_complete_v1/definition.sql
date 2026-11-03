CREATE OR REPLACE FUNCTION "api"."svc_study_run_complete_v1"("p_run_id" "uuid", "p_job_id" "uuid", "p_lease_token" "uuid", "p_completion" "jsonb", "p_idempotency_key" "text") RETURNS "jsonb"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$ select private.study_complete('run',p_run_id,p_job_id,p_lease_token,p_completion,p_idempotency_key) $$;

ALTER FUNCTION "api"."svc_study_run_complete_v1"("p_run_id" "uuid", "p_job_id" "uuid", "p_lease_token" "uuid", "p_completion" "jsonb", "p_idempotency_key" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."svc_study_run_complete_v1"("p_run_id" "uuid", "p_job_id" "uuid", "p_lease_token" "uuid", "p_completion" "jsonb", "p_idempotency_key" "text") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."svc_study_run_complete_v1"("p_run_id" "uuid", "p_job_id" "uuid", "p_lease_token" "uuid", "p_completion" "jsonb", "p_idempotency_key" "text") TO "service_role";
