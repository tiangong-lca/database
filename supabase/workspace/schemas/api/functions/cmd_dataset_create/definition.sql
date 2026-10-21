CREATE OR REPLACE FUNCTION "api"."cmd_dataset_create"("p_table" "text", "p_id" "uuid", "p_json_ordered" "jsonb", "p_model_id" "uuid" DEFAULT NULL::"uuid", "p_rule_verification" boolean DEFAULT NULL::boolean, "p_audit" "jsonb" DEFAULT '{}'::"jsonb", "p_model_version" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'api', 'private', 'public', 'util', 'extensions', 'pg_temp'
    AS $_$
declare
  v_actor uuid := auth.uid();
  v_model_version text := nullif(btrim(coalesce(p_model_version, '')), '');
  v_created_row jsonb;
  v_stable_review_detail text;
begin
  if v_actor is null then
    return jsonb_build_object(
      'ok', false,
      'code', 'AUTH_REQUIRED',
      'status', 401,
      'message', 'Authentication required'
    );
  end if;

  if p_table = 'lifecyclemodels' then
    return jsonb_build_object(
      'ok', false,
      'code', 'LIFECYCLEMODEL_BUNDLE_REQUIRED',
      'status', 400,
      'message', 'Lifecycle models must use bundle create and delete commands'
    );
  end if;

  if p_table not in (
    'contacts',
    'sources',
    'unitgroups',
    'flowproperties',
    'flows',
    'processes'
  ) then
    return jsonb_build_object(
      'ok', false,
      'code', 'INVALID_DATASET_TABLE',
      'status', 400,
      'message', 'Unsupported dataset table'
    );
  end if;

  if p_json_ordered is null then
    return jsonb_build_object(
      'ok', false,
      'code', 'JSON_ORDERED_REQUIRED',
      'status', 400,
      'message', 'jsonOrdered is required'
    );
  end if;

  if p_table <> 'processes' and p_model_id is not null then
    return jsonb_build_object(
      'ok', false,
      'code', 'MODEL_ID_NOT_ALLOWED',
      'status', 400,
      'message', 'modelId is only allowed for process dataset creation'
    );
  end if;

  if p_table <> 'processes' and v_model_version is not null then
    return jsonb_build_object(
      'ok', false,
      'code', 'MODEL_VERSION_NOT_ALLOWED',
      'status', 400,
      'message', 'modelVersion is only allowed for process dataset creation'
    );
  end if;

  if v_model_version is not null and p_model_id is null then
    return jsonb_build_object(
      'ok', false,
      'code', 'MODEL_ID_REQUIRED_FOR_MODEL_VERSION',
      'status', 400,
      'message', 'modelId is required when modelVersion is provided'
    );
  end if;

  if v_model_version is not null
     and v_model_version !~ '^[0-9]{2}\.[0-9]{2}\.[0-9]{3}$' then
    return jsonb_build_object(
      'ok', false,
      'code', 'INVALID_MODEL_VERSION',
      'status', 400,
      'message', 'modelVersion must use NN.NN.NNN format'
    );
  end if;

  if p_table = 'flows' then
    perform set_config('lock_timeout', '2s', true);
    perform set_config('statement_timeout', '8s', true);
  end if;

  begin
    if p_table = 'processes' then
      execute format(
        'insert into public.%I as t (id, json_ordered, model_id, model_version, rule_verification)
         values ($1, $2::json, $3, $4, $5)
         returning jsonb_build_object(
           ''id'', t.id,
           ''version'', t.version,
           ''state_code'', t.state_code,
           ''user_id'', t.user_id,
           ''team_id'', t.team_id,
           ''model_id'', t.model_id,
           ''model_version'', t.model_version,
           ''rule_verification'', t.rule_verification
         )',
        p_table
      )
        into v_created_row
        using p_id, p_json_ordered, p_model_id, v_model_version, p_rule_verification;
    else
      execute format(
        'insert into public.%I as t (id, json_ordered, rule_verification)
         values ($1, $2::json, $3)
         returning jsonb_build_object(
           ''id'', t.id,
           ''version'', t.version,
           ''state_code'', t.state_code,
           ''user_id'', t.user_id,
           ''team_id'', t.team_id,
           ''model_id'', null,
           ''model_version'', null,
           ''rule_verification'', t.rule_verification
         )',
        p_table
      )
        into v_created_row
        using p_id, p_json_ordered, p_rule_verification;
    end if;
  exception
    when lock_not_available then
      return jsonb_build_object(
        'ok', false,
        'code', 'DATASET_CREATE_LOCK_TIMEOUT',
        'status', 503,
        'message', 'Dataset creation is temporarily blocked by concurrent database work'
      );
    when query_canceled then
      return jsonb_build_object(
        'ok', false,
        'code', 'DATASET_CREATE_TIMEOUT',
        'status', 503,
        'message', 'Dataset creation exceeded the database timeout'
      );
    when unique_violation then
      return jsonb_build_object(
        'ok', false,
        'code', '23505',
        'status', 409,
        'message', 'Dataset with the same id and version already exists'
      );
    when not_null_violation then
      return jsonb_build_object(
        'ok', false,
        'code', '23502',
        'status', 400,
        'message', 'Dataset creation requires a valid id, version, and jsonOrdered payload'
      );
    when check_violation then
      if sqlerrm = 'DATASET_REVIEW_IN_PROGRESS' then
        get stacked diagnostics v_stable_review_detail = pg_exception_detail;
        return jsonb_build_object('ok',false,'code','DATASET_REVIEW_IN_PROGRESS',
          'status',409,'message','The owner dataset family is under review',
          'details',v_stable_review_detail::jsonb);
      end if;
      return jsonb_build_object(
        'ok', false,
        'code', sqlstate,
        'status', 400,
        'message', sqlerrm
      );
  end;

  insert into private.command_audit_log (
    command,
    actor_user_id,
    target_table,
    target_id,
    target_version,
    payload
  )
  values (
    'cmd_dataset_create',
    v_actor,
    p_table,
    p_id,
    nullif(v_created_row->>'version', ''),
    coalesce(p_audit, '{}'::jsonb)
  );

  return jsonb_build_object(
    'ok', true,
    'data', v_created_row
  );
end;
$_$;

ALTER FUNCTION "api"."cmd_dataset_create"("p_table" "text", "p_id" "uuid", "p_json_ordered" "jsonb", "p_model_id" "uuid", "p_rule_verification" boolean, "p_audit" "jsonb", "p_model_version" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."cmd_dataset_create"("p_table" "text", "p_id" "uuid", "p_json_ordered" "jsonb", "p_model_id" "uuid", "p_rule_verification" boolean, "p_audit" "jsonb", "p_model_version" "text") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."cmd_dataset_create"("p_table" "text", "p_id" "uuid", "p_json_ordered" "jsonb", "p_model_id" "uuid", "p_rule_verification" boolean, "p_audit" "jsonb", "p_model_version" "text") TO "api_internal_executor";

GRANT ALL ON FUNCTION "api"."cmd_dataset_create"("p_table" "text", "p_id" "uuid", "p_json_ordered" "jsonb", "p_model_id" "uuid", "p_rule_verification" boolean, "p_audit" "jsonb", "p_model_version" "text") TO "authenticated";
