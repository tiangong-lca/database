CREATE OR REPLACE FUNCTION "api"."svc_study_analysis_advanced_read_input_v1"("p_analysis_id" "uuid", "p_job_id" "uuid", "p_lease_token" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$declare a private.study_advanced_analyses%rowtype;snapshot uuid;begin
 perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');select * into a from private.study_advanced_analyses where id=p_analysis_id;
 perform private.study_require(found and a.job_id=p_job_id,'REFERENCE_MISMATCH');perform private.study_authorize(a.study_id,a.requested_by,a.requested_client_id,'write');
 snapshot:=private.study_advanced_rights(a.study_id,a.baseline_run_id,a.requested_by,a.requested_client_id);perform private.study_require(snapshot=a.source_snapshot_id,'REFERENCE_MISMATCH');
 perform private.study_analysis_require_current(a.study_id,jsonb_build_object('runIds',jsonb_build_array(a.baseline_run_id)));
 perform private.study_advanced_lock_job(a.study_id,p_job_id,p_lease_token,a.id);
 return jsonb_build_object('ok',true,'data',jsonb_build_object('schemaVersion','lca.study-analysis-input.v2','analysis',private.study_advanced_record(a.id)-'factsRef',
 'baseline',private.study_advanced_baseline(a.study_id,a.baseline_run_id),'sourceSnapshot',private.study_record('modelSourceSnapshot',snapshot),
 'sourceArtifact',private.study_private_artifact(a.study_id,(select artifact_id from private.study_source_snapshots where id=snapshot))));
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);end$$;

ALTER FUNCTION "api"."svc_study_analysis_advanced_read_input_v1"("p_analysis_id" "uuid", "p_job_id" "uuid", "p_lease_token" "uuid") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."svc_study_analysis_advanced_read_input_v1"("p_analysis_id" "uuid", "p_job_id" "uuid", "p_lease_token" "uuid") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."svc_study_analysis_advanced_read_input_v1"("p_analysis_id" "uuid", "p_job_id" "uuid", "p_lease_token" "uuid") TO "service_role";
