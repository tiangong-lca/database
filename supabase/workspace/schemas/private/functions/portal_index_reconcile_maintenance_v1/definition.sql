CREATE OR REPLACE FUNCTION "private"."portal_index_reconcile_maintenance_v1"("p_limit" integer) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    SET "lock_timeout" TO '5s'
    SET "statement_timeout" TO '10s'
    AS $$
declare
  v_config private.portal_index_config%rowtype;
  v_released integer;
  v_complete boolean;
begin
  if p_limit is null or p_limit not between 1 and 1000 then
    raise invalid_parameter_value using message = 'invalid Portal index maintenance batch';
  end if;
  lock table private.display_catalog_search_rows_v1 in share row exclusive mode;
  select * into strict v_config from private.portal_index_config for update;
  if private.portal_display_mode_v1() is distinct from 'display' then
    raise object_not_in_prerequisite_state using message = 'Portal display is unavailable';
  end if;
  if v_config.maintenance_resume_transaction = pg_current_xact_id() then
    raise object_not_in_prerequisite_state using message = 'commit Portal display restoration before reconciliation';
  end if;
  perform private.portal_display_assert_contract_v1();
  with held as (
    select event_id from private.portal_index_outbox
    where state = 'held' order by event_id limit p_limit
  )
  update private.portal_index_outbox as q set state = 'pending'
  from held where q.event_id = held.event_id;
  get diagnostics v_released = row_count;
  select not exists (select 1 from private.portal_index_outbox where state = 'held') into v_complete;
  if v_complete and v_config.maintenance_gap then
    update private.portal_index_config
    set maintenance_gap = false, maintenance_transaction = null, maintenance_resume_transaction = null
    where singleton;
  end if;
  return jsonb_build_object('released', v_released, 'complete', v_complete);
end;
$$;

ALTER FUNCTION "private"."portal_index_reconcile_maintenance_v1"("p_limit" integer) OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."portal_index_reconcile_maintenance_v1"("p_limit" integer) FROM PUBLIC;
