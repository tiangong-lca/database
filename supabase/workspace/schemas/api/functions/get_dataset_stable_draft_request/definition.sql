CREATE OR REPLACE FUNCTION "api"."get_dataset_stable_draft_request"("p_request_id" "uuid", "p_request" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
declare
  v_actor uuid := auth.uid();
  v_validated jsonb;
  v_request jsonb;
  v_fingerprint text;
  v_receipt jsonb;
  v_current jsonb;
  v_current_draft jsonb;
  v_status text;
begin
  if v_actor is null then
    return jsonb_build_object('ok',false,'code','AUTH_REQUIRED','status',401,'message','Authentication required');
  end if;
  v_validated := private.stable_draft_request_validate(p_request_id,p_request);
  if not (v_validated->>'ok')::boolean then return v_validated; end if;
  v_request := v_validated->'data';
  if (v_request->>'expectedActorId')::uuid <> v_actor then
    return jsonb_build_object('ok',false,'code','DATASET_ACTOR_MISMATCH','status',403,'message','The expected actor does not match the authenticated actor');
  end if;
  v_fingerprint := pg_catalog.encode(extensions.digest(pg_catalog.convert_to(v_request::text,'UTF8'),'sha256'),'hex');
  select payload into v_receipt from private.command_audit_log
    where command='cmd_dataset_prepare_stable_draft' and actor_user_id=v_actor and payload->>'requestId'=p_request_id::text;
  if v_receipt is null then
    return jsonb_build_object('ok',false,'code','REQUEST_NOT_RECORDED','status',404,'message','No committed receipt is visible; do not redispatch creation');
  end if;
  if v_receipt->>'requestSha256' <> v_fingerprint then
    return jsonb_build_object('ok',false,'code','REQUEST_ID_REUSED','status',409,'message','This request UUID already binds another request');
  end if;
  execute pg_catalog.format('select to_jsonb(d) from public.%I d where d.id=$1 and d.version=$2 and d.user_id=$3',v_request->>'table')
    into v_current using (v_request->>'id')::uuid,v_receipt#>>'{result,version}',v_actor;
  if v_current is null then
    v_status:='missing';
  elsif v_request->>'table'='processes'
      and (v_current->>'model_id' is not null or (v_current->>'state_code')::integer=120) then
    -- The generic readback must not become a new reader for excluded native or
    -- Result scopes. The immutable original receipt is still recoverable.
    v_status:='changed';
  elsif v_request->>'table'='flows' and (
      v_current#>>'{json_ordered,flowDataSet,modellingAndValidation,LCIMethod,typeOfDataSet}' is null
      or v_current#>>'{json_ordered,flowDataSet,modellingAndValidation,LCIMethod,typeOfDataSet}' not in ('Product flow','Waste flow')) then
    v_status:='changed';
  else
    v_current_draft:=jsonb_build_object('version',v_current->>'version','userId',v_current->>'user_id',
      'stateCode',(v_current->>'state_code')::integer,'jsonOrdered',v_current->'json_ordered');
    v_status:=case when v_current_draft=v_receipt#>'{result,selectedDraft}' then 'unchanged' else 'changed' end;
  end if;
  return jsonb_build_object('ok',true,'data',jsonb_build_object('recorded',true,'result',v_receipt->'result',
    'targetStatus',v_status,'currentDraft',v_current_draft));
end;
$_$;

ALTER FUNCTION "api"."get_dataset_stable_draft_request"("p_request_id" "uuid", "p_request" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."get_dataset_stable_draft_request"("p_request_id" "uuid", "p_request" "jsonb") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."get_dataset_stable_draft_request"("p_request_id" "uuid", "p_request" "jsonb") TO "authenticated";
