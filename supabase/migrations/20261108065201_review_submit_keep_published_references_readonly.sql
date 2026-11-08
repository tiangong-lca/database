-- #955: approved/commercial references are read-only during review submission.
-- Keep collection, permissions, reference inventory and draft freezing unchanged.
CREATE OR REPLACE FUNCTION "api"."cmd_review_submit"("p_target_table" "text", "p_target_id" "uuid", "p_target_version" "text", "p_audit" "jsonb" DEFAULT '{}'::"jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'api', 'private', 'public', 'util', 'extensions', 'pg_temp'
    AS $_$
declare
  v_actor uuid := auth.uid();
  v_table text := lower(coalesce(p_target_table, ''));
  v_root_row jsonb;
  v_checksum text;
  v_root_review_id uuid := gen_random_uuid();
  v_root_review private.reviews%rowtype;
  v_reference private.reviews%rowtype;
  v_target record;
  v_target_checksum text;
  v_affected jsonb := '[]'::jsonb;
  v_event_key text;
begin
  if v_actor is null then
    return jsonb_build_object(
      'ok', false,
      'code', 'AUTH_REQUIRED',
      'status', 401,
      'message', 'Authentication required'
    );
  end if;

  if v_table not in (
    'contacts',
    'sources',
    'unitgroups',
    'flowproperties',
    'flows',
    'processes',
    'lifecyclemodels'
  ) then
    return jsonb_build_object(
      'ok', false,
      'code', 'INVALID_DATASET_TABLE',
      'status', 400,
      'message', 'Unsupported dataset table for review submission'
    );
  end if;

  v_root_row := api.cmd_review_get_dataset_row(
    v_table,
    p_target_id,
    p_target_version,
    true
  );

  if v_root_row is null then
    return jsonb_build_object(
      'ok', false,
      'code', 'DATASET_NOT_FOUND',
      'status', 404,
      'message', 'Dataset not found'
    );
  end if;

  if nullif(v_root_row->>'user_id', '')::uuid is distinct from v_actor then
    return jsonb_build_object(
      'ok', false,
      'code', 'ROOT_DATASET_NOT_OWNED',
      'status', 403,
      'message', 'Only the dataset owner can submit review'
    );
  end if;

  if coalesce((v_root_row->>'state_code')::integer, 0) <> 0 then
    return jsonb_build_object(
      'ok', false,
      'code', case
        when coalesce((v_root_row->>'state_code')::integer, 0) = 100
          then 'APPROVED_DATASET_IMMUTABLE'
        else 'DATA_UNDER_REVIEW'
      end,
      'status', 409,
      'message', 'Only a Draft dataset can be submitted'
    );
  end if;

  v_checksum := private.review_revision_fingerprint_v1(v_table, v_root_row);

  if exists (
    select 1
    from private.review_candidate_root_ids_v1(
      v_table,
      p_target_id,
      p_target_version
    ) as candidate
    where private.review_root_currently_references_target_v1(
      candidate.root_review_id,
      v_table,
      p_target_id,
      p_target_version
    )
  ) then
    v_reference := private.review_get_or_create_reference_v1(
      v_table,
      v_root_row,
      v_checksum,
      v_actor
    );

    perform set_config('app.review_controlled_write', 'on', true);
    execute format(
      'update public.%I
          set state_code = 20,
              modified_at = now()
        where id = $1
          and version = $2
          and state_code = 0',
      v_table
    ) using p_target_id, p_target_version;
    perform set_config('app.review_controlled_write', 'off', true);

    insert into private.command_audit_log (
      command, actor_user_id, target_table, target_id, target_version, payload
    ) values (
      'cmd_review_submit', v_actor, v_table, p_target_id, p_target_version,
      coalesce(p_audit, '{}'::jsonb) || jsonb_build_object(
        'review_id', v_reference.id,
        'review_kind', 'reference',
        'submission_mode', 'reference_repair'
      )
    );

    return jsonb_build_object(
      'ok', true,
      'data', jsonb_build_object(
        'reviewId', v_reference.id,
        'reviewKind', 'reference',
        'submissionMode', 'reference_repair'
      )
    );
  end if;

  if exists (
    select 1
    from private.reviews as active_root
    where active_root.review_kind = 'root'
      and active_root.target_table = v_table
      and active_root.data_id = p_target_id
      and btrim(active_root.data_version::text) = p_target_version
      and active_root.state_code in (0, 1)
  ) then
    return jsonb_build_object(
      'ok', false,
      'code', 'DATA_UNDER_REVIEW',
      'status', 409,
      'message', 'An active Root Review already exists'
    );
  end if;

  create temporary table if not exists review_submit_targets (
    table_name text not null,
    dataset_id uuid not null,
    dataset_version text not null,
    state_code integer not null,
    reviews jsonb,
    dataset_row jsonb not null,
    is_root boolean not null default false,
    primary key (table_name, dataset_id, dataset_version)
  ) on commit drop;
  truncate table review_submit_targets;

  insert into review_submit_targets
  select *
  from api.cmd_review_collect_dataset_targets(
    jsonb_build_array(jsonb_build_object(
      'table', v_table,
      'id', p_target_id,
      'version', p_target_version,
      'is_root', true
    )),
    true
  );

  if not exists (
    select 1
    from review_submit_targets
    where is_root
      and table_name = v_table
      and dataset_id = p_target_id
      and dataset_version = p_target_version
  ) then
    return jsonb_build_object(
      'ok', false,
      'code', 'DATASET_NOT_FOUND',
      'status', 404,
      'message', 'Dataset not found'
    );
  end if;

  for v_target in
    select *
    from review_submit_targets
    order by is_root desc, table_name, dataset_id, dataset_version
  loop
    if nullif(v_target.dataset_row->>'user_id', '') is null
      and (v_target.is_root or v_target.state_code < 100) then
      return jsonb_build_object(
        'ok', false,
        'code', case when v_target.is_root
          then 'ROOT_OWNER_UNRESOLVED'
          else 'REFERENCE_OWNER_UNRESOLVED'
        end,
        'status', 409,
        'message', 'Dataset owner could not be resolved'
      );
    end if;

    if not v_target.is_root
      and nullif(v_target.dataset_row->>'user_id', '')::uuid <> v_actor
      and not private.review_dataset_can_read_v1(
        v_actor,
        v_target.table_name,
        v_target.dataset_row
      ) then
      return jsonb_build_object(
        'ok', false,
        'code', 'REFERENCE_ACCESS_DENIED',
        'status', 403,
        'message', 'A referenced dataset is not accessible'
      );
    end if;

    v_target_checksum := private.review_revision_fingerprint_v1(
      v_target.table_name,
      v_target.dataset_row
    );

    if not v_target.is_root then
      v_reference := private.review_get_or_create_reference_v1(
        v_target.table_name,
        v_target.dataset_row,
        v_target_checksum,
        v_actor
      );
    end if;
  end loop;

  insert into private.reviews (
    id,
    data_id,
    data_version,
    state_code,
    reviewer_id,
    json,
    review_kind,
    target_table,
    submitted_revision_checksum,
    target_owner_id,
    target_team_id
  )
  values (
    v_root_review_id,
    p_target_id,
    p_target_version,
    0,
    '[]'::jsonb,
    private.review_build_json_v1(
      v_table,
      v_root_row,
      v_actor,
      'submit_review',
      v_actor
    ),
    'root',
    v_table,
    v_checksum,
    v_actor,
    nullif(v_root_row->>'team_id', '')::uuid
  )
  returning * into v_root_review;

  perform set_config('app.review_controlled_write', 'on', true);
  for v_target in
    select *
    from review_submit_targets
    order by is_root desc, table_name, dataset_id, dataset_version
  loop
    execute format(
      'update public.%I
          set state_code = case when state_code < 20 then 20 else state_code end,
              reviews = case
                when state_code < 100
                  then api.cmd_review_append_review_ref(reviews, $1)
                else reviews
              end,
              modified_at = now()
        where id = $2
          and version = $3
          and state_code < 100',
      v_target.table_name
    ) using v_root_review_id, v_target.dataset_id, v_target.dataset_version;

    if not v_target.is_root
      and v_target.state_code < 20
      and nullif(v_target.dataset_row->>'user_id', '')::uuid <> v_actor then
      v_event_key := private.review_notify_event_v1(
        'reference_entered_review',
        (
          select reference_review.id
          from private.reviews as reference_review
          where reference_review.review_kind = 'reference'
            and reference_review.target_table = v_target.table_name
            and reference_review.data_id = v_target.dataset_id
            and btrim(reference_review.data_version::text) = v_target.dataset_version
            and reference_review.submitted_revision_checksum =
              private.review_revision_fingerprint_v1(
                v_target.table_name,
                v_target.dataset_row
              )
            and reference_review.state_code in (-1, 0, 1, 2)
          order by case when reference_review.state_code in (0, 1, 2) then 0 else 1 end,
                   reference_review.modified_at desc,
                   reference_review.id
          limit 1
        ),
        nullif(v_target.dataset_row->>'user_id', '')::uuid,
        v_actor,
        v_target.table_name,
        v_target.dataset_id,
        v_target.dataset_version,
        null,
        null,
        null
      );
    end if;

    v_affected := v_affected || jsonb_build_array(jsonb_build_object(
      'table', v_target.table_name,
      'id', v_target.dataset_id,
      'version', v_target.dataset_version,
      'previous_state_code', v_target.state_code,
      'state_code', case
        when v_target.state_code < 20 then 20
        else v_target.state_code
      end
    ));
  end loop;
  perform set_config('app.review_controlled_write', 'off', true);

  insert into private.command_audit_log (
    command,
    actor_user_id,
    target_table,
    target_id,
    target_version,
    payload
  )
  values (
    'cmd_review_submit',
    v_actor,
    v_table,
    p_target_id,
    p_target_version,
    coalesce(p_audit, '{}'::jsonb) || jsonb_build_object(
      'review_id', v_root_review_id,
      'review_kind', 'root',
      'submission_mode', 'root',
      'affected_datasets', v_affected
    )
  );

  return jsonb_build_object(
    'ok', true,
    'data', jsonb_build_object(
      'reviewId', v_root_review_id,
      'reviewKind', 'root',
      'submissionMode', 'root',
      'review', to_jsonb(v_root_review),
      'affectedDatasets', v_affected
    )
  );
exception
  when others then
    perform set_config('app.review_controlled_write', 'off', true);
    if sqlerrm = 'REFERENCE_OWNER_UNRESOLVED' then
      return jsonb_build_object(
        'ok', false,
        'code', sqlerrm,
        'status', 409,
        'message', 'Review submission could not be completed'
      );
    end if;
    raise;
end;
$_$;

ALTER FUNCTION "api"."cmd_review_submit"("p_target_table" "text", "p_target_id" "uuid", "p_target_version" "text", "p_audit" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."cmd_review_submit"("p_target_table" "text", "p_target_id" "uuid", "p_target_version" "text", "p_audit" "jsonb") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."cmd_review_submit"("p_target_table" "text", "p_target_id" "uuid", "p_target_version" "text", "p_audit" "jsonb") TO "api_internal_executor";

GRANT ALL ON FUNCTION "api"."cmd_review_submit"("p_target_table" "text", "p_target_id" "uuid", "p_target_version" "text", "p_audit" "jsonb") TO "authenticated";
