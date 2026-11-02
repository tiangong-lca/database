CREATE OR REPLACE FUNCTION "api"."svc_final_result_readiness_describe_v2"("p_verification_id" "uuid") RETURNS "jsonb"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
 select jsonb_build_object('ok',true,'data',(select jsonb_build_object('verificationId',v.id,'header',v.header,
   'registeredArtifactCount',(select count(*) from private.final_result_release_artifact_proofs where verification_id=v.id),
   'readinessReceipt',(select receipt from private.final_result_release_readiness where verification_id=v.id),'publicationAuthorized',false)
   from private.final_result_release_verifications v where v.id=p_verification_id));
$$;

ALTER FUNCTION "api"."svc_final_result_readiness_describe_v2"("p_verification_id" "uuid") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."svc_final_result_readiness_describe_v2"("p_verification_id" "uuid") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."svc_final_result_readiness_describe_v2"("p_verification_id" "uuid") TO "service_role";
