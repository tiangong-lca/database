CREATE OR REPLACE FUNCTION "api"."svc_study_runtime_configure_v1"("p_expected_revision" bigint, "p_configuration" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$ declare cfg private.study_runtime_config%rowtype; enabled boolean; v_fingerprint text; begin
  perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');
  perform private.study_require(private.study_keys(p_configuration,array['schemaVersion','sourceEnabled','computeEnabled','disclosureEnabled','profileId','calculationContractRef','compilerVersion','qualificationEvidenceRef','methodRefs'])
    and p_configuration->>'schemaVersion'='lca.study-runtime-qualification.v1' and p_configuration->>'compilerVersion'='study.compiler.v1'
    and p_configuration->>'profileId'='lca.study-explicit-v1' and private.study_text(p_configuration->'qualificationEvidenceRef',128,'^[A-Za-z0-9][A-Za-z0-9._:-]*$')
    and jsonb_typeof(p_configuration->'sourceEnabled')='boolean' and jsonb_typeof(p_configuration->'computeEnabled')='boolean'
    and jsonb_typeof(p_configuration->'disclosureEnabled')='boolean','INVALID_REQUEST');
  v_fingerprint:=p_configuration->'calculationContractRef'->>'sha256'; enabled:=(p_configuration->>'computeEnabled')::boolean;
  perform private.study_require(private.study_keys(p_configuration->'calculationContractRef',array['kind','schema','sha256'])
    and p_configuration->'calculationContractRef'->>'kind'='calculation_contract' and p_configuration->'calculationContractRef'->>'schema'='lca.calculation-contract.v1'
    and exists(select 1 from private.lca_calculation_contracts where lca_calculation_contracts.fingerprint=v_fingerprint),'REFERENCE_MISMATCH');
  if enabled then perform private.study_require(private.study_method_refs_valid(p_configuration->'methodRefs') and jsonb_array_length(p_configuration->'methodRefs')<=25,'INVALID_REQUEST');
  else perform private.study_require(jsonb_typeof(p_configuration->'methodRefs')='array','INVALID_REQUEST'); end if;
  select * into cfg from private.study_runtime_config where singleton for update;
  perform private.study_require(cfg.revision=p_expected_revision,'REVISION_CONFLICT');
  insert into private.study_profiles(profile_id,calculation_fingerprint,enabled) values('lca.study-explicit-v1',v_fingerprint,enabled)
    on conflict(profile_id) do update set calculation_fingerprint=excluded.calculation_fingerprint,enabled=excluded.enabled;
  update private.study_runtime_config set revision=revision+1,source_enabled=(p_configuration->>'sourceEnabled')::boolean,
    compute_enabled=enabled,disclosure_enabled=(p_configuration->>'disclosureEnabled')::boolean,
    qualification_evidence_ref=p_configuration->>'qualificationEvidenceRef',method_refs=p_configuration->'methodRefs' where singleton;
  return jsonb_build_object('ok',true,'data',jsonb_build_object('revision',cfg.revision+1));
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
end $_$;

ALTER FUNCTION "api"."svc_study_runtime_configure_v1"("p_expected_revision" bigint, "p_configuration" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."svc_study_runtime_configure_v1"("p_expected_revision" bigint, "p_configuration" "jsonb") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."svc_study_runtime_configure_v1"("p_expected_revision" bigint, "p_configuration" "jsonb") TO "service_role";
