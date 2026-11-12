CREATE OR REPLACE FUNCTION "private"."portal_index_was_latest_v1"("p_kind" "text", "p_id" "uuid", "p_version" "text", "p_allowed_brands" "text"[], "p_xid" "xid8") RETURNS boolean
    LANGUAGE "sql" STABLE
    SET "search_path" TO ''
    AS $$
  select not exists (
    -- A higher version already changed in the capture group can have been
    -- public before the group even if it is absent from the current projection.
    select 1 from private.portal_index_outbox as older
    where older.provider = 'indexnow' and older.source_transaction = p_xid
      and older.before_brand is not null
      and (older.dataset_kind, older.dataset_id) = (p_kind, p_id)
      and older.dataset_version > p_version
    union all
    select 1 from private.display_sitemap_rows_v1 as s
    join private.dataset_display_settings as d
      on (d.dataset_kind, d.dataset_id, d.dataset_version::text)
        = (s.dataset_kind, s.id, s.version)
    where (s.dataset_kind, s.id) = (p_kind, p_id) and s.version > p_version
      and s.contract_version = 1 and d.is_visible and d.brand = any(p_allowed_brands)
      and not exists (
        select 1 from private.portal_index_outbox as added
        where added.provider = 'indexnow' and added.source_transaction = p_xid
          and added.before_brand is null
          and (added.dataset_kind, added.dataset_id, added.dataset_version)
            = (s.dataset_kind, s.id, s.version)
      )
  );
$$;

ALTER FUNCTION "private"."portal_index_was_latest_v1"("p_kind" "text", "p_id" "uuid", "p_version" "text", "p_allowed_brands" "text"[], "p_xid" "xid8") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."portal_index_was_latest_v1"("p_kind" "text", "p_id" "uuid", "p_version" "text", "p_allowed_brands" "text"[], "p_xid" "xid8") FROM PUBLIC;
