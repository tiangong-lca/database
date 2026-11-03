CREATE OR REPLACE FUNCTION "private"."study_source_items"("p_value" "jsonb") RETURNS SETOF "jsonb"
    LANGUAGE "plpgsql" IMMUTABLE
    SET "search_path" TO ''
    AS $$ begin
  if p_value is null or p_value='null'::jsonb then return; end if;
  if jsonb_typeof(p_value)='array' then return query select * from jsonb_array_elements(p_value);
  elsif jsonb_typeof(p_value)='object' then return next p_value;
  else raise exception 'INVALID_REQUEST'; end if;
end $$;

ALTER FUNCTION "private"."study_source_items"("p_value" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_source_items"("p_value" "jsonb") FROM PUBLIC;
