CREATE OR REPLACE FUNCTION "private"."study_comparability_valid"("p_value" "jsonb") RETURNS boolean
    LANGUAGE "plpgsql" IMMUTABLE
    SET "search_path" TO ''
    AS $_$ declare x jsonb; seen text[]:='{}'::text[]; begin
 if not private.study_keys(p_value,array['status','reasonCodes']) or coalesce(p_value->>'status' not in ('not_assessed','comparable','not_comparable'),true)
 or jsonb_typeof(p_value->'reasonCodes') is distinct from 'array' then return false; end if;
 if jsonb_array_length(p_value->'reasonCodes')>32 then return false; end if;
 for x in select * from jsonb_array_elements(p_value->'reasonCodes') loop
  if not private.study_text(x,128,'^[a-z][a-z0-9_]*$') or (x#>>'{}')=any(seen) then return false; end if;
  seen:=seen||(x#>>'{}');
 end loop; return true;
end $_$;

ALTER FUNCTION "private"."study_comparability_valid"("p_value" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_comparability_valid"("p_value" "jsonb") FROM PUBLIC;
