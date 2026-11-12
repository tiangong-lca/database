CREATE OR REPLACE FUNCTION "private"."portal_index_set_scheduler_v1"("p_enabled" boolean) RETURNS bigint
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    SET "lock_timeout" TO '5s'
    AS $$
declare
  v_config private.portal_index_config%rowtype;
  v_job record;
  v_job_name constant text := 'dispatch-portal-index-notifications-v1';
  v_schedule constant text := '* * * * *';
  v_command constant text := 'select private.portal_index_wake_v1();';
begin
  if p_enabled is null then
    raise invalid_parameter_value using message = 'invalid Portal index scheduler state';
  end if;
  select * into strict v_config from private.portal_index_config for update;
  select jobid, schedule, command, database, username, active into v_job
  from cron.job where jobname = v_job_name;
  if found and (v_job.schedule, v_job.command, v_job.database, v_job.username)
    is distinct from (v_schedule, v_command, current_database(), current_user::text) then
    raise object_not_in_prerequisite_state using message = 'Portal index scheduler job does not match';
  end if;
  if not p_enabled then
    if v_job.jobid is not null then perform cron.unschedule(v_job.jobid); end if;
    return v_job.jobid;
  end if;
  if not v_config.dispatch_enabled or v_config.maintenance_gap
    or private.portal_display_mode_v1() is distinct from 'display' then
    raise object_not_in_prerequisite_state using message = 'Portal index dispatch is disabled';
  end if;
  perform private.portal_display_assert_contract_v1();
  perform private.portal_index_scheduler_transport_v1();
  if v_job.jobid is null then
    return cron.schedule(v_job_name, v_schedule, v_command);
  end if;
  if not v_job.active then
    perform cron.alter_job(v_job.jobid, active => true);
  end if;
  return v_job.jobid;
end;
$$;

ALTER FUNCTION "private"."portal_index_set_scheduler_v1"("p_enabled" boolean) OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."portal_index_set_scheduler_v1"("p_enabled" boolean) FROM PUBLIC;
