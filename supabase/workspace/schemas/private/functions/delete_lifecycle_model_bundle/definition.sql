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

ALTER FUNCTION "private"."delete_lifecycle_model_bundle"("p_model_id" "uuid", "p_version" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."delete_lifecycle_model_bundle"("p_model_id" "uuid", "p_version" "text") FROM PUBLIC;

GRANT ALL ON FUNCTION "private"."delete_lifecycle_model_bundle"("p_model_id" "uuid", "p_version" "text") TO "service_role";

GRANT ALL ON FUNCTION "private"."delete_lifecycle_model_bundle"("p_model_id" "uuid", "p_version" "text") TO "api_internal_executor";
