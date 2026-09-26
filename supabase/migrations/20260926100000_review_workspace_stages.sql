-- Database #721: align review queues with the reviewer/review-admin workspace.
-- V4 remains available for existing clients. V5 changes only queue vocabulary,
-- exposes progress/opinion counts, and adds a read-only batch preflight.

create or replace function api.qry_review_get_admin_queue_items_v5(
  p_status text default null,
  p_page integer default 1,
  p_page_size integer default 50,
  p_sort_by text default 'modified_at',
  p_sort_order text default 'desc',
  p_display_mode text default 'all',
  p_target_table text default null,
  p_query text default null
)
returns table (
  id uuid,
  data_id uuid,
  data_version text,
  state_code integer,
  review_kind text,
  target_table text,
  reviewer_id jsonb,
  "json" jsonb,
  deadline timestamptz,
  created_at timestamptz,
  modified_at timestamptz,
  comment_state_codes jsonb,
  reviewer_count integer,
  completed_reviewer_count integer,
  approve_opinion_count integer,
  reject_opinion_count integer,
  root_matches_status boolean,
  root_can_read boolean,
  total_count bigint
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_query text := nullif(pg_catalog.btrim(p_query), '');
  v_limit integer := greatest(1, least(coalesce(p_page_size, 50), 100));
  v_offset integer := (greatest(coalesce(p_page, 1), 1) - 1) * v_limit;
  v_sort_key text := case pg_catalog.lower(coalesce(p_sort_by, ''))
    when 'created_at' then 'created_at'
    when 'createat' then 'created_at'
    when 'deadline' then 'deadline'
    when 'state_code' then 'state_code'
    when 'statecode' then 'state_code'
    else 'modified_at'
  end;
  v_order_dir text := api.cmd_membership_resolve_sort_direction(p_sort_order);
  v_status text := pg_catalog.lower(coalesce(p_status, ''));
  v_display_mode text := pg_catalog.lower(pg_catalog.btrim(coalesce(p_display_mode, 'all')));
  v_target_table text := nullif(
    pg_catalog.lower(pg_catalog.btrim(coalesce(p_target_table, ''))),
    ''
  );
begin
  if v_actor is null or not api.cmd_review_is_review_admin(v_actor) then
    return;
  end if;
  if v_status not in ('', 'all', 'unassigned', 'in-progress', 'completed') then
    return;
  end if;
  if v_display_mode not in ('all', 'model_process', 'other') then
    raise exception using errcode = '22023', message = 'INVALID_REVIEW_DISPLAY_MODE';
  end if;
  if v_target_table is not null and not (
    v_target_table = any(array[
      'contacts', 'sources', 'unitgroups', 'flowproperties', 'flows',
      'processes', 'lifecyclemodels'
    ]::text[])
  ) then
    raise exception using errcode = '22023', message = 'INVALID_REVIEW_TARGET_TABLE';
  end if;
  if pg_catalog.char_length(v_query) > 1000 then
    raise exception using errcode = '22023', message = 'REVIEW_QUERY_TOO_LONG';
  end if;

  return query
  with matches as materialized (
    select * from private.review_search_dataset_versions_v1(v_query, v_target_table)
    where v_query is not null
  ), q as (
    select
      review_row.id,
      review_row.data_id,
      pg_catalog.btrim(review_row.data_version::text) as data_version,
      review_row.state_code,
      review_row.review_kind,
      review_row.target_table,
      coalesce(review_row.reviewer_id, '[]'::jsonb) as reviewer_id,
      coalesce(review_row.json, '{}'::jsonb) as json,
      review_row.deadline,
      review_row.created_at,
      review_row.modified_at,
      coalesce(review_comments.comment_state_codes, '[]'::jsonb) as comment_state_codes,
      pg_catalog.jsonb_array_length(coalesce(review_row.reviewer_id, '[]'::jsonb))::integer
        as reviewer_count,
      coalesce(review_comments.completed_reviewer_count, 0)::integer
        as completed_reviewer_count,
      coalesce(review_comments.approve_opinion_count, 0)::integer as approve_opinion_count,
      coalesce(review_comments.reject_opinion_count, 0)::integer as reject_opinion_count,
      true as root_matches_status,
      true as root_can_read
    from private.reviews as review_row
    left join lateral (
      select
        pg_catalog.jsonb_agg(
          pg_catalog.to_jsonb(comment_row.state_code)
          order by comment_row.created_at, comment_row.reviewer_id
        ) filter (where comment_row.reviewer_id is not null) as comment_state_codes,
        pg_catalog.count(*) filter (
          where comment_row.state_code in (1, -3, 2, -1)
        ) as completed_reviewer_count,
        pg_catalog.count(*) filter (where comment_row.state_code in (1, 2))
          as approve_opinion_count,
        pg_catalog.count(*) filter (where comment_row.state_code in (-3, -1))
          as reject_opinion_count
      from private.comments as comment_row
      where comment_row.review_id = review_row.id
        and coalesce(review_row.reviewer_id, '[]'::jsonb)
          @> pg_catalog.jsonb_build_array(pg_catalog.to_jsonb(comment_row.reviewer_id::text))
        and comment_row.state_code <> -2
    ) as review_comments on true
    where review_row.review_kind in ('root', 'reference')
      and (
        v_status in ('', 'all')
        or (v_status = 'unassigned' and review_row.state_code = 0)
        or (v_status = 'in-progress' and review_row.state_code = 1)
        or (v_status = 'completed' and review_row.state_code in (-1, 2))
      )
      and (
        v_display_mode = 'all'
        or (v_display_mode = 'model_process' and review_row.target_table in ('processes', 'lifecyclemodels'))
        or (v_display_mode = 'other' and review_row.target_table not in ('processes', 'lifecyclemodels'))
      )
      and (v_target_table is null or review_row.target_table = v_target_table)
      and (v_query is null or exists (
        select 1 from matches
        where matches.target_table = review_row.target_table
          and matches.data_id = review_row.data_id
          and matches.data_version = review_row.data_version
      ))
  )
  select q.*, pg_catalog.count(*) over() as total_count
  from q
  order by
    case when v_sort_key = 'created_at' and v_order_dir = 'asc' then q.created_at end asc nulls last,
    case when v_sort_key = 'created_at' and v_order_dir = 'desc' then q.created_at end desc nulls last,
    case when v_sort_key = 'deadline' and v_order_dir = 'asc' then q.deadline end asc nulls last,
    case when v_sort_key = 'deadline' and v_order_dir = 'desc' then q.deadline end desc nulls last,
    case when v_sort_key = 'state_code' and v_order_dir = 'asc' then q.state_code end asc nulls last,
    case when v_sort_key = 'state_code' and v_order_dir = 'desc' then q.state_code end desc nulls last,
    case when v_sort_key = 'modified_at' and v_order_dir = 'asc' then q.modified_at end asc nulls last,
    case when v_sort_key = 'modified_at' and v_order_dir = 'desc' then q.modified_at end desc nulls last,
    q.id
  limit v_limit offset v_offset;
end;
$$;

alter function api.qry_review_get_admin_queue_items_v5(
  text, integer, integer, text, text, text, text, text
) owner to postgres;
revoke all on function api.qry_review_get_admin_queue_items_v5(
  text, integer, integer, text, text, text, text, text
) from public, anon, service_role;
grant execute on function api.qry_review_get_admin_queue_items_v5(
  text, integer, integer, text, text, text, text, text
) to authenticated, api_internal_executor;

comment on function api.qry_review_get_admin_queue_items_v5(
  text, integer, integer, text, text, text, text, text
) is
  'Review-admin workspace queue: unassigned, in-progress, and completed stages with current-reviewer progress and opinion counts.';

create or replace function api.qry_review_get_member_queue_items_v5(
  p_status text default 'pending',
  p_page integer default 1,
  p_page_size integer default 50,
  p_sort_by text default 'modified_at',
  p_sort_order text default 'desc',
  p_display_mode text default 'all',
  p_target_table text default null,
  p_query text default null
)
returns table (
  id uuid,
  data_id uuid,
  data_version text,
  review_state_code integer,
  review_kind text,
  target_table text,
  reviewer_id jsonb,
  "json" jsonb,
  deadline timestamptz,
  created_at timestamptz,
  modified_at timestamptz,
  comment_state_code integer,
  comment_json jsonb,
  comment_created_at timestamptz,
  comment_modified_at timestamptz,
  reviewer_count integer,
  completed_reviewer_count integer,
  approve_opinion_count integer,
  reject_opinion_count integer,
  root_matches_status boolean,
  root_can_read boolean,
  total_count bigint
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_query text := nullif(pg_catalog.btrim(p_query), '');
  v_limit integer := greatest(1, least(coalesce(p_page_size, 50), 100));
  v_offset integer := (greatest(coalesce(p_page, 1), 1) - 1) * v_limit;
  v_sort_key text := case pg_catalog.lower(coalesce(p_sort_by, ''))
    when 'created_at' then 'created_at'
    when 'createat' then 'created_at'
    when 'deadline' then 'deadline'
    when 'state_code' then 'state_code'
    when 'statecode' then 'state_code'
    when 'comment_modified_at' then 'comment_modified_at'
    when 'commentmodifiedat' then 'comment_modified_at'
    else 'modified_at'
  end;
  v_order_dir text := api.cmd_membership_resolve_sort_direction(p_sort_order);
  v_status text := pg_catalog.lower(coalesce(p_status, 'pending'));
  v_display_mode text := pg_catalog.lower(pg_catalog.btrim(coalesce(p_display_mode, 'all')));
  v_target_table text := nullif(
    pg_catalog.lower(pg_catalog.btrim(coalesce(p_target_table, ''))),
    ''
  );
begin
  if v_actor is null or not api.cmd_review_is_review_member(v_actor) then
    return;
  end if;
  if v_status not in ('pending', 'submitted', 'completed') then
    return;
  end if;
  if v_display_mode not in ('all', 'model_process', 'other') then
    raise exception using errcode = '22023', message = 'INVALID_REVIEW_DISPLAY_MODE';
  end if;
  if v_target_table is not null and not (
    v_target_table = any(array[
      'contacts', 'sources', 'unitgroups', 'flowproperties', 'flows',
      'processes', 'lifecyclemodels'
    ]::text[])
  ) then
    raise exception using errcode = '22023', message = 'INVALID_REVIEW_TARGET_TABLE';
  end if;
  if pg_catalog.char_length(v_query) > 1000 then
    raise exception using errcode = '22023', message = 'REVIEW_QUERY_TOO_LONG';
  end if;

  return query
  with matches as materialized (
    select * from private.review_search_dataset_versions_v1(v_query, v_target_table)
    where v_query is not null
  ), q as (
    select
      review_row.id,
      review_row.data_id,
      pg_catalog.btrim(review_row.data_version::text) as data_version,
      review_row.state_code as review_state_code,
      review_row.review_kind,
      review_row.target_table,
      coalesce(review_row.reviewer_id, '[]'::jsonb) as reviewer_id,
      coalesce(review_row.json, '{}'::jsonb) as json,
      review_row.deadline,
      review_row.created_at,
      greatest(review_row.modified_at, actor_comment.modified_at) as modified_at,
      actor_comment.state_code as comment_state_code,
      coalesce(actor_comment.json::jsonb, '{}'::jsonb) as comment_json,
      actor_comment.created_at as comment_created_at,
      actor_comment.modified_at as comment_modified_at,
      pg_catalog.jsonb_array_length(coalesce(review_row.reviewer_id, '[]'::jsonb))::integer
        as reviewer_count,
      coalesce(review_comments.completed_reviewer_count, 0)::integer
        as completed_reviewer_count,
      coalesce(review_comments.approve_opinion_count, 0)::integer as approve_opinion_count,
      coalesce(review_comments.reject_opinion_count, 0)::integer as reject_opinion_count,
      true as root_matches_status,
      true as root_can_read
    from private.comments as actor_comment
    join private.reviews as review_row on review_row.id = actor_comment.review_id
    left join lateral (
      select
        pg_catalog.count(*) filter (
          where comment_row.state_code in (1, -3, 2, -1)
        ) as completed_reviewer_count,
        pg_catalog.count(*) filter (where comment_row.state_code in (1, 2))
          as approve_opinion_count,
        pg_catalog.count(*) filter (where comment_row.state_code in (-3, -1))
          as reject_opinion_count
      from private.comments as comment_row
      where comment_row.review_id = review_row.id
        and coalesce(review_row.reviewer_id, '[]'::jsonb)
          @> pg_catalog.jsonb_build_array(pg_catalog.to_jsonb(comment_row.reviewer_id::text))
        and comment_row.state_code <> -2
    ) as review_comments on true
    where review_row.review_kind in ('root', 'reference')
      and actor_comment.reviewer_id = v_actor
      and api.policy_review_can_read(review_row.id, v_actor)
      and (
        (v_status = 'pending' and review_row.state_code = 1 and actor_comment.state_code = 0)
        or (v_status = 'submitted' and review_row.state_code = 1 and actor_comment.state_code in (1, -3))
        or (v_status = 'completed' and review_row.state_code in (-1, 2) and actor_comment.state_code <> -2)
      )
      and (
        v_display_mode = 'all'
        or (v_display_mode = 'model_process' and review_row.target_table in ('processes', 'lifecyclemodels'))
        or (v_display_mode = 'other' and review_row.target_table not in ('processes', 'lifecyclemodels'))
      )
      and (v_target_table is null or review_row.target_table = v_target_table)
      and (v_query is null or exists (
        select 1 from matches
        where matches.target_table = review_row.target_table
          and matches.data_id = review_row.data_id
          and matches.data_version = review_row.data_version
      ))
  )
  select q.*, pg_catalog.count(*) over() as total_count
  from q
  order by
    case when v_sort_key = 'created_at' and v_order_dir = 'asc' then q.created_at end asc nulls last,
    case when v_sort_key = 'created_at' and v_order_dir = 'desc' then q.created_at end desc nulls last,
    case when v_sort_key = 'deadline' and v_order_dir = 'asc' then q.deadline end asc nulls last,
    case when v_sort_key = 'deadline' and v_order_dir = 'desc' then q.deadline end desc nulls last,
    case when v_sort_key = 'state_code' and v_order_dir = 'asc' then q.review_state_code end asc nulls last,
    case when v_sort_key = 'state_code' and v_order_dir = 'desc' then q.review_state_code end desc nulls last,
    case when v_sort_key = 'comment_modified_at' and v_order_dir = 'asc' then q.comment_modified_at end asc nulls last,
    case when v_sort_key = 'comment_modified_at' and v_order_dir = 'desc' then q.comment_modified_at end desc nulls last,
    case when v_sort_key = 'modified_at' and v_order_dir = 'asc' then q.modified_at end asc nulls last,
    case when v_sort_key = 'modified_at' and v_order_dir = 'desc' then q.modified_at end desc nulls last,
    q.id
  limit v_limit offset v_offset;
end;
$$;

alter function api.qry_review_get_member_queue_items_v5(
  text, integer, integer, text, text, text, text, text
) owner to postgres;
revoke all on function api.qry_review_get_member_queue_items_v5(
  text, integer, integer, text, text, text, text, text
) from public, anon, service_role;
grant execute on function api.qry_review_get_member_queue_items_v5(
  text, integer, integer, text, text, text, text, text
) to authenticated, api_internal_executor;

comment on function api.qry_review_get_member_queue_items_v5(
  text, integer, integer, text, text, text, text, text
) is
  'Reviewer workspace queue: pending, submitted opinion, and terminal completed stages with actor comment and aggregate progress facts.';

create or replace function api.qry_review_batch_eligibility_v1(
  p_review_ids uuid[],
  p_operation text
)
returns table (
  ordinal integer,
  review_id uuid,
  eligible boolean,
  reason_code text,
  state_code integer,
  target_table text,
  data_version text,
  reviewer_count integer,
  submitted_opinion_count integer,
  approve_opinion_count integer,
  reject_opinion_count integer
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_operation text := pg_catalog.lower(pg_catalog.btrim(coalesce(p_operation, '')));
  v_is_admin boolean;
  v_is_member boolean;
begin
  if v_actor is null then return; end if;
  if v_operation not in (
    'admin-assign', 'admin-approve', 'admin-reject',
    'reviewer-approve', 'reviewer-reject'
  ) then
    raise exception using errcode = '22023', message = 'INVALID_REVIEW_BATCH_OPERATION';
  end if;

  v_is_admin := api.cmd_review_is_review_admin(v_actor);
  v_is_member := api.cmd_review_is_review_member(v_actor);
  if (v_operation like 'admin-%' and not v_is_admin)
    or (v_operation like 'reviewer-%' and not v_is_member) then
    return;
  end if;

  return query
  with requested as (
    select requested_id, requested_ordinal::integer
    from pg_catalog.unnest(coalesce(p_review_ids, array[]::uuid[]))
      with ordinality as item(requested_id, requested_ordinal)
  ), facts as (
    select
      requested.requested_ordinal,
      requested.requested_id,
      review_row.id,
      review_row.state_code,
      review_row.target_table,
      pg_catalog.btrim(review_row.data_version::text) as data_version,
      pg_catalog.jsonb_array_length(coalesce(review_row.reviewer_id, '[]'::jsonb))::integer
        as reviewer_count,
      coalesce(review_comments.submitted_opinion_count, 0)::integer
        as submitted_opinion_count,
      coalesce(review_comments.approve_opinion_count, 0)::integer as approve_opinion_count,
      coalesce(review_comments.reject_opinion_count, 0)::integer as reject_opinion_count,
      actor_comment.state_code as actor_comment_state_code,
      coalesce(review_row.reviewer_id, '[]'::jsonb)
        @> pg_catalog.jsonb_build_array(pg_catalog.to_jsonb(v_actor::text)) as actor_is_assigned
    from requested
    left join private.reviews as review_row
      on review_row.id = requested.requested_id
      and (
        v_operation like 'admin-%'
        or api.policy_review_can_read(review_row.id, v_actor)
      )
    left join private.comments as actor_comment
      on actor_comment.review_id = review_row.id and actor_comment.reviewer_id = v_actor
    left join lateral (
      select
        pg_catalog.count(*) filter (where comment_row.state_code in (1, -3))
          as submitted_opinion_count,
        pg_catalog.count(*) filter (where comment_row.state_code = 1)
          as approve_opinion_count,
        pg_catalog.count(*) filter (where comment_row.state_code = -3)
          as reject_opinion_count
      from private.comments as comment_row
      where comment_row.review_id = review_row.id
        and coalesce(review_row.reviewer_id, '[]'::jsonb)
          @> pg_catalog.jsonb_build_array(pg_catalog.to_jsonb(comment_row.reviewer_id::text))
        and comment_row.state_code <> -2
    ) as review_comments on true
  )
  select
    facts.requested_ordinal,
    facts.requested_id,
    case
      when facts.id is null then false
      when v_operation = 'admin-assign' then facts.state_code in (0, 1)
      when v_operation = 'admin-approve' then
        facts.state_code = 1
        and facts.reviewer_count > 0
        and facts.submitted_opinion_count = facts.reviewer_count
      when v_operation = 'admin-reject' then facts.state_code in (0, 1)
      else facts.state_code = 1
        and facts.actor_is_assigned
        and facts.actor_comment_state_code = 0
    end as eligible,
    case
      when facts.id is null then 'REVIEW_NOT_FOUND'
      when v_operation = 'admin-assign' and facts.state_code not in (0, 1)
        then 'REVIEW_ALREADY_COMPLETED'
      when v_operation = 'admin-approve' and facts.state_code <> 1
        then 'REVIEW_NOT_IN_PROGRESS'
      when v_operation = 'admin-approve' and facts.reviewer_count = 0
        then 'REVIEWER_REQUIRED'
      when v_operation = 'admin-approve'
        and facts.submitted_opinion_count <> facts.reviewer_count
        then 'REVIEWER_OPINIONS_PENDING'
      when v_operation = 'admin-reject' and facts.state_code not in (0, 1)
        then 'REVIEW_ALREADY_COMPLETED'
      when v_operation like 'reviewer-%' and facts.state_code <> 1
        then 'REVIEW_NOT_IN_PROGRESS'
      when v_operation like 'reviewer-%' and not facts.actor_is_assigned
        then 'REVIEWER_REQUIRED'
      when v_operation like 'reviewer-%' and facts.actor_comment_state_code <> 0
        then 'OPINION_ALREADY_SUBMITTED'
      else null
    end as reason_code,
    facts.state_code,
    facts.target_table,
    facts.data_version,
    facts.reviewer_count,
    facts.submitted_opinion_count,
    facts.approve_opinion_count,
    facts.reject_opinion_count
  from facts
  order by facts.requested_ordinal;
end;
$$;

alter function api.qry_review_batch_eligibility_v1(uuid[], text) owner to postgres;
revoke all on function api.qry_review_batch_eligibility_v1(uuid[], text)
  from public, anon, service_role;
grant execute on function api.qry_review_batch_eligibility_v1(uuid[], text)
  to authenticated, api_internal_executor;

comment on function api.qry_review_batch_eligibility_v1(uuid[], text) is
  'Read-only, actor-scoped preflight for review batch confirmations; execution commands remain authoritative and independently revalidate state.';

-- A submitted complex root opinion remains editable until the administrator
-- finalizes the review. Saving it again intentionally returns that opinion to
-- pending so it cannot be mistaken for a currently submitted decision.
create or replace function api.cmd_review_save_comment_draft(
  p_review_id uuid,
  p_json jsonb,
  p_audit jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_review private.reviews%rowtype;
  v_comment private.comments%rowtype;
  v_comment_json jsonb := coalesce(p_json, '{}'::jsonb);
  v_review_json jsonb;
  v_previous_comment_state integer;
begin
  if v_actor is null then
    return pg_catalog.jsonb_build_object('ok', false, 'code', 'AUTH_REQUIRED', 'status', 401, 'message', 'Authentication required');
  end if;
  if coalesce(pg_catalog.jsonb_typeof(v_comment_json), 'null') <> 'object' then
    return pg_catalog.jsonb_build_object('ok', false, 'code', 'INVALID_COMMENT_JSON', 'status', 400, 'message', 'comment json must be an object');
  end if;

  select review_row.* into v_review
  from private.reviews as review_row
  where review_row.id = p_review_id
  for update;

  if not found then
    return pg_catalog.jsonb_build_object('ok', false, 'code', 'REVIEW_NOT_FOUND', 'status', 404, 'message', 'Review not found');
  end if;
  if v_review.state_code <> 1 then
    return pg_catalog.jsonb_build_object(
      'ok', false,
      'code', 'INVALID_REVIEW_STATE',
      'status', 409,
      'message', 'Review comments can only be edited before finalization',
      'details', pg_catalog.jsonb_build_object('state_code', v_review.state_code)
    );
  end if;
  if not api.cmd_review_json_array(v_review.reviewer_id)
    @> pg_catalog.jsonb_build_array(pg_catalog.to_jsonb(v_actor::text)) then
    return pg_catalog.jsonb_build_object('ok', false, 'code', 'REVIEWER_REQUIRED', 'status', 403, 'message', 'Only assigned reviewers can edit review comments');
  end if;

  select comment_row.* into v_comment
  from private.comments as comment_row
  where comment_row.review_id = p_review_id and comment_row.reviewer_id = v_actor
  for update;

  if found and v_comment.state_code not in (0, 1, -3) then
    return pg_catalog.jsonb_build_object(
      'ok', false,
      'code', 'INVALID_COMMENT_STATE',
      'status', 409,
      'message', 'This reviewer comment can no longer be edited',
      'details', pg_catalog.jsonb_build_object('state_code', v_comment.state_code)
    );
  end if;

  v_previous_comment_state := v_comment.state_code;
  if v_comment.review_id is null then
    insert into private.comments (review_id, reviewer_id, json, state_code)
    values (p_review_id, v_actor, v_comment_json::json, 0)
    returning * into v_comment;
  else
    update private.comments
    set json = v_comment_json::json,
        state_code = 0,
        modified_at = pg_catalog.now()
    where review_id = p_review_id and reviewer_id = v_actor
    returning * into v_comment;
  end if;

  v_review_json := api.cmd_review_append_log(
    coalesce(v_review.json, '{}'::jsonb),
    'submit_comments_temporary',
    v_actor,
    pg_catalog.jsonb_build_object(
      'reviewer_id', v_actor,
      'previous_comment_state_code', v_previous_comment_state,
      'comment_state_code', 0
    )
  );
  update private.reviews
  set json = v_review_json, modified_at = pg_catalog.now()
  where id = p_review_id
  returning * into v_review;

  insert into private.command_audit_log (
    command, actor_user_id, target_table, target_id, payload
  ) values (
    'cmd_review_save_comment_draft', v_actor, 'reviews', p_review_id,
    coalesce(p_audit, '{}'::jsonb) || pg_catalog.jsonb_build_object(
      'reviewer_id', v_actor,
      'previous_comment_state_code', v_previous_comment_state,
      'comment_state_code', 0
    )
  );

  return pg_catalog.jsonb_build_object(
    'ok', true,
    'data', pg_catalog.jsonb_build_object(
      'review', pg_catalog.to_jsonb(v_review),
      'comment', pg_catalog.to_jsonb(v_comment)
    )
  );
end;
$$;

alter function api.cmd_review_save_comment_draft(uuid, jsonb, jsonb) owner to postgres;
revoke all on function api.cmd_review_save_comment_draft(uuid, jsonb, jsonb)
  from public, anon;
grant execute on function api.cmd_review_save_comment_draft(uuid, jsonb, jsonb)
  to authenticated, api_internal_executor;

comment on function api.cmd_review_save_comment_draft(uuid, jsonb, jsonb) is
  'Stores an assigned reviewer draft only while the review is active; re-editing a submitted opinion resets its state to pending without provisioning references.';

insert into private.api_capability_grants (
  routine_identity, capability_id, allow_anon, allow_authenticated, allow_service_role
)
values
  (
    'api.qry_review_get_admin_queue_items_v5(text, integer, integer, text, text, text, text, text)',
    'NX-REV-01', false, true, false
  ),
  (
    'api.qry_review_get_member_queue_items_v5(text, integer, integer, text, text, text, text, text)',
    'NX-REV-01', false, true, false
  ),
  (
    'api.qry_review_batch_eligibility_v1(uuid[], text)',
    'NX-REV-01', false, true, false
  )
on conflict (routine_identity) do update set
  capability_id = excluded.capability_id,
  allow_anon = excluded.allow_anon,
  allow_authenticated = excluded.allow_authenticated,
  allow_service_role = excluded.allow_service_role;
