CREATE OR REPLACE FUNCTION "private"."study_analysis_config_valid"("p_config" "jsonb") RETURNS boolean
    LANGUAGE "plpgsql" IMMUTABLE
    SET "search_path" TO ''
    AS $_$ declare x jsonb; seen uuid[]:='{}'::uuid[]; rid uuid; begin
 if not private.study_keys(p_config,array['schemaVersion','kind','runIds'])
  or p_config->>'schemaVersion' is distinct from 'lca.study-analysis-config.v1'
  or coalesce(p_config->>'kind' not in ('contribution','comparison'),true) or jsonb_typeof(p_config->'runIds') is distinct from 'array' then return false; end if;
 if jsonb_array_length(p_config->'runIds')<>(case p_config->>'kind' when 'contribution' then 1 else 2 end) then return false; end if;
 for x in select * from jsonb_array_elements(p_config->'runIds') loop
  if jsonb_typeof(x)<>'string' or x#>>'{}' !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then return false; end if;
  rid:=(x#>>'{}')::uuid; if rid=any(seen) then return false; end if; seen:=seen||rid;
 end loop; return true;
exception when invalid_text_representation then return false;
end $_$;

ALTER FUNCTION "private"."study_analysis_config_valid"("p_config" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_analysis_config_valid"("p_config" "jsonb") FROM PUBLIC;
