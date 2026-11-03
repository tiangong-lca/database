CREATE OR REPLACE FUNCTION "private"."study_require"("p_condition" boolean, "p_code" "text") RETURNS "void"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$ begin
  if p_condition is not true then raise exception using errcode='P0001',message=p_code; end if;
end $$;

ALTER FUNCTION "private"."study_require"("p_condition" boolean, "p_code" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_require"("p_condition" boolean, "p_code" "text") FROM PUBLIC;
