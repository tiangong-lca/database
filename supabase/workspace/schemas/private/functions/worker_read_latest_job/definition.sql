CREATE OR REPLACE FUNCTION "private"."worker_read_latest_job"("p_requested_by" "uuid" DEFAULT NULL::"uuid", "p_subject_type" "text" DEFAULT NULL::"text", "p_subject_id" "uuid" DEFAULT NULL::"uuid", "p_subject_version" "text" DEFAULT NULL::"text", "p_job_kind" "text" DEFAULT NULL::"text", "p_statuses" "text"[] DEFAULT NULL::"text"[], "p_include_internal" boolean DEFAULT false) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'private', 'api', 'public', 'util', 'extensions', 'pg_temp'
    AS $$
declare
  v_subject_type text := nullif(trim(p_subject_type), '');
  v_subject_version text := nullif(trim(p_subject_version), '');
  v_job_kind text := nullif(lower(trim(p_job_kind)), '');
  v_job private.worker_jobs%rowtype;
begin
  if not coalesce(util.is_service_request(), false) then
    return jsonb_build_object(
      'ok', false,
      'code', 'SERVICE_ROLE_REQUIRED',
      'status', 403,
      'message', 'Service role is required to read worker jobs'
    );
  end if;

  if p_statuses is not null
    and exists (
      select 1
      from unnest(p_statuses) as status_value
      where status_value not in (
        'queued',
        'running',
        'waiting',
        'completed',
        'blocked',
        'stale',
        'failed',
        'cancelled'
      )
    ) then
    return jsonb_build_object(
      'ok', false,
      'code', 'INVALID_WORKER_JOB_STATUS',
      'status', 400,
      'message', 'statuses contains an unsupported worker job status'
    );
  end if;

  select *
    into v_job
  from private.worker_jobs
  where job_kind not like 'study.%' and (p_requested_by is null or requested_by = p_requested_by)
    and (v_subject_type is null or subject_type = v_subject_type)
    and (p_subject_id is null or subject_id = p_subject_id)
    and (v_subject_version is null or subject_version = v_subject_version)
    and (v_job_kind is null or job_kind = v_job_kind)
    and (p_statuses is null or status = any(p_statuses))
  order by updated_at desc, created_at desc
  limit 1;

  return jsonb_build_object(
    'ok', true,
    'data', case
      when v_job.id is null then null
      else private.worker_job_payload(v_job, p_include_internal)
    end
  );
end;
$$;

ALTER FUNCTION "private"."worker_read_latest_job"("p_requested_by" "uuid", "p_subject_type" "text", "p_subject_id" "uuid", "p_subject_version" "text", "p_job_kind" "text", "p_statuses" "text"[], "p_include_internal" boolean) OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."worker_read_latest_job"("p_requested_by" "uuid", "p_subject_type" "text", "p_subject_id" "uuid", "p_subject_version" "text", "p_job_kind" "text", "p_statuses" "text"[], "p_include_internal" boolean) FROM PUBLIC;

GRANT ALL ON FUNCTION "private"."worker_read_latest_job"("p_requested_by" "uuid", "p_subject_type" "text", "p_subject_id" "uuid", "p_subject_version" "text", "p_job_kind" "text", "p_statuses" "text"[], "p_include_internal" boolean) TO "service_role";

GRANT ALL ON FUNCTION "private"."worker_read_latest_job"("p_requested_by" "uuid", "p_subject_type" "text", "p_subject_id" "uuid", "p_subject_version" "text", "p_job_kind" "text", "p_statuses" "text"[], "p_include_internal" boolean) TO "api_internal_executor";
