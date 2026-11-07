CREATE OR REPLACE FUNCTION api.cmd_review_collect_dataset_targets(p_roots jsonb, p_lock boolean DEFAULT false)
 RETURNS TABLE(table_name text, dataset_id uuid, dataset_version text, state_code integer, reviews jsonb, dataset_row jsonb, is_root boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'api', 'private', 'public', 'util', 'extensions', 'pg_temp'
AS $function$
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
      from api.cmd_review_extract_refs(coalesce(v_current_row->'json', '{}'::jsonb))
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
        from (values (v_current_row->'json_ordered'), (v_current_row->'json')) as doc(payload)
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
$function$;

ALTER FUNCTION "api"."cmd_review_collect_dataset_targets"("p_roots" "jsonb", "p_lock" boolean) OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."cmd_review_collect_dataset_targets"("p_roots" "jsonb", "p_lock" boolean) FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."cmd_review_collect_dataset_targets"("p_roots" "jsonb", "p_lock" boolean) TO "api_internal_executor";
