CREATE OR REPLACE FUNCTION "api"."svc_study_review_method_intent_resolve_v1"("p_intent_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$declare i private.study_review_intents%rowtype;r private.study_report_revisions%rowtype;s private.study_report_shares%rowtype;e private.study_review_exports%rowtype;
 st jsonb;producer jsonb;runs jsonb;methodAssessments jsonb;issuer uuid;artifact jsonb;begin
 perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');i:=private.study_method_review_intent_check(p_intent_id);
 if i.response is not null then return i.response;end if;
 select * into r from private.study_report_revisions where id=i.report_id;st:=jsonb_set(private.study_review_state(r.id),'{checkedAt}',to_jsonb(i.created_at));
 if i.operation='export.download' then
  select * into e from private.study_review_exports where id=i.export_id;
  artifact:=private.study_private_artifact(i.study_id,e.bundle_artifact_id)||jsonb_build_object('kind','artifactCapability');
 elsif i.share_id is null then
  select owner_id into issuer from private.studies where id=i.study_id;
  select jsonb_agg(jsonb_build_object('run',private.study_record('run',rn.id),'revision',private.study_record('studyRevision',rn.study_revision_id),
   'scenario',private.study_record('scenarioRevision',rn.scenario_id),'preparation',private.study_record('modelPreparation',rn.preparation_id),
   'preparedArtifact',private.study_private_artifact(i.study_id,p.input_artifact_id),'resultArtifact',private.study_private_artifact(i.study_id,rn.result_artifact_id)) order by x.n)
   into runs from jsonb_array_elements_text(r.run_ids) with ordinality x(v,n) join private.study_runs rn on rn.id=x.v::uuid and rn.study_id=i.study_id join private.study_model_preparations p on p.id=rn.preparation_id;
  select jsonb_agg(jsonb_build_object('assessment',private.study_method_record(a.id),'factsArtifact',private.study_private_artifact(i.study_id,a.facts_artifact_id),'sourceSnapshotRef',(select ar.ref from private.study_source_snapshots ss join private.study_artifacts ar on ar.id=ss.artifact_id where ss.id=a.source_snapshot_id)) order by x.n)
   into methodAssessments from jsonb_array_elements_text(r.method_assessment_ids) with ordinality x(v,n) join private.study_method_assessments a on a.id=x.v::uuid and a.study_id=i.study_id;
  producer:=jsonb_build_object('kind','reportMethodCommandContext','intentId',i.id,'expiresAt',i.expires_at,'operation',i.operation,
   'request',i.request,
   'studyId',i.study_id,'actorId',issuer,'clientId',null,'grantEpoch',i.grant_epoch,'generatedAt',i.created_at,'reportRevisionId',r.id,'contentArtifactId',null,
   'exportId',i.export_id,'projectionArtifactId',i.projection_artifact_id,'resourcesArtifactId',i.resources_artifact_id,'bundleArtifactId',i.bundle_artifact_id,
   'report',private.study_method_report_record(r.id),'contentArtifact',private.study_private_artifact(i.study_id,r.content_artifact_id),'runs',runs,'methodAssessments',methodAssessments,
   'factsBindingHash',private.study_method_report_binding(i.study_id,r.run_ids,r.method_assessment_ids),'disclosureContextHash',i.disclosure_context_hash,
   'exportProfile',(select export_profile from private.study_method_review_config where singleton));
 else
  select * into s from private.study_report_shares where id=i.share_id;select * into e from private.study_review_exports where id=s.export_id;
  artifact:=private.study_private_artifact(i.study_id,case when i.operation='share.view' then e.projection_artifact_id else e.bundle_artifact_id end)||jsonb_build_object('kind','artifactCapability');
 end if;
 return jsonb_build_object('ok',true,'data',jsonb_build_object('kind','studyMethodReviewContext','intentId',i.id,'expiresAt',i.expires_at,'operation',i.operation,'actorId',i.actor_id,'clientId',i.client_id,
 'request',i.request,'currentState',st,'producerContext',producer,'share',private.study_review_share_record(s.id),'export',e.record,'artifact',artifact));
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
end$$;

ALTER FUNCTION "api"."svc_study_review_method_intent_resolve_v1"("p_intent_id" "uuid") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."svc_study_review_method_intent_resolve_v1"("p_intent_id" "uuid") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."svc_study_review_method_intent_resolve_v1"("p_intent_id" "uuid") TO "service_role";
