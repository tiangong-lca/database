CREATE OR REPLACE FUNCTION "api"."cmd_dataset_prepare_stable_draft"("p_request_id" "uuid", "p_request" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
declare
  v_actor uuid := auth.uid();
  v_validated jsonb;
  v_request jsonb;
  v_fingerprint text;
  v_receipt jsonb;
  v_table text;
  v_id uuid;
  v_source jsonb;
  v_drafts jsonb;
  v_reviews jsonb;
  v_current_expected jsonb;
  v_versions jsonb;
  v_expected_versions jsonb;
  v_selected jsonb;
  v_selected_version text;
  v_outcome text;
  v_result jsonb;
  v_write jsonb;
  v_created_row jsonb;
  v_highest_version text;
  v_root_key text;
  v_uri_slug text;
  v_version text;
  v_created_body jsonb;
  v_source_body jsonb;
  v_error text;
  v_details text;
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
  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
    return jsonb_build_object('ok',false,'code','DATASET_DRAFT_ISOLATION_REQUIRED','status',409,'message','Stable draft admission requires READ COMMITTED');
  end if;
  if not pg_catalog.pg_try_advisory_xact_lock(
      pg_catalog.hashtext('stable_draft_request:' || v_actor::text),pg_catalog.hashtext(p_request_id::text)) then
    return jsonb_build_object('ok',false,'code','DATASET_STABLE_DRAFT_BUSY','status',503,'message','The original request is still in progress');
  end if;
  v_fingerprint := pg_catalog.encode(extensions.digest(pg_catalog.convert_to(v_request::text,'UTF8'),'sha256'),'hex');
  select payload into v_receipt from private.command_audit_log
    where command = 'cmd_dataset_prepare_stable_draft'
      and actor_user_id = v_actor and payload->>'requestId' = p_request_id::text;
  if v_receipt is not null then
    if v_receipt->>'requestSha256' <> v_fingerprint then
      return jsonb_build_object('ok',false,'code','REQUEST_ID_REUSED','status',409,'message','This request UUID already binds another request');
    end if;
  end if;

  v_table := v_request->>'table';
  v_id := (v_request->>'id')::uuid;
  if not pg_catalog.pg_try_advisory_xact_lock(pg_catalog.hashtext('cmd_dataset_create_version:' || v_table),pg_catalog.hashtext(v_id::text)) then
    return jsonb_build_object('ok',false,'code','DATASET_STABLE_DRAFT_BUSY','status',503,'message','Dataset family is busy');
  end if;
  perform pg_catalog.set_config('lock_timeout','2s',true);
  perform pg_catalog.set_config('statement_timeout','8s',true);

  execute pg_catalog.format(
    'select coalesce(jsonb_agg(jsonb_build_object(''table'',%L,''id'',s.id,
       ''version'',s.version,''userId'',s.user_id,''stateCode'',s.state_code,
       ''reviewId'',s.review_id) order by s.version),''[]''::jsonb)
       from (select d.* from public.%I d where d.id=$1 and d.user_id=$2
         and d.state_code>=20 and d.state_code<100 order by d.version for update of d)s',v_table,v_table)
    into v_reviews using v_id,v_actor;
  if jsonb_array_length(v_reviews)>0 then
    return jsonb_build_object('ok',false,'code','DATASET_REVIEW_IN_PROGRESS','status',409,
      'message','The owner dataset family is under review; resume its existing review',
      'details',jsonb_build_object('table',v_table,'id',v_id,'reviews',v_reviews));
  end if;
  if v_receipt is not null then
    return jsonb_build_object('ok',true,'data',jsonb_set(v_receipt->'result','{replayed}','true'::jsonb));
  end if;

  execute pg_catalog.format('select to_jsonb(d) from public.%I d where d.id=$1 and d.version=$2
    and (d.state_code in (100,200) or d.user_id=$3) for update of d',v_table)
    into v_source using v_id,v_request#>>'{source,version}',v_actor;
  if v_source is null then
    return jsonb_build_object('ok',false,'code','DATASET_SOURCE_NOT_FOUND','status',404,'message','Exact source dataset not found');
  end if;
  if (v_source->>'state_code')::integer = 120 then
    return jsonb_build_object('ok',false,'code','RESULT_VERSION_DERIVATION_BLOCKED','status',403,'message','A Result Process cannot be a successor source');
  end if;
  if (v_source->>'state_code')::integer is null or (v_source->>'state_code')::integer not in (100,200) then
    return jsonb_build_object('ok',false,'code','DATASET_SOURCE_NOT_PUBLIC','status',403,'message','The source must still be public state 100 or 200');
  end if;
  if v_table='processes' and v_source->>'model_id' is not null then
    return jsonb_build_object('ok',false,'code','LIFECYCLEMODEL_BUNDLE_REQUIRED','status',409,'message','Model-bound Processes require their native bundle contract');
  end if;
  if v_table='flows' and (
      v_source#>>'{json_ordered,flowDataSet,modellingAndValidation,LCIMethod,typeOfDataSet}' is null
      or v_source#>>'{json_ordered,flowDataSet,modellingAndValidation,LCIMethod,typeOfDataSet}' not in ('Product flow','Waste flow')) then
    return jsonb_build_object('ok',false,'code','DATASET_REFERENCE_ONLY','status',403,'message','Stable draft preparation supports only Product/Waste flows; Elementary or unknown flows are reference-only');
  end if;
  if (v_source->>'user_id')::uuid is distinct from (v_request#>>'{source,userId}')::uuid
     or (v_source->>'state_code')::integer is distinct from (v_request#>>'{source,stateCode}')::integer
     or v_source->'json_ordered' is distinct from v_request#>'{source,jsonOrdered}' then
    return jsonb_build_object('ok',false,'code','DATASET_SOURCE_CHANGED','status',409,'message','The source owner, state or complete before content changed');
  end if;

  -- Lock every eligible row, not a latest-version projection. The admission
  -- trigger prevents a competing insert/owner/state change while this family
  -- lock is held. READ COMMITTED refreshes after any exact-row lock wait.
  execute pg_catalog.format(
    'select coalesce(jsonb_agg(to_jsonb(s) order by s.version),''[]''::jsonb)
       from (select d.* from public.%I d where d.id=$1 and d.user_id=$2 and d.state_code=0 order by d.version for update of d) s',v_table)
    into v_drafts using v_id,v_actor;
  if v_table='processes' and exists (select 1 from jsonb_array_elements(v_drafts) x where x->>'model_id' is not null) then
    return jsonb_build_object('ok',false,'code','LIFECYCLEMODEL_BUNDLE_REQUIRED','status',409,'message','A model-bound draft is present in this owner family');
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('version',x->>'version','jsonOrdered',x->'json_ordered') order by x->>'version'),'[]'::jsonb),
         coalesce(jsonb_agg(x->'version' order by x->>'version'),'[]'::jsonb)
    into v_current_expected,v_versions from jsonb_array_elements(v_drafts) x;
  select coalesce(jsonb_agg(x->'version' order by x->>'version'),'[]'::jsonb)
    into v_expected_versions from jsonb_array_elements(v_request->'expectedDrafts') x;
  if v_versions is distinct from v_expected_versions then
    return jsonb_build_object('ok',false,'code','DATASET_DRAFT_CENSUS_CHANGED','status',409,'message','The complete owner draft version set changed',
      'details',jsonb_build_object('draftVersions',v_versions));
  end if;
  if v_current_expected is distinct from v_request->'expectedDrafts' then
    return jsonb_build_object('ok',false,'code','DATASET_BEFORE_CONTENT_CHANGED','status',409,'message','An owner draft changed since it was read');
  end if;
  v_selected_version := v_request->>'selectedVersion';
  if v_selected_version is not null and not (v_versions ? v_selected_version) then
    return jsonb_build_object('ok',false,'code','DATASET_DRAFT_SELECTION_INVALID','status',409,'message','Selected version is not in the complete current owner draft set');
  end if;
  if jsonb_array_length(v_drafts)>1 and v_selected_version is null then
    return jsonb_build_object('ok',false,'code','DATASET_DRAFT_CONFLICT','status',409,'message','Multiple owner drafts require an explicit reviewed selection',
      'details',jsonb_build_object('draftVersions',v_versions,'drafts',v_current_expected));
  end if;
  if jsonb_array_length(v_drafts)=0 then
    -- Native NN.NN.NNN allocation truncates an overflowing three-digit major
    -- through lpad(...,2). Do not duplicate its allocator or admit an exhausted
    -- family through this facade. Reuse/explicit selection needs no allocation.
    execute pg_catalog.format('select max(d.version::text) from public.%I d where d.id=$1
      and d.version::text ~ ''^[0-9]{2}\.[0-9]{2}\.[0-9]{3}$''',v_table)
      into v_highest_version using v_id;
    if v_highest_version='99.99.999' then
      return jsonb_build_object('ok',false,'code','DATASET_VERSION_EXHAUSTED','status',409,'message','No successor fits the supported dataset version format');
    end if;
    v_write := api.cmd_dataset_create_version(v_table,v_id,v_source->>'version',v_source->'json_ordered',
      null,false,
      jsonb_build_object('requestId',p_request_id,'source','stable_owner_draft'),null);
    if v_write->'ok' is distinct from 'true'::jsonb then
      if v_write->'ok'='false'::jsonb and jsonb_typeof(v_write->'code')='string'
         and jsonb_typeof(v_write->'message')='string' and jsonb_typeof(v_write->'status')='number' then
        -- Even a delegated rejection rolls back the whole function block, so a
        -- malformed/faulty delegate cannot leave an unreceipted insert behind.
        raise exception using errcode='P0001',message='DATASET_STABLE_DRAFT_DELEGATE_REJECTED',detail=v_write::text;
      end if;
      raise exception using errcode='P0001',message='DATASET_STABLE_DRAFT_RESULT_INVALID';
    end if;
    v_selected := v_write->'data';
    if jsonb_typeof(v_selected) is distinct from 'object'
       or v_selected->>'id' is distinct from v_id::text
       or v_selected->>'user_id' is distinct from v_actor::text
       or v_selected->'state_code' is distinct from '0'::jsonb
       or v_selected->'rule_verification' is distinct from 'false'::jsonb
       or v_selected->>'model_id' is not null
       or jsonb_typeof(v_selected->'version') is distinct from 'string'
       or (v_selected->>'version') !~ '^[0-9]{2}\.[0-9]{2}\.[0-9]{3}$'
       or (v_selected->>'version') <= v_highest_version
       or jsonb_typeof(v_selected->'json_ordered') is distinct from 'object' then
      raise exception using errcode='P0001',message='DATASET_STABLE_DRAFT_RESULT_INVALID';
    end if;
    v_version:=v_selected->>'version';
    execute pg_catalog.format('select to_jsonb(d) from public.%I d where d.id=$1 and d.version=$2',v_table)
      into v_created_row using v_id,v_version;
    if v_created_row is null or v_created_row->>'user_id' is distinct from v_actor::text
       or v_created_row->'state_code' is distinct from '0'::jsonb
       or v_created_row->'rule_verification' is distinct from 'false'::jsonb
       or v_created_row->>'model_id' is not null
       or v_created_row->'json_ordered' is distinct from v_selected->'json_ordered' then
      raise exception using errcode='P0001',message='DATASET_STABLE_DRAFT_RESULT_INVALID';
    end if;
    v_root_key:=case v_table when 'contacts' then 'contactDataSet' when 'sources' then 'sourceDataSet'
      when 'flows' then 'flowDataSet' else 'processDataSet' end;
    v_uri_slug:=case v_table when 'contacts' then 'contact' when 'sources' then 'source'
      when 'flows' then 'productFlow' else 'process' end;
    v_created_body:=v_selected->'json_ordered';
    v_source_body:=v_source->'json_ordered';
    if v_created_body#>>array[v_root_key,'administrativeInformation','publicationAndOwnership','common:dataSetVersion'] is distinct from v_version
       or v_created_body#>>array[v_root_key,'administrativeInformation','publicationAndOwnership','common:permanentDataSetURI']
         is distinct from 'https://lcdn.tiangong.earth/datasetdetail/'||v_uri_slug||'.xhtml?uuid='||v_id::text||'&version='||v_version
       or (v_created_body #- array[v_root_key,'administrativeInformation','publicationAndOwnership','common:dataSetVersion']
            #- array[v_root_key,'administrativeInformation','publicationAndOwnership','common:permanentDataSetURI'])
          is distinct from (v_source_body #- array[v_root_key,'administrativeInformation','publicationAndOwnership','common:dataSetVersion']
            #- array[v_root_key,'administrativeInformation','publicationAndOwnership','common:permanentDataSetURI']) then
      raise exception using errcode='P0001',message='DATASET_STABLE_DRAFT_RESULT_INVALID';
    end if;
    v_versions := jsonb_build_array(v_selected->>'version');
    v_outcome := 'created';
  else
    if v_selected_version is null then v_selected_version := v_drafts->0->>'version'; end if;
    select x into v_selected from jsonb_array_elements(v_drafts) x where x->>'version'=v_selected_version;
    v_outcome := case when jsonb_array_length(v_drafts)>1 then 'selected' else 'reused' end;
  end if;
  -- Report the complete conflict set before classifying a chosen draft. An
  -- unselected reference-only sibling must not disappear from the census.
  if v_outcome<>'created' and v_table='flows' and (
      v_selected#>>'{json_ordered,flowDataSet,modellingAndValidation,LCIMethod,typeOfDataSet}' is null
      or v_selected#>>'{json_ordered,flowDataSet,modellingAndValidation,LCIMethod,typeOfDataSet}' not in ('Product flow','Waste flow')) then
    return jsonb_build_object('ok',false,'code','DATASET_REFERENCE_ONLY','status',403,'message','The selected flow is Elementary or unknown; stable generic preparation is closed');
  end if;
  v_result := jsonb_build_object('requestId',p_request_id,'table',v_table,'id',v_id,'actorId',v_actor,
    'outcome',v_outcome,'version',v_selected->>'version','sourceVersion',v_source->>'version',
    'draftVersions',v_versions,'selectedDraft',jsonb_build_object('version',v_selected->>'version',
      'userId',v_selected->>'user_id','stateCode',(v_selected->>'state_code')::integer,'jsonOrdered',v_selected->'json_ordered'),
    'replayed',false);
  insert into private.command_audit_log(command,actor_user_id,target_table,target_id,target_version,payload)
    values ('cmd_dataset_prepare_stable_draft',v_actor,v_table,v_id,v_selected->>'version',
      jsonb_build_object('requestId',p_request_id,'requestSha256',v_fingerprint,'result',v_result));
  return jsonb_build_object('ok',true,'data',v_result);
exception
  when raise_exception then
    get stacked diagnostics v_error=message_text,v_details=pg_exception_detail;
    if v_error='DATASET_STABLE_DRAFT_RESULT_INVALID' then
      return jsonb_build_object('ok',false,'code',v_error,'status',500,'message','The version writer returned an invalid target; preparation was rolled back');
    elsif v_error='DATASET_STABLE_DRAFT_DELEGATE_REJECTED' then
      return v_details::jsonb;
    end if;
    raise;
  when lock_not_available or deadlock_detected or query_canceled then
    return jsonb_build_object('ok',false,'code','DATASET_STABLE_DRAFT_BUSY','status',503,'message','Stable draft preparation is temporarily busy');
  when check_violation then
    get stacked diagnostics v_error=message_text,v_details=pg_exception_detail;
    if v_error in ('DATASET_DRAFT_CONFLICT','LIFECYCLEMODEL_BUNDLE_REQUIRED') then
      return jsonb_build_object('ok',false,'code',v_error,'status',409,'message',v_error,'details',v_details::jsonb);
    end if;
    raise;
end;
$_$;

ALTER FUNCTION "api"."cmd_dataset_prepare_stable_draft"("p_request_id" "uuid", "p_request" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."cmd_dataset_prepare_stable_draft"("p_request_id" "uuid", "p_request" "jsonb") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."cmd_dataset_prepare_stable_draft"("p_request_id" "uuid", "p_request" "jsonb") TO "authenticated";
