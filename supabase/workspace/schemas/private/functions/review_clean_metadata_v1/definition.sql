CREATE OR REPLACE FUNCTION "private"."review_clean_metadata_v1"("p_value" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" IMMUTABLE
    SET "search_path" TO ''
    AS $$
declare
  v_result jsonb;
  v_item jsonb;
  v_key text;
  v_clean jsonb;
begin
  if p_value is null or p_value = 'null'::jsonb then return null; end if;
  if jsonb_typeof(p_value) = 'object' then
    v_result := '{}'::jsonb;
    for v_key, v_item in select key, value from jsonb_each(p_value) loop
      v_clean := private.review_clean_metadata_v1(v_item);
      if v_clean is not null then v_result := v_result || jsonb_build_object(v_key, v_clean); end if;
    end loop;
    return nullif(v_result, '{}'::jsonb);
  elsif jsonb_typeof(p_value) = 'array' then
    v_result := '[]'::jsonb;
    for v_item in select value from jsonb_array_elements(p_value) loop
      v_clean := private.review_clean_metadata_v1(v_item);
      if v_clean is not null then v_result := v_result || jsonb_build_array(v_clean); end if;
    end loop;
    return nullif(v_result, '[]'::jsonb);
  elsif jsonb_typeof(p_value) = 'string'
    and (btrim(p_value #>> '{}') = '' or p_value #>> '{}' = 'undefined') then
    return null;
  end if;
  return p_value;
end;
$$;

ALTER FUNCTION "private"."review_clean_metadata_v1"("p_value" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."review_clean_metadata_v1"("p_value" "jsonb") FROM PUBLIC;
