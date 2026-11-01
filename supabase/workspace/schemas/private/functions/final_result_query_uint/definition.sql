CREATE OR REPLACE FUNCTION "private"."final_result_query_uint"("p_value" "jsonb", "p_max" bigint) RETURNS bigint
    LANGUAGE "plpgsql" IMMUTABLE
    SET "search_path" TO ''
    AS $_$
begin
  if jsonb_typeof(p_value) is distinct from 'number' or (p_value#>>'{}') !~ '^(0|[1-9][0-9]{0,15})$' then
    raise exception using errcode='22023',message='Invalid final Result query integer';
  end if;
  if (p_value#>>'{}')::bigint > p_max then
    raise exception using errcode='22023',message='Final Result query integer exceeds budget';
  end if;
  return (p_value#>>'{}')::bigint;
end;
$_$;

ALTER FUNCTION "private"."final_result_query_uint"("p_value" "jsonb", "p_max" bigint) OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."final_result_query_uint"("p_value" "jsonb", "p_max" bigint) FROM PUBLIC;
