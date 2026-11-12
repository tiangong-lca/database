CREATE OR REPLACE FUNCTION "private"."portal_index_work_v1"("p_event" "private"."portal_index_outbox") RETURNS "jsonb"
    LANGUAGE "sql" IMMUTABLE
    SET "search_path" TO ''
    AS $$
  select p_event.lease_candidates || jsonb_build_object(
    'eventId', p_event.event_id::text,
    'leaseToken', p_event.lease_token,
    'attempt', p_event.attempt,
    'accepted', coalesce((
      select jsonb_agg(key order by key)
      from private.portal_index_receipt_keys_v1(p_event.lease_candidates) as keys(key)
      where p_event.accepted_keys @> jsonb_build_array(key)
    ), '[]'::jsonb)
  );
$$;

ALTER FUNCTION "private"."portal_index_work_v1"("p_event" "private"."portal_index_outbox") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."portal_index_work_v1"("p_event" "private"."portal_index_outbox") FROM PUBLIC;
