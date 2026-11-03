CREATE OR REPLACE FUNCTION "private"."worker_list_jobs"("p_requested_by" "uuid" DEFAULT NULL::"uuid", "p_subject_type" "text" DEFAULT NULL::"text", "p_subject_id" "uuid" DEFAULT NULL::"uuid", "p_statuses" "text"[] DEFAULT NULL::"text"[], "p_visibility" "text" DEFAULT NULL::"text", "p_limit" integer DEFAULT 50, "p_include_internal" boolean DEFAULT false) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'private', 'api', 'public', 'util', 'extensions', 'pg_temp'
    AS $$
declare
  v_limit integer := greatest(1, least(coalesce(p_limit, 50), 200));
  v_jobs jsonb := '[]'::jsonb;
begin
  if not coalesce(util.is_service_request(), false) then
    return jsonb_build_object(
      'ok', false,
      'code', 'SERVICE_ROLE_REQUIRED',
      'status', 403,
      'message', 'Service role is required to list worker jobs'
    );
  end if;

  if p_visibility is not null and p_visibility not in ('user', 'operator', 'system') then
    return jsonb_build_object(
      'ok', false,
      'code', 'INVALID_WORKER_JOB_VISIBILITY',
      'status', 400,
      'message', 'visibility must be user, operator, or system'
    );
  end if;

  select coalesce(jsonb_agg(private.worker_job_payload(j, p_include_internal) order by j.updated_at desc), '[]'::jsonb)
    into v_jobs
  from (
    select *
    from private.worker_jobs
    where job_kind not like 'study.%'
      and (p_requested_by is null or requested_by = p_requested_by)
      and (p_subject_type is null or subject_type = p_subject_type)
      and (p_subject_id is null or subject_id = p_subject_id)
      and (p_visibility is null or visibility = p_visibility)
      and (p_statuses is null or status = any(p_statuses))
    order by updated_at desc
    limit v_limit
  ) as j;

  return jsonb_build_object(
    'ok', true,
    'data', v_jobs
  );
end;
$$;

ALTER FUNCTION "private"."worker_list_jobs"("p_requested_by" "uuid", "p_subject_type" "text", "p_subject_id" "uuid", "p_statuses" "text"[], "p_visibility" "text", "p_limit" integer, "p_include_internal" boolean) OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."worker_list_jobs"("p_requested_by" "uuid", "p_subject_type" "text", "p_subject_id" "uuid", "p_statuses" "text"[], "p_visibility" "text", "p_limit" integer, "p_include_internal" boolean) FROM PUBLIC;

GRANT ALL ON FUNCTION "private"."worker_list_jobs"("p_requested_by" "uuid", "p_subject_type" "text", "p_subject_id" "uuid", "p_statuses" "text"[], "p_visibility" "text", "p_limit" integer, "p_include_internal" boolean) TO "service_role";

GRANT ALL ON FUNCTION "private"."worker_list_jobs"("p_requested_by" "uuid", "p_subject_type" "text", "p_subject_id" "uuid", "p_statuses" "text"[], "p_visibility" "text", "p_limit" integer, "p_include_internal" boolean) TO "api_internal_executor";
