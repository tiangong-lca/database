CREATE OR REPLACE FUNCTION "private"."study_definition_valid"("p_definition" "jsonb") RETURNS boolean
    LANGUAGE "plpgsql" IMMUTABLE
    SET "search_path" TO ''
    AS $_$ declare f jsonb; a jsonb; begin
  if not private.study_keys(p_definition,array['goal','functionalUnit','systemBoundary','methodRefs','assumptions'])
    or not private.study_text(p_definition->'goal',4096) or not private.study_text(p_definition->'systemBoundary',4096)
    or not private.study_method_refs_valid(p_definition->'methodRefs')
    or jsonb_typeof(p_definition->'assumptions') is distinct from 'array' then return false; end if;
  f:=p_definition->'functionalUnit';
  if not private.study_keys(f,array['amount','unit','referenceFlowId'])
    or not private.study_text(f->'amount',64,'^([1-9][0-9]*(\.[0-9]+)?|0\.[0-9]*[1-9][0-9]*)$')
    or not private.study_text(f->'unit',128) or not private.study_text(f->'referenceFlowId',128,'^[A-Za-z0-9][A-Za-z0-9._:-]*$')
    or jsonb_array_length(p_definition->'assumptions')>128 then return false; end if;
  for a in select * from jsonb_array_elements(p_definition->'assumptions') loop
    if not private.study_keys(a,array['id','statement','evidenceRef'])
      or not private.study_text(a->'id',128,'^[A-Za-z0-9][A-Za-z0-9._:-]*$')
      or not private.study_text(a->'statement',4096)
      or not private.study_text(a->'evidenceRef',128,'^[A-Za-z0-9][A-Za-z0-9._:-]*$') then return false; end if;
  end loop;
  return true;
end $_$;

ALTER FUNCTION "private"."study_definition_valid"("p_definition" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_definition_valid"("p_definition" "jsonb") FROM PUBLIC;
