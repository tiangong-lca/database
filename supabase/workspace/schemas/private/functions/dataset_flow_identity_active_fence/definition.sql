CREATE OR REPLACE FUNCTION "private"."dataset_flow_identity_active_fence"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_old_id uuid;
  v_new_id uuid;
  v_old_version text;
  v_new_version text;
  v_old_user_id uuid;
  v_new_user_id uuid;
  v_old_state_code integer;
  v_new_state_code integer;
  v_actor uuid;
  v_permit_scope uuid;
  v_is_exact_process boolean := false;
  v_is_guarded boolean := false;
begin
  if tg_op <> 'INSERT' then
    v_old_id := old.id;
    v_old_version := btrim(old.version::text);
    v_old_user_id := old.user_id;
    v_old_state_code := old.state_code;
  end if;
  if tg_op <> 'DELETE' then
    v_new_id := new.id;
    v_new_version := btrim(new.version::text);
    v_new_user_id := new.user_id;
    v_new_state_code := new.state_code;
  end if;

  if tg_table_name = 'processes' then
    -- Derivative workers may continue while a scope is active, but only when
    -- the protected columns are stable. Identical JSON text needs no parse;
    -- different spellings still use the original JSONB equality semantics.
    if tg_op = 'UPDATE'
      and new.id is not distinct from old.id
      and new.version is not distinct from old.version
      and new.user_id is not distinct from old.user_id
      and new.state_code is not distinct from old.state_code
      and new.model_id is not distinct from old.model_id
      and new.rule_verification is not distinct from old.rule_verification
      and new.json is not distinct from old.json
      and (case
        when new.json_ordered::text collate "C" is not distinct from old.json_ordered::text
          then true
        else new.json_ordered::jsonb is not distinct from old.json_ordered::jsonb
      end) then
      return new;
    end if;

    -- Serialize both ownership domains.  This closes UPDATEs that move a row
    -- from a foreign owner into the actor (or away from the actor).
    for v_actor in
      select distinct actor_id
      from (values (v_old_user_id), (v_new_user_id)) as actors(actor_id)
      where actor_id is not null
      order by actor_id
    loop
      if not pg_try_advisory_xact_lock(hashtextextended(
        'dataset-flow-identity-actor:' || v_actor::text, 0
      )) then
        raise exception using errcode = '55P03',
          message = 'FLOW_IDENTITY_ACTIVE_SCOPE_ACTOR_FENCE_BUSY';
      end if;
    end loop;
    -- The only primary mutation permit is a private, transaction-scoped row
    -- minted by the rewrite core and consumed exactly once here.  Caller-set
    -- custom GUCs have no authority.
    if tg_op = 'UPDATE'
      and new.id is not distinct from old.id
      and new.version is not distinct from old.version
      and new.user_id is not distinct from old.user_id
      and new.state_code is not distinct from old.state_code
      and new.model_id is not distinct from old.model_id
      and new.rule_verification is not distinct from old.rule_verification
      and new.json::jsonb is not distinct from old.json::jsonb then
      with consumed as (
        delete from util.dataset_flow_identity_mutation_permits as permit
        using util.dataset_flow_identity_process_ledger as ledger,
          util.dataset_flow_identity_scopes as scope
        where permit.transaction_id = txid_current()
          and permit.process_id = old.id
          and permit.process_version = btrim(old.version::text)
          and permit.before_payload_sha256
            = util.dataset_flow_identity_sha256(old.json_ordered::jsonb)
          and permit.after_payload_sha256
            = util.dataset_flow_identity_sha256(new.json_ordered::jsonb)
          and ledger.scope_id = permit.scope_id
          and ledger.ordinal = permit.ordinal
          and ledger.process_id = permit.process_id
          and ledger.process_version = permit.process_version
          and ledger.mutation_nonce = permit.mutation_nonce
          and ledger.status = 'pending' and ledger.active
          and scope.id = ledger.scope_id
          and scope.actor_user_id = old.user_id
          and scope.status in (
            'sealed', 'running', 'primary_complete', 'derivatives_pending'
          )
        returning permit.scope_id
      )
      select consumed.scope_id into v_permit_scope from consumed;
      if v_permit_scope is not null then
        return new;
      end if;
    end if;

    -- An exact captured process stays fenced after its source references have
    -- been removed.  Source-reference inspection alone is not sufficient.
    select exists (
      select 1
      from util.dataset_flow_identity_scopes as scope
      join util.dataset_flow_identity_process_ledger as ledger
        on ledger.scope_id = scope.id and ledger.active
      where scope.status in (
          'sealed', 'running', 'primary_complete', 'derivatives_pending'
        )
        and (
          (scope.actor_user_id = v_old_user_id
            and ledger.process_id = v_old_id
            and ledger.process_version = v_old_version)
          or (scope.actor_user_id = v_new_user_id
            and ledger.process_id = v_new_id
            and ledger.process_version = v_new_version)
        )
    ) into v_is_exact_process;
    if v_is_exact_process then
      raise exception using errcode = '55000',
        message = 'FLOW_IDENTITY_ACTIVE_SCOPE_PROCESS_FENCE';
    end if;

    select exists (
      select 1
      from util.dataset_flow_identity_scopes as scope
      join util.dataset_flow_identity_capture_source_guards as guard
        on guard.receipt_id = scope.receipt_id
      cross join lateral jsonb_array_elements(
        case when scope.actor_user_id = v_old_user_id
          then coalesce(private.dataset_flow_identity_exchanges(old.json_ordered::jsonb), '[]'::jsonb)
          else '[]'::jsonb end
        || case when scope.actor_user_id = v_new_user_id
          then coalesce(private.dataset_flow_identity_exchanges(new.json_ordered::jsonb), '[]'::jsonb)
          else '[]'::jsonb end
      ) as exchange(value)
      where scope.status in (
          'sealed', 'running', 'primary_complete', 'derivatives_pending'
        )
        and exchange.value #>> '{referenceToFlowDataSet,@refObjectId}'
          = guard.source_id::text
        and exchange.value #>> '{referenceToFlowDataSet,@version}'
          = guard.source_version
    ) into v_is_guarded;
    if v_is_guarded then
      raise exception using errcode = '55000',
        message = 'FLOW_IDENTITY_ACTIVE_SCOPE_PROCESS_FENCE';
    end if;
    return case when tg_op = 'DELETE' then old else new end;
  end if;

  if tg_table_name = 'flows' then
    if tg_op = 'UPDATE' then
      declare
        old_primary public.flows := old;
        new_primary public.flows := new;
      begin
        -- Mask only the four worker outputs. Future columns participate too.
        -- Compare storage images first: json has no native equality operator.
        old_primary.extracted_md := null;
        old_primary.search_text := null;
        old_primary.embedding_ft := null;
        old_primary.embedding_ft_at := null;
        new_primary.extracted_md := null;
        new_primary.search_text := null;
        new_primary.embedding_ft := null;
        new_primary.embedding_ft_at := null;
        if old_primary operator(pg_catalog.*=) new_primary then
          return new;
        end if;
        -- Different encodings can have the same JSON meaning (e.g. whitespace,
        -- numeric scale, or a SQL NULL versus JSON null inside a record).
        if to_jsonb(old_primary) = to_jsonb(new_primary) then
          return new;
        end if;
      end;
    end if;

    -- Acquire every OLD/NEW and guarded-scope actor in one globally sorted
    -- pass.  Splitting those sets into two loops permits A->Z and Z->A lock
    -- inversion for cross-owner public-target updates.
    for v_actor in
      select distinct actor_id
      from (
        values (v_old_user_id), (v_new_user_id)
        union all
        select scope.actor_user_id
        from util.dataset_flow_identity_scopes as scope
        where scope.status in (
            'sealed', 'running', 'primary_complete', 'derivatives_pending'
          )
          and (
            scope.actor_user_id in (v_old_user_id, v_new_user_id)
            or exists (
              select 1
              from util.dataset_flow_identity_capture_source_guards as guard
              where guard.receipt_id = scope.receipt_id
                and ((guard.source_id = v_old_id
                    and guard.source_version = v_old_version)
                  or (guard.source_id = v_new_id
                    and guard.source_version = v_new_version))
            )
            or exists (
              select 1
              from util.dataset_flow_identity_capture_target_guards as guard
              where guard.receipt_id = scope.receipt_id
                and ((guard.target_id = v_old_id
                    and guard.target_version = v_old_version)
                  or (guard.target_id = v_new_id
                    and guard.target_version = v_new_version))
            )
          )
      ) as actors(actor_id)
      where actor_id is not null
      order by actor_id
    loop
      if not pg_try_advisory_xact_lock(hashtextextended(
        'dataset-flow-identity-actor:' || v_actor::text, 0
      )) then
        raise exception using errcode = '55P03',
          message = 'FLOW_IDENTITY_ACTIVE_SCOPE_ACTOR_FENCE_BUSY';
      end if;
    end loop;
    select exists (
      select 1
      from util.dataset_flow_identity_scopes as scope
      where scope.status in (
          'sealed', 'running', 'primary_complete', 'derivatives_pending'
        )
        and (
          (scope.actor_user_id = v_old_user_id
            and v_old_state_code = 0
            and old.json_ordered::jsonb #>>
              '{flowDataSet,modellingAndValidation,LCIMethod,typeOfDataSet}'
              = 'Elementary flow')
          or (scope.actor_user_id = v_new_user_id
            and v_new_state_code = 0
            and new.json_ordered::jsonb #>>
              '{flowDataSet,modellingAndValidation,LCIMethod,typeOfDataSet}'
              = 'Elementary flow')
          or exists (
            select 1
            from util.dataset_flow_identity_capture_source_guards as guard
            where guard.receipt_id = scope.receipt_id
              and ((guard.source_id = v_old_id
                  and guard.source_version = v_old_version)
                or (guard.source_id = v_new_id
                  and guard.source_version = v_new_version))
          )
          or exists (
            select 1
            from util.dataset_flow_identity_capture_target_guards as guard
            where guard.receipt_id = scope.receipt_id
              and ((guard.target_id = v_old_id
                  and guard.target_version = v_old_version)
                or (guard.target_id = v_new_id
                  and guard.target_version = v_new_version))
          )
        )
    ) into v_is_guarded;
    if v_is_guarded then
      raise exception using errcode = '55000',
        message = 'FLOW_IDENTITY_ACTIVE_SCOPE_FLOW_FENCE';
    end if;
    return case when tg_op = 'DELETE' then old else new end;
  end if;

  if tg_table_name in ('flowproperties', 'unitgroups') then
    for v_actor in
      select distinct scope.actor_user_id
      from util.dataset_flow_identity_scopes as scope
      join util.dataset_flow_identity_capture_support_guards as guard
        on guard.receipt_id = scope.receipt_id
        and guard.support_table = tg_table_name
        and ((guard.support_id = v_old_id
            and guard.support_version = v_old_version)
          or (guard.support_id = v_new_id
            and guard.support_version = v_new_version))
      where scope.status in (
        'sealed', 'running', 'primary_complete', 'derivatives_pending'
      )
      order by scope.actor_user_id
    loop
      if not pg_try_advisory_xact_lock(hashtextextended(
        'dataset-flow-identity-actor:' || v_actor::text, 0
      )) then
        raise exception using errcode = '55P03',
          message = 'FLOW_IDENTITY_ACTIVE_SCOPE_ACTOR_FENCE_BUSY';
      end if;
    end loop;
    select exists (
      select 1
      from util.dataset_flow_identity_scopes as scope
      join util.dataset_flow_identity_capture_support_guards as guard
        on guard.receipt_id = scope.receipt_id
        and guard.support_table = tg_table_name
        and ((guard.support_id = v_old_id
            and guard.support_version = v_old_version)
          or (guard.support_id = v_new_id
            and guard.support_version = v_new_version))
      where scope.status in (
        'sealed', 'running', 'primary_complete', 'derivatives_pending'
      )
    ) into v_is_guarded;
    if v_is_guarded then
      raise exception using errcode = '55000',
        message = 'FLOW_IDENTITY_ACTIVE_SCOPE_SUPPORT_FENCE';
    end if;
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

ALTER FUNCTION "private"."dataset_flow_identity_active_fence"() OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."dataset_flow_identity_active_fence"() FROM PUBLIC;

GRANT ALL ON FUNCTION "private"."dataset_flow_identity_active_fence"() TO "api_internal_executor";
