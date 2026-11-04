CREATE OR REPLACE FUNCTION "private"."study_method_evidence_refs"("p_study" "uuid", "p_config" "jsonb", "p_actor" "uuid", "p_client" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$declare r jsonb;e private.study_method_evidence%rowtype;begin
 perform private.study_authorize(p_study,p_actor,p_client,'read');
 for r in select * from jsonb_array_elements(p_config->'evidenceRefs') loop
  select * into e from private.study_method_evidence where study_id=p_study and artifact_id=(r->'artifactRef'->>'id')::uuid;
  perform private.study_require(found and e.requirement_id=r->>'requirementId' and e.declared_kind=r->>'declaredKind'
   and exists(select 1 from private.study_artifacts where study_id=p_study and id=e.artifact_id and ref=r->'artifactRef'),'REFERENCE_MISMATCH');
 end loop;
 if p_config->'declarations'->'categoryRule'->>'kind'='commissionDeveloped' then
  select * into e from private.study_method_evidence where study_id=p_study and id=(p_config->'declarations'->'categoryRule'->>'evidenceId')::uuid;
  perform private.study_require(found and e.requirement_id='PEF-01' and e.declared_kind='applicabilityRecord' and exists(select 1 from jsonb_array_elements(p_config->'evidenceRefs') declared(ref) where declared.ref->'artifactRef'->>'id'=e.artifact_id::text),'REFERENCE_MISMATCH');
 end if;
end$$;

ALTER FUNCTION "private"."study_method_evidence_refs"("p_study" "uuid", "p_config" "jsonb", "p_actor" "uuid", "p_client" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_method_evidence_refs"("p_study" "uuid", "p_config" "jsonb", "p_actor" "uuid", "p_client" "text") FROM PUBLIC;
