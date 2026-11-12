CREATE OR REPLACE FUNCTION "api"."svc_portal_index_withdrawal_feed_v1"("p_origin" "text", "p_allowed_brands" "text"[]) RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    SET "statement_timeout" TO '10s'
    AS $$
declare
  v_config private.portal_index_config%rowtype;
  v_brands text[];
  v_result jsonb;
  v_exact_count bigint;
begin
  if not util.is_service_request() then
    raise insufficient_privilege using message = 'service role required';
  end if;
  v_brands := private.portal_normalize_brand_scope_v1(p_allowed_brands);
  select * into strict v_config from private.portal_index_config;
  if v_config.origin is null
    or (p_origin, v_brands) is distinct from (v_config.origin, v_config.allowed_brands) then
    raise invalid_parameter_value using message = 'Portal index destination mismatch';
  end if;
  if private.portal_display_mode_v1() is distinct from 'display' then
    raise object_not_in_prerequisite_state using message = 'Portal display is unavailable';
  end if;
  if v_config.maintenance_gap then
    raise object_not_in_prerequisite_state using message = 'Portal index maintenance requires reconciliation';
  end if;
  perform private.portal_display_assert_contract_v1();

  with latest as (
    select distinct on (q.dataset_kind, q.dataset_id, q.dataset_version)
      q.dataset_kind, q.dataset_id, q.dataset_version, q.accepted_keys
    from private.portal_index_outbox as q
    where q.provider = 'baidu_withdrawal'
      and not exists (
        select 1
        from private.display_sitemap_rows_v1 as s
        join private.dataset_display_settings as d
          on (d.dataset_kind, d.dataset_id, d.dataset_version::text)
            = (s.dataset_kind, s.id, s.version)
        where (s.dataset_kind, s.id, s.version) = (q.dataset_kind, q.dataset_id, q.dataset_version)
          and s.contract_version = 1 and d.is_visible and d.brand = any(v_brands)
      )
    order by q.dataset_kind, q.dataset_id, q.dataset_version, q.event_id desc
  ), proved as materialized (
    select * from latest where accepted_keys <> '[]'::jsonb limit 12501
  )
  select (select count(*) from proved), coalesce(jsonb_agg(
    proof.key - 'operation' order by dataset_kind, dataset_id, dataset_version, proof.key->>'locale'
  ), '[]'::jsonb)
  into v_exact_count, v_result
  from proved cross join lateral jsonb_array_elements(accepted_keys) as proof(key);

  if v_exact_count > 12500 or jsonb_array_length(v_result) > 50000
    or octet_length(v_result::text) >= 10000000 then
    raise program_limit_exceeded using message = 'Portal withdrawal export exceeds its bound';
  end if;
  return v_result;
end;
$$;

ALTER FUNCTION "api"."svc_portal_index_withdrawal_feed_v1"("p_origin" "text", "p_allowed_brands" "text"[]) OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."svc_portal_index_withdrawal_feed_v1"("p_origin" "text", "p_allowed_brands" "text"[]) FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."svc_portal_index_withdrawal_feed_v1"("p_origin" "text", "p_allowed_brands" "text"[]) TO "service_role";
