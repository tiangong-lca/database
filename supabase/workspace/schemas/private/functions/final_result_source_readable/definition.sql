CREATE OR REPLACE FUNCTION "private"."final_result_source_readable"("p_id" "uuid", "p_version" "text") RETURNS boolean
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    SET "row_security" TO 'on'
    AS $$
begin
 return auth.uid() is not null and exists(select 1 from public.processes where id=p_id and version=p_version::character(9) and state_code<>120);
end;
$$;

ALTER FUNCTION "private"."final_result_source_readable"("p_id" "uuid", "p_version" "text") OWNER TO "api_internal_executor";

REVOKE ALL ON FUNCTION "private"."final_result_source_readable"("p_id" "uuid", "p_version" "text") FROM PUBLIC;

GRANT ALL ON FUNCTION "private"."final_result_source_readable"("p_id" "uuid", "p_version" "text") TO "postgres";
