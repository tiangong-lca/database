-- Exact group snapshot, atomic optimistic concurrency and durable save receipts.
begin;

create table private.model_bundle_save_receipts (
    actor_id uuid not null,
    operation_id uuid not null,
    request_hash bytea not null,
    model_id uuid not null,
    model_version text not null,
    revision text not null,
    members jsonb not null,
    saved_at timestamptz not null default transaction_timestamp(),
    primary key (actor_id, operation_id)
);
alter table private.model_bundle_save_receipts enable row level security;
revoke all on private.model_bundle_save_receipts from public, anon, authenticated, service_role;

-- Ordinary writers acquire a shared group lock. The guarded writer takes the
-- exclusive lock before reading the snapshot. Taking these locks without
-- waiting avoids inverting row-lock order with an already-running writer.
create function private.model_bundle_lock_key(p_model_id uuid, p_version text)
returns bigint language sql immutable strict set search_path = '' as $$
    select pg_catalog.hashtextextended(p_model_id::text || ':' || btrim(p_version), 880)
$$;

create function private.fence_model_bundle_write_v1()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
    v_old_key bigint;
    v_new_key bigint;
begin
    if tg_table_name = 'processes' then
        if tg_op <> 'INSERT' then
            v_old_key := private.model_bundle_lock_key(old.model_id, coalesce(old.model_version, old.version));
        end if;
        if tg_op <> 'DELETE' then
            v_new_key := private.model_bundle_lock_key(new.model_id, coalesce(new.model_version, new.version));
        end if;
    else
        if tg_op <> 'INSERT' then
            v_old_key := private.model_bundle_lock_key(old.id, old.version);
        end if;
        if tg_op <> 'DELETE' then
            v_new_key := private.model_bundle_lock_key(new.id, new.version);
        end if;
    end if;
    if (v_old_key is not null and not pg_catalog.pg_try_advisory_xact_lock_shared(v_old_key))
       or (v_new_key is not null and v_new_key is distinct from v_old_key
           and not pg_catalog.pg_try_advisory_xact_lock_shared(v_new_key)) then
        raise exception using errcode = '55P03', message = 'MODEL_MEMBERSHIP_BUSY';
    end if;
    if tg_op = 'DELETE' then return old; end if;
    return new;
end
$$;
-- The fenced trigger accesses no table data and is not a callable API.
revoke all on function private.fence_model_bundle_write_v1() from public, anon, authenticated, service_role;

create trigger zz_model_bundle_write_fence
before insert or update or delete on public.lifecyclemodels
for each row execute function private.fence_model_bundle_write_v1();

create trigger zz_model_bundle_write_fence
before insert or update or delete on public.processes
for each row execute function private.fence_model_bundle_write_v1();

create function private.model_bundle_snapshot_v1(p_actor uuid, p_id uuid, p_version text)
returns jsonb language plpgsql stable set search_path = '' as $$
declare
    v_model public.lifecyclemodels%rowtype;
    v_declared jsonb;
    v_primary jsonb;
    v_members jsonb;
    v_rows jsonb;
    v_result jsonb;
