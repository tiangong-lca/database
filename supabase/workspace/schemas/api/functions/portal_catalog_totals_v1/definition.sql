CREATE OR REPLACE FUNCTION "api"."portal_catalog_totals_v1"("p_allowed_brands" "text"[]) RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    SET "row_security" TO 'on'
    SET "statement_timeout" TO '8s'
    SET "plan_cache_mode" TO 'force_custom_plan'
    AS $$
declare
  result jsonb;
  old_brands text:=current_setting('portal.display_brands',true);
  old_global text:=current_setting('portal.display_global',true);
  old_filter text:=current_setting('portal.display_filter_brand',true);
  diagnostic_message text;
  diagnostic_state text;
begin
  perform private.portal_display_begin_request_v1(p_allowed_brands,'{}');
  perform private.display_assert_navigation_contract_v1();
  -- Exact public versions under the existing deployment scope and forced RLS.
  -- No branch membership, vocabulary expansion, latest-version collapse or cache.
  select jsonb_build_object('schemaVersion','portal.public-catalog-totals.v1',
    'countBasis','public_versions','totals',jsonb_build_object(
      'process',count(*) filter(where dataset_kind='process'),
      'flow',count(*) filter(where dataset_kind='flow')))
    into result from private.display_navigation_versions_v1;
  perform set_config('portal.display_brands',coalesce(old_brands,''),true);
  perform set_config('portal.display_global',coalesce(old_global,''),true);
  perform set_config('portal.display_filter_brand',coalesce(old_filter,''),true);
  return result;
exception
  when sqlstate '22023' then
    raise exception using errcode='22023',message='invalid portal request';
  when query_canceled then
    get stacked diagnostics diagnostic_message=MESSAGE_TEXT;
    raise log using message='portal read failure diagnostic',detail=jsonb_build_object(
      'schemaVersion','portal.read-failure.v1','rpc','display_catalog_totals_v1',
      'category','cancellation','reason',case diagnostic_message
        when 'canceling statement due to statement timeout' then 'statement_timeout'
        when 'canceling statement due to user request' then 'cancel_request'
        else 'unknown' end)::text;
    raise exception using errcode='P0001',message='portal catalog unavailable';
  when others then
    get stacked diagnostics diagnostic_state=RETURNED_SQLSTATE;
    raise log using message='portal read failure diagnostic',detail=jsonb_build_object(
      'schemaVersion','portal.read-failure.v1','rpc','display_catalog_totals_v1',
      'category','internal','reason',case diagnostic_state when '55000' then 'contract_drift' else 'other' end)::text;
    raise exception using errcode='P0001',message='portal catalog unavailable';
end;
$$;

ALTER FUNCTION "api"."portal_catalog_totals_v1"("p_allowed_brands" "text"[]) OWNER TO "portal_display_executor";

REVOKE ALL ON FUNCTION "api"."portal_catalog_totals_v1"("p_allowed_brands" "text"[]) FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."portal_catalog_totals_v1"("p_allowed_brands" "text"[]) TO "anon";

GRANT ALL ON FUNCTION "api"."portal_catalog_totals_v1"("p_allowed_brands" "text"[]) TO "authenticated";
