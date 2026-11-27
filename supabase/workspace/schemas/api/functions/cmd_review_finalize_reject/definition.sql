CREATE OR REPLACE FUNCTION "api"."cmd_review_finalize_reject"("p_review_id" "uuid", "p_reason" "text", "p_audit" "jsonb" DEFAULT '{}'::"jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
declare
  v_actor uuid := auth.uid();
  v_review private.reviews%rowtype;
  v_reason text := btrim(coalesce(p_reason, ''));
  v_other_active boolean;
begin
  if v_actor is null or not api.cmd_review_is_review_admin(v_actor) then
    return jsonb_build_object(
      'ok', false,
      'code', 'REVIEW_ADMIN_REQUIRED',
      'status', 403
    );
  end if;

  if v_reason = '' then
    return jsonb_build_object(
      'ok', false,
      'code', 'REVIEW_REJECT_REASON_REQUIRED',
      'status', 400
    );
  end if;

  -- Root and Reference decisions for the same dataset version must see the
  -- preceding decision before checking whether the dataset can be released.
  -- Use the same lock order regardless of which review was requested.
  perform peer.id
  from private.reviews as requested
  join private.reviews as peer
    on peer.target_table = requested.target_table
    and peer.data_id = requested.data_id
    and btrim(peer.data_version::text) = btrim(requested.data_version::text)
  where requested.id = p_review_id
    and requested.review_kind in ('root', 'reference')
    and requested.state_code in (0, 1)
    and peer.state_code in (0, 1)
  order by peer.id
  for update of peer;

  select review_row.*
  into v_review
  from private.reviews as review_row
  where review_row.id = p_review_id
  for update;

  if not found or v_review.review_kind not in ('root', 'reference') then
    return jsonb_build_object(
      'ok', false,
      'code', 'REVIEW_NOT_FOUND',
      'status', 404
    );
  end if;

  if v_review.state_code not in (0, 1) then
    return jsonb_build_object(
      'ok', false,
      'code', 'INVALID_REVIEW_STATE',
      'status', 409
    );
  end if;

  select exists (
    select 1
    from private.reviews as active_review
    where active_review.id <> p_review_id
      and active_review.target_table = v_review.target_table
      and active_review.data_id = v_review.data_id
      and btrim(active_review.data_version::text)
        = btrim(v_review.data_version::text)
      and active_review.state_code in (0, 1)
  )
  into v_other_active;

  perform set_config('app.review_controlled_write', 'on', true);
  if not v_other_active then
    execute format(
      'update public.%I
          set state_code = 0,
              modified_at = now()
        where id = $1
          and version = $2
          and state_code = 20',
      v_review.target_table
    ) using v_review.data_id, btrim(v_review.data_version::text);
  end if;

  update private.comments
  set state_code = -1,
      modified_at = now()
  where review_id = p_review_id
    and state_code <> -2;

  update private.reviews
  set state_code = -1,
      json = api.cmd_review_append_log(
        jsonb_set(
          coalesce(json, '{}'::jsonb),
          '{comment}',
          coalesce(json->'comment', '{}'::jsonb)
            || jsonb_build_object('message', v_reason),
          true
        ),
        'rejected',
        v_actor,
        jsonb_build_object('reason', v_reason)
      ),
      modified_at = now()
  where id = p_review_id
  returning * into v_review;
  perform set_config('app.review_controlled_write', 'off', true);

  perform private.review_notify_event_v1(
    case when v_review.review_kind = 'root'
      then 'root_rejected'
      else 'reference_rejected'
    end,
    v_review.id,
    v_review.target_owner_id,
    v_actor,
    v_review.target_table,
    v_review.data_id,
    btrim(v_review.data_version::text),
    case when v_review.review_kind = 'root' then v_review.id else null end,
    null,
    'ADMIN_REJECTED'
  );

  if v_review.review_kind = 'reference' then
    perform private.review_notify_impacted_roots_v1(
      v_review,
      'reference_rejected',
      v_actor,
      'ADMIN_REJECTED'
    );
  end if;

  insert into private.command_audit_log (
    command,
    actor_user_id,
    target_table,
    target_id,
    payload
  )
  values (
    'cmd_review_finalize_reject',
    v_actor,
    'reviews',
    p_review_id,
    coalesce(p_audit, '{}'::jsonb) || jsonb_build_object(
      'review_kind', v_review.review_kind,
      'reason', v_reason,
      'target_released', not v_other_active
    )
  );

  return jsonb_build_object(
    'ok', true,
    'data', jsonb_build_object(
      'review', to_jsonb(v_review),
      'targetReleased', not v_other_active
    )
  );
exception
  when others then
    perform set_config('app.review_controlled_write', 'off', true);
    raise;
end;
$_$;

ALTER FUNCTION "api"."cmd_review_finalize_reject"("p_review_id" "uuid", "p_reason" "text", "p_audit" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."cmd_review_finalize_reject"("p_review_id" "uuid", "p_reason" "text", "p_audit" "jsonb") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."cmd_review_finalize_reject"("p_review_id" "uuid", "p_reason" "text", "p_audit" "jsonb") TO "api_internal_executor";

GRANT ALL ON FUNCTION "api"."cmd_review_finalize_reject"("p_review_id" "uuid", "p_reason" "text", "p_audit" "jsonb") TO "authenticated";
