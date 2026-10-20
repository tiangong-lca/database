-- Database #855 / CLI #372: preserve one ordinary owner draft per typed UUID.
-- The existing version allocator and guarded-save writer remain the only writers.
-- Historical duplicate drafts are neither rewritten nor deleted. Existing
-- model-bound scopes retain their prior multiple-version contract; model_id is
-- an exclusion, NOT proof of trusted native admission or global uniqueness.
-- Mixed standalone/model-bound owner-draft families fail closed.
begin;

create or replace function private.guard_stable_owner_draft()
returns trigger
language plpgsql volatile security definer
set search_path = ''
as $guard$
declare
  v_old_id uuid;
  v_old_version text;
  v_new_model uuid;
  v_old_model uuid;
  v_new_flow_type text;
  v_old_flow_type text;
  v_conflicts jsonb;
  v_reviews jsonb;
  v_old_review boolean := false;
  v_new_review boolean := coalesce(new.state_code >= 20 and new.state_code < 100,false);
begin
  if tg_table_name = 'processes' then
    v_new_model := new.model_id;
  elsif tg_table_name = 'flows' then
    v_new_flow_type := new.json_ordered::jsonb#>>'{flowDataSet,modellingAndValidation,LCIMethod,typeOfDataSet}';
  end if;

  if tg_op = 'UPDATE' then
    if tg_table_name='processes' and old.state_code=120 then
      return new; -- the unchanged final Result immutability guard owns rejection
    end if;
    v_old_review:=coalesce(old.state_code >= 20 and old.state_code < 100,false);
    if tg_table_name = 'processes' then
      v_old_model := old.model_id;
    elsif tg_table_name = 'flows' then
      v_old_flow_type := old.json_ordered::jsonb#>>'{flowDataSet,modellingAndValidation,LCIMethod,typeOfDataSet}';
    end if;
    -- Do not turn routine content/derivative updates into historical cleanup.
    -- This check runs AFTER JSON/version synchronization, including json_ordered
    -- updates which change the generated version without an UPDATE OF version.
    if old.state_code = 0 and old.id = new.id
       and new.state_code = 0
       and old.version = new.version
       and old.user_id is not distinct from new.user_id
       and v_old_model is not distinct from v_new_model
       and v_old_flow_type is not distinct from v_new_flow_type then
      return new;
    end if;
    if old.state_code is not distinct from new.state_code and new.state_code is distinct from 0
       and old.id=new.id and old.version=new.version
       and old.user_id is not distinct from new.user_id then
      return new;
    end if;
    v_old_id := old.id;
    v_old_version := old.version;
  end if;
  if new.state_code is distinct from 0 and not v_new_review and not v_old_review then
    return new;
  end if;

  -- An advisory lock alone cannot refresh a repeatable-read snapshot. The
  -- volatile trigger's post-lock SPI query sees fresh committed rows only at
  -- READ COMMITTED. Refuse unsupported isolation instead of claiming uniqueness.
  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
    raise exception using errcode = '25000',
      message = 'DATASET_DRAFT_ISOLATION_REQUIRED';
  end if;

  if not pg_catalog.pg_try_advisory_xact_lock(
    pg_catalog.hashtext('cmd_dataset_create_version:' || tg_table_name),
    pg_catalog.hashtext(new.id::text)
  ) then
    raise exception using errcode = '55P03',
      message = 'DATASET_STABLE_DRAFT_BUSY';
  end if;

  -- Review entry/exit shares this exact family lock. In particular a 0 -> 20
  -- transition may not commit between a preparer's review check and draft census.
  -- Ordinary same-state content/derivative saves returned above.
  if new.state_code is distinct from 0 then return new;end if;
  execute pg_catalog.format(
    'select coalesce(jsonb_agg(jsonb_build_object(''table'',%L,''id'',d.id,
       ''version'',d.version,''userId'',d.user_id,''stateCode'',d.state_code,
       ''reviewId'',d.review_id) order by d.version),''[]''::jsonb)
       from public.%I d where d.id=$1 and d.user_id is not distinct from $2
        and d.state_code>=20 and d.state_code<100
        and not(d.id is not distinct from $3 and d.version is not distinct from $4)',
    tg_table_name,tg_table_name)
    into v_reviews using new.id,new.user_id,v_old_id,v_old_version;
  if jsonb_array_length(v_reviews)>0 then
    raise exception using errcode='23514',message='DATASET_REVIEW_IN_PROGRESS',
      detail=jsonb_build_object('table',tg_table_name,'id',new.id,'reviews',v_reviews)::text;
  end if;

  -- Existing model-bound-only scopes may coexist. Any crossing between a
  -- standalone draft and a model-bound row conflicts, including an ordinary
  -- caller supplying a fabricated modelId after standalone preparation.
  -- Model-only creation remains outside this slice's uniqueness claim.
  execute pg_catalog.format(
    'select coalesce(jsonb_agg(jsonb_build_object(''version'', d.version,
       ''userId'', d.user_id, ''stateCode'', d.state_code) order by d.version), ''[]''::jsonb)
       from public.%I d
      where d.id = $1 and d.user_id is not distinct from $2 and d.state_code = 0
        and not (d.id is not distinct from $3 and d.version is not distinct from $4)
        %s',
    tg_table_name,
    case when tg_table_name = 'processes' and v_new_model is not null
         then 'and d.model_id is null'
         when tg_table_name = 'flows' and (v_new_flow_type is null or v_new_flow_type not in ('Product flow','Waste flow'))
         then 'and d.json_ordered::jsonb#>>''{flowDataSet,modellingAndValidation,LCIMethod,typeOfDataSet}'' in (''Product flow'',''Waste flow'')'
         else '' end
  ) into v_conflicts using new.id, new.user_id, v_old_id, v_old_version;

  if jsonb_array_length(v_conflicts) > 0 then
    raise exception using errcode = '23514',
      message = case when v_new_model is not null
        then 'LIFECYCLEMODEL_BUNDLE_REQUIRED' else 'DATASET_DRAFT_CONFLICT' end,
      detail = jsonb_build_object('drafts', v_conflicts)::text;
  end if;
  return new;
