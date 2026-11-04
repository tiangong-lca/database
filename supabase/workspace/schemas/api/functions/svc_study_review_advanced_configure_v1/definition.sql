CREATE OR REPLACE FUNCTION "api"."svc_study_review_advanced_configure_v1"("p_expected_revision" bigint, "p_configuration" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$declare cfg private.study_advanced_review_config%rowtype;p jsonb:=p_configuration->'exportProfile';begin
 perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');
 perform private.study_require(private.study_keys(p_configuration,array['qualificationVersion','enabled','exportEnabled','exportProfile','evidenceRef'])
 and p_configuration->>'qualificationVersion'='lca.study-advanced-review-qualification.v1' and jsonb_typeof(p_configuration->'enabled')='boolean'
 and jsonb_typeof(p_configuration->'exportEnabled')='boolean' and private.study_text(p_configuration->'evidenceRef',512),'INVALID_REQUEST');
 if p<>'null'::jsonb then
  perform private.study_require(private.study_keys(p,array['issuerId','keyId','rendererVersion','viewModelVersion','rendererArtifactHash','policyId'])
   and private.study_text(p->'issuerId',128,'^[A-Za-z0-9][A-Za-z0-9._:-]*$') and private.study_text(p->'keyId',128,'^[A-Za-z0-9][A-Za-z0-9._:-]*$')
   and p->>'rendererVersion'='2.0.0' and p->>'viewModelVersion'='lca.study-report-view.v2'
   and private.study_text(p->'rendererArtifactHash',64,'^[0-9a-f]{64}$') and p->>'policyId'='lca.study-report-disclosure.v1','INVALID_REQUEST');
 end if;
 select * into cfg from private.study_advanced_review_config where singleton for update;perform private.study_require(cfg.revision=p_expected_revision,'REVISION_CONFLICT');
 update private.study_advanced_review_config set revision=revision+1,enabled=(p_configuration->>'enabled')::boolean,export_enabled=(p_configuration->>'exportEnabled')::boolean,
  export_profile=nullif(p,'null'::jsonb),qualification_evidence_ref=p_configuration->>'evidenceRef' where singleton returning * into cfg;
 return jsonb_build_object('ok',true,'data',jsonb_build_object('revision',cfg.revision,'enabled',cfg.enabled,'qualificationVersion','lca.study-advanced-review-qualification.v1','evidenceRef',cfg.qualification_evidence_ref));
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
when invalid_text_representation or check_violation or not_null_violation then return jsonb_build_object('ok',false,'code','INVALID_REQUEST');end$_$;

ALTER FUNCTION "api"."svc_study_review_advanced_configure_v1"("p_expected_revision" bigint, "p_configuration" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."svc_study_review_advanced_configure_v1"("p_expected_revision" bigint, "p_configuration" "jsonb") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."svc_study_review_advanced_configure_v1"("p_expected_revision" bigint, "p_configuration" "jsonb") TO "service_role";
