CREATE OR REPLACE FUNCTION "api"."cmd_review_finalize_approve"("p_review_id" "uuid", "p_audit" "jsonb" DEFAULT '{}'::"jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'api', 'private', 'public', 'util', 'extensions', 'pg_temp'
    AS $_$
declare
  v_actor uuid := auth.uid();
  v_review private.reviews%rowtype;
  v_target_row jsonb;
  v_current_checksum text;
  v_approved_checksum text;
  v_review_items jsonb := '[]'::jsonb;
  v_compliance_items jsonb := '[]'::jsonb;
begin
  if v_actor is null or not api.cmd_review_is_review_admin(v_actor) then
    return jsonb_build_object(
      'ok', false,
      'code', 'REVIEW_ADMIN_REQUIRED',
      'status', 403
    );
  end if;

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

  if v_review.state_code <> 1 then
    return jsonb_build_object(
      'ok', false,
      'code', 'INVALID_REVIEW_STATE',
      'status', 409
    );
  end if;

  begin
    perform private.review_assert_current_approval_v1(v_review);
  exception
    when sqlstate '55000' then
      return jsonb_build_object(
        'ok', false,
        'code', sqlerrm,
        'status', 409
      );
  end;

  v_target_row := api.cmd_review_get_dataset_row(
    v_review.target_table,
    v_review.data_id,
    btrim(v_review.data_version::text),
    true
  );

  if v_target_row is null then
    return jsonb_build_object(
      'ok', false,
      'code', 'REVIEW_TARGET_NOT_FOUND',
      'status', 404
    );
  end if;

  if coalesce((v_target_row->>'state_code')::integer, 0) not in (20, 100) then
    return jsonb_build_object(
      'ok', false,
      'code', 'REVIEW_TARGET_NOT_IN_REVIEW',
      'status', 409
    );
  end if;

  v_current_checksum := private.review_revision_fingerprint_v1(
    v_review.target_table,
    v_target_row
  );
  if v_current_checksum <> v_review.submitted_revision_checksum then
    return jsonb_build_object(
      'ok', false,
      'code', 'REVISION_CHECKSUM_MISMATCH',
      'status', 409
    );
  end if;

  perform set_config('app.review_controlled_write', 'on', true);

  if v_review.review_kind = 'root'
    and v_review.target_table in ('processes', 'lifecyclemodels') then
    select coalesce(jsonb_agg(review_item.value), '[]'::jsonb)
    into v_review_items
    from private.comments as comment_row
    cross join lateral jsonb_array_elements(
      api.cmd_review_json_array(
        to_jsonb(comment_row.json)
          #> '{modellingAndValidation,validation,review}'
      )
    ) as review_item(value)
    where comment_row.review_id = p_review_id
      and comment_row.state_code = 1;

    select coalesce(jsonb_agg(compliance_item.value), '[]'::jsonb)
    into v_compliance_items
    from private.comments as comment_row
    cross join lateral jsonb_array_elements(
      api.cmd_review_json_array(
        to_jsonb(comment_row.json)
          #> '{modellingAndValidation,complianceDeclarations,compliance}'
      )
    ) as compliance_item(value)
    where comment_row.review_id = p_review_id
      and comment_row.state_code = 1;

    v_target_row := api.cmd_review_apply_mv_payload(
      v_review.target_table,
      v_review.data_id,
      btrim(v_review.data_version::text),
      v_review_items,
      v_compliance_items
    );
  end if;

  v_approved_checksum := private.review_revision_fingerprint_v1(
    v_review.target_table,
    v_target_row
  );

  if v_review.review_kind = 'root'
    and v_review.target_table not in ('processes', 'lifecyclemodels')
    and v_approved_checksum <> v_review.submitted_revision_checksum then
    perform set_config('app.review_controlled_write', 'off', true);
    return jsonb_build_object(
      'ok', false,
      'code', 'REVISION_CHECKSUM_MISMATCH',
      'status', 409
    );
  end if;

  if v_review.review_kind = 'reference' then
    v_approved_checksum := v_review.submitted_revision_checksum;
  end if;

  execute format(
    'update public.%I
        set state_code = 100,
            modified_at = now()
      where id = $1
        and version = $2
        and state_code in (20, 100)',
    v_review.target_table
  ) using v_review.data_id, btrim(v_review.data_version::text);

  update private.comments
  set state_code = 2,
      modified_at = now()
  where review_id = p_review_id
    and state_code <> -2;

  update private.reviews
  set state_code = 2,
      approved_revision_checksum = v_approved_checksum,
      json = api.cmd_review_append_log(
        coalesce(json, '{}'::jsonb),
        'approved',
        v_actor,
        jsonb_build_object(
          'approved_revision_checksum',
          v_approved_checksum
        )
      ),
      modified_at = now()
  where id = p_review_id
  returning * into v_review;

  if v_review.review_kind = 'reference' then
    perform private.review_notify_impacted_roots_v1(
      v_review,
      'reference_approved',
      v_actor,
      null
    );
  end if;

  perform set_config('app.review_controlled_write', 'off', true);

  insert into private.command_audit_log (
    command,
    actor_user_id,
    target_table,
    target_id,
    payload
  )
  values (
    'cmd_review_finalize_approve',
    v_actor,
    'reviews',
    p_review_id,
    coalesce(p_audit, '{}'::jsonb) || jsonb_build_object(
      'review_kind', v_review.review_kind,
      'approved_revision_checksum', v_approved_checksum,
      'target_state_code', 100
    )
  );

  return jsonb_build_object(
    'ok', true,
    'data', jsonb_build_object('review', to_jsonb(v_review))
  );
exception
  when others then
    perform set_config('app.review_controlled_write', 'off', true);
    raise;
end;
$_$;

ALTER FUNCTION "api"."cmd_review_finalize_approve"("p_review_id" "uuid", "p_audit" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."cmd_review_finalize_approve"("p_review_id" "uuid", "p_audit" "jsonb") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."cmd_review_finalize_approve"("p_review_id" "uuid", "p_audit" "jsonb") TO "api_internal_executor";

GRANT ALL ON FUNCTION "api"."cmd_review_finalize_approve"("p_review_id" "uuid", "p_audit" "jsonb") TO "authenticated";
