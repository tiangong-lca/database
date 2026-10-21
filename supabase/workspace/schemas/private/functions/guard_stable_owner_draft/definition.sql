CREATE OR REPLACE FUNCTION "private"."guard_stable_owner_draft"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
declare
  v_old_id uuid;
  v_old_version text;
  v_new_model uuid;
  v_old_model uuid;
  v_new_flow_type text;
  v_old_flow_type text;
  v_conflicts jsonb;
  v_exact_key_exists boolean;
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

  -- BEFORE INSERT runs before native uniqueness/ON CONFLICT arbitration.
  -- An existing exact post-sync PK is not new admission. Pin that key so a
  -- concurrent DELETE/key change cannot remove the conflict after this check.
  -- DO UPDATE runs the UPDATE guard separately against its actual final row.
  if tg_op = 'INSERT' then
    begin
      execute pg_catalog.format(
        'select true from public.%I d where d.id=$1 and d.version=$2 for key share nowait',
        tg_table_name)
        into v_exact_key_exists using new.id,new.version;
    exception when lock_not_available then
      raise exception using errcode='55P03',message='DATASET_STABLE_DRAFT_BUSY';
    end;
    -- EXECUTE does not set FOUND; the explicit result distinguishes no row.
    if v_exact_key_exists is true then return new;end if;
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
$_$;

ALTER FUNCTION "private"."guard_stable_owner_draft"() OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."guard_stable_owner_draft"() FROM PUBLIC;
