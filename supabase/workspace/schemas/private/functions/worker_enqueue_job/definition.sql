CREATE OR REPLACE FUNCTION "private"."worker_enqueue_job"("p_job_kind" "text", "p_payload_json" "jsonb" DEFAULT '{}'::"jsonb", "p_payload_schema_version" "text" DEFAULT NULL::"text", "p_subject_type" "text" DEFAULT NULL::"text", "p_subject_id" "uuid" DEFAULT NULL::"uuid", "p_subject_version" "text" DEFAULT NULL::"text", "p_requested_by" "uuid" DEFAULT NULL::"uuid", "p_requester_type" "text" DEFAULT 'user'::"text", "p_team_id" "uuid" DEFAULT NULL::"uuid", "p_idempotency_key" "text" DEFAULT NULL::"text", "p_request_hash" "text" DEFAULT NULL::"text", "p_concurrency_key" "text" DEFAULT NULL::"text", "p_priority" integer DEFAULT NULL::integer, "p_queue_key" "text" DEFAULT NULL::"text", "p_run_after" timestamp with time zone DEFAULT NULL::timestamp with time zone, "p_visibility" "text" DEFAULT NULL::"text", "p_max_attempts" integer DEFAULT NULL::integer, "p_timeout_at" timestamp with time zone DEFAULT NULL::timestamp with time zone, "p_payload_ref" "jsonb" DEFAULT NULL::"jsonb", "p_parent_job_id" "uuid" DEFAULT NULL::"uuid", "p_root_job_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'private', 'api', 'public', 'util', 'extensions', 'pg_temp'
    AS $$
declare
  v_job_kind text := lower(trim(coalesce(p_job_kind, '')));
  v_requester_type text := lower(trim(coalesce(p_requester_type, 'user')));
  v_kind private.worker_job_kinds%rowtype;
  v_existing private.worker_jobs%rowtype;
  v_job private.worker_jobs%rowtype;
  v_payload jsonb := coalesce(p_payload_json, '{}'::jsonb);
  v_payload_ref jsonb := p_payload_ref;
  v_visibility text;
  v_payload_schema_version text;
  v_priority integer;
  v_max_attempts integer;
  v_idempotency_key text := nullif(trim(p_idempotency_key), '');
  v_request_hash text := nullif(trim(p_request_hash), '');
  v_concurrency_key text := nullif(trim(p_concurrency_key), '');
  v_queue_key text := nullif(trim(p_queue_key), '');
begin
  if not private.study_generic_job_allowed(p_job_kind,null,'enqueue') then return jsonb_build_object('ok',false,'code','STUDY_SCOPED_ROUTE_REQUIRED','status',403,'message','Study task requires scoped authorization'); end if;
  if not coalesce(util.is_service_request(), false) then
    return jsonb_build_object(
      'ok', false,
      'code', 'SERVICE_ROLE_REQUIRED',
      'status', 403,
      'message', 'Service role is required to enqueue worker jobs'
    );
  end if;

  select *
    into v_kind
  from private.worker_job_kinds
  where job_kind = v_job_kind;

  if v_kind.job_kind is null then
    return jsonb_build_object(
      'ok', false,
      'code', 'WORKER_JOB_KIND_UNSUPPORTED',
      'status', 400,
      'message', 'Unsupported worker job kind'
    );
  end if;

  if jsonb_typeof(v_payload) <> 'object' then
    return jsonb_build_object(
      'ok', false,
      'code', 'INVALID_WORKER_JOB_PAYLOAD',
      'status', 400,
      'message', 'worker job payload must be a JSON object'
    );
  end if;

  if v_payload_ref is not null and jsonb_typeof(v_payload_ref) <> 'object' then
    return jsonb_build_object(
      'ok', false,
      'code', 'INVALID_WORKER_JOB_PAYLOAD_REF',
      'status', 400,
      'message', 'worker job payloadRef must be a JSON object'
    );
  end if;

  if v_requester_type not in ('user', 'system', 'service', 'operator') then
    return jsonb_build_object(
      'ok', false,
      'code', 'INVALID_WORKER_JOB_REQUESTER_TYPE',
      'status', 400,
      'message', 'requesterType must be user, system, service, or operator'
    );
  end if;

  if v_requester_type = 'user' and p_requested_by is null then
    return jsonb_build_object(
      'ok', false,
      'code', 'WORKER_JOB_REQUESTED_BY_REQUIRED',
      'status', 400,
      'message', 'requestedBy is required for user-requested worker jobs'
    );
  end if;

  v_visibility := lower(trim(coalesce(p_visibility, v_kind.default_visibility)));
  if v_visibility not in ('user', 'operator', 'system') then
    return jsonb_build_object(
      'ok', false,
      'code', 'INVALID_WORKER_JOB_VISIBILITY',
      'status', 400,
      'message', 'visibility must be user, operator, or system'
    );
  end if;

  v_payload_schema_version := coalesce(
    nullif(trim(p_payload_schema_version), ''),
    v_kind.payload_schema_version
  );
  v_priority := coalesce(p_priority, v_kind.default_priority);
  v_max_attempts := greatest(1, coalesce(p_max_attempts, v_kind.default_max_attempts, 3));

  -- Scheduled maintenance uses a logical, caller-supplied idempotency key. Lock
  -- the full key for this transaction and reuse terminal as well as active jobs;
  -- an operator can still force a deliberate retry with a new explicit key.
  if v_kind.worker_queue = 'maintenance' and v_idempotency_key is not null then
    perform pg_advisory_xact_lock(hashtextextended(
      concat_ws(
        ':',
        'worker-maintenance-idempotency-v1',
        v_kind.worker_runtime,
        v_kind.job_kind,
        coalesce(p_requested_by::text, ''),
        v_idempotency_key
      ),
      0
    ));

    select *
      into v_existing
    from private.worker_jobs
    where worker_runtime = v_kind.worker_runtime
      and job_kind = v_kind.job_kind
      and requested_by is not distinct from p_requested_by
      and idempotency_key = v_idempotency_key
    order by created_at desc, id desc
    limit 1;

    if v_existing.id is not null then
      return jsonb_build_object(
        'ok', true,
        'data', private.worker_job_payload(v_existing, true),
        'reused', true
      );
    end if;
  elsif v_idempotency_key is not null then
    select *
      into v_existing
    from private.worker_jobs
    where worker_runtime = v_kind.worker_runtime
      and job_kind = v_kind.job_kind
      and requested_by is not distinct from p_requested_by
      and idempotency_key = v_idempotency_key
      and status in ('queued', 'running', 'waiting', 'stale', 'blocked')
    order by created_at desc, id desc
    limit 1;

    if v_existing.id is not null then
      return jsonb_build_object(
        'ok', true,
        'data', private.worker_job_payload(v_existing, true),
        'reused', true
      );
    end if;
  end if;

  -- The request identity deliberately excludes idempotency/concurrency keys:
  -- they are transport controls, while this identity represents the exact
  -- deterministic work request. Only the latest exact request can suppress a
  -- new enqueue, and only when it is explicitly non-retryable.
  if v_request_hash is not null then
    select *
      into v_existing
    from private.worker_jobs
    where worker_runtime = v_kind.worker_runtime
      and job_kind = v_kind.job_kind
      and requester_type = v_requester_type
      and requested_by is not distinct from p_requested_by
      and team_id is not distinct from p_team_id
      and queue_key is not distinct from v_queue_key
      and payload_schema_version = v_payload_schema_version
      and request_hash = v_request_hash
    order by created_at desc, id desc
    limit 1;

    if v_existing.status = 'failed' and v_existing.retryable is false then
      return jsonb_build_object(
        'ok', false,
        'code', 'WORKER_REQUEST_NON_RETRYABLE_FAILURE',
        'status', 409,
        'message', 'The latest exact worker request failed and is not retryable',
        'reused', true,
        'reuseReason', 'terminal_non_retryable_failure',
        'details', jsonb_build_object(
          'workerJob', private.worker_job_payload(v_existing, false)
        )
      );
    end if;
  end if;

  if v_concurrency_key is not null then
    select *
      into v_existing
    from private.worker_jobs
    where worker_runtime = v_kind.worker_runtime
      and worker_queue = v_kind.worker_queue
      and concurrency_key = v_concurrency_key
      and status in ('queued', 'running', 'waiting', 'stale')
    order by created_at desc, id desc
    limit 1;

    if v_existing.id is not null then
      return jsonb_build_object(
        'ok', false,
        'code', 'WORKER_JOB_CONCURRENCY_CONFLICT',
        'status', 409,
        'message', 'A conflicting worker job is already active',
        'details', private.worker_job_payload(v_existing, false)
      );
    end if;
  end if;

  insert into private.worker_jobs (
    job_kind,
    worker_runtime,
    worker_queue,
    priority,
    queue_key,
    root_job_id,
    parent_job_id,
    subject_type,
    subject_id,
    subject_version,
    requester_type,
    requested_by,
    team_id,
    idempotency_key,
    request_hash,
    concurrency_key,
    visibility,
    run_after,
    max_attempts,
    timeout_at,
    payload_schema_version,
    payload_json,
    payload_ref,
    result_schema_version
  ) values (
    v_kind.job_kind,
    v_kind.worker_runtime,
    v_kind.worker_queue,
    v_priority,
    v_queue_key,
    p_root_job_id,
    p_parent_job_id,
    nullif(trim(p_subject_type), ''),
    p_subject_id,
    nullif(trim(p_subject_version), ''),
    v_requester_type,
    p_requested_by,
    p_team_id,
    v_idempotency_key,
    v_request_hash,
    v_concurrency_key,
    v_visibility,
    coalesce(p_run_after, now()),
    v_max_attempts,
    p_timeout_at,
    v_payload_schema_version,
    v_payload,
    v_payload_ref,
    v_kind.result_schema_version
  )
  returning *
    into v_job;

  insert into private.worker_job_events (
    job_id,
    event_type,
    status,
    details
  ) values (
    v_job.id,
    'enqueued',
    v_job.status,
    jsonb_build_object(
      'jobKind', v_job.job_kind,
      'workerQueue', v_job.worker_queue,
      'idempotencyKey', v_job.idempotency_key,
      'concurrencyKey', v_job.concurrency_key
    )
  );

  return jsonb_build_object(
    'ok', true,
    'data', private.worker_job_payload(v_job, true),
    'reused', false
  );
exception
  when unique_violation then
    return jsonb_build_object(
      'ok', false,
      'code', 'WORKER_JOB_UNIQUE_CONFLICT',
      'status', 409,
      'message', 'A worker job with the same idempotency or concurrency key already exists'
    );
end;
$$;

ALTER FUNCTION "private"."worker_enqueue_job"("p_job_kind" "text", "p_payload_json" "jsonb", "p_payload_schema_version" "text", "p_subject_type" "text", "p_subject_id" "uuid", "p_subject_version" "text", "p_requested_by" "uuid", "p_requester_type" "text", "p_team_id" "uuid", "p_idempotency_key" "text", "p_request_hash" "text", "p_concurrency_key" "text", "p_priority" integer, "p_queue_key" "text", "p_run_after" timestamp with time zone, "p_visibility" "text", "p_max_attempts" integer, "p_timeout_at" timestamp with time zone, "p_payload_ref" "jsonb", "p_parent_job_id" "uuid", "p_root_job_id" "uuid") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."worker_enqueue_job"("p_job_kind" "text", "p_payload_json" "jsonb", "p_payload_schema_version" "text", "p_subject_type" "text", "p_subject_id" "uuid", "p_subject_version" "text", "p_requested_by" "uuid", "p_requester_type" "text", "p_team_id" "uuid", "p_idempotency_key" "text", "p_request_hash" "text", "p_concurrency_key" "text", "p_priority" integer, "p_queue_key" "text", "p_run_after" timestamp with time zone, "p_visibility" "text", "p_max_attempts" integer, "p_timeout_at" timestamp with time zone, "p_payload_ref" "jsonb", "p_parent_job_id" "uuid", "p_root_job_id" "uuid") FROM PUBLIC;

GRANT ALL ON FUNCTION "private"."worker_enqueue_job"("p_job_kind" "text", "p_payload_json" "jsonb", "p_payload_schema_version" "text", "p_subject_type" "text", "p_subject_id" "uuid", "p_subject_version" "text", "p_requested_by" "uuid", "p_requester_type" "text", "p_team_id" "uuid", "p_idempotency_key" "text", "p_request_hash" "text", "p_concurrency_key" "text", "p_priority" integer, "p_queue_key" "text", "p_run_after" timestamp with time zone, "p_visibility" "text", "p_max_attempts" integer, "p_timeout_at" timestamp with time zone, "p_payload_ref" "jsonb", "p_parent_job_id" "uuid", "p_root_job_id" "uuid") TO "service_role";

GRANT ALL ON FUNCTION "private"."worker_enqueue_job"("p_job_kind" "text", "p_payload_json" "jsonb", "p_payload_schema_version" "text", "p_subject_type" "text", "p_subject_id" "uuid", "p_subject_version" "text", "p_requested_by" "uuid", "p_requester_type" "text", "p_team_id" "uuid", "p_idempotency_key" "text", "p_request_hash" "text", "p_concurrency_key" "text", "p_priority" integer, "p_queue_key" "text", "p_run_after" timestamp with time zone, "p_visibility" "text", "p_max_attempts" integer, "p_timeout_at" timestamp with time zone, "p_payload_ref" "jsonb", "p_parent_job_id" "uuid", "p_root_job_id" "uuid") TO "api_internal_executor";
