CREATE OR REPLACE FUNCTION "api"."qry_review_get_items"("p_review_ids" "uuid"[] DEFAULT NULL::"uuid"[], "p_data_id" "uuid" DEFAULT NULL::"uuid", "p_data_version" "text" DEFAULT NULL::"text", "p_state_codes" integer[] DEFAULT NULL::integer[]) RETURNS TABLE("id" "uuid", "data_id" "uuid", "data_version" "text", "state_code" integer, "reviewer_id" "jsonb", "json" "jsonb", "deadline" timestamp with time zone, "created_at" timestamp with time zone, "modified_at" timestamp with time zone, "target_table" "text", "submitted_revision_checksum" "text", "opinion_scope" "text")
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  with actor as materialized (
    select
      auth.uid() as id,
      private.oauth_client_has_capability('NX-REV-01') as participant_access,
      private.oauth_client_has_capability('CLI-REVIEW-AUTHOR-01') as author_access
  )
  select
    r.id,
    r.data_id,
    r.data_version::text,
    r.state_code,
    case when a.participant_access then coalesce(r.reviewer_id, '[]'::jsonb) else '[]'::jsonb end,
    case when a.participant_access then coalesce(r.json, '{}'::jsonb) else
      jsonb_strip_nulls(jsonb_build_object(
        'review_kind', r.review_kind,
        'data', jsonb_build_object(
          'id', r.data_id,
          'version', r.data_version::text,
          'table', coalesce(r.target_table, r.json->'data'->>'table'),
          'name', r.json->'data'->'name'
        ),
        'user', jsonb_build_object('id', a.id),
        'comment', case when r.state_code = -1 then
          jsonb_build_object('message', private.review_rejection_reason_v1(r.json))
        end
      ))
    end,
    case when a.participant_access then r.deadline end,
    r.created_at,
    r.modified_at,
    coalesce(r.target_table, r.json->'data'->>'table'),
    r.submitted_revision_checksum,
    case
      when a.participant_access and api.cmd_review_is_review_admin(a.id) then 'admin'
      when a.participant_access and api.cmd_review_is_review_member(a.id)
        and (r.reviewer_id ? a.id::text or exists (
          select 1 from private.comments as c where c.review_id = r.id and c.reviewer_id = a.id
        )) then 'reviewer'
      else 'returned'
    end
  from private.reviews as r
  cross join actor as a
  where a.id is not null
    and (p_review_ids is null or r.id = any (p_review_ids))
    and (
      p_data_id is null
      or r.data_id = p_data_id
      or (r.data_id is null and r.json->'data'->>'id' = p_data_id::text)
    )
    and (
      p_data_version is null
      or r.data_version = p_data_version
      or (r.data_version is null and r.json->'data'->>'version' = p_data_version)
    )
    and (p_state_codes is null or r.state_code = any (p_state_codes))
    and (
      a.participant_access
      or (
        a.author_access
        and r.json->'user'->>'id' = a.id::text
        and (r.target_owner_id is null or r.target_owner_id = a.id)
        and (
          r.review_kind = 'root'
          or r.review_kind is null -- Historical author records predate the root/reference split.
          or (
            r.review_kind = 'reference'
            and exists (
              -- A reference can be created by another root submitter. Count it
              -- as the owner's submission only when that owner submitted it.
              select 1
              from private.command_audit_log as submission
              where submission.command = 'cmd_review_submit'
                and submission.actor_user_id = a.id
                and submission.target_table = r.target_table
                and submission.target_id = r.data_id
                and submission.target_version = r.data_version::text
                and submission.payload->>'review_id' = r.id::text
            )
          )
        )
      )
    )
    and api.policy_review_can_read(r.id, a.id)
  order by r.modified_at desc, r.id desc;
$$;

ALTER FUNCTION "api"."qry_review_get_items"("p_review_ids" "uuid"[], "p_data_id" "uuid", "p_data_version" "text", "p_state_codes" integer[]) OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."qry_review_get_items"("p_review_ids" "uuid"[], "p_data_id" "uuid", "p_data_version" "text", "p_state_codes" integer[]) FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."qry_review_get_items"("p_review_ids" "uuid"[], "p_data_id" "uuid", "p_data_version" "text", "p_state_codes" integer[]) TO "api_internal_executor";

GRANT ALL ON FUNCTION "api"."qry_review_get_items"("p_review_ids" "uuid"[], "p_data_id" "uuid", "p_data_version" "text", "p_state_codes" integer[]) TO "authenticated";
