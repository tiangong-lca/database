CREATE OR REPLACE FUNCTION "private"."review_assert_metadata_v1"("p_value" "jsonb", "p_table" "text") RETURNS "void"
    LANGUAGE "plpgsql" IMMUTABLE
    SET "search_path" TO ''
    AS $$
begin
  if private.review_metadata_schema_v1(p_table) is null
    or not extensions.jsonb_matches_schema(
      private.review_metadata_schema_v1(p_table)::json, coalesce(p_value, '{}'::jsonb)
    ) then
    raise exception using errcode = '22023', message = 'REVIEW_METADATA_INVALID',
      hint = 'Correct the review and compliance fields before submitting an approval.';
  end if;
end;
$$;

ALTER FUNCTION "private"."review_assert_metadata_v1"("p_value" "jsonb", "p_table" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."review_assert_metadata_v1"("p_value" "jsonb", "p_table" "text") FROM PUBLIC;
