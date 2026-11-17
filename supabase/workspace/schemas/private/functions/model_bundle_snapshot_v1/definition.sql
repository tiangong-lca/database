CREATE OR REPLACE FUNCTION "private"."model_bundle_snapshot_v1"("p_actor" "uuid", "p_id" "uuid", "p_version" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE
    SET "search_path" TO ''
    AS $_$
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
$_$;

ALTER FUNCTION "private"."model_bundle_snapshot_v1"("p_actor" "uuid", "p_id" "uuid", "p_version" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."model_bundle_snapshot_v1"("p_actor" "uuid", "p_id" "uuid", "p_version" "text") FROM PUBLIC;
