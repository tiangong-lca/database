CREATE OR REPLACE FUNCTION "private"."portal_index_prune_v1"("p_limit" integer) RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    SET "statement_timeout" TO '5s'
    AS $$
declare v_count integer;
begin
  if p_limit is null or p_limit not between 1 and 1000 then
    raise invalid_parameter_value using message = 'invalid Portal index prune';
  end if;
  with expired as (
    select event_id from private.portal_index_outbox
    where state in ('accepted', 'skipped') and settled_at < clock_timestamp() - interval '30 days'
      and provider <> 'baidu_withdrawal'
    order by settled_at, event_id limit p_limit for update skip locked
  )
  delete from private.portal_index_outbox as q
  using expired where q.event_id = expired.event_id;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

ALTER FUNCTION "private"."portal_index_prune_v1"("p_limit" integer) OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."portal_index_prune_v1"("p_limit" integer) FROM PUBLIC;
