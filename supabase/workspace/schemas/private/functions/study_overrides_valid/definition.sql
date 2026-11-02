CREATE OR REPLACE FUNCTION "private"."study_overrides_valid"("p_overrides" "jsonb") RETURNS boolean
    LANGUAGE "plpgsql" IMMUTABLE
    SET "search_path" TO ''
    AS $_$ declare o jsonb; paths text[]:='{}'; amount double precision; begin
  if jsonb_typeof(p_overrides) is distinct from 'array' then return false; end if;
  if jsonb_array_length(p_overrides)>256 then return false; end if;
  for o in select * from jsonb_array_elements(p_overrides) loop
    if not private.study_keys(o,array['path','value'])
      or not private.study_text(o->'path',256,'^/instances/[A-Za-z0-9_-]+/exchanges/[A-Za-z0-9_-]+/amount$')
      or jsonb_typeof(o->'value') is distinct from 'number' or o->>'path'=any(paths) then return false; end if;
    amount:=(o->>'value')::double precision;
    if amount='Infinity'::double precision or amount='-Infinity'::double precision or amount='NaN'::double precision then return false; end if;
    paths:=paths||(o->>'path');
  end loop;
  return true;
exception when data_exception then return false;
end $_$;

ALTER FUNCTION "private"."study_overrides_valid"("p_overrides" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_overrides_valid"("p_overrides" "jsonb") FROM PUBLIC;
