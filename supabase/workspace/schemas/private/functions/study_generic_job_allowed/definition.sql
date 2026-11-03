CREATE OR REPLACE FUNCTION "private"."study_generic_job_allowed"("p_kind" "text", "p_job" "uuid", "p_action" "text") RETURNS boolean
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$ declare kind text:=p_kind; begin
  if kind is null and p_job is not null then select job_kind into kind from private.worker_jobs where id=p_job; end if;
  -- Match the canonical enqueuer's normalization before classifying its route.
  kind:=lower(trim(kind));
  return kind is null or kind not like 'study.%' or coalesce(current_setting('app.study.task_context',true)=p_action,false);
end $$;

ALTER FUNCTION "private"."study_generic_job_allowed"("p_kind" "text", "p_job" "uuid", "p_action" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_generic_job_allowed"("p_kind" "text", "p_job" "uuid", "p_action" "text") FROM PUBLIC;
