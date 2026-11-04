CREATE OR REPLACE FUNCTION "api"."svc_study_report_method_intent_resolve_v1"("p_intent_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare i private.study_report_intents%rowtype;r private.study_report_revisions%rowtype;runids jsonb;assessmentids jsonb;runs jsonb;methodAssessments jsonb;begin
 perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');i:=private.study_method_report_intent_check(p_intent_id);
 if i.response is not null then return i.response;end if;
 if i.operation='report.create' then runids:=i.request->'runIds';assessmentids:=i.request->'methodAssessmentIds';
 else select * into r from private.study_report_revisions where id=i.report_id;runids:=r.run_ids;assessmentids:=r.method_assessment_ids;end if;
 select jsonb_agg(jsonb_build_object('run',private.study_record('run',rn.id),'revision',private.study_record('studyRevision',rn.study_revision_id),
 'scenario',private.study_record('scenarioRevision',rn.scenario_id),'preparation',private.study_record('modelPreparation',rn.preparation_id),
 'preparedArtifact',private.study_private_artifact(i.study_id,p.input_artifact_id),'resultArtifact',private.study_private_artifact(i.study_id,rn.result_artifact_id)) order by e.n)
 into runs from jsonb_array_elements_text(runids) with ordinality e(v,n) join private.study_runs rn on rn.id=e.v::uuid and rn.study_id=i.study_id
 join private.study_model_preparations p on p.id=rn.preparation_id;
 select jsonb_agg(jsonb_build_object('assessment',private.study_method_record(a.id),'factsArtifact',private.study_private_artifact(i.study_id,a.facts_artifact_id),'sourceSnapshotRef',(select ar.ref from private.study_source_snapshots ss join private.study_artifacts ar on ar.id=ss.artifact_id where ss.id=a.source_snapshot_id)) order by e.n)
 into methodAssessments from jsonb_array_elements_text(assessmentids) with ordinality e(v,n) join private.study_method_assessments a on a.id=e.v::uuid and a.study_id=i.study_id;
 return jsonb_build_object('ok',true,'data',jsonb_build_object('kind','reportMethodCommandContext','intentId',i.id,'expiresAt',i.expires_at,'operation',i.operation,
 'request',i.request,'studyId',i.study_id,'actorId',i.actor_id,'clientId',i.client_id,'grantEpoch',i.grant_epoch,'generatedAt',i.created_at,
 'reportRevisionId',i.report_id,'contentArtifactId',i.content_artifact_id,'exportId',i.export_id,'projectionArtifactId',i.projection_artifact_id,
 'resourcesArtifactId',i.resources_artifact_id,'bundleArtifactId',i.bundle_artifact_id,'report',i.report_snapshot,
 'contentArtifact',case when r.id is not null then private.study_private_artifact(i.study_id,r.content_artifact_id) end,'runs',runs,'methodAssessments',methodAssessments,
 'exportProfile',case when i.operation='export.request' then (select export_profile from private.study_reporting_config where singleton) end,
 'disclosureContextHash',case when i.operation='export.request' then private.study_report_disclosure_context(i) end,
 'factsBindingHash',private.study_method_report_binding(i.study_id,runids,assessmentids)));
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
end$$;

ALTER FUNCTION "api"."svc_study_report_method_intent_resolve_v1"("p_intent_id" "uuid") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."svc_study_report_method_intent_resolve_v1"("p_intent_id" "uuid") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."svc_study_report_method_intent_resolve_v1"("p_intent_id" "uuid") TO "service_role";
