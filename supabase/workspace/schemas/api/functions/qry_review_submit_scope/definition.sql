CREATE OR REPLACE FUNCTION "api"."qry_review_submit_scope"("p_target_table" "text", "p_target_id" "uuid", "p_target_version" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'api', 'private', 'public', 'util', 'extensions', 'pg_temp'
    AS $$
declare
  v_actor uuid := auth.uid();
  v_table text := lower(coalesce(p_target_table, ''));
  v_root_row jsonb;
  v_root_state integer;
  v_target record;
  v_scope_targets jsonb := '[]'::jsonb;
  v_canonical_scope jsonb := '[]'::jsonb;
  v_scope_digest text;
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
    false
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

  v_root_state := coalesce((v_root_row->>'state_code')::integer, 0);
  if v_root_state <> 0 then
    return jsonb_build_object(
      'ok', false,
      'code', case
        when v_root_state = 100
          then 'APPROVED_DATASET_IMMUTABLE'
        else 'DATA_UNDER_REVIEW'
      end,
      'status', 409,
      'message', 'Only a Draft dataset can be submitted'
    );
  end if;

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
    v_scope_targets := jsonb_build_array(jsonb_build_object(
      'table', v_table,
      'id', p_target_id,
      'version', p_target_version,
      'is_root', true,
      'previous_state_code', v_root_state,
      'proposed_state_code', 20,
      'owner_match', true
    ));
    v_canonical_scope := jsonb_build_array(jsonb_build_object(
      'table', v_table,
      'id', p_target_id,
      'version', p_target_version,
      'is_root', true,
      'previous_state_code', v_root_state,
      'proposed_state_code', 20
    ));
    v_scope_digest := encode(
      extensions.digest(convert_to(v_canonical_scope::text, 'UTF8'), 'sha256'),
      'hex'
    );

    return jsonb_build_object(
      'ok', true,
      'data', jsonb_build_object(
        'submissionMode', 'reference_repair',
        'scopeDigest', v_scope_digest,
        'targets', v_scope_targets
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

  create temporary table if not exists review_submit_scope_preview (
    table_name text not null,
    dataset_id uuid not null,
    dataset_version text not null,
    state_code integer not null,
    reviews jsonb,
    dataset_row jsonb not null,
    is_root boolean not null default false,
    primary key (table_name, dataset_id, dataset_version)
  ) on commit drop;
  truncate table review_submit_scope_preview;

  insert into review_submit_scope_preview
  select *
  from api.cmd_review_collect_dataset_targets(
    jsonb_build_array(jsonb_build_object(
      'table', v_table,
      'id', p_target_id,
      'version', p_target_version,
      'is_root', true
    )),
    false
  );

  if not exists (
    select 1
    from review_submit_scope_preview
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
    from review_submit_scope_preview
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

    v_scope_targets := v_scope_targets || jsonb_build_array(jsonb_build_object(
      'table', v_target.table_name,
      'id', v_target.dataset_id,
      'version', v_target.dataset_version,
      'is_root', v_target.is_root,
      'previous_state_code', v_target.state_code,
      'proposed_state_code', case when v_target.state_code < 20 then 20 else v_target.state_code end,
      'owner_match', nullif(v_target.dataset_row->>'user_id', '')::uuid is not distinct from v_actor
    ));
    v_canonical_scope := v_canonical_scope || jsonb_build_array(jsonb_build_object(
      'table', v_target.table_name,
      'id', v_target.dataset_id,
      'version', v_target.dataset_version,
      'is_root', v_target.is_root,
      'previous_state_code', v_target.state_code,
      'proposed_state_code', case when v_target.state_code < 20 then 20 else v_target.state_code end
    ));
  end loop;

  v_scope_digest := encode(
    extensions.digest(convert_to(v_canonical_scope::text, 'UTF8'), 'sha256'),
    'hex'
  );

  return jsonb_build_object(
    'ok', true,
    'data', jsonb_build_object(
      'submissionMode', 'root',
      'scopeDigest', v_scope_digest,
      'targets', v_scope_targets
    )
  );
end;
$$;

ALTER FUNCTION "api"."qry_review_submit_scope"("p_target_table" "text", "p_target_id" "uuid", "p_target_version" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."qry_review_submit_scope"("p_target_table" "text", "p_target_id" "uuid", "p_target_version" "text") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."qry_review_submit_scope"("p_target_table" "text", "p_target_id" "uuid", "p_target_version" "text") TO "authenticated";

GRANT ALL ON FUNCTION "api"."qry_review_submit_scope"("p_target_table" "text", "p_target_id" "uuid", "p_target_version" "text") TO "api_internal_executor";
