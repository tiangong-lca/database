CREATE OR REPLACE FUNCTION "api"."svc_study_source_acquisition_read_input_v1"("p_acquisition_id" "uuid", "p_job_id" "uuid", "p_lease_token" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    SET "statement_timeout" TO '15s'
    AS $$
declare a private.study_source_acquisitions%rowtype; packet jsonb;
begin
  perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');
  select * into a from private.study_source_acquisitions where id=p_acquisition_id;
  perform private.study_require(a.job_id=p_job_id,'REFERENCE_MISMATCH');
  perform private.study_authorize(a.study_id,a.requested_by,a.requested_client_id,'write');
  perform private.study_lock_job(a.study_id,p_job_id,p_lease_token,'study.source_acquire','acquisitionId',a.id);
  -- A same-lease request may have captured while this caller waited for the
  -- ordered Study/job locks. Use the committed packet, never the pre-lock row.
  select * into a from private.study_source_acquisitions where id=p_acquisition_id;
  perform private.study_require(found and a.job_id=p_job_id,'REFERENCE_MISMATCH');
  if a.source_packet is null then
    packet:=private.study_capture_source(a.origin_ref,a.requested_by,a.requested_client_id);
    perform private.study_require(octet_length(packet::text)<=4194304,'CAPABILITY_UNAVAILABLE');
    update private.study_source_acquisitions set source_packet=packet where id=a.id;
  else packet:=a.source_packet; perform private.study_source_rights(packet->'sourceAuthorization'->'sourceScope',a.requested_by,a.requested_client_id); end if;
  return jsonb_build_object('ok',true,'data',jsonb_build_object('acquisition',private.study_record('modelSourceAcquisition',a.id),'sourcePacket',packet));
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
when invalid_text_representation or numeric_value_out_of_range or invalid_parameter_value then return jsonb_build_object('ok',false,'code','INVALID_REQUEST');
end $$;

ALTER FUNCTION "api"."svc_study_source_acquisition_read_input_v1"("p_acquisition_id" "uuid", "p_job_id" "uuid", "p_lease_token" "uuid") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."svc_study_source_acquisition_read_input_v1"("p_acquisition_id" "uuid", "p_job_id" "uuid", "p_lease_token" "uuid") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."svc_study_source_acquisition_read_input_v1"("p_acquisition_id" "uuid", "p_job_id" "uuid", "p_lease_token" "uuid") TO "service_role";
