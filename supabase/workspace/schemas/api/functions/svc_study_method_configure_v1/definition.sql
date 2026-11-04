CREATE OR REPLACE FUNCTION "api"."svc_study_method_configure_v1"("p_expected_revision" bigint, "p_configuration" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$declare cfg private.study_method_config%rowtype;begin
 perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');
 perform private.study_require(private.study_keys(p_configuration,array['executionEnabled','reportEnabled','maxEvidenceRefs','maxSelectedFactorRecords','qualificationEvidenceRef'])
 and jsonb_typeof(p_configuration->'executionEnabled')='boolean' and jsonb_typeof(p_configuration->'reportEnabled')='boolean'
 and(p_configuration->'maxEvidenceRefs'='null'::jsonb or(jsonb_typeof(p_configuration->'maxEvidenceRefs')='number' and(p_configuration->>'maxEvidenceRefs')::numeric between 0 and 128 and trunc((p_configuration->>'maxEvidenceRefs')::numeric)=(p_configuration->>'maxEvidenceRefs')::numeric))
 and(p_configuration->'maxSelectedFactorRecords'='null'::jsonb or(jsonb_typeof(p_configuration->'maxSelectedFactorRecords')='number' and(p_configuration->>'maxSelectedFactorRecords')::numeric between 1 and 8192 and trunc((p_configuration->>'maxSelectedFactorRecords')::numeric)=(p_configuration->>'maxSelectedFactorRecords')::numeric))
 and(p_configuration->'qualificationEvidenceRef'='null'::jsonb or private.study_method_text(p_configuration->'qualificationEvidenceRef',2048)),'INVALID_REQUEST');
 select * into cfg from private.study_method_config where singleton for update;perform private.study_require(cfg.revision=p_expected_revision,'REVISION_CONFLICT');
 update private.study_method_config set revision=revision+1,execution_enabled=(p_configuration->>'executionEnabled')::boolean,report_enabled=(p_configuration->>'reportEnabled')::boolean,
 max_evidence_refs=(p_configuration->>'maxEvidenceRefs')::integer,max_selected_factor_records=(p_configuration->>'maxSelectedFactorRecords')::integer,qualification_evidence_ref=p_configuration->>'qualificationEvidenceRef' where singleton;
 return jsonb_build_object('ok',true,'data',jsonb_build_object('revision',cfg.revision+1));
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
when invalid_text_representation or numeric_value_out_of_range or not_null_violation or check_violation then return jsonb_build_object('ok',false,'code','INVALID_REQUEST');end$$;

ALTER FUNCTION "api"."svc_study_method_configure_v1"("p_expected_revision" bigint, "p_configuration" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."svc_study_method_configure_v1"("p_expected_revision" bigint, "p_configuration" "jsonb") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."svc_study_method_configure_v1"("p_expected_revision" bigint, "p_configuration" "jsonb") TO "service_role";
