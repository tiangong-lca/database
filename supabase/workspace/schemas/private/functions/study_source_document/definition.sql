CREATE OR REPLACE FUNCTION "private"."study_source_document"("p_kind" "text", "p_id" "text", "p_version" "text", "p_actor" "uuid", "p_client" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
declare t text; raw text; state integer; owner_id uuid; visible jsonb; claims text; sub text; role_claim text; root_key text; body jsonb;
begin
  perform private.study_require(private.study_client_allowed(p_client,'DB-CORE-READ-01'),'FORBIDDEN');
  perform private.study_require(p_version ~ '^[0-9]{2}\.[0-9]{2}\.[0-9]{3}$','REFERENCE_MISMATCH');
  t:=case p_kind when 'lifecyclemodel' then 'lifecyclemodels' when 'process' then 'processes'
    when 'flow' then 'flows' when 'flowproperty' then 'flowproperties' when 'unitgroup' then 'unitgroups' end;
  perform private.study_require(t is not null,'REFERENCE_MISMATCH');
  execute format('select json_ordered::text,state_code,user_id from public.%I where id=$1 and version=$2 for share',t)
    into raw,state,owner_id using p_id::uuid,p_version;
  perform private.study_require(found and raw is not null and(state=100 or(state=0 and owner_id=p_actor)),'DISCLOSURE_DENIED');
  -- Bound a single stored row before JSONB projection, parsing or hashing.
  perform private.study_require(octet_length(raw)<=4194304,'CAPABILITY_UNAVAILABLE');
  claims:=current_setting('request.jwt.claims',true); sub:=current_setting('request.jwt.claim.sub',true); role_claim:=current_setting('request.jwt.claim.role',true);
  perform set_config('request.jwt.claims',jsonb_strip_nulls(jsonb_build_object('sub',p_actor,'role','authenticated','client_id',p_client))::text,true);
  perform set_config('request.jwt.claim.sub',p_actor::text,true); perform set_config('request.jwt.claim.role','authenticated',true);
  visible:=private.study_source_visible_row(p_kind,p_id::uuid,p_version);
  perform set_config('request.jwt.claims',coalesce(claims,''),true); perform set_config('request.jwt.claim.sub',coalesce(sub,''),true); perform set_config('request.jwt.claim.role',coalesce(role_claim,''),true);
  perform private.study_require(visible is not null and visible->>'text'=raw and (visible->>'stateCode')::integer=state
    and nullif(visible->>'ownerActorId','')::uuid is not distinct from owner_id,'DISCLOSURE_DENIED');
  body:=raw::jsonb; perform private.study_require(jsonb_typeof(body)='object','INVALID_REQUEST');
  root_key:=case p_kind when 'lifecyclemodel' then 'lifeCycleModelDataSet' when 'process' then 'processDataSet'
    when 'flow' then 'flowDataSet' when 'flowproperty' then 'flowPropertyDataSet' when 'unitgroup' then 'unitGroupDataSet' end;
  perform private.study_require(jsonb_typeof(body->root_key)='object','REFERENCE_MISMATCH');
  return jsonb_build_object('kind',p_kind,'identity',jsonb_build_object('id',p_id,'version',p_version),'stateCode',state,
    'ownerActorId',owner_id,'sha256',encode(extensions.digest(convert_to(raw,'UTF8'),'sha256'),'hex'),'json',raw);
exception when others then
  if claims is not null then perform set_config('request.jwt.claims',claims,true); end if;
  if sub is not null then perform set_config('request.jwt.claim.sub',sub,true); end if;
  if role_claim is not null then perform set_config('request.jwt.claim.role',role_claim,true); end if;
  raise;
end $_$;

ALTER FUNCTION "private"."study_source_document"("p_kind" "text", "p_id" "text", "p_version" "text", "p_actor" "uuid", "p_client" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_source_document"("p_kind" "text", "p_id" "text", "p_version" "text", "p_actor" "uuid", "p_client" "text") FROM PUBLIC;
