CREATE OR REPLACE FUNCTION "private"."study_method_text"("p_value" "jsonb", "p_max" integer) RETURNS boolean
    LANGUAGE "plpgsql" IMMUTABLE
    SET "search_path" TO ''
    AS $$declare v text;begin
 if jsonb_typeof(p_value) is distinct from 'string' then return false;end if;v:=p_value#>>'{}';
 return octet_length(v) between 1 and p_max and v !~ U&'[\0001-\001F\007F-\009F]'
 and btrim(v,U&'\0009\000A\000B\000C\000D\0020\0085\00A0\1680\2000\2001\2002\2003\2004\2005\2006\2007\2008\2009\200A\2028\2029\202F\205F\3000')<>'';
end$$;

ALTER FUNCTION "private"."study_method_text"("p_value" "jsonb", "p_max" integer) OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_method_text"("p_value" "jsonb", "p_max" integer) FROM PUBLIC;
