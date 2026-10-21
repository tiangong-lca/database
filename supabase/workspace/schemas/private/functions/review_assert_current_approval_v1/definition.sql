CREATE OR REPLACE FUNCTION "private"."review_assert_current_approval_v1"("p_review" "private"."reviews") RETURNS "void"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if pg_catalog.jsonb_array_length(
    coalesce(p_review.reviewer_id, '[]'::jsonb)
  ) = 0 then
    raise exception using
      errcode = '55000',
      message = 'REVIEWER_REQUIRED';
  end if;

  if not exists (
    select 1
    from private.comments as comment_row
    where comment_row.review_id = p_review.id
      and comment_row.state_code = 1
      and coalesce(p_review.reviewer_id, '[]'::jsonb)
        @> pg_catalog.jsonb_build_array(comment_row.reviewer_id::text)
  ) then
    raise exception using
      errcode = '55000',
      message = 'REVIEWER_APPROVAL_REQUIRED';
  end if;
end;
$$;

ALTER FUNCTION "private"."review_assert_current_approval_v1"("p_review" "private"."reviews") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."review_assert_current_approval_v1"("p_review" "private"."reviews") FROM PUBLIC;

GRANT ALL ON FUNCTION "private"."review_assert_current_approval_v1"("p_review" "private"."reviews") TO "api_internal_executor";
