CREATE OR REPLACE FUNCTION "api"."svc_result_query_describe_v2"("p_artifact_id" "uuid", "p_target_hash" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
declare v_artifact private.final_result_query_artifacts%rowtype; v_receipt jsonb;
begin
  if p_artifact_id is null or coalesce(p_target_hash,'') !~ '^[0-9a-f]{64}$' then
    raise exception using errcode='22023',message='Invalid final Result query lookup';
  end if;
  select * into v_artifact from private.final_result_query_artifacts where id=p_artifact_id;
  if not found then return jsonb_build_object('ok',true,'data',null); end if;
  select receipt into v_receipt from private.final_result_query_seals
    where artifact_id=p_artifact_id and target_hash=p_target_hash;
  return jsonb_build_object('ok',true,'data',jsonb_build_object('artifact',v_artifact.artifact_ref,
    'inputHash',v_artifact.input_hash,'resultCount',v_artifact.result_count,
    'registeredResultCount',(select count(*) from private.final_result_query_rows where artifact_id=p_artifact_id),
    'readbackReceipt',v_receipt,'publicationAuthorized',false));
end;
$_$;

ALTER FUNCTION "api"."svc_result_query_describe_v2"("p_artifact_id" "uuid", "p_target_hash" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."svc_result_query_describe_v2"("p_artifact_id" "uuid", "p_target_hash" "text") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."svc_result_query_describe_v2"("p_artifact_id" "uuid", "p_target_hash" "text") TO "service_role";
