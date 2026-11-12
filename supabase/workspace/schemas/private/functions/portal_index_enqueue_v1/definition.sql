CREATE OR REPLACE FUNCTION "private"."portal_index_enqueue_v1"("p_kind" "text", "p_id" "uuid", "p_version" "text", "p_before_brand" "text", "p_after_brand" "text", "p_maintenance_transaction" "xid8", "p_allowed_brands" "text"[]) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_xid xid8;
  v_held boolean := p_maintenance_transaction is not null;
  v_state text := case when v_held then 'held' else 'pending' end;
  v_removed_latest boolean;
begin
  if p_before_brand is null and p_after_brand is null then return; end if;
  v_xid := coalesce(p_maintenance_transaction, pg_current_xact_id());

  insert into private.portal_index_outbox as existing (
    provider, during_maintenance, source_transaction, dataset_kind, dataset_id, dataset_version,
    before_brand, after_brand, state
  )
  select provider, v_held, v_xid, p_kind, p_id, p_version, p_before_brand, p_after_brand, v_state
  from (values ('indexnow'), ('baidu')) as destinations(provider)
  on conflict (provider, source_transaction, dataset_kind, dataset_id, dataset_version)
  do update set after_brand = excluded.after_brand, removed_latest = false,
    during_maintenance = existing.during_maintenance or excluded.during_maintenance,
    state = case when excluded.during_maintenance then 'held' else existing.state end;

  if p_after_brand is null then
    -- This exact URL first appeared and then disappeared before commit or
    -- within one unavailable interval. It never became publicly visible.
    delete from private.portal_index_outbox
    where provider in ('indexnow', 'baidu') and source_transaction = v_xid
      and (dataset_kind, dataset_id, dataset_version) = (p_kind, p_id, p_version)
      and before_brand is null and after_brand is null;

    if exists (
      select 1 from private.portal_index_outbox
      where provider = 'indexnow' and source_transaction = v_xid
        and (dataset_kind, dataset_id, dataset_version) = (p_kind, p_id, p_version)
        and before_brand is not null
    ) then
      v_removed_latest := private.portal_index_was_latest_v1(
        p_kind, p_id, p_version, p_allowed_brands, v_xid
      );
      if v_removed_latest then
        update private.portal_index_outbox set removed_latest = true
        where provider in ('indexnow','baidu') and source_transaction = v_xid
          and (dataset_kind, dataset_id, dataset_version) = (p_kind, p_id, p_version);
      end if;
    end if;

    -- A separate lane can confirm dead links while ordinary Baidu is disabled
    -- or has no submission quota. Inherit the first brand from the same transaction.
    insert into private.portal_index_outbox as existing (
      provider, during_maintenance, source_transaction, dataset_kind, dataset_id, dataset_version,
      before_brand, after_brand, state
    )
    select 'baidu_withdrawal', v_held, v_xid, p_kind, p_id, p_version, before_brand, null, v_state
    from private.portal_index_outbox
    where provider = 'baidu' and source_transaction = v_xid
      and (dataset_kind, dataset_id, dataset_version) = (p_kind, p_id, p_version)
      and before_brand is not null
    on conflict (provider, source_transaction, dataset_kind, dataset_id, dataset_version)
    do update set during_maintenance = existing.during_maintenance or excluded.during_maintenance,
      state = case when excluded.during_maintenance then 'held' else existing.state end;
  else
    delete from private.portal_index_outbox
    where provider = 'baidu_withdrawal' and source_transaction = v_xid
      and (dataset_kind, dataset_id, dataset_version) = (p_kind, p_id, p_version);
  end if;
end;
$$;

ALTER FUNCTION "private"."portal_index_enqueue_v1"("p_kind" "text", "p_id" "uuid", "p_version" "text", "p_before_brand" "text", "p_after_brand" "text", "p_maintenance_transaction" "xid8", "p_allowed_brands" "text"[]) OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."portal_index_enqueue_v1"("p_kind" "text", "p_id" "uuid", "p_version" "text", "p_before_brand" "text", "p_after_brand" "text", "p_maintenance_transaction" "xid8", "p_allowed_brands" "text"[]) FROM PUBLIC;
