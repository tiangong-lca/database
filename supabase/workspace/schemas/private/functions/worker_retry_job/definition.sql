CREATE OR REPLACE FUNCTION "private"."worker_retry_job"("p_job_id" "uuid", "p_run_after" timestamp with time zone DEFAULT NULL::timestamp with time zone, "p_max_attempts" integer DEFAULT NULL::integer, "p_reason" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'private', 'api', 'public', 'util', 'extensions', 'pg_temp'
    AS $$
declare
  v_job private.worker_jobs%rowtype;
  v_retry_at timestamptz;
begin
  if not private.study_generic_job_allowed(null,p_job_id,'retry') then return jsonb_build_object('ok',false,'code','STUDY_SCOPED_ROUTE_REQUIRED','status',403,'message','Study task requires scoped authorization'); end if;
  if not coalesce(util.is_service_request(), false) then
    return jsonb_build_object(
      'ok', false,
      'code', 'SERVICE_ROLE_REQUIRED',
      'status', 403,
      'message', 'Service role is required to retry worker jobs'
    );
  end if;

  select *
    into v_job
  from private.worker_jobs
  where id = p_job_id
  for update;

  if v_job.id is null then
    return jsonb_build_object(
      'ok', false,
      'code', 'WORKER_JOB_NOT_FOUND',
      'status', 404,
      'message', 'Worker job not found'
    );
  end if;

  if v_job.status not in ('failed', 'blocked', 'stale', 'waiting', 'cancelled') then
    return jsonb_build_object(
      'ok', false,
      'code', 'WORKER_JOB_NOT_RETRYABLE',
      'status', 409,
      'message', 'Worker job is not in a retryable status'
    );
  end if;

  -- A retry may have waited for its row lock across the admission deadline.
  v_retry_at := clock_timestamp();
  if v_job.job_kind = 'ai.tidas_suggestion'
    and v_job.timeout_at is not null and v_job.timeout_at <= v_retry_at then
    return jsonb_build_object(
      'ok', false, 'code', 'WORKER_JOB_DEADLINE_EXPIRED', 'status', 409,
      'message', 'Expired AI suggestions require a new request'
    );
  end if;

  update private.worker_jobs
    set status = 'queued',
        run_after = coalesce(p_run_after, case when v_job.job_kind = 'ai.tidas_suggestion'
          then v_retry_at else now() end),
        attempt_count = 0,
        max_attempts = greatest(1, coalesce(p_max_attempts, max_attempts)),
        leased_by = null,
        lease_token = null,
        lease_expires_at = null,
        diagnostics = '{}'::jsonb,
        error_code = null,
        error_message = null,
        error_details = null,
        blocker_codes = '{}'::text[],
        resolution_scope = null,
        retryable = null,
        cancelled_at = null,
        cancelled_by = null,
        finished_at = null,
        updated_at = case when v_job.job_kind = 'ai.tidas_suggestion'
          then v_retry_at else now() end
  where id = v_job.id
  returning *
    into v_job;

  insert into private.worker_job_events (
    job_id,
    event_type,
    status,
    message,
    details,
    created_at
  ) values (
    v_job.id,
    'retried',
    v_job.status,
    p_reason,
    jsonb_build_object('runAfter', v_job.run_after),
    case when v_job.job_kind = 'ai.tidas_suggestion' then v_retry_at else now() end
  );

  return jsonb_build_object(
    'ok', true,
    'data', private.worker_job_payload(v_job, true)
  );
end;
$$;

ALTER FUNCTION "private"."worker_retry_job"("p_job_id" "uuid", "p_run_after" timestamp with time zone, "p_max_attempts" integer, "p_reason" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."worker_retry_job"("p_job_id" "uuid", "p_run_after" timestamp with time zone, "p_max_attempts" integer, "p_reason" "text") FROM PUBLIC;

GRANT ALL ON FUNCTION "private"."worker_retry_job"("p_job_id" "uuid", "p_run_after" timestamp with time zone, "p_max_attempts" integer, "p_reason" "text") TO "service_role";

GRANT ALL ON FUNCTION "private"."worker_retry_job"("p_job_id" "uuid", "p_run_after" timestamp with time zone, "p_max_attempts" integer, "p_reason" "text") TO "api_internal_executor";
