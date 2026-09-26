CREATE OR REPLACE FUNCTION "api"."qry_review_batch_eligibility_v1"("p_review_ids" "uuid"[], "p_operation" "text") RETURNS TABLE("ordinal" integer, "review_id" "uuid", "eligible" boolean, "reason_code" "text", "state_code" integer, "target_table" "text", "data_version" "text", "reviewer_count" integer, "submitted_opinion_count" integer, "approve_opinion_count" integer, "reject_opinion_count" integer)
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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

ALTER FUNCTION "api"."qry_review_batch_eligibility_v1"("p_review_ids" "uuid"[], "p_operation" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."qry_review_batch_eligibility_v1"("p_review_ids" "uuid"[], "p_operation" "text") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."qry_review_batch_eligibility_v1"("p_review_ids" "uuid"[], "p_operation" "text") TO "authenticated";

GRANT ALL ON FUNCTION "api"."qry_review_batch_eligibility_v1"("p_review_ids" "uuid"[], "p_operation" "text") TO "api_internal_executor";
