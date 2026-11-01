CREATE OR REPLACE FUNCTION "private"."save_lifecycle_model_bundle"("p_plan" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'private', 'api', 'public', 'util', 'extensions', 'pg_temp'
    AS $_$
declare
    v_mode text := coalesce(p_plan->>'mode', '');
    v_model_id uuid := nullif(p_plan->>'modelId', '')::uuid;
    v_expected_version text := nullif(btrim(coalesce(p_plan->>'version', '')), '');
    v_actor_user_id uuid := nullif(p_plan->>'actorUserId', '')::uuid;
    v_allocate_version boolean := coalesce((p_plan->>'allocateVersion')::boolean, false);
    v_source_version text := nullif(btrim(coalesce(p_plan->>'sourceVersion', '')), '');
    v_parent jsonb := coalesce(p_plan->'parent', '{}'::jsonb);
    v_parent_json_ordered jsonb := v_parent->'jsonOrdered';
    v_parent_json_tg jsonb := coalesce(v_parent->'jsonTg', '{}'::jsonb);
    v_parent_rule_verification boolean := coalesce((v_parent->>'ruleVerification')::boolean, true);
    v_process_mutations jsonb := coalesce(p_plan->'processMutations', '[]'::jsonb);
    v_mutation jsonb;
    v_child_id uuid;
    v_child_version text;
    v_saved_child_version text;
    v_child_json_ordered jsonb;
    v_child_rule_verification boolean;
    v_result_row lifecyclemodels%rowtype;
    v_rows_affected integer;
    v_highest_version text;
    v_parts integer[];
    v_allocated_version text;
    v_model_version text;
    v_allocated_uri text;
    v_dataset jsonb;
    v_admin jsonb;
    v_pub jsonb;
    v_resulting_refs jsonb;
    v_submodels jsonb;
    v_process_instances jsonb;
    v_included_refs jsonb;
    v_rewritten jsonb;
    v_mutation_index integer;
begin
    if v_mode not in ('create', 'update') then
        raise exception 'INVALID_PLAN';
    end if;

    if v_model_id is null or v_parent_json_ordered is null then
        raise exception 'INVALID_PLAN';
    end if;

    if v_actor_user_id is null then
        raise exception 'INVALID_PLAN';
    end if;

    if jsonb_typeof(v_process_mutations) <> 'array' then
        raise exception 'INVALID_PLAN';
    end if;

    if v_allocate_version then
        if v_mode <> 'create' or v_source_version is null then
            raise exception 'INVALID_PLAN';
        end if;

        perform set_config('lock_timeout', '2s', true);
        perform set_config('statement_timeout', '8s', true);
        perform pg_advisory_xact_lock(
            hashtext('save_lifecycle_model_bundle:create_version'),
            hashtext(v_model_id::text)
        );

        perform 1
          from lifecyclemodels d
         where d.id = v_model_id
           and d.version = v_source_version
           and (
             d.state_code >= 100
             or d.user_id = v_actor_user_id
             or exists (
               select 1
                 from private.roles r
                where r.team_id = d.team_id
                  and r.user_id = v_actor_user_id
                  and r.role::text = any(array['admin', 'member', 'owner'])
             )
           );

        if not found then
            raise exception 'MODEL_NOT_FOUND';
        end if;

        select version::text
          into v_highest_version
          from public.lifecyclemodels
         where id = v_model_id
           and version::text ~ '^[0-9]{2}\.[0-9]{2}\.[0-9]{3}$'
         order by split_part(version::text, '.', 1)::integer desc,
                  split_part(version::text, '.', 2)::integer desc,
                  split_part(version::text, '.', 3)::integer desc
         limit 1;

        if v_highest_version is null then
            v_parts := array[0, 0, -1];
        else
            v_parts := array[
                split_part(v_highest_version, '.', 1)::integer,
                split_part(v_highest_version, '.', 2)::integer,
                split_part(v_highest_version, '.', 3)::integer
            ];
        end if;

        v_parts[3] := v_parts[3] + 1;

        if v_parts[3] > 999 then
            v_parts[3] := 0;
            v_parts[2] := v_parts[2] + 1;
        end if;

        if v_parts[2] > 99 then
            v_parts[2] := 0;
            v_parts[1] := v_parts[1] + 1;
        end if;

        v_allocated_version := lpad(v_parts[1]::text, 2, '0')
            || '.'
            || lpad(v_parts[2]::text, 2, '0')
            || '.'
            || lpad(v_parts[3]::text, 3, '0');
        v_allocated_uri := 'https://lcdn.tiangong.earth/datasetdetail/lifecyclemodel.xhtml?uuid='
            || v_model_id::text
            || '&version='
            || v_allocated_version;

        v_dataset := coalesce(v_parent_json_ordered->'lifeCycleModelDataSet', '{}'::jsonb);
        v_admin := coalesce(v_dataset->'administrativeInformation', '{}'::jsonb);
        v_pub := coalesce(v_admin->'publicationAndOwnership', '{}'::jsonb);
        v_pub := jsonb_set(v_pub, '{common:dataSetVersion}', to_jsonb(v_allocated_version), true);
        v_pub := jsonb_set(v_pub, '{common:permanentDataSetURI}', to_jsonb(v_allocated_uri), true);
        v_admin := jsonb_set(v_admin, '{publicationAndOwnership}', v_pub, true);
        v_dataset := jsonb_set(v_dataset, '{administrativeInformation}', v_admin, true);
        v_parent_json_ordered := jsonb_set(
            v_parent_json_ordered,
            '{lifeCycleModelDataSet}',
            v_dataset,
            true
        );

        v_resulting_refs := v_parent_json_ordered #> '{lifeCycleModelDataSet,lifeCycleModelInformation,dataSetInformation,referenceToResultingProcess}';
        if jsonb_typeof(v_resulting_refs) = 'array' then
            select coalesce(
                jsonb_agg(
                    case
                        when jsonb_typeof(value) = 'object'
                            then jsonb_set(value, '{@version}', to_jsonb(v_allocated_version), true)
                        else value
                    end
                ),
                '[]'::jsonb
            )
              into v_resulting_refs
              from jsonb_array_elements(v_resulting_refs);
            v_parent_json_ordered := jsonb_set(
                v_parent_json_ordered,
                '{lifeCycleModelDataSet,lifeCycleModelInformation,dataSetInformation,referenceToResultingProcess}',
                v_resulting_refs,
                true
            );
        elsif jsonb_typeof(v_resulting_refs) = 'object' then
            v_parent_json_ordered := jsonb_set(
                v_parent_json_ordered,
                '{lifeCycleModelDataSet,lifeCycleModelInformation,dataSetInformation,referenceToResultingProcess}',
                jsonb_set(v_resulting_refs, '{@version}', to_jsonb(v_allocated_version), true),
                true
            );
        end if;

        -- Only exact references to Processes created by this bundle follow its
        -- allocated version. References to source inventories remain version-pinned.
        v_process_instances := v_parent_json_ordered #> '{lifeCycleModelDataSet,lifeCycleModelInformation,technology,processes,processInstance}';
        if jsonb_typeof(v_process_instances) in ('array', 'object') then
            select coalesce(jsonb_agg(
                case when exists (
                    select 1 from jsonb_array_elements(v_process_mutations) m
                    where m->>'op' = 'create'
                      and m->>'id' = i.value #>> '{referenceToProcess,@refObjectId}'
                      and m #>> '{jsonOrdered,processDataSet,administrativeInformation,publicationAndOwnership,common:dataSetVersion}'
                          = i.value #>> '{referenceToProcess,@version}'
                ) then jsonb_set(i.value, '{referenceToProcess,@version}', to_jsonb(v_allocated_version), false)
                else i.value end order by i.ordinality
            ), '[]'::jsonb) into v_rewritten
            from jsonb_array_elements(
                case when jsonb_typeof(v_process_instances) = 'array' then v_process_instances
                     else jsonb_build_array(v_process_instances) end
            ) with ordinality i(value, ordinality);
            v_parent_json_ordered := jsonb_set(
                v_parent_json_ordered,
                '{lifeCycleModelDataSet,lifeCycleModelInformation,technology,processes,processInstance}',
                case when jsonb_typeof(v_process_instances) = 'array' then v_rewritten
                     else v_rewritten->0 end,
                false
            );
        end if;

        for v_mutation_index in 0 .. jsonb_array_length(v_process_mutations) - 1 loop
            v_mutation := v_process_mutations->v_mutation_index;
            if v_mutation->>'op' <> 'create' then
                continue;
            end if;
            v_included_refs := v_mutation #> '{jsonOrdered,processDataSet,processInformation,technology,referenceToIncludedProcesses}';
            if jsonb_typeof(v_included_refs) in ('array', 'object') then
                select coalesce(jsonb_agg(
                    case when exists (
                        select 1 from jsonb_array_elements(v_process_mutations) m
                        where m->>'op' = 'create'
                          and m->>'id' = r.value->>'@refObjectId'
                          and m #>> '{jsonOrdered,processDataSet,administrativeInformation,publicationAndOwnership,common:dataSetVersion}'
                              = r.value->>'@version'
                    ) then jsonb_set(r.value, '{@version}', to_jsonb(v_allocated_version), false)
                    else r.value end order by r.ordinality
                ), '[]'::jsonb) into v_rewritten
                from jsonb_array_elements(
                    case when jsonb_typeof(v_included_refs) = 'array' then v_included_refs
                         else jsonb_build_array(v_included_refs) end
                ) with ordinality r(value, ordinality);
                v_process_mutations := jsonb_set(
                    v_process_mutations,
                    array[v_mutation_index::text, 'jsonOrdered', 'processDataSet', 'processInformation', 'technology', 'referenceToIncludedProcesses'],
                    case when jsonb_typeof(v_included_refs) = 'array' then v_rewritten
                         else v_rewritten->0 end,
                    false
                );
            end if;
        end loop;

        if jsonb_typeof(v_parent_json_tg->'submodels') = 'array' then
            select coalesce(
                jsonb_agg(
                    case
                        when jsonb_typeof(value) = 'object'
                            then jsonb_set(value, '{version}', to_jsonb(v_allocated_version), true)
                        else value
                    end
                ),
                '[]'::jsonb
            )
              into v_submodels
              from jsonb_array_elements(v_parent_json_tg->'submodels');
            v_parent_json_tg := jsonb_set(v_parent_json_tg, '{submodels}', v_submodels, true);
        end if;
    end if;

    if v_mode = 'update' then
        if v_expected_version is null then
            raise exception 'INVALID_PLAN';
        end if;

        perform 1
          from lifecyclemodels
         where id = v_model_id
           and version = v_expected_version
           and user_id = v_actor_user_id
           and state_code = 0
         for update;

        if not found then
            raise exception 'MODEL_NOT_FOUND';
        end if;
    end if;

    v_model_version := case
        when v_allocate_version then v_allocated_version
        when v_mode = 'update' then v_expected_version
        else nullif(
            btrim(
                coalesce(
                    v_parent_json_ordered #>> '{lifeCycleModelDataSet,administrativeInformation,publicationAndOwnership,common:dataSetVersion}',
                    ''
                )
            ),
            ''
        )
    end;

    if v_model_version is null
       or v_model_version !~ '^[0-9]{2}\.[0-9]{2}\.[0-9]{3}$' then
        raise exception 'INVALID_PLAN';
    end if;

    for v_mutation in
        select value
          from jsonb_array_elements(v_process_mutations)
    loop
        case coalesce(v_mutation->>'op', '')
            when 'delete' then
                v_child_id := nullif(v_mutation->>'id', '')::uuid;
                v_child_version := nullif(btrim(coalesce(v_mutation->>'version', '')), '');

                if v_child_id is null or v_child_version is null then
                    raise exception 'INVALID_PLAN';
                end if;

                execute 'del' || 'ete from processes where id = $1 and version = $2 and model_id = $3 and coalesce(model_version, version) = $4 and user_id = $5 and state_code = 0'
                   using v_child_id, v_child_version, v_model_id, v_model_version, v_actor_user_id;

                get diagnostics v_rows_affected = row_count;
                if v_rows_affected = 0 then
                    raise exception 'PROCESS_NOT_FOUND';
                end if;
            when 'create' then
                v_child_id := nullif(v_mutation->>'id', '')::uuid;
                v_child_json_ordered := v_mutation->'jsonOrdered';
                v_child_rule_verification := coalesce(
                    (v_mutation->>'ruleVerification')::boolean,
                    true
                );

                if v_child_id is null or v_child_json_ordered is null then
                    raise exception 'INVALID_PLAN';
                end if;

                if v_allocate_version then
                    v_dataset := coalesce(v_child_json_ordered->'processDataSet', '{}'::jsonb);
                    v_admin := coalesce(v_dataset->'administrativeInformation', '{}'::jsonb);
                    v_pub := coalesce(v_admin->'publicationAndOwnership', '{}'::jsonb);
                    v_pub := jsonb_set(
                        v_pub,
                        '{common:dataSetVersion}',
                        to_jsonb(v_allocated_version),
                        true
                    );
                    v_pub := jsonb_set(
                        v_pub,
                        '{common:permanentDataSetURI}',
                        to_jsonb(
                            'https://lcdn.tiangong.earth/datasetdetail/process.xhtml?uuid='
                            || v_child_id::text
                            || '&version='
                            || v_allocated_version
                        ),
                        true
                    );
                    v_admin := jsonb_set(v_admin, '{publicationAndOwnership}', v_pub, true);
                    v_dataset := jsonb_set(v_dataset, '{administrativeInformation}', v_admin, true);
                    v_child_json_ordered := jsonb_set(
                        v_child_json_ordered,
                        '{processDataSet}',
                        v_dataset,
                        true
                    );
                end if;

                begin
                    insert into processes (
                        id,
                        json_ordered,
                        model_id,
                        model_version,
                        user_id,
                        rule_verification
                    )
                    values (
                        v_child_id,
                        v_child_json_ordered::json,
                        v_model_id,
                        v_model_version,
                        v_actor_user_id,
                        v_child_rule_verification
                    );
                exception
                    when unique_violation then
                        raise exception 'VERSION_CONFLICT';
                end;
            when 'update' then
                v_child_id := nullif(v_mutation->>'id', '')::uuid;
                v_child_version := nullif(btrim(coalesce(v_mutation->>'version', '')), '');
                v_child_json_ordered := v_mutation->'jsonOrdered';
                v_child_rule_verification := coalesce(
                    (v_mutation->>'ruleVerification')::boolean,
                    true
                );

                if v_child_id is null or v_child_version is null or v_child_json_ordered is null then
                    raise exception 'INVALID_PLAN';
                end if;

                update processes
                   set json_ordered = v_child_json_ordered::json,
                       model_id = v_model_id,
                       model_version = v_model_version,
                       rule_verification = v_child_rule_verification
                 where id = v_child_id
                   and version = v_child_version
                   and model_id = v_model_id
                   and coalesce(model_version, version) = v_model_version
                   and user_id = v_actor_user_id
                   and state_code = 0
                returning version::text into v_saved_child_version;

                if not found then
                    raise exception 'PROCESS_NOT_FOUND';
                end if;
                -- JSON synchronization may derive a different key from content.
                -- Reject that change within the same transaction.
                if v_saved_child_version is distinct from v_child_version then
                    raise exception 'INVALID_PLAN';
                end if;
            else
                raise exception 'INVALID_PLAN';
        end case;
    end loop;

    if v_mode = 'create' then
        begin
            insert into lifecyclemodels (
                id,
                json_ordered,
                json_tg,
                user_id,
                rule_verification
            )
            values (
                v_model_id,
                v_parent_json_ordered::json,
                v_parent_json_tg,
                v_actor_user_id,
                v_parent_rule_verification
            )
            returning *
                 into v_result_row;
        exception
            when unique_violation then
                raise exception 'VERSION_CONFLICT';
        end;
    else
        update lifecyclemodels
           set json_ordered = v_parent_json_ordered::json,
               json_tg = v_parent_json_tg,
               rule_verification = v_parent_rule_verification
         where id = v_model_id
           and version = v_expected_version
           and user_id = v_actor_user_id
           and state_code = 0
        returning *
             into v_result_row;

        if not found then
            raise exception 'MODEL_NOT_FOUND';
        end if;
        if v_result_row.version::text is distinct from v_expected_version then
            raise exception 'INVALID_PLAN';
        end if;
    end if;

    return jsonb_build_object(
        'model_id', v_result_row.id,
        'version', v_result_row.version,
        'lifecycle_model', to_jsonb(v_result_row)
    );
end;
$_$;

ALTER FUNCTION "private"."save_lifecycle_model_bundle"("p_plan" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."save_lifecycle_model_bundle"("p_plan" "jsonb") FROM PUBLIC;

GRANT ALL ON FUNCTION "private"."save_lifecycle_model_bundle"("p_plan" "jsonb") TO "service_role";

GRANT ALL ON FUNCTION "private"."save_lifecycle_model_bundle"("p_plan" "jsonb") TO "api_internal_executor";
