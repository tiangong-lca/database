CREATE OR REPLACE FUNCTION "util"."queue_dataset_extraction_jobs"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_entity_kind text;
  v_message jsonb;
begin
  if TG_TABLE_SCHEMA <> 'public' then
    raise exception 'dataset extraction jobs only support public schema, got %', TG_TABLE_SCHEMA;
  end if;

  v_entity_kind := case TG_TABLE_NAME
    when 'flows' then 'flow'
    when 'processes' then 'process'
    when 'lifecyclemodels' then 'lifecyclemodel'
    when 'contacts' then 'contact'
    when 'flowproperties' then 'flowproperty'
    when 'sources' then 'source'
    when 'unitgroups' then 'unitgroup'
    else null
  end;

  if v_entity_kind is null then
    raise exception 'unsupported dataset extraction table %', TG_TABLE_NAME;
  end if;

  -- The dataset row already serializes saves for this primary key. Lock the
  -- unread message until COMMIT so a claimant cannot read the previous body
  -- while this transaction is reusing that wake-up. A claim in progress gets
  -- its own successor with a different msg_id (and its own retry budget).
  if TG_TABLE_NAME in ('flows', 'processes', 'lifecyclemodels') then
    perform 1 from pgmq.q_dataset_extraction_jobs q
    where q.read_ct = 0
      and q.message->>'schema' = 'public'
      and q.message->>'extraction_kind' = 'extracted_md'
      and q.message->>'table' = TG_TABLE_NAME
      and q.message->>'entity_kind' = v_entity_kind
      and q.message->>'id' = NEW.id::text
      and q.message->>'version' = btrim(NEW.version::text)
    limit 1 for update skip locked;
    if found then
      return NEW;
    end if;
  end if;

  v_message := jsonb_build_object(
    'schema', TG_TABLE_SCHEMA,
    'table', TG_TABLE_NAME,
    'id', NEW.id,
    'version', btrim(NEW.version::text),
    'entity_kind', v_entity_kind,
    'extraction_kind', 'extracted_md',
    'created_at', clock_timestamp()
  );

  perform pgmq.send(
    queue_name => 'dataset_extraction_jobs',
    msg => v_message
  );

  return NEW;
end;
$$;

ALTER FUNCTION "util"."queue_dataset_extraction_jobs"() OWNER TO "postgres";

REVOKE ALL ON FUNCTION "util"."queue_dataset_extraction_jobs"() FROM PUBLIC;
