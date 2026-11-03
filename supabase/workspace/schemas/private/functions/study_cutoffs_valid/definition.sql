CREATE OR REPLACE FUNCTION "private"."study_cutoffs_valid"("p_value" "jsonb") RETURNS boolean
    LANGUAGE "plpgsql" IMMUTABLE
    SET "search_path" TO ''
    AS $_$ declare x jsonb; seen text[]:='{}'; k text; begin
  if jsonb_typeof(p_value) is distinct from 'array' or jsonb_array_length(p_value)>256 then return false; end if;
  for x in select * from jsonb_array_elements(p_value) loop
    if not private.study_keys(x,array['port','reason']) or not private.study_keys(x->'port',array['instanceId','exchangeId'])
      or not private.study_text(x->'port'->'instanceId',128,'^[A-Za-z0-9_-]+$')
      or not private.study_text(x->'port'->'exchangeId',128,'^[A-Za-z0-9_-]+$') or not private.study_text(x->'reason',1024) then return false; end if;
    k:=x->'port'->>'instanceId'||':'||(x->'port'->>'exchangeId');
    if k=any(seen) then return false; end if; seen:=seen||k;
  end loop; return true;
end $_$;

ALTER FUNCTION "private"."study_cutoffs_valid"("p_value" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_cutoffs_valid"("p_value" "jsonb") FROM PUBLIC;
