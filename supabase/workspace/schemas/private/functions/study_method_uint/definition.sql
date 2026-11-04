CREATE OR REPLACE FUNCTION "private"."study_method_uint"("p_value" "jsonb", "p_min" integer, "p_max" integer) RETURNS boolean
    LANGUAGE "plpgsql" IMMUTABLE
    SET "search_path" TO ''
    AS $_$begin
 return coalesce(jsonb_typeof(p_value)='number' and p_value::text ~ '^(0|[1-9][0-9]*)$' and(p_value#>>'{}')::numeric between p_min and p_max,false);
exception when invalid_text_representation or numeric_value_out_of_range then return false;end$_$;

ALTER FUNCTION "private"."study_method_uint"("p_value" "jsonb", "p_min" integer, "p_max" integer) OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_method_uint"("p_value" "jsonb", "p_min" integer, "p_max" integer) FROM PUBLIC;
