CREATE OR REPLACE FUNCTION "api"."svc_study_advanced_configure_v1"("p_expected_revision" bigint, "p_configuration" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$declare cfg private.study_advanced_config%rowtype;begin
 perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');
 perform private.study_require(private.study_keys(p_configuration,array['sensitivityEnabled','uncertaintyEnabled','reportEnabled','maxParameters','maxSamples','qualificationEvidenceRef'])
 and jsonb_typeof(p_configuration->'sensitivityEnabled')='boolean' and jsonb_typeof(p_configuration->'uncertaintyEnabled')='boolean' and jsonb_typeof(p_configuration->'reportEnabled')='boolean'
 and (p_configuration->'maxParameters'='null'::jsonb or (jsonb_typeof(p_configuration->'maxParameters')='number' and (p_configuration->>'maxParameters')::numeric between 1 and 2147483647 and trunc((p_configuration->>'maxParameters')::numeric)=(p_configuration->>'maxParameters')::numeric))
 and (p_configuration->'maxSamples'='null'::jsonb or (jsonb_typeof(p_configuration->'maxSamples')='number' and (p_configuration->>'maxSamples')::numeric between 2 and 4294967295 and trunc((p_configuration->>'maxSamples')::numeric)=(p_configuration->>'maxSamples')::numeric))
 and (p_configuration->'qualificationEvidenceRef'='null'::jsonb or private.study_text(p_configuration->'qualificationEvidenceRef',2048)),'INVALID_REQUEST');
 select * into cfg from private.study_advanced_config where singleton for update;perform private.study_require(cfg.revision=p_expected_revision,'REVISION_CONFLICT');
 update private.study_advanced_config set revision=revision+1,sensitivity_enabled=(p_configuration->>'sensitivityEnabled')::boolean,
 uncertainty_enabled=(p_configuration->>'uncertaintyEnabled')::boolean,report_enabled=(p_configuration->>'reportEnabled')::boolean,
 max_parameters=(p_configuration->>'maxParameters')::integer,max_samples=(p_configuration->>'maxSamples')::bigint,qualification_evidence_ref=p_configuration->>'qualificationEvidenceRef' where singleton;
 return jsonb_build_object('ok',true,'data',jsonb_build_object('revision',cfg.revision+1));
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
when check_violation or not_null_violation or invalid_text_representation or numeric_value_out_of_range then return jsonb_build_object('ok',false,'code','INVALID_REQUEST');end$$;

ALTER FUNCTION "api"."svc_study_advanced_configure_v1"("p_expected_revision" bigint, "p_configuration" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."svc_study_advanced_configure_v1"("p_expected_revision" bigint, "p_configuration" "jsonb") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."svc_study_advanced_configure_v1"("p_expected_revision" bigint, "p_configuration" "jsonb") TO "service_role";
