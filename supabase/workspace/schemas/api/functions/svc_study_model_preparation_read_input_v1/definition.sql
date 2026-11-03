CREATE OR REPLACE FUNCTION "api"."svc_study_model_preparation_read_input_v1"("p_preparation_id" "uuid", "p_job_id" "uuid", "p_lease_token" "uuid") RETURNS "jsonb"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$ select private.study_read_worker_input('modelPreparation',p_preparation_id,p_job_id,p_lease_token) $$;

ALTER FUNCTION "api"."svc_study_model_preparation_read_input_v1"("p_preparation_id" "uuid", "p_job_id" "uuid", "p_lease_token" "uuid") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."svc_study_model_preparation_read_input_v1"("p_preparation_id" "uuid", "p_job_id" "uuid", "p_lease_token" "uuid") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."svc_study_model_preparation_read_input_v1"("p_preparation_id" "uuid", "p_job_id" "uuid", "p_lease_token" "uuid") TO "service_role";
