CREATE OR REPLACE FUNCTION "private"."worker_cancel_job"("p_job_id" "uuid", "p_cancelled_by" "uuid" DEFAULT NULL::"uuid", "p_reason" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'private', 'api', 'public', 'util', 'extensions', 'pg_temp'
    AS $$
declare
  v_job private.worker_jobs%rowtype;
begin
  if not private.study_generic_job_allowed(null,p_job_id,'cancel') then return jsonb_build_object('ok',false,'code','STUDY_SCOPED_ROUTE_REQUIRED','status',403,'message','Study task requires scoped authorization'); end if;
  if not coalesce(util.is_service_request(), false) then
    return jsonb_build_object(
      'ok', false,
      'code', 'SERVICE_ROLE_REQUIRED',
      'status', 403,
      'message', 'Service role is required to cancel worker jobs'
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

  if v_job.status in ('completed', 'blocked', 'failed') then
    return jsonb_build_object(
      'ok', false,
      'code', 'WORKER_JOB_TERMINAL',
      'status', 409,
      'message', 'Completed, blocked, and failed worker jobs cannot be cancelled'
    );
  end if;

  if v_job.status = 'cancelled' then
    return jsonb_build_object(
      'ok', true,
      'data', private.worker_job_payload(v_job, true)
    );
  end if;

  update private.worker_jobs
    set status = 'cancelled',
        cancelled_at = now(),
        cancelled_by = p_cancelled_by,
        leased_by = null,
        lease_token = null,
        lease_expires_at = null,
        error_code = 'worker_job_cancelled',
        error_message = coalesce(nullif(trim(p_reason), ''), 'Worker job was cancelled'),
        updated_at = now(),
        finished_at = now()
  where id = v_job.id
  returning *
    into v_job;

  insert into private.worker_job_events (
    job_id,
    event_type,
    status,
    message,
    details
  ) values (
    v_job.id,
    'cancelled',
    v_job.status,
    p_reason,
    jsonb_build_object('cancelledBy', p_cancelled_by)
  );

  return jsonb_build_object(
    'ok', true,
    'data', private.worker_job_payload(v_job, true)
  );
end;
$$;

ALTER FUNCTION "private"."worker_cancel_job"("p_job_id" "uuid", "p_cancelled_by" "uuid", "p_reason" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."worker_cancel_job"("p_job_id" "uuid", "p_cancelled_by" "uuid", "p_reason" "text") FROM PUBLIC;

GRANT ALL ON FUNCTION "private"."worker_cancel_job"("p_job_id" "uuid", "p_cancelled_by" "uuid", "p_reason" "text") TO "service_role";

GRANT ALL ON FUNCTION "private"."worker_cancel_job"("p_job_id" "uuid", "p_cancelled_by" "uuid", "p_reason" "text") TO "api_internal_executor";
