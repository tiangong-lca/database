CREATE OR REPLACE FUNCTION "private"."portal_index_requeue_v1"("p_provider" "text", "p_reason" "text", "p_limit" integer) RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    SET "statement_timeout" TO '5s'
    AS $$
declare v_count integer;
begin
  if p_provider is null or p_provider not in ('indexnow', 'baidu')
    or p_reason is null or p_limit is null or p_limit not between 1 and 500 then
    raise invalid_parameter_value using message = 'invalid Portal index requeue';
  end if;
  with blocked as (
    select event_id from private.portal_index_outbox
    where provider = p_provider and state = 'blocked' and last_reason = p_reason
    order by event_id limit p_limit for update skip locked
  )
  update private.portal_index_outbox as q
  set state = 'pending', available_at = clock_timestamp(), last_settlement_token = null
  from blocked where q.event_id = blocked.event_id;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

ALTER FUNCTION "private"."portal_index_requeue_v1"("p_provider" "text", "p_reason" "text", "p_limit" integer) OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."portal_index_requeue_v1"("p_provider" "text", "p_reason" "text", "p_limit" integer) FROM PUBLIC;
