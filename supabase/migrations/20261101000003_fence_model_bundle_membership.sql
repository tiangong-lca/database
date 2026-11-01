-- Database #880. Serialize membership additions against a whole-bundle delete.
-- Exact Model keys share one advisory-lock namespace. Unrelated versions remain
-- independent, and a truly absent parent retains the legacy linking contract.
begin;

create or replace function private.fence_process_model_membership_v1()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_model_version text;
begin
  v_model_version := coalesce(new.model_version, new.version::text);
  if tg_op = 'UPDATE'
     and new.model_id is not distinct from old.model_id
     and v_model_version is not distinct from coalesce(old.model_version, old.version::text) then
    return new;
  end if;

  -- A shared lock permits independent link writers for the same Model. Never
  -- wait here while holding an existing Process row that a delete may need.
  if not pg_catalog.pg_try_advisory_xact_lock_shared(
    pg_catalog.hashtextextended(new.model_id::text || ':' || btrim(v_model_version), 880)
  ) then
    raise exception using errcode = '55P03', message = 'MODEL_MEMBERSHIP_BUSY';
  end if;
  return new;
end;
$$;

alter function private.fence_process_model_membership_v1() owner to postgres;
revoke all on function private.fence_process_model_membership_v1()
  from public, anon, authenticated, service_role;

-- Run after processes_json_sync_trigger has derived the final Process version.
-- A BEFORE trigger also fences an insert before it can wait on a unique key
-- belonging to a Process being deleted by the other transaction.
create trigger zz_process_model_membership_fence
before insert or update on public.processes
for each row when (new.model_id is not null)
execute function private.fence_process_model_membership_v1();

CREATE OR REPLACE FUNCTION "private"."delete_lifecycle_model_bundle"("p_model_id" "uuid", "p_version" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'private', 'api', 'public', 'util', 'extensions', 'pg_temp'
    AS $_$
declare
    v_rows_affected integer;
    v_owner uuid;
    v_expected_children integer;
begin
    if p_model_id is null or nullif(btrim(coalesce(p_version, '')), '') is null then
        raise exception 'INVALID_PLAN';
    end if;

    select user_id into v_owner
      from public.lifecyclemodels
     where id = p_model_id
       and version = p_version
       and state_code = 0
     for update;

    if not found then
        raise exception 'MODEL_NOT_FOUND';
    end if;

    -- Advisory locks cannot refresh a Repeatable Read transaction snapshot.
    -- A whole-bundle destructive set requires the normal command isolation.
    if current_setting('transaction_isolation') not in ('read committed', 'read uncommitted') then
        raise exception using errcode = '0A000', message = 'UNSUPPORTED_TRANSACTION_ISOLATION';
    end if;

    -- Fail immediately if a linked Process is in flight, including one whose
    -- parent was absent when it was created. A subsequent attempt gets a fresh
    -- committed membership set without inverting parent/child row-lock order.
    if not pg_catalog.pg_try_advisory_xact_lock(
        pg_catalog.hashtextextended(p_model_id::text || ':' || btrim(p_version), 880)
    ) then
        raise exception using errcode = '55P03', message = 'MODEL_MEMBERSHIP_BUSY';
    end if;

    -- Materialize and lock relational membership once, including legacy fallback
    -- and cross-version children. The destructive set cannot gain later rows.
    -- A count mismatch rejects the complete command and rolls back any deletion.
    execute 'with members as materialized (
        select id, version, user_id, state_code
          from public.processes
         where model_id = $1 and coalesce(model_version, version) = $2
         order by id, version
         for update
    ), removed as (' || 'del' || 'ete from public.processes p using members m
        where p.id = m.id and p.version = m.version
          and p.model_id = $1 and coalesce(p.model_version, p.version) = $2
          and m.user_id = $3 and m.state_code = 0
          and p.user_id = $3 and p.state_code = 0
        returning 1
    ) select (select count(*) from removed), (select count(*) from members)'
       into v_rows_affected, v_expected_children
       using p_model_id, p_version, v_owner;
    if v_rows_affected <> v_expected_children then
        raise exception 'PROCESS_NOT_FOUND';
    end if;

    execute 'del' || 'ete from lifecyclemodels where id = $1 and version = $2
        and user_id = $3 and state_code = 0'
       using p_model_id, p_version, v_owner;

    get diagnostics v_rows_affected = row_count;
    if v_rows_affected = 0 then
        raise exception 'MODEL_NOT_FOUND';
    end if;

    return jsonb_build_object(
        'model_id', p_model_id,
        'version', p_version
    );
end;
$_$;

-- Replace the two parent predicates in the existing save routine: the initial
-- row lock and the final UPDATE. The child predicates use the child version.
do $migration$
declare
  definition text := pg_catalog.pg_get_functiondef('private.save_lifecycle_model_bundle(jsonb)'::regprocedure);
  owner_draft constant text := $old$           and version = v_expected_version
           and user_id = v_actor_user_id
           and state_code = 0$old$;
  permitted_draft constant text := $new$           and version = v_expected_version
           and state_code = 0
           and (user_id = v_actor_user_id or (
               v_process_mutations = '[]'::jsonb
               and api.svc_membership_is_review_admin(v_actor_user_id) @> '{"ok":true,"data":true}'::jsonb
           ))$new$;
begin
  if cardinality(string_to_array(definition, owner_draft)) <> 3 then
    raise exception 'Expected owner-draft guards on both the Model lock and update';
  end if;
  execute replace(definition, owner_draft, permitted_draft);
end;
$migration$;

commit;
