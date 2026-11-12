CREATE OR REPLACE FUNCTION "private"."portal_display_index_same_timestamp_v1"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_config private.portal_index_config%rowtype := private.portal_index_capture_config_v1();
  v_brand text;
begin
  if not v_config.capture_enabled then return null; end if;
  select brand into v_brand from private.display_catalog_search_rows_v1
  where dataset_kind = tg_argv[0] and id = new.id and version = new.version::text
    and brand = any(v_config.allowed_brands);
  if v_brand is not null then
    perform private.portal_index_enqueue_v1(
      tg_argv[0], new.id, new.version::text, v_brand, v_brand,
      v_config.maintenance_transaction, v_config.allowed_brands
    );
  end if;
  return null;
end;
$$;

ALTER FUNCTION "private"."portal_display_index_same_timestamp_v1"() OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."portal_display_index_same_timestamp_v1"() FROM PUBLIC;
