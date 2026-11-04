CREATE OR REPLACE FUNCTION "private"."study_method_uuid"("p_value" "jsonb") RETURNS boolean
    LANGUAGE "sql" IMMUTABLE
    SET "search_path" TO ''
    AS $_$
 select jsonb_typeof(p_value)='string' and (p_value#>>'{}') ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' and (p_value#>>'{}')<>'00000000-0000-0000-0000-000000000000'$_$;

ALTER FUNCTION "private"."study_method_uuid"("p_value" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_method_uuid"("p_value" "jsonb") FROM PUBLIC;
