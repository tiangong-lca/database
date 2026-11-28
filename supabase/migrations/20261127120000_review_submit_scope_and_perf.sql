begin;

-- #1330 + #548:
-- 1. Skip duplicate JSON/json_ordered ref extraction in cmd_review_collect_dataset_targets.
-- 2. Add read-only api.qry_review_submit_scope for exact target & transition preview.
-- 3. Enforce optional expected_scope_digest / expected_scope_targets before any writes in cmd_review_submit.
-- 4. Skip redundant fingerprinting & no-op updates for state_code >= 100 references and reuse reference review IDs.

CREATE OR REPLACE FUNCTION "api"."cmd_review_collect_dataset_targets"("p_roots" "jsonb", "p_lock" boolean DEFAULT false) RETURNS TABLE("table_name" "text", "dataset_id" "uuid", "dataset_version" "text", "state_code" integer, "reviews" "jsonb", "dataset_row" "jsonb", "is_root" boolean)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'api', 'private', 'public', 'util', 'extensions', 'pg_temp'
    AS $_$
declare
  v_root jsonb;
  v_current record;
  v_current_row jsonb;
  v_current_state_code integer;
  v_ref record;
  v_ref_table text;
  v_owner_id uuid;
  v_owner_version text;
begin
  create temporary table if not exists cmd_review_collect_queue (
    table_name text not null,
    dataset_id uuid not null,
    dataset_version text not null,
    is_root boolean not null default false,
    primary key (table_name, dataset_id, dataset_version)
  ) on commit drop;

  create temporary table if not exists cmd_review_collect_targets (
    table_name text not null,
    dataset_id uuid not null,
    dataset_version text not null,
    state_code integer not null,
    reviews jsonb,
    dataset_row jsonb not null,
    is_root boolean not null default false,
    primary key (table_name, dataset_id, dataset_version)
  ) on commit drop;

  truncate table cmd_review_collect_queue;
  truncate table cmd_review_collect_targets;

  if jsonb_typeof(p_roots) <> 'array' then
    return;
  end if;

  for v_root in
    select value
    from jsonb_array_elements(p_roots)
  loop
    if lower(coalesce(v_root->>'table', '')) not in (
      'contacts',
      'sources',
      'unitgroups',
      'flowproperties',
      'flows',
      'processes',
      'lifecyclemodels'
    ) then
      continue;
    end if;

    if not (coalesce(v_root->>'id', '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') then
      continue;
    end if;

    if nullif(v_root->>'version', '') is null then
      continue;
    end if;

    insert into cmd_review_collect_queue (
      table_name,
      dataset_id,
      dataset_version,
      is_root
    )
    values (
      lower(v_root->>'table'),
      (v_root->>'id')::uuid,
      v_root->>'version',
      coalesce((v_root->>'is_root')::boolean, false)
    )
    on conflict do nothing;
  end loop;

  while exists (select 1 from cmd_review_collect_queue) loop
    select
      q.table_name,
      q.dataset_id,
      q.dataset_version,
      q.is_root
    into v_current
    from cmd_review_collect_queue as q
    order by q.is_root desc, q.table_name, q.dataset_id, q.dataset_version
    limit 1;

    delete from cmd_review_collect_queue as q
    where q.table_name = v_current.table_name
      and q.dataset_id = v_current.dataset_id
      and q.dataset_version = v_current.dataset_version;

    if exists (
      select 1
      from cmd_review_collect_targets as t
      where t.table_name = v_current.table_name
        and t.dataset_id = v_current.dataset_id
        and t.dataset_version = v_current.dataset_version
    ) then
      continue;
    end if;

    v_current_row := api.cmd_review_get_dataset_row(
      v_current.table_name,
      v_current.dataset_id,
      v_current.dataset_version,
      p_lock
    );

    if v_current_row is null then
      continue;
    end if;

    v_current_state_code := coalesce((v_current_row->>'state_code')::integer, 0);

    insert into cmd_review_collect_targets (
      table_name,
      dataset_id,
      dataset_version,
      state_code,
      reviews,
      dataset_row,
      is_root
    )
    values (
      v_current.table_name,
      v_current.dataset_id,
      v_current.dataset_version,
      v_current_state_code,
      v_current_row->'reviews',
      v_current_row,
      v_current.is_root
    )
    on conflict do nothing;

    -- An owned result leads back to its exact Model even when submitted as root.
    -- Never infer ownership from matching UUIDs or a latest-version lookup.
    if v_current.table_name = 'processes' then
      v_owner_id := nullif(v_current_row->>'model_id', '')::uuid;
      v_owner_version := coalesce(nullif(v_current_row->>'model_version', ''), v_current.dataset_version);
      if v_owner_id is not null and api.cmd_review_get_dataset_row(
        'lifecyclemodels', v_owner_id, v_owner_version, false
      ) is not null then
        insert into cmd_review_collect_queue (table_name, dataset_id, dataset_version, is_root)
        values ('lifecyclemodels', v_owner_id, v_owner_version, false)
        on conflict do nothing;
      end if;
    end if;

    if v_current_state_code >= 100 and not v_current.is_root then
      continue;
    end if;

    for v_ref in (
      select *
      from api.cmd_review_extract_refs(coalesce(v_current_row->'json_ordered', '{}'::jsonb))
      union
      select *
      from api.cmd_review_extract_refs(v_current_row->'json')
      where v_current_row->'json' is not null
        and v_current_row->'json' <> '{}'::jsonb
        and v_current_row->'json' is distinct from coalesce(v_current_row->'json_ordered', '{}'::jsonb)
    ) loop
      v_ref_table := api.cmd_review_ref_type_to_table(v_ref.ref_type);

      if v_ref_table is null then
        continue;
      end if;

      if v_ref_table = v_current.table_name
         and v_ref.ref_object_id = v_current.dataset_id
         and v_ref.ref_version = v_current.dataset_version then
        continue;
      end if;

      insert into cmd_review_collect_queue (
        table_name,
        dataset_id,
        dataset_version,
        is_root
      )
      values (
        v_ref_table,
        v_ref.ref_object_id,
        v_ref.ref_version,
        false
      )
      on conflict do nothing;
    end loop;

    if v_current.table_name = 'lifecyclemodels' then
      -- Only exact current references plus stored ownership establish generated membership.
      -- json_tg is frontend reconstruction data and is never review authority.
      insert into cmd_review_collect_queue (table_name, dataset_id, dataset_version, is_root)
      select 'processes', model_process.id, model_process.version, false
      from public.processes as model_process
      join (
        select refs.value->>'@refObjectId' as id, refs.value->>'@version' as version
        from (
          select v_current_row->'json_ordered' as payload
          where v_current_row->'json_ordered' is not null
          union all
          select v_current_row->'json' as payload
          where v_current_row->'json' is not null
            and v_current_row->'json' <> '{}'::jsonb
            and v_current_row->'json' is distinct from coalesce(v_current_row->'json_ordered', '{}'::jsonb)
        ) as doc(payload)
        cross join lateral (
          select value from jsonb_path_query(coalesce(doc.payload, '{}'::jsonb),
            '$.lifeCycleModelDataSet.lifeCycleModelInformation.dataSetInformation.referenceToResultingProcess[*]') as item(value)
          union
          select value from jsonb_path_query(coalesce(doc.payload, '{}'::jsonb),
            '$.lifeCycleModelDataSet.lifeCycleModelInformation.technology.processes.processInstance[*].referenceToProcess') as item(value)
        ) as refs
      ) as current_ref on current_ref.id = model_process.id::text
        and current_ref.version = model_process.version
      where model_process.model_id = v_current.dataset_id
        and coalesce(model_process.model_version, model_process.version) = v_current.dataset_version
      on conflict do nothing;
    end if;
  end loop;

  return query
  select
    t.table_name,
    t.dataset_id,
    t.dataset_version,
    t.state_code,
    t.reviews,
    t.dataset_row,
    t.is_root
  from cmd_review_collect_targets as t
  order by t.is_root desc, t.table_name, t.dataset_id, t.dataset_version;
end;
$_$;

CREATE OR REPLACE FUNCTION "private"."review_scope_matches_v1"(
  "p_expected_digest" "text",
  "p_expected_targets" "jsonb",
  "p_actual_digest" "text",
  "p_actual_targets" "jsonb"
) RETURNS boolean
    LANGUAGE "plpgsql" IMMUTABLE
    SET "search_path" TO ''
    AS $$
declare
  v_elem jsonb;
  v_proposed_text text;
  v_actual jsonb;
  v_matched_actual jsonb;
begin
  if p_expected_digest is not null and p_expected_digest <> p_actual_digest then
    return false;
  end if;

  if p_expected_targets is not null then
    if pg_catalog.jsonb_typeof(p_expected_targets) <> 'array' then
      return false;
    end if;

    for v_elem in
      select value
      from pg_catalog.jsonb_array_elements(p_expected_targets)
    loop
      if pg_catalog.jsonb_typeof(v_elem) <> 'object' then
        return false;
      end if;

      v_proposed_text := nullif(
        pg_catalog.btrim(coalesce(v_elem->>'proposed_state_code', v_elem->>'proposedStateCode', '')),
        ''
      );

      select a.value
      into v_matched_actual
      from pg_catalog.jsonb_array_elements(coalesce(p_actual_targets, '[]'::jsonb)) as a(value)
      where a.value->>'table' = lower(coalesce(v_elem->>'table', ''))
        and a.value->>'id' = coalesce(v_elem->>'id', '')
        and a.value->>'version' = coalesce(v_elem->>'version', '')
      limit 1;

      if v_matched_actual is null then
        return false;
      end if;

      if v_proposed_text is not null then
        if not (v_proposed_text ~ '^-?\d+$')
           or v_proposed_text::integer <> (v_matched_actual->>'proposed_state_code')::integer then
          return false;
        end if;
      end if;
    end loop;

    for v_actual in
      select value
      from pg_catalog.jsonb_array_elements(coalesce(p_actual_targets, '[]'::jsonb))
    loop
      if coalesce((v_actual->>'is_root')::boolean, false)
         or coalesce((v_actual->>'previous_state_code')::integer, 0) < 20 then
        if not exists (
          select 1
          from pg_catalog.jsonb_array_elements(p_expected_targets) as e(value)
          where lower(coalesce(e.value->>'table', '')) = v_actual->>'table'
            and coalesce(e.value->>'id', '') = v_actual->>'id'
            and coalesce(e.value->>'version', '') = v_actual->>'version'
            and (
              nullif(pg_catalog.btrim(coalesce(e.value->>'proposed_state_code', e.value->>'proposedStateCode', '')), '') is null
              or (
                pg_catalog.btrim(coalesce(e.value->>'proposed_state_code', e.value->>'proposedStateCode', '')) ~ '^-?\d+$'
                and pg_catalog.btrim(coalesce(e.value->>'proposed_state_code', e.value->>'proposedStateCode', ''))::integer = (v_actual->>'proposed_state_code')::integer
              )
            )
        ) then
          return false;
        end if;
      end if;
    end loop;
  end if;

  return true;
end;
$$;

ALTER FUNCTION "private"."review_scope_matches_v1"("p_expected_digest" "text", "p_expected_targets" "jsonb", "p_actual_digest" "text", "p_actual_targets" "jsonb") OWNER TO "postgres";
REVOKE ALL ON FUNCTION "private"."review_scope_matches_v1"("p_expected_digest" "text", "p_expected_targets" "jsonb", "p_actual_digest" "text", "p_actual_targets" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."review_scope_matches_v1"("p_expected_digest" "text", "p_expected_targets" "jsonb", "p_actual_digest" "text", "p_actual_targets" "jsonb") TO "api_internal_executor";

CREATE OR REPLACE FUNCTION "api"."qry_review_submit_scope"(
  "p_target_table" "text",
  "p_target_id" "uuid",
  "p_target_version" "text"
) RETURNS "jsonb"
    LANGUAGE "plpgsql" VOLATILE SECURITY DEFINER
    SET "search_path" TO 'api', 'private', 'public', 'util', 'extensions', 'pg_temp'
    AS $_$
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
$_$;

ALTER FUNCTION "api"."qry_review_submit_scope"("p_target_table" "text", "p_target_id" "uuid", "p_target_version" "text") OWNER TO "postgres";
REVOKE ALL ON FUNCTION "api"."qry_review_submit_scope"("p_target_table" "text", "p_target_id" "uuid", "p_target_version" "text") FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION "api"."qry_review_submit_scope"("p_target_table" "text", "p_target_id" "uuid", "p_target_version" "text") TO "authenticated";
GRANT ALL ON FUNCTION "api"."qry_review_submit_scope"("p_target_table" "text", "p_target_id" "uuid", "p_target_version" "text") TO "api_internal_executor";

insert into private.api_capability_grants (
  routine_identity, capability_id, allow_anon, allow_authenticated, allow_service_role
) values (
  'api.qry_review_submit_scope(text, uuid, text)',
  'CLI-REVIEW-AUTHOR-01', false, true, false
)
on conflict do nothing;

CREATE OR REPLACE FUNCTION "api"."cmd_review_submit"("p_target_table" "text", "p_target_id" "uuid", "p_target_version" "text", "p_audit" "jsonb" DEFAULT '{}'::"jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'api', 'private', 'public', 'util', 'extensions', 'pg_temp'
    AS $_$
declare
  v_actor uuid := auth.uid();
  v_table text := lower(coalesce(p_target_table, ''));
  v_root_row jsonb;
  v_root_state integer;
  v_checksum text;
  v_root_review_id uuid := gen_random_uuid();
  v_root_review private.reviews%rowtype;
  v_reference private.reviews%rowtype;
  v_target record;
  v_target_checksum text;
  v_affected jsonb := '[]'::jsonb;
  v_event_key text;
  v_expected_digest text := nullif(
    btrim(coalesce(p_audit #>> '{payload,expected_scope_digest}', p_audit ->> 'expected_scope_digest', '')),
    ''
  );
  v_expected_targets jsonb := coalesce(
    p_audit #> '{payload,expected_scope_targets}',
    p_audit -> 'expected_scope_targets'
  );
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

    if not private.review_scope_matches_v1(
      v_expected_digest,
      v_expected_targets,
      v_scope_digest,
      v_scope_targets
    ) then
      return jsonb_build_object(
        'ok', false,
        'code', 'REVIEW_SCOPE_DRIFT',
        'status', 409,
        'message', 'Related review submission scope does not match the authorized scope',
        'data', jsonb_build_object(
          'submissionMode', 'reference_repair',
          'expectedScopeDigest', v_expected_digest,
          'actualScopeDigest', v_scope_digest,
          'actualTargets', v_scope_targets
        )
      );
    end if;

    v_checksum := private.review_revision_fingerprint_v1(v_table, v_root_row);

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
    reference_review_id uuid,
    primary key (table_name, dataset_id, dataset_version)
  ) on commit drop;
  truncate table review_submit_targets;

  insert into review_submit_targets (
    table_name,
    dataset_id,
    dataset_version,
    state_code,
    reviews,
    dataset_row,
    is_root
  )
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

  -- Loop 1: Validate ownership/access and collect canonical scope before any writes.
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

  if not private.review_scope_matches_v1(
    v_expected_digest,
    v_expected_targets,
    v_scope_digest,
    v_scope_targets
  ) then
    return jsonb_build_object(
      'ok', false,
      'code', 'REVIEW_SCOPE_DRIFT',
      'status', 409,
      'message', 'Related review submission scope does not match the authorized scope',
      'data', jsonb_build_object(
        'submissionMode', 'root',
        'expectedScopeDigest', v_expected_digest,
        'actualScopeDigest', v_scope_digest,
        'actualTargets', v_scope_targets
      )
    );
  end if;

  -- Loop 2 (#1330): Fingerprint & provision reference reviews only for state_code < 100 references.
  for v_target in
    select *
    from review_submit_targets
    where not is_root
      and state_code < 100
    order by table_name, dataset_id, dataset_version
  loop
    v_target_checksum := private.review_revision_fingerprint_v1(
      v_target.table_name,
      v_target.dataset_row
    );

    v_reference := private.review_get_or_create_reference_v1(
      v_target.table_name,
      v_target.dataset_row,
      v_target_checksum,
      v_actor
    );

    update review_submit_targets
    set reference_review_id = v_reference.id
    where table_name = v_target.table_name
      and dataset_id = v_target.dataset_id
      and dataset_version = v_target.dataset_version;
  end loop;

  v_checksum := private.review_revision_fingerprint_v1(v_table, v_root_row);

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
    if v_target.state_code < 100 then
      execute format(
        'update public.%I
            set state_code = case when state_code < 20 then 20 else state_code end,
                reviews = api.cmd_review_append_review_ref(reviews, $1),
                modified_at = now()
          where id = $2
            and version = $3
            and state_code < 100',
        v_target.table_name
      ) using v_root_review_id, v_target.dataset_id, v_target.dataset_version;
    end if;

    if not v_target.is_root
      and v_target.state_code < 20
      and nullif(v_target.dataset_row->>'user_id', '')::uuid <> v_actor
      and v_target.reference_review_id is not null then
      v_event_key := private.review_notify_event_v1(
        'reference_entered_review',
        v_target.reference_review_id,
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

notify pgrst, 'reload schema';

commit;
