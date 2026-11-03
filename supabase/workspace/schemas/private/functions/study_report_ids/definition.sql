CREATE OR REPLACE FUNCTION "private"."study_report_ids"("p_ids" "jsonb", "p_min" integer, "p_max" integer) RETURNS boolean
    LANGUAGE "plpgsql" IMMUTABLE
    SET "search_path" TO ''
    AS $_$declare x jsonb;seen text[]:='{}'::text[];begin
 if jsonb_typeof(p_ids) is distinct from 'array' then return false;end if;
 if jsonb_array_length(p_ids) not between p_min and p_max then return false;end if;
 for x in select * from jsonb_array_elements(p_ids) loop
  if not private.study_text(x,128,'^[A-Za-z0-9][A-Za-z0-9._:-]*$') or (x#>>'{}')=any(seen) then return false;end if;seen:=seen||(x#>>'{}');
 end loop;return true;
end$_$;

ALTER FUNCTION "private"."study_report_ids"("p_ids" "jsonb", "p_min" integer, "p_max" integer) OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_report_ids"("p_ids" "jsonb", "p_min" integer, "p_max" integer) FROM PUBLIC;
