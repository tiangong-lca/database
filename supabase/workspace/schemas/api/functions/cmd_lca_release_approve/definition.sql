CREATE OR REPLACE FUNCTION "api"."cmd_lca_release_approve"("p_release_run_id" "uuid", "p_publish_plan_hash" "text", "p_expires_at" timestamp with time zone DEFAULT NULL::timestamp with time zone, "p_reason" "text" DEFAULT NULL::"text", "p_audit" "jsonb" DEFAULT '{}'::"jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'api', 'private', 'public', 'util', 'extensions', 'pg_temp'
    AS $_$
declare
  v_actor uuid := auth.uid();
  v_run private.lca_release_runs%rowtype;
  v_approval private.lca_release_approvals%rowtype;
  v_now timestamptz := clock_timestamp();
  v_expires_at timestamptz;
  v_approval_hash text;
begin
  if v_actor is null then
    return private.lca_release_error('auth_required', 401, 'Authentication required');
  end if;
  if not private.lca_release_is_manager() then
    return private.lca_release_error('not_data_product_manager', 403, 'Data product manager role is required');
  end if;
  if coalesce(p_publish_plan_hash, '') !~ '^[0-9a-f]{64}$' then
    return private.lca_release_error('invalid_publish_plan_hash', 400, 'publishPlanHash must be SHA-256');
  end if;

  select * into v_run
  from private.lca_release_runs
  where id = p_release_run_id
  for update;

  if v_run.id is null then
    return private.lca_release_error('release_run_not_found', 404, 'Release run not found');
  end if;
  if v_run.publication_format<>'legacy-four-zip.v1' then
    return private.lca_release_error('final_result_versioned_api_required',409,'Use the explicit final Result release API');
  end if;
  if v_run.publish_plan_hash <> p_publish_plan_hash then
    return private.lca_release_error('publish_plan_hash_mismatch', 409, 'Approval must bind the exact immutable publish plan');
  end if;
  if v_run.status not in ('ready_for_approval', 'approved') then
    return private.lca_release_error('release_not_ready_for_approval', 409, 'Release run is not ready for approval');
  end if;
  if v_run.release_manifest_hash is null
     or (select count(*) from private.lca_release_artifacts where release_run_id = v_run.id) <> 4 then
    return private.lca_release_error('release_artifacts_incomplete', 409, 'Four verified release artifacts are required before approval');
  end if;

  update private.lca_release_approvals
  set status = 'expired'
  where release_run_id = v_run.id
    and status = 'approved'
    and expires_at <= v_now;

  select * into v_approval
  from private.lca_release_approvals
  where release_run_id = v_run.id
    and status = 'approved'
  for update;

  if v_approval.id is not null then
    if v_approval.publish_plan_hash = p_publish_plan_hash then
      return jsonb_build_object(
        'ok', true,
        'reused', true,
        'data', jsonb_build_object(
          'approvalId', v_approval.id,
          'approvalHash', v_approval.approval_hash,
          'publishPlanHash', v_approval.publish_plan_hash,
          'approvedBy', v_approval.approved_by,
          'approvedAt', v_approval.approved_at,
          'expiresAt', v_approval.expires_at
        )
      );
    end if;
    return private.lca_release_error('active_approval_conflict', 409, 'An active approval exists for different content');
  end if;

  v_expires_at := coalesce(p_expires_at, v_now + interval '24 hours');
  if v_expires_at <= v_now then
    return private.lca_release_error('approval_expiry_invalid', 400, 'Approval expiry must be in the future');
  end if;
  v_approval_hash := encode(
    extensions.digest(
      convert_to(
        concat_ws('|', v_run.id::text, p_publish_plan_hash, v_actor::text, v_now::text),
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );

  insert into private.lca_release_approvals (
    release_run_id, publish_plan_hash, approval_hash, status,
    approved_by, approved_at, expires_at, reason, audit_correlation
  ) values (
    v_run.id, p_publish_plan_hash, v_approval_hash, 'approved',
    v_actor, v_now, v_expires_at, nullif(trim(coalesce(p_reason, '')), ''),
    coalesce(p_audit, '{}'::jsonb)
  )
  returning * into v_approval;

  update private.lca_release_runs
  set status = 'approved', approved_at = v_now, updated_at = v_now
  where id = v_run.id;

  insert into private.command_audit_log (
    command, actor_user_id, target_table, target_id, target_version, payload
  ) values (
    'cmd_lca_release_approve', v_actor, 'lca_release_approvals', v_approval.id,
    v_run.release_version,
    coalesce(p_audit, '{}'::jsonb) || jsonb_build_object(
      'releaseRunId', v_run.id,
      'publishPlanHash', p_publish_plan_hash,
      'approvalHash', v_approval_hash,
      'expiresAt', v_expires_at
    )
  );

  return jsonb_build_object(
    'ok', true,
    'reused', false,
    'data', jsonb_build_object(
      'approvalId', v_approval.id,
      'approvalHash', v_approval.approval_hash,
      'publishPlanHash', v_approval.publish_plan_hash,
      'approvedBy', v_approval.approved_by,
      'approvedAt', v_approval.approved_at,
      'expiresAt', v_approval.expires_at
    )
  );
end;
$_$;

ALTER FUNCTION "api"."cmd_lca_release_approve"("p_release_run_id" "uuid", "p_publish_plan_hash" "text", "p_expires_at" timestamp with time zone, "p_reason" "text", "p_audit" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."cmd_lca_release_approve"("p_release_run_id" "uuid", "p_publish_plan_hash" "text", "p_expires_at" timestamp with time zone, "p_reason" "text", "p_audit" "jsonb") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."cmd_lca_release_approve"("p_release_run_id" "uuid", "p_publish_plan_hash" "text", "p_expires_at" timestamp with time zone, "p_reason" "text", "p_audit" "jsonb") TO "api_internal_executor";

GRANT ALL ON FUNCTION "api"."cmd_lca_release_approve"("p_release_run_id" "uuid", "p_publish_plan_hash" "text", "p_expires_at" timestamp with time zone, "p_reason" "text", "p_audit" "jsonb") TO "authenticated";
