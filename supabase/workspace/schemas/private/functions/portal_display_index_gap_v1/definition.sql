CREATE OR REPLACE FUNCTION "private"."portal_display_index_gap_v1"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare v_xid xid8;
begin
  if old.mode = new.mode then return new; end if;
  -- Serialize the mode switch with already-running and future display writes.
  lock table private.display_catalog_search_rows_v1 in share row exclusive mode;
  v_xid := pg_current_xact_id();
  if old.mode = 'display' and new.mode <> 'display' then
    update private.portal_index_config
    set maintenance_gap = true,
        maintenance_transaction = case when maintenance_resume_transaction = v_xid
          then maintenance_transaction else v_xid end,
        maintenance_resume_transaction = null
    where singleton and capture_enabled;
  elsif new.mode = 'display' then
    -- Writes in this transaction still precede externally visible recovery.
    update private.portal_index_config
    set maintenance_resume_transaction = v_xid
    where singleton and maintenance_transaction is not null;
  end if;
  return new;
end;
$$;

ALTER FUNCTION "private"."portal_display_index_gap_v1"() OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."portal_display_index_gap_v1"() FROM PUBLIC;
