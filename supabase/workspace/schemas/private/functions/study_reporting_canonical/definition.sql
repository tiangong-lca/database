CREATE OR REPLACE FUNCTION "private"."study_reporting_canonical"("p_value" "jsonb") RETURNS "text"
    LANGUAGE "plpgsql" STABLE
    SET "search_path" TO ''
    AS $$declare result text;begin
 case jsonb_typeof(p_value)
 when 'object' then select '{'||coalesce(string_agg(to_jsonb(k)::text||':'||private.study_reporting_canonical(v),',' order by k collate "C"),'')||'}' into result from jsonb_each(p_value)e(k,v);
 when 'array' then select '['||coalesce(string_agg(private.study_reporting_canonical(v),',' order by n),'')||']' into result from jsonb_array_elements(p_value) with ordinality e(v,n);
 when 'number' then
  if (p_value::text)::numeric<>trunc((p_value::text)::numeric) or abs((p_value::text)::numeric)>9007199254740991 then raise exception 'REFERENCE_MISMATCH';end if;
  result:=((p_value::text)::numeric::bigint)::text;
 else result:=p_value::text;end case;return result;
end$$;

ALTER FUNCTION "private"."study_reporting_canonical"("p_value" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_reporting_canonical"("p_value" "jsonb") FROM PUBLIC;
