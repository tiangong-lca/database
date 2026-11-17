CREATE OR REPLACE FUNCTION "private"."model_bundle_operation_v1"("p_actor" "uuid", "p_request" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $_$
declare
    v_action text := p_request->>'action';
    v_id uuid := (p_request->>'modelId')::uuid;
    v_version text := p_request->>'version';
    v_operation uuid := (p_request->>'operationId')::uuid;
    v_plan jsonb := p_request->'plan';
    v_expected text := p_request->>'expectedRevision';
    v_request_hash bytea;
    v_snapshot jsonb;
    v_receipt private.model_bundle_save_receipts%rowtype;
    v_mutation jsonb;
    v_member_version text;
    v_written jsonb;
begin
    if p_actor is null then raise exception using errcode = '42501', message = 'AUTH_REQUIRED'; end if;
    if v_id is null or coalesce(v_version, '') !~ '^[0-9]{2}\.[0-9]{2}\.[0-9]{3}$'
       or coalesce(v_action, '') not in ('inspect','recover','save') then
        raise exception 'INVALID_PLAN';
    end if;
    if v_action = 'inspect' then
        return jsonb_build_object('protocol','model-bundle.v1','status','observed',
            'snapshot', private.model_bundle_snapshot_v1(p_actor, v_id, v_version));
    end if;
    if v_operation is null then raise exception 'INVALID_PLAN'; end if;

    if v_action = 'save' then
        if current_setting('transaction_isolation') not in ('read committed','read uncommitted') then
            raise exception using errcode = '0A000', message = 'UNSUPPORTED_TRANSACTION_ISOLATION';
        end if;
        if not pg_catalog.pg_try_advisory_xact_lock(
            pg_catalog.hashtextextended(p_actor::text || ':' || v_operation::text, 976)
        ) then
            raise exception using errcode = '55P03', message = 'MODEL_MEMBERSHIP_BUSY';
        end if;
        v_request_hash := sha256(convert_to(p_request::text, 'UTF8'));
    end if;
    select * into v_receipt from private.model_bundle_save_receipts
    where actor_id = p_actor and operation_id = v_operation;
    if found then
        if v_action = 'save' and v_request_hash is distinct from v_receipt.request_hash then
            raise exception 'MODEL_OPERATION_CONFLICT';
        end if;
        if v_id = v_receipt.model_id and v_version = v_receipt.model_version then
            return jsonb_build_object('protocol','model-bundle.v1','status','committed',
                'modelId',v_id,'version',v_version,'operationId',v_operation,
                'revision',v_receipt.revision,'members',v_receipt.members,'savedAt',v_receipt.saved_at);
        end if;
    end if;
    if v_action = 'recover' then
        return jsonb_build_object('protocol','model-bundle.v1','status','unknown','operationId',v_operation);
    end if;

    if coalesce(v_plan->>'mode','') not in ('create','update')
       or v_plan->>'modelId' is distinct from v_id::text
       or v_plan->>'version' is distinct from v_version
       or coalesce(v_plan->>'allocateVersion','false') <> 'false'
       or jsonb_typeof(v_plan->'processMutations') is distinct from 'array'
       or v_plan #>> '{parent,jsonOrdered,lifeCycleModelDataSet,lifeCycleModelInformation,dataSetInformation,common:UUID}'
            is distinct from v_id::text
       or v_plan #>> '{parent,jsonOrdered,lifeCycleModelDataSet,administrativeInformation,publicationAndOwnership,common:dataSetVersion}'
            is distinct from v_version
       or not (p_request ? 'expectedRevision') then
        raise exception 'INVALID_PLAN';
    end if;
    if not pg_catalog.pg_try_advisory_xact_lock(private.model_bundle_lock_key(v_id, v_version)) then
        raise exception using errcode = '55P03', message = 'MODEL_MEMBERSHIP_BUSY';
    end if;
    if v_plan->>'mode' = 'update' then
        v_snapshot := private.model_bundle_snapshot_v1(p_actor, v_id, v_version);
        if v_snapshot is null or v_snapshot #>> '{model,state_code}' <> '0'
           or v_expected is null or v_snapshot->>'revision' is distinct from v_expected then
            raise exception 'MODEL_BUNDLE_CONFLICT';
        end if;
    else
        if v_expected is not null then raise exception 'INVALID_PLAN'; end if;
        if exists (select 1 from public.lifecyclemodels where id = v_id and version = v_version)
           or exists (select 1 from public.processes where model_id = v_id
                        and coalesce(model_version, version) = v_version and state_code < 100) then
            raise exception 'MODEL_BUNDLE_CONFLICT';
        end if;
    end if;

    for v_mutation in select value from jsonb_array_elements(v_plan->'processMutations') loop
        if coalesce(v_mutation->>'op','') not in ('create','update','delete') then
            raise exception 'INVALID_PLAN';
        end if;
        if v_mutation->>'op' <> 'delete' then
            v_member_version := v_mutation #>> '{jsonOrdered,processDataSet,administrativeInformation,publicationAndOwnership,common:dataSetVersion}';
            if v_mutation #>> '{jsonOrdered,processDataSet,processInformation,dataSetInformation,common:UUID}'
                  is distinct from v_mutation->>'id'
               or v_member_version is null
               or (v_mutation->>'op' = 'update' and v_member_version is distinct from v_mutation->>'version')
               or v_mutation->>'modelId' is distinct from v_id::text then
                raise exception 'INVALID_PLAN';
            end if;
        end if;
        if v_mutation->>'op' <> 'create' and not exists (
            select 1 from jsonb_array_elements(v_snapshot->'processes') r
            where r->>'id' = v_mutation->>'id' and r->>'version' = v_mutation->>'version'
              and r->>'state_code' = '0'
        ) then
            raise exception 'MODEL_MEMBERSHIP_INVALID';
        end if;
    end loop;

    v_written := private.save_lifecycle_model_bundle(
        jsonb_set(v_plan, '{actorUserId}', to_jsonb(p_actor::text))
    );
    if v_written->>'model_id' is distinct from v_id::text
       or v_written->>'version' is distinct from v_version then
        raise exception 'INVALID_PLAN';
    end if;
    v_snapshot := private.model_bundle_snapshot_v1(p_actor, v_id, v_version);
    if v_snapshot is null or v_snapshot->'members' = '[]'::jsonb then
        raise exception 'MODEL_MEMBERSHIP_INVALID';
    end if;
    insert into private.model_bundle_save_receipts
        (actor_id,operation_id,request_hash,model_id,model_version,revision,members)
    values
        (p_actor,v_operation,v_request_hash,v_id,v_version,v_snapshot->>'revision',v_snapshot->'members')
    returning * into v_receipt;
    return jsonb_build_object('protocol','model-bundle.v1','status','committed',
        'modelId',v_id,'version',v_version,'operationId',v_operation,
        'revision',v_receipt.revision,'members',v_receipt.members,'savedAt',v_receipt.saved_at);
end
$_$;

ALTER FUNCTION "private"."model_bundle_operation_v1"("p_actor" "uuid", "p_request" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."model_bundle_operation_v1"("p_actor" "uuid", "p_request" "jsonb") FROM PUBLIC;