begin
    select * into v_model from public.lifecyclemodels
     where id = p_id and version = p_version and user_id = p_actor;
    if not found then return null; end if;

    v_declared := coalesce(v_model.json_tg::jsonb->'submodels', '[]'::jsonb);
    v_primary := v_model.json_ordered::jsonb #>
      '{lifeCycleModelDataSet,lifeCycleModelInformation,dataSetInformation,referenceToResultingProcess}';
    if jsonb_typeof(v_declared) <> 'array' then
        raise exception 'MODEL_MEMBERSHIP_INVALID';
    end if;
    if v_declared = '[]'::jsonb and v_primary is not null then
        v_declared := jsonb_build_array(jsonb_build_object(
            'id', v_primary->>'@refObjectId', 'version', v_primary->>'@version', 'type', 'primary'
        ));
    end if;

    if exists (
        select 1 from jsonb_array_elements(v_declared) as m
        where jsonb_typeof(m) <> 'object'
           or coalesce(m->>'id', '') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
           or coalesce(m->>'version', '') !~ '^[0-9]{2}\.[0-9]{2}\.[0-9]{3}$'
           or coalesce(m->>'type', '') not in ('primary','secondary','allocated')
    ) or exists (
        select 1 from jsonb_array_elements(v_declared) as m
        group by m->>'id', m->>'version' having count(*) > 1
    ) or (v_declared <> '[]'::jsonb and (
        (select count(*) from jsonb_array_elements(v_declared) m where m->>'type' = 'primary') <> 1
        or not exists (
            select 1 from jsonb_array_elements(v_declared) m
            where m->>'type' = 'primary' and m->>'id' = v_primary->>'@refObjectId'
              and m->>'version' = v_primary->>'@version'
        )
    )) then
        raise exception 'MODEL_MEMBERSHIP_INVALID';
    end if;

    with actual as materialized (
        select id, version, model_version, user_id, state_code, modified_at,
               json_ordered, rule_verification
          from public.processes
         where model_id = p_id and coalesce(model_version, version) = p_version
           and state_code < 100
    ), declared as materialized (
        select m as member, (m->>'id')::uuid as id, m->>'version' as version
          from jsonb_array_elements(v_declared) m
    )
    select
        jsonb_agg(d.member order by d.id, d.version),
        jsonb_agg(jsonb_build_object(
            'id', a.id, 'version', a.version, 'model_id', p_id, 'model_version', a.model_version,
            'state_code', a.state_code, 'modified_at', a.modified_at, 'json_ordered', a.json_ordered,
            'rule_verification', a.rule_verification
        ) order by d.id, d.version)
        into v_members, v_rows
      from declared d full join actual a on d.id = a.id and d.version = a.version
      having count(*) = count(d.id) and count(*) = count(a.id)
         and count(*) = count(*) filter (where a.user_id = p_actor);
    if not found then raise exception 'MODEL_MEMBERSHIP_INVALID'; end if;

    v_result := jsonb_build_object(
        'model', jsonb_build_object(
            'id', v_model.id, 'version', v_model.version, 'modified_at', v_model.modified_at,
            'state_code', v_model.state_code, 'json_ordered', v_model.json_ordered,
            'json_tg', v_model.json_tg, 'rule_verification', v_model.rule_verification
        ),
        'members', coalesce(v_members, '[]'::jsonb),
        'processes', coalesce(v_rows, '[]'::jsonb)
    );
    return v_result || jsonb_build_object(
        'revision', encode(sha256(convert_to(v_result::text, 'UTF8')), 'hex')
    );
end
$$;

create function private.model_bundle_operation_v1(p_actor uuid, p_request jsonb)
returns jsonb language plpgsql volatile set search_path = '' as $$
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
$$;
revoke all on function private.model_bundle_snapshot_v1(uuid,uuid,text) from public, anon, authenticated, service_role;
revoke all on function private.model_bundle_operation_v1(uuid,jsonb) from public, anon, authenticated, service_role;

-- The existing API route and OAuth capability continue to own admission.
create or replace function api.cmd_lifecycle_model_bundle_save(p_plan jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
    v_actor uuid := auth.uid();
begin
    if v_actor is null then raise exception using errcode = '42501', message = 'AUTH_REQUIRED'; end if;
    if p_plan ? 'protocol' then
        if p_plan->>'protocol' is distinct from 'model-bundle.v1' then raise exception 'INVALID_PLAN'; end if;
        return private.model_bundle_operation_v1(v_actor, p_plan);
    end if;
    return private.save_lifecycle_model_bundle(
        jsonb_set(coalesce(p_plan, '{}'::jsonb), '{actorUserId}', to_jsonb(v_actor::text), true)
    );
end
$$;

commit;
