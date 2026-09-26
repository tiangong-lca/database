CREATE OR REPLACE FUNCTION "api"."cmd_review_save_comment_draft"("p_review_id" "uuid", "p_json" "jsonb", "p_audit" "jsonb" DEFAULT '{}'::"jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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

ALTER FUNCTION "api"."cmd_review_save_comment_draft"("p_review_id" "uuid", "p_json" "jsonb", "p_audit" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."cmd_review_save_comment_draft"("p_review_id" "uuid", "p_json" "jsonb", "p_audit" "jsonb") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."cmd_review_save_comment_draft"("p_review_id" "uuid", "p_json" "jsonb", "p_audit" "jsonb") TO "api_internal_executor";

GRANT ALL ON FUNCTION "api"."cmd_review_save_comment_draft"("p_review_id" "uuid", "p_json" "jsonb", "p_audit" "jsonb") TO "authenticated";
