CREATE OR REPLACE FUNCTION "private"."study_keys"("p_value" "jsonb", "p_keys" "text"[]) RETURNS boolean
    LANGUAGE "plpgsql" IMMUTABLE
    SET "search_path" TO ''
    AS $$ begin
  if jsonb_typeof(p_value) is distinct from 'object' then return false; end if;
  return p_value ?& p_keys and not exists(select 1 from jsonb_object_keys(p_value) k where k<>all(p_keys));
end $$;

ALTER FUNCTION "private"."study_keys"("p_value" "jsonb", "p_keys" "text"[]) OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_keys"("p_value" "jsonb", "p_keys" "text"[]) FROM PUBLIC;
