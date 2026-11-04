CREATE OR REPLACE FUNCTION "private"."study_method_evidence_body_valid"("p_value" "jsonb") RETURNS boolean
    LANGUAGE "plpgsql" STABLE
    SET "search_path" TO ''
    AS $_$declare c jsonb;seen jsonb:='[]'::jsonb;begin
 if not private.study_keys(p_value,array['schemaVersion','requirementId','declaredKind','title','statement','citations'])
 or p_value->>'schemaVersion' is distinct from 'lca.study-method-evidence.v1' or p_value->>'requirementId' !~ '^PEF-(0[1-9]|1[0-9]|20)$'
 or not private.study_method_text(p_value->'requirementId',6) or not private.study_method_text(p_value->'declaredKind',32) or p_value->>'declaredKind' not in('sourceRecord','applicabilityRecord','professionalRecord')
 or not private.study_method_evidence_plain(p_value->'title',256) or not private.study_method_evidence_plain(p_value->'statement',8192)
 or jsonb_typeof(p_value->'citations') is distinct from 'array' then return false;end if;
 if jsonb_array_length(p_value->'citations')>32 or octet_length(private.study_reporting_canonical(p_value))>65536 then return false;end if;
 for c in select * from jsonb_array_elements(p_value->'citations') loop
  if not private.study_keys(c,array['kind','identity','version','contentHash','locator'])
  or not private.study_method_text(c->'kind',32) or c->>'kind' not in('normativeSource','datasetRevision','document','professionalRecord','otherDeclaredSource')
  or not private.study_method_evidence_plain(c->'identity',256) or not private.study_method_evidence_plain(c->'version',128)
  or not private.study_method_evidence_plain(c->'locator',512) or(c->'contentHash'<>'null'::jsonb and not private.study_text(c->'contentHash',64,'^[0-9a-f]{64}$'))
  or seen @> jsonb_build_array(c) then return false;end if;
  seen:=seen||jsonb_build_array(c);
 end loop;return true;
end$_$;

ALTER FUNCTION "private"."study_method_evidence_body_valid"("p_value" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_method_evidence_body_valid"("p_value" "jsonb") FROM PUBLIC;
