CREATE OR REPLACE FUNCTION "api"."cmd_dataset_create_version"("p_table" "text", "p_id" "uuid", "p_source_version" "text", "p_json_ordered" "jsonb", "p_model_id" "uuid" DEFAULT NULL::"uuid", "p_rule_verification" boolean DEFAULT NULL::boolean, "p_audit" "jsonb" DEFAULT '{}'::"jsonb", "p_model_version" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'api', 'private', 'public', 'util', 'extensions', 'pg_temp'
    AS $_$
declare
  v_actor uuid := auth.uid();
  v_model_version text := nullif(btrim(coalesce(p_model_version, '')), '');
  v_root_key text;
  v_uri_slug text;
  v_source_exists boolean := false;
  v_source_state integer;
  v_source_version text := nullif(btrim(coalesce(p_source_version, '')), '');
  v_highest_version text;
  v_parts integer[];
  v_next_version text;
  v_next_uri text;
  v_payload jsonb;
  v_dataset jsonb;
  v_admin jsonb;
  v_pub jsonb;
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

  case p_table
    when 'contacts' then
      v_root_key := 'contactDataSet';
      v_uri_slug := 'contact';
    when 'sources' then
      v_root_key := 'sourceDataSet';
      v_uri_slug := 'source';
    when 'unitgroups' then
      v_root_key := 'unitGroupDataSet';
      v_uri_slug := 'unitgroup';
    when 'flowproperties' then
      v_root_key := 'flowPropertyDataSet';
      v_uri_slug := 'flowproperty';
    when 'flows' then
      v_root_key := 'flowDataSet';
      v_uri_slug := 'productFlow';
    when 'processes' then
      v_root_key := 'processDataSet';
      v_uri_slug := 'process';
    when 'lifecyclemodels' then
      return jsonb_build_object(
        'ok', false,
        'code', 'LIFECYCLEMODEL_BUNDLE_REQUIRED',
        'status', 400,
        'message', 'Lifecycle models must use bundle create-version commands'
      );
    else
      return jsonb_build_object(
        'ok', false,
        'code', 'INVALID_DATASET_TABLE',
        'status', 400,
        'message', 'Unsupported dataset table'
      );
  end case;

  if p_id is null then
    return jsonb_build_object(
      'ok', false,
      'code', 'DATASET_ID_REQUIRED',
      'status', 400,
      'message', 'id is required'
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

  if v_source_version is null then
    return jsonb_build_object(
      'ok', false,
      'code', 'DATASET_SOURCE_VERSION_REQUIRED',
      'status', 400,
      'message', 'sourceVersion is required'
    );
  end if;

  if p_table <> 'processes' and p_model_id is not null then
    return jsonb_build_object(
      'ok', false,
      'code', 'MODEL_ID_NOT_ALLOWED',
      'status', 400,
      'message', 'modelId is only allowed for process dataset version creation'
    );
  end if;

  if p_table <> 'processes' and v_model_version is not null then
    return jsonb_build_object(
      'ok', false,
      'code', 'MODEL_VERSION_NOT_ALLOWED',
      'status', 400,
      'message', 'modelVersion is only allowed for process dataset version creation'
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

  perform set_config('lock_timeout', '2s', true);
  perform set_config('statement_timeout', '8s', true);

  begin
    perform pg_advisory_xact_lock(
      hashtext('cmd_dataset_create_version:' || p_table),
      hashtext(p_id::text)
    );

    execute format(
      'select exists(
         select 1
           from public.%I d
          where d.id = $1
            and d.version = $2
            and (
              d.state_code >= 100
              or d.user_id = $3
              or exists (
                select 1
                  from private.roles r
                 where r.team_id = d.team_id
                   and r.user_id = $3
                   and r.role::text = any(array[''admin'', ''member'', ''owner''])
              )
            )
       )',
      p_table
    )
      into v_source_exists
      using p_id, v_source_version, v_actor;

    if not v_source_exists then
      return jsonb_build_object(
        'ok', false,
        'code', 'DATASET_SOURCE_NOT_FOUND',
        'status', 404,
        'message', 'Source dataset version not found'
      );
    end if;

    -- Result isolation: a published Result Process is never a version source, because
    -- the derived row would be created as an ordinary owner-ready draft. The source row
    -- is locked first so its state cannot change between this admission check and the
    -- insert, and the established per-identity advisory lock above is retained; no broad
    -- table lock is taken. The check reads the source's own state, so it holds even when
    -- no publication receipt exists.
    if p_table = 'processes' then
      execute format(
        'select d.state_code from public.%I d where d.id = $1 and d.version = $2 for update of d',
        p_table
      )
        into v_source_state
        using p_id, v_source_version;

      if v_source_state = 120 then
        return jsonb_build_object(
          'ok', false,
          'code', 'RESULT_VERSION_DERIVATION_BLOCKED',
          'status', 403,
          'message', 'A published Result Process cannot be used as a version source',
          'details', jsonb_build_object(
            'state_code', v_source_state
          )
        );
      end if;
    end if;

    execute format(
      'select version::text
         from public.%I
        where id = $1
          and version::text ~ ''^[0-9]{2}\.[0-9]{2}\.[0-9]{3}$''
        order by split_part(version::text, ''.'', 1)::integer desc,
                 split_part(version::text, ''.'', 2)::integer desc,
                 split_part(version::text, ''.'', 3)::integer desc
        limit 1',
      p_table
    )
      into v_highest_version
      using p_id;

    if v_highest_version is null then
      v_parts := array[0, 0, -1];
    else
      v_parts := array[
        split_part(v_highest_version, '.', 1)::integer,
        split_part(v_highest_version, '.', 2)::integer,
        split_part(v_highest_version, '.', 3)::integer
      ];
    end if;

    v_parts[3] := v_parts[3] + 1;

    if v_parts[3] > 999 then
      v_parts[3] := 0;
      v_parts[2] := v_parts[2] + 1;
    end if;

    if v_parts[2] > 99 then
      v_parts[2] := 0;
      v_parts[1] := v_parts[1] + 1;
    end if;

    v_next_version := lpad(v_parts[1]::text, 2, '0')
      || '.'
      || lpad(v_parts[2]::text, 2, '0')
      || '.'
      || lpad(v_parts[3]::text, 3, '0');
    v_next_uri := 'https://lcdn.tiangong.earth/datasetdetail/'
      || v_uri_slug
      || '.xhtml?uuid='
      || p_id::text
      || '&version='
      || v_next_version;

    v_payload := p_json_ordered;
    v_dataset := coalesce(v_payload->v_root_key, '{}'::jsonb);
    v_admin := coalesce(v_dataset->'administrativeInformation', '{}'::jsonb);
    v_pub := coalesce(v_admin->'publicationAndOwnership', '{}'::jsonb);
    v_pub := jsonb_set(v_pub, '{common:dataSetVersion}', to_jsonb(v_next_version), true);
    v_pub := jsonb_set(v_pub, '{common:permanentDataSetURI}', to_jsonb(v_next_uri), true);
    v_admin := jsonb_set(v_admin, '{publicationAndOwnership}', v_pub, true);
    v_dataset := jsonb_set(v_dataset, '{administrativeInformation}', v_admin, true);
    v_payload := jsonb_set(v_payload, array[v_root_key], v_dataset, true);

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
           ''rule_verification'', t.rule_verification,
           ''json_ordered'', t.json_ordered::jsonb
         )',
        p_table
      )
        into v_created_row
        using p_id, v_payload, p_model_id, v_model_version, p_rule_verification;
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
           ''rule_verification'', t.rule_verification,
           ''json_ordered'', t.json_ordered::jsonb
         )',
        p_table
      )
        into v_created_row
        using p_id, v_payload, p_rule_verification;
    end if;
  exception
    when lock_not_available then
      return jsonb_build_object(
        'ok', false,
        'code', 'DATASET_CREATE_VERSION_LOCK_TIMEOUT',
        'status', 503,
        'message', 'Dataset version creation is temporarily blocked by concurrent database work'
      );
    when query_canceled then
      return jsonb_build_object(
        'ok', false,
        'code', 'DATASET_CREATE_VERSION_TIMEOUT',
        'status', 503,
        'message', 'Dataset version creation exceeded the database timeout'
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
        'message', 'Dataset version creation requires a valid id, version, and jsonOrdered payload'
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
    'cmd_dataset_create_version',
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

ALTER FUNCTION "api"."cmd_dataset_create_version"("p_table" "text", "p_id" "uuid", "p_source_version" "text", "p_json_ordered" "jsonb", "p_model_id" "uuid", "p_rule_verification" boolean, "p_audit" "jsonb", "p_model_version" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."cmd_dataset_create_version"("p_table" "text", "p_id" "uuid", "p_source_version" "text", "p_json_ordered" "jsonb", "p_model_id" "uuid", "p_rule_verification" boolean, "p_audit" "jsonb", "p_model_version" "text") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."cmd_dataset_create_version"("p_table" "text", "p_id" "uuid", "p_source_version" "text", "p_json_ordered" "jsonb", "p_model_id" "uuid", "p_rule_verification" boolean, "p_audit" "jsonb", "p_model_version" "text") TO "api_internal_executor";

GRANT ALL ON FUNCTION "api"."cmd_dataset_create_version"("p_table" "text", "p_id" "uuid", "p_source_version" "text", "p_json_ordered" "jsonb", "p_model_id" "uuid", "p_rule_verification" boolean, "p_audit" "jsonb", "p_model_version" "text") TO "authenticated";
