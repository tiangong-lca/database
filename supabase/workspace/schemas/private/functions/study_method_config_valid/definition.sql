CREATE OR REPLACE FUNCTION "private"."study_method_config_valid"("p_config" "jsonb") RETURNS boolean
    LANGUAGE "plpgsql" STABLE
    SET "search_path" TO ''
    AS $_$declare d jsonb;rule jsonb;e jsonb;seen text[]:='{}'::text[];k text;begin
 if not private.study_keys(p_config,array['schemaVersion','baselineRunId','moduleRef','declarations','evidenceRefs'])
 or p_config->>'schemaVersion' is distinct from 'lca.study-method-assessment-config.v1'
 or not private.study_method_uuid(p_config->'baselineRunId') or p_config->'moduleRef' is distinct from private.study_method_module()
 or octet_length(private.study_reporting_canonical(p_config))>262144 then return false;end if;
 d:=p_config->'declarations';rule:=d->'categoryRule';
 if not private.study_keys(d,array['productRole','studyPhase','referenceUnitBasis','categoryRule'])
 or d->>'productRole' is distinct from 'finishedCementIntermediate' or d->>'studyPhase' not in('screening','finalStudy')
 or jsonb_typeof(d->'studyPhase') is distinct from 'string' or d->>'referenceUnitBasis' is distinct from 'declaredMass' then return false;end if;
 if rule->>'kind'='noneEstablished' then if not private.study_keys(rule,array['kind']) then return false;end if;
 elsif rule->>'kind'='commissionDeveloped' then
  if not private.study_keys(rule,array['kind','referenceId','version','evidenceId']) or not private.study_method_text(rule->'referenceId',256)
   or not private.study_method_text(rule->'version',128) or not private.study_method_uuid(rule->'evidenceId') then return false;end if;
 else return false;end if;
 if jsonb_typeof(p_config->'evidenceRefs') is distinct from 'array' then return false;end if;
 if jsonb_array_length(p_config->'evidenceRefs')>128 then return false;end if;
 for e in select * from jsonb_array_elements(p_config->'evidenceRefs') loop
  if not private.study_keys(e,array['requirementId','declaredKind','artifactRef']) or e->>'requirementId' !~ '^PEF-(0[1-9]|1[0-9]|20)$'
   or not private.study_method_text(e->'requirementId',6) or not private.study_method_text(e->'declaredKind',32) or e->>'declaredKind' not in('sourceRecord','applicabilityRecord','professionalRecord')
   or not private.study_method_artifact_valid(e->'artifactRef','methodEvidence','lca.study-method-evidence.v1') then return false;end if;
  k:=(e->>'requirementId')||':'||(e->'artifactRef'->>'id');if k=any(seen) then return false;end if;seen:=seen||k;
 end loop;return true;
exception when invalid_text_representation or numeric_value_out_of_range then return false;end$_$;

ALTER FUNCTION "private"."study_method_config_valid"("p_config" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_method_config_valid"("p_config" "jsonb") FROM PUBLIC;
