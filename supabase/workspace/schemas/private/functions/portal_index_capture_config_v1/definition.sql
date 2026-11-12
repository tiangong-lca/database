CREATE OR REPLACE FUNCTION "private"."portal_index_capture_config_v1"() RETURNS "private"."portal_index_config"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
declare v_config private.portal_index_config%rowtype;
begin
  if current_setting('transaction_isolation') in ('repeatable read', 'serializable') then
    -- Reject a stale snapshot that crossed a configuration or rollout fence.
    select * into strict v_config from private.portal_index_config for share;
  else
    select * into strict v_config from private.portal_index_config;
  end if;
  if v_config.maintenance_resume_transaction is not null
    and v_config.maintenance_resume_transaction <> pg_current_xact_id() then
    v_config.maintenance_transaction := null;
  end if;
  return v_config;
end;
$$;

ALTER FUNCTION "private"."portal_index_capture_config_v1"() OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."portal_index_capture_config_v1"() FROM PUBLIC;
