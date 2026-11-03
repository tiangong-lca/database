CREATE OR REPLACE FUNCTION "private"."review_guard_comment_metadata_v1"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
declare
  v_table text;
  v_metadata jsonb;
begin
  select r.target_table into v_table from private.reviews r
  where r.id = new.review_id and r.review_kind = 'root';
  if v_table not in ('processes', 'lifecyclemodels') or v_table is null then return new; end if;
  if not coalesce(new.json::jsonb ? 'modellingAndValidation', false) then return new; end if;
  v_metadata := private.review_clean_metadata_v1(new.json::jsonb -> 'modellingAndValidation');
  if new.state_code = 1 then
    perform private.review_assert_metadata_v1(v_metadata, v_table);
  end if;
  new.json := case when v_metadata is null then new.json::jsonb - 'modellingAndValidation'
    else jsonb_set(new.json::jsonb, '{modellingAndValidation}', v_metadata) end;
  return new;
end;
$$;

ALTER FUNCTION "private"."review_guard_comment_metadata_v1"() OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."review_guard_comment_metadata_v1"() FROM PUBLIC;
