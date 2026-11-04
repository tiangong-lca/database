CREATE OR REPLACE FUNCTION "private"."study_method_evidence_record"("p_id" "uuid") RETURNS "jsonb"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
 select jsonb_build_object('schemaVersion','lca.study-method-evidence-record.v1','evidenceId',e.id,'studyId',e.study_id,'requirementId',e.requirement_id,'declaredKind',e.declared_kind,
 'artifactRef',a.ref,'recordedAt',e.recorded_at,'status','recorded_unverified') from private.study_method_evidence e join private.study_artifacts a on a.study_id=e.study_id and a.id=e.artifact_id where e.id=p_id$$;

ALTER FUNCTION "private"."study_method_evidence_record"("p_id" "uuid") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_method_evidence_record"("p_id" "uuid") FROM PUBLIC;
