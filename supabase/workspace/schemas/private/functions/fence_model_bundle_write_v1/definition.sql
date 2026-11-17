CREATE OR REPLACE FUNCTION "private"."fence_model_bundle_write_v1"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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

ALTER FUNCTION "private"."fence_model_bundle_write_v1"() OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."fence_model_bundle_write_v1"() FROM PUBLIC;
