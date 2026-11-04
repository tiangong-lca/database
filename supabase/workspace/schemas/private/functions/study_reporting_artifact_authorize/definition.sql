CREATE OR REPLACE FUNCTION "private"."study_reporting_artifact_authorize"("p_study" "uuid", "p_ref" "jsonb", "p_actor" "uuid", "p_client" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$declare r private.study_report_revisions%rowtype;e private.study_report_exports%rowtype;a private.study_artifacts%rowtype;begin
 if p_ref->>'type' not in ('reportContent','reportProjection','renderResources','reportExportBundle') then return private.study_analysis_artifact_authorize(p_study,p_ref,p_actor,p_client);end if;
 perform private.study_authorize(p_study,p_actor,p_client,'read');
 perform private.study_require((select disclosure_enabled from private.study_runtime_config where singleton),'CAPABILITY_UNAVAILABLE');
 select * into a from private.study_artifacts where study_id=p_study and id=(p_ref->>'id')::uuid;perform private.study_require(found and a.ref=p_ref,'REFERENCE_MISMATCH');
 if p_ref->>'type'='reportContent' then
  select * into r from private.study_report_revisions where study_id=p_study and content_artifact_id=a.id;
  perform private.study_require(found and r.template_id='lca.study-report.v1','DISCLOSURE_DENIED');perform private.study_report_rights(p_study,r.run_ids,r.analysis_ids,p_actor,p_client);
 else
  select * into e from private.study_report_exports where study_id=p_study and (projection_artifact_id=a.id or resources_artifact_id=a.id or bundle_artifact_id=a.id);
  perform private.study_require(found,'DISCLOSURE_DENIED');perform private.study_report_export_authorize(e.id,p_actor,p_client);
 end if;
 return jsonb_build_object('kind','artifactCapability','studyId',p_study,'artifactRef',a.ref,'storageBucket',a.bucket,'storageObjectPath',a.object_path);
end$$;

ALTER FUNCTION "private"."study_reporting_artifact_authorize"("p_study" "uuid", "p_ref" "jsonb", "p_actor" "uuid", "p_client" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_reporting_artifact_authorize"("p_study" "uuid", "p_ref" "jsonb", "p_actor" "uuid", "p_client" "text") FROM PUBLIC;
