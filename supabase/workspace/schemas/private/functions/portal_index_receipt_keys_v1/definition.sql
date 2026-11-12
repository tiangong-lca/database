CREATE OR REPLACE FUNCTION "private"."portal_index_receipt_keys_v1"("p_candidates" "jsonb") RETURNS SETOF "jsonb"
    LANGUAGE "sql" IMMUTABLE
    SET "search_path" TO ''
    AS $$
  select candidate || jsonb_build_object('operation', operation, 'locale', locale)
  from (
    select 'upsert' as operation, value as candidate from jsonb_array_elements(p_candidates->'upserts')
    union all
    select 'withdrawal', value from jsonb_array_elements(p_candidates->'withdrawals')
  ) as candidates
  cross join (values ('zh-CN'), ('en'), ('de'), ('fr')) as locales(locale);
$$;

ALTER FUNCTION "private"."portal_index_receipt_keys_v1"("p_candidates" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."portal_index_receipt_keys_v1"("p_candidates" "jsonb") FROM PUBLIC;
