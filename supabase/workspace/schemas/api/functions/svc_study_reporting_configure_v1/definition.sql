CREATE OR REPLACE FUNCTION "api"."svc_study_reporting_configure_v1"("p_expected_revision" bigint, "p_configuration" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$declare cfg private.study_reporting_config%rowtype;p jsonb:=p_configuration->'exportProfile';begin
 perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');
 perform private.study_require(private.study_keys(p_configuration,array['schemaVersion','analysisEnabled','reportEnabled','exportEnabled','qualificationEvidenceRef','exportProfile'])
 and p_configuration->>'schemaVersion'='lca.study-reporting-qualification.v1' and jsonb_typeof(p_configuration->'analysisEnabled')='boolean'
 and jsonb_typeof(p_configuration->'reportEnabled')='boolean' and jsonb_typeof(p_configuration->'exportEnabled')='boolean'
 and private.study_text(p_configuration->'qualificationEvidenceRef',128,'^[A-Za-z0-9][A-Za-z0-9._:-]*$'),'INVALID_REQUEST');
 if p<>'null'::jsonb then
  perform private.study_require(private.study_keys(p,array['issuerId','keyId','rendererVersion','viewModelVersion','rendererArtifactHash','policyId'])
  and private.study_text(p->'issuerId',128,'^[A-Za-z0-9][A-Za-z0-9._:-]*$') and private.study_text(p->'keyId',128,'^[A-Za-z0-9][A-Za-z0-9._:-]*$')
  and p->>'rendererVersion'='1.0.0' and p->>'viewModelVersion'='lca.study-report-view.v1'
  and private.study_text(p->'rendererArtifactHash',64,'^[0-9a-f]{64}$') and p->>'policyId'='lca.study-report-disclosure.v1','INVALID_REQUEST');
 end if;
 perform private.study_require(not (p_configuration->>'exportEnabled')::boolean or p<>'null'::jsonb,'CAPABILITY_UNAVAILABLE');
 select * into cfg from private.study_reporting_config where singleton for update;perform private.study_require(cfg.revision=p_expected_revision,'REVISION_CONFLICT');
 update private.study_reporting_config set revision=revision+1,analysis_enabled=(p_configuration->>'analysisEnabled')::boolean,report_enabled=(p_configuration->>'reportEnabled')::boolean,
 export_enabled=(p_configuration->>'exportEnabled')::boolean,qualification_evidence_ref=p_configuration->>'qualificationEvidenceRef',export_profile=nullif(p,'null'::jsonb) where singleton;
 return jsonb_build_object('ok',true,'data',jsonb_build_object('revision',cfg.revision+1));
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
end$_$;

ALTER FUNCTION "api"."svc_study_reporting_configure_v1"("p_expected_revision" bigint, "p_configuration" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."svc_study_reporting_configure_v1"("p_expected_revision" bigint, "p_configuration" "jsonb") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."svc_study_reporting_configure_v1"("p_expected_revision" bigint, "p_configuration" "jsonb") TO "service_role";
