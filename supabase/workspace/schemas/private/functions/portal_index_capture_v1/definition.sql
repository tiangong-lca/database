CREATE OR REPLACE FUNCTION "private"."portal_index_capture_v1"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_config private.portal_index_config%rowtype;
  v_brands text[];
  v_before_brand text;
  v_after_brand text;
  v_identity_changed boolean := false;
begin
  if tg_op = 'UPDATE' and
    (old.dataset_kind, old.id, old.version, old.brand, old.state_code, old.modified_at, old.card, old.document)
    is not distinct from
    (new.dataset_kind, new.id, new.version, new.brand, new.state_code, new.modified_at, new.card, new.document) then
    return null;
  end if;
  v_config := private.portal_index_capture_config_v1();
  if not v_config.capture_enabled then return null; end if;
  v_brands := v_config.allowed_brands;

  if tg_op <> 'INSERT' and old.brand = any(v_brands) then
    v_before_brand := old.brand;
  end if;
  if tg_op <> 'DELETE' and new.brand = any(v_brands) then
    v_after_brand := new.brand;
  end if;
  if tg_op = 'UPDATE' then
    v_identity_changed := (old.dataset_kind, old.id, old.version)
      is distinct from (new.dataset_kind, new.id, new.version);
  end if;
  if tg_op = 'DELETE' or v_identity_changed then
    perform private.portal_index_enqueue_v1(
      old.dataset_kind, old.id, old.version, v_before_brand, null,
      v_config.maintenance_transaction, v_brands
    );
    v_before_brand := null;
  end if;
  if tg_op <> 'DELETE' then
    perform private.portal_index_enqueue_v1(
      new.dataset_kind, new.id, new.version, v_before_brand, v_after_brand,
      v_config.maintenance_transaction, v_brands
    );
  end if;
  return null;
end;
$$;

ALTER FUNCTION "private"."portal_index_capture_v1"() OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."portal_index_capture_v1"() FROM PUBLIC;
