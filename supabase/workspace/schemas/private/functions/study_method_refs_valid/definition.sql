CREATE OR REPLACE FUNCTION "private"."study_method_refs_valid"("p_refs" "jsonb") RETURNS boolean
    LANGUAGE "plpgsql" IMMUTABLE
    SET "search_path" TO ''
    AS $_$ declare r jsonb; ids text[]:='{}'; begin
  if jsonb_typeof(p_refs) is distinct from 'array' then return false; end if;
  if jsonb_array_length(p_refs) not between 1 and 32 then return false; end if;
  for r in select * from jsonb_array_elements(p_refs) loop
    if not private.study_keys(r,array['type','datasetType','id','version'])
      or r->>'type' is distinct from 'datasetRevision' or r->>'datasetType' is distinct from 'lciamethod'
      or not private.study_text(r->'id',128,'^[A-Za-z0-9][A-Za-z0-9._:-]*$')
      or not private.study_text(r->'version',128,'^[0-9]{2}\.[0-9]{2}\.[0-9]{3}$')
      or r->>'id'=any(ids) then return false; end if;
    ids:=ids||(r->>'id');
  end loop;
  return true;
end $_$;

ALTER FUNCTION "private"."study_method_refs_valid"("p_refs" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_method_refs_valid"("p_refs" "jsonb") FROM PUBLIC;
