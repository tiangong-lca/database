CREATE OR REPLACE FUNCTION "api"."svc_study_review_configure_v1"("p_expected_revision" bigint, "p_configuration" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$declare cfg private.study_review_config%rowtype;begin
 perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');
 perform private.study_require(private.study_keys(p_configuration,array['qualificationVersion','enabled','evidenceRef'])
  and p_configuration->>'qualificationVersion'='lca.study-review-qualification.v1' and jsonb_typeof(p_configuration->'enabled')='boolean'
  and private.study_text(p_configuration->'evidenceRef',512),'INVALID_REQUEST');
 select * into cfg from private.study_review_config where singleton for update;perform private.study_require(cfg.revision=p_expected_revision,'REVISION_CONFLICT');
 update private.study_review_config set revision=revision+1,enabled=(p_configuration->>'enabled')::boolean,qualification_evidence_ref=p_configuration->>'evidenceRef' where singleton returning * into cfg;
 return jsonb_build_object('ok',true,'data',jsonb_build_object('revision',cfg.revision,'enabled',cfg.enabled,'qualificationVersion','lca.study-review-qualification.v1','evidenceRef',cfg.qualification_evidence_ref));
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);end$$;

ALTER FUNCTION "api"."svc_study_review_configure_v1"("p_expected_revision" bigint, "p_configuration" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."svc_study_review_configure_v1"("p_expected_revision" bigint, "p_configuration" "jsonb") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."svc_study_review_configure_v1"("p_expected_revision" bigint, "p_configuration" "jsonb") TO "service_role";
