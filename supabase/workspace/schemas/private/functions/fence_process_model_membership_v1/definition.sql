CREATE OR REPLACE FUNCTION "private"."fence_process_model_membership_v1"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
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

ALTER FUNCTION "private"."fence_process_model_membership_v1"() OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."fence_process_model_membership_v1"() FROM PUBLIC;
