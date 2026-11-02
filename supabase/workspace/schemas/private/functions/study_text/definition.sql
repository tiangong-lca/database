CREATE OR REPLACE FUNCTION "private"."study_text"("p_value" "jsonb", "p_max" integer, "p_pattern" "text" DEFAULT NULL::"text") RETURNS boolean
    LANGUAGE "plpgsql" IMMUTABLE
    SET "search_path" TO ''
    AS $$ declare v text; begin
  if jsonb_typeof(p_value) is distinct from 'string' then return false; end if;
  v:=p_value#>>'{}';
  -- Edge's qualified Zod4 text bounds count Unicode code points. Retain its
  -- separate UTF8 byte bound; do not substitute JS UTF16 string.length here.
  if length(v) not between 1 and p_max
    or octet_length(v)>p_max*4 or btrim(v,U&'\0009\000A\000B\000C\000D\0020\00A0\1680\2000\2001\2002\2003\2004\2005\2006\2007\2008\2009\200A\2028\2029\202F\205F\3000\FEFF')=''
    or v ~ U&'[\0001-\0008\000B\000C\000E-\001F\007F]' then return false; end if;
  return p_pattern is null or v ~ p_pattern;
end $$;

ALTER FUNCTION "private"."study_text"("p_value" "jsonb", "p_max" integer, "p_pattern" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_text"("p_value" "jsonb", "p_max" integer, "p_pattern" "text") FROM PUBLIC;