end;
$guard$;

alter function private.guard_stable_owner_draft() owner to postgres;
revoke all on function private.guard_stable_owner_draft() from public, anon, authenticated, service_role;

-- PostgreSQL orders same-event triggers alphabetically. This guard follows the
-- *_json_sync_trigger and all current transforming BEFORE triggers. It is an
-- all-column UPDATE trigger because a body sync can change version implicitly.
create trigger zzz_guard_owner_draft_stability
before insert or update on public.contacts
for each row execute function private.guard_stable_owner_draft();

-- The legacy writers already catch CHECK violations. Preserve their other
-- errors and writer bodies, but do not discard the new guard's complete review
-- return points. This is not a second allocator or a new lifecycle writer.
do $legacy_review_error$
declare
  v_signature text;
  v_definition text;
  v_declaration constant text := '  v_created_row jsonb;';
  v_handler constant text := '    when check_violation then
      return jsonb_build_object(';
  v_replacement constant text := '    when check_violation then
      if sqlerrm = ''DATASET_REVIEW_IN_PROGRESS'' then
        get stacked diagnostics v_stable_review_detail = pg_exception_detail;
        return jsonb_build_object(''ok'',false,''code'',''DATASET_REVIEW_IN_PROGRESS'',
          ''status'',409,''message'',''The owner dataset family is under review'',
          ''details'',v_stable_review_detail::jsonb);
      end if;
      return jsonb_build_object(';
begin
  foreach v_signature in array array[
    'api.cmd_dataset_create(text,uuid,jsonb,uuid,boolean,jsonb,text)',
    'api.cmd_dataset_create_version(text,uuid,text,jsonb,uuid,boolean,jsonb,text)'
  ] loop
    v_definition:=pg_catalog.pg_get_functiondef(v_signature::regprocedure);
    if (length(v_definition)-length(replace(v_definition,v_declaration,'')))/length(v_declaration)<>1
       or (length(v_definition)-length(replace(v_definition,v_handler,'')))/length(v_handler)<>1 then
      raise exception 'Stable draft review wrapper precondition changed: %',v_signature;
    end if;
    v_definition:=replace(v_definition,v_declaration,v_declaration||E'\n  v_stable_review_detail text;');
    execute replace(v_definition,v_handler,v_replacement);
  end loop;
end;
$legacy_review_error$;
create trigger zzz_guard_owner_draft_stability
before insert or update on public.sources
for each row execute function private.guard_stable_owner_draft();
create trigger zzz_guard_owner_draft_stability
before insert or update on public.flows
for each row execute function private.guard_stable_owner_draft();
create trigger zzz_guard_owner_draft_stability
before insert or update on public.processes
for each row execute function private.guard_stable_owner_draft();

create or replace function private.stable_draft_request_validate(p_request_id uuid, p_request jsonb)
returns jsonb
language plpgsql immutable
set search_path = ''
as $validate$
declare
  v_item jsonb;
  v_source jsonb;
  v_drafts jsonb;
  v_count bigint;
  v_distinct_count bigint;
  v_uuid_pattern constant text := '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';
  v_version_pattern constant text := '^[0-9]{2}\.[0-9]{2}\.[0-9]{3}$';
begin
  if p_request_id is null or jsonb_typeof(p_request) is distinct from 'object' then
    return jsonb_build_object('ok', false, 'code', 'INVALID_STABLE_DRAFT_REQUEST', 'status', 400,
      'message', 'A request UUID and complete request object are required');
  end if;
  if p_request ? 'initialJsonOrdered' or p_request->'source' = 'null'::jsonb then
    return jsonb_build_object('ok', false, 'code', 'DATASET_INITIAL_CREATION_UNSUPPORTED', 'status', 400,
      'message', 'This contract requires an exact public source; initial creation is not supported');
  end if;
  if p_request->>'table' = 'lifecyclemodels' then
    return jsonb_build_object('ok', false, 'code', 'LIFECYCLEMODEL_BUNDLE_REQUIRED', 'status', 409,
      'message', 'LifecycleModels require their native bundle contract');
  end if;
  if p_request->>'table' is null or p_request->>'table' not in ('contacts', 'sources', 'flows', 'processes') then
    return jsonb_build_object('ok', false, 'code', 'INVALID_DATASET_TABLE', 'status', 400,
      'message', 'Stable draft preparation supports contacts, sources, flows and standalone processes');
  end if;
  if (p_request - array['table','id','expectedActorId','expectedDrafts','selectedVersion','source']) <> '{}'::jsonb
     or not (p_request ?& array['table','id','expectedActorId','expectedDrafts','source'])
     or jsonb_typeof(p_request->'id') is distinct from 'string'
     or (p_request->>'id') !~ v_uuid_pattern
     or jsonb_typeof(p_request->'expectedActorId') is distinct from 'string'
     or (p_request->>'expectedActorId') !~ v_uuid_pattern
     or jsonb_typeof(p_request->'expectedDrafts') is distinct from 'array'
     or (p_request->'selectedVersion' is not null and p_request->'selectedVersion' <> 'null'::jsonb
         and (jsonb_typeof(p_request->'selectedVersion') <> 'string'
              or (p_request->>'selectedVersion') !~ v_version_pattern)) then
    return jsonb_build_object('ok', false, 'code', 'INVALID_STABLE_DRAFT_REQUEST', 'status', 400,
      'message', 'Invalid request fields, UUIDs, versions or complete draft set');
  end if;
  v_source := p_request->'source';
  if jsonb_typeof(v_source) is distinct from 'object'
     or (v_source - array['version','userId','stateCode','jsonOrdered']) <> '{}'::jsonb
     or not (v_source ?& array['version','userId','stateCode','jsonOrdered'])
     or jsonb_typeof(v_source->'version') is distinct from 'string'
     or (v_source->>'version') !~ v_version_pattern
     or jsonb_typeof(v_source->'userId') is distinct from 'string'
     or (v_source->>'userId') !~ v_uuid_pattern
     or v_source->'stateCode' not in ('100'::jsonb,'200'::jsonb)
     or jsonb_typeof(v_source->'jsonOrdered') is distinct from 'object' then
    return jsonb_build_object('ok', false, 'code', 'INVALID_STABLE_DRAFT_REQUEST', 'status', 400,
      'message', 'An exact state-100/200 source owner/version and complete JSON object are required');
  end if;
  for v_item in select value from jsonb_array_elements(p_request->'expectedDrafts') loop
    if jsonb_typeof(v_item) is distinct from 'object'
       or (v_item - array['version','jsonOrdered']) <> '{}'::jsonb
       or not (v_item ?& array['version','jsonOrdered'])
       or jsonb_typeof(v_item->'version') is distinct from 'string'
       or (v_item->>'version') !~ v_version_pattern
       or jsonb_typeof(v_item->'jsonOrdered') is distinct from 'object' then
      return jsonb_build_object('ok', false, 'code', 'INVALID_STABLE_DRAFT_REQUEST', 'status', 400,
        'message', 'Each expected draft requires one exact version and complete JSON object');
    end if;
  end loop;
  select count(*), count(distinct value->>'version'),
    coalesce(jsonb_agg(value order by value->>'version'), '[]'::jsonb)
    into v_count, v_distinct_count, v_drafts
    from jsonb_array_elements(p_request->'expectedDrafts');
  if v_count <> v_distinct_count then
    return jsonb_build_object('ok', false, 'code', 'INVALID_STABLE_DRAFT_REQUEST', 'status', 400,
      'message', 'Expected draft versions must be unique');
  end if;
  return jsonb_build_object('ok', true, 'data',
    jsonb_set(jsonb_set(p_request, '{expectedDrafts}', v_drafts),
      '{selectedVersion}', coalesce(p_request->'selectedVersion','null'::jsonb)));
end;
$validate$;
alter function private.stable_draft_request_validate(uuid, jsonb) owner to postgres;
revoke all on function private.stable_draft_request_validate(uuid, jsonb) from public, anon, authenticated, service_role;

-- An exact request receipt belongs to the existing audit owner, not a second
-- business ledger. The partial uniqueness affects only the new command.
create unique index command_audit_stable_draft_request_uq
on private.command_audit_log (actor_user_id, (payload->>'requestId'))
where command = 'cmd_dataset_prepare_stable_draft';

create or replace function api.cmd_dataset_prepare_stable_draft(p_request_id uuid, p_request jsonb)
returns jsonb
language plpgsql volatile security definer
set search_path = ''
as $prepare$
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
$prepare$;

create or replace function api.get_dataset_stable_draft_request(p_request_id uuid, p_request jsonb)
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $readback$
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
$readback$;

alter function api.cmd_dataset_prepare_stable_draft(uuid,jsonb) owner to postgres;
alter function api.get_dataset_stable_draft_request(uuid,jsonb) owner to postgres;
revoke all on function api.cmd_dataset_prepare_stable_draft(uuid,jsonb) from public,anon,authenticated,service_role;
revoke all on function api.get_dataset_stable_draft_request(uuid,jsonb) from public,anon,authenticated,service_role;
grant execute on function api.cmd_dataset_prepare_stable_draft(uuid,jsonb) to authenticated;
grant execute on function api.get_dataset_stable_draft_request(uuid,jsonb) to authenticated;
insert into private.api_capability_grants(routine_identity,capability_id,allow_anon,allow_authenticated,allow_service_role)
values ('api.cmd_dataset_prepare_stable_draft(uuid, jsonb)','CLI-RPC-01',false,true,false),
       ('api.get_dataset_stable_draft_request(uuid, jsonb)','DB-CORE-READ-01',false,true,false)
on conflict(routine_identity) do update set capability_id=excluded.capability_id,
  allow_anon=excluded.allow_anon,allow_authenticated=excluded.allow_authenticated,allow_service_role=excluded.allow_service_role;

notify pgrst, 'reload schema';
commit;
