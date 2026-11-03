CREATE OR REPLACE FUNCTION "api"."cmd_study_v1"("p_request" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$ begin
  if p_request->>'operation'='task.cancel' then return private.study_task_control(p_request); end if;
  if p_request->>'operation' in ('model.source.resolve','model.prepare','run.submit','run.cancel') then return private.study_task_command(p_request); end if;
  return private.study_cmd_core_v1(p_request);
end $$;

ALTER FUNCTION "api"."cmd_study_v1"("p_request" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."cmd_study_v1"("p_request" "jsonb") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."cmd_study_v1"("p_request" "jsonb") TO "authenticated";
