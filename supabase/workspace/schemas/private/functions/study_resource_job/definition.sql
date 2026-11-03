CREATE OR REPLACE FUNCTION "private"."study_resource_job"("p_study" "uuid", "p_type" "text", "p_id" "uuid") RETURNS "uuid"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$ declare job uuid; begin
  case p_type
    when 'modelSourceAcquisition' then select job_id into job from private.study_source_acquisitions where study_id=p_study and id=p_id;
    when 'modelPreparation' then select job_id into job from private.study_model_preparations where study_id=p_study and id=p_id;
    when 'run' then select job_id into job from private.study_runs where study_id=p_study and id=p_id;
    else perform private.study_require(false,'INVALID_REQUEST');
  end case;
  perform private.study_require(job is not null,'FORBIDDEN'); return job;
end $$;

ALTER FUNCTION "private"."study_resource_job"("p_study" "uuid", "p_type" "text", "p_id" "uuid") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_resource_job"("p_study" "uuid", "p_type" "text", "p_id" "uuid") FROM PUBLIC;
