-- Database #935 / Portal #184: calculate only the counts the consumer uses.
-- Additive APIs preserve legacy DTOs/cursors and exact forced-RLS visibility.
-- No table, index, writer, timeout increase or persistent cache.
begin;
select private.portal_display_assert_contract_v1();
grant create on schema private,api to portal_display_executor;
CREATE OR REPLACE FUNCTION "private"."display_navigation_impl_v1"("p_kind" "text", "p_query" "text", "p_filters" "jsonb", "p_dimension" "text", "p_parent_node_id" "text", "p_cursor_node_id" "text", "p_limit" integer, "p_fingerprint" "text", "p_include_totals" boolean) RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER PARALLEL RESTRICTED
    SET "search_path" TO ''
    SET "row_security" TO 'on'
    SET "plan_cache_mode" TO 'force_custom_plan'
    SET "statement_timeout" TO '8s'
    SET "work_mem" TO '32MB'
    AS $$
declare
  v_parent jsonb;
  v_ancestors jsonb:='[]';
  v_nodes jsonb;
  v_totals jsonb;
  v_next text;
  v_result jsonb;
  v_after_code text;
  v_trimmed boolean:=false;
begin
  perform private.display_assert_navigation_contract_v1();
  if p_parent_node_id is not null and not exists (
    select 1 from private.display_read_navigation_node_v1 n
    where n.node_id=p_parent_node_id and n.dimension=p_dimension
      and (n.source_file is not null or n.node_id in ('class:isic','class:cpc','class:elementary','geo:unmapped')
        or exists(select 1 from private.display_navigation_membership_v1 m where m.node_id=n.node_id))
  ) then raise exception using errcode='22023',message='invalid portal request'; end if;
  if p_cursor_node_id is not null then
    select n.code into v_after_code from private.display_read_navigation_node_v1 n
    where n.node_id=p_cursor_node_id and n.dimension=p_dimension
      and n.parent_node_id is not distinct from p_parent_node_id;
    if not found then raise exception using errcode='22023',message='invalid portal request'; end if;
  end if;

  with matched as materialized (
    select * from private.display_navigation_matched_versions_v1(case when p_include_totals then 'all' else p_kind end,p_query,p_filters)
  ), matched_count as materialized (select count(*) as n from matched
  ), children as materialized (
    select n.* from private.display_read_navigation_node_v1 n
    where n.dimension=p_dimension and n.parent_node_id is not distinct from p_parent_node_id
      and (n.source_file is not null or n.node_id in ('class:isic','class:cpc','class:elementary','geo:unmapped') or exists (
        select 1 from private.display_navigation_membership_v1 m
        where m.node_id=n.node_id and (p_kind='all' or m.dataset_kind=p_kind)
          and ((p_query='' and p_filters='{}'::jsonb)
            or (m.dataset_kind,m.id,m.version) in (select dataset_kind,id,version from matched))))
      and (p_dimension<>'classification' or p_kind='all' or n.taxonomy not in ('isic','cpc','elementary')
        or (p_kind='process' and n.taxonomy='isic') or (p_kind='flow' and n.taxonomy in ('cpc','elementary')))
      and (p_cursor_node_id is null or (n.code collate "C",n.node_id collate "C")>(v_after_code collate "C",p_cursor_node_id collate "C"))
    order by n.code collate "C",n.node_id collate "C" limit p_limit+1
  ), targets as materialized (
    select * from children
    union all
    select n.* from private.display_read_navigation_node_v1 n where n.node_id=p_parent_node_id
  ), counted_memberships as not materialized (
    -- Reuse complete matched keys once. Small sets use the existing exact
    -- membership key; broad and empty reads retain the branch semijoin.
    -- 2048 chooses the measured read shape, never a candidate/count limit.
    select m.node_id,m.direct
    from matched k join private.display_navigation_membership_v1 m
      on (m.dataset_kind,m.id,m.version)=(k.dataset_kind,k.id,k.version)
      and m.dimension=p_dimension
    where not (p_query='' and p_filters='{}'::jsonb)
      and (select n from matched_count)<=2048
      and (p_kind='all' or m.dataset_kind=p_kind)
      and m.node_id=any(array(select n.node_id from targets n))
    union all
    select m.node_id,m.direct
    from private.display_navigation_membership_v1 m
    where ((p_query='' and p_filters='{}'::jsonb) or (select n from matched_count)>2048)
      and m.dimension=p_dimension and (p_kind='all' or m.dataset_kind=p_kind)
      and ((p_query='' and p_filters='{}'::jsonb)
        or (m.dataset_kind,m.id,m.version) in (select dataset_kind,id,version from matched))
      and m.node_id=any(array(select n.node_id from targets n))
  ), counted as materialized (
    select node_id,count(*) as count,count(*) filter(where direct) as direct_count
    from counted_memberships group by node_id
  ), decorated as materialized (
    select n.node_id,n.code,jsonb_build_object(
      'nodeId',n.node_id,'parentNodeId',n.parent_node_id,'code',n.code,'taxonomy',n.taxonomy,
      'count',coalesce(c.count,0),'directCount',coalesce(c.direct_count,0),
      'hasChildren',exists(select 1 from private.display_read_navigation_node_v1 child where child.parent_node_id=n.node_id
        and (child.source_file is not null or exists(select 1 from private.display_navigation_membership_v1 m where m.node_id=child.node_id)))
    ) as value from targets n left join counted c on c.node_id=n.node_id
  ), paged as (
    select d.*,row_number() over(order by d.code collate "C",d.node_id collate "C") as rn
    from decorated d where d.node_id is distinct from p_parent_node_id
  ) select
    coalesce((select jsonb_agg(value order by rn) from paged where rn<=p_limit),'[]'::jsonb),
    (select case when count(*)>p_limit then (array_agg(node_id order by rn))[p_limit] else null end from paged),
    (select value from decorated where node_id=p_parent_node_id),
    (case when not p_include_totals then null when p_query='' and p_filters='{}'::jsonb then
      (select jsonb_build_object('process',count(*) filter(where dataset_kind='process'),'flow',count(*) filter(where dataset_kind='flow'))
       from private.display_navigation_versions_v1)
     else (select jsonb_build_object('process',count(*) filter(where dataset_kind='process'),'flow',count(*) filter(where dataset_kind='flow')) from matched) end)
  into v_nodes,v_next,v_parent,v_totals;

  with recursive ancestors as (
    select n.node_id,n.parent_node_id,n.code,n.taxonomy,1 as depth
    from private.display_read_navigation_node_v1 n
    where n.node_id=(select p.parent_node_id from private.display_read_navigation_node_v1 p where p.node_id=p_parent_node_id)
    union all
    select n.node_id,n.parent_node_id,n.code,n.taxonomy,a.depth+1
    from ancestors a join private.display_read_navigation_node_v1 n on n.node_id=a.parent_node_id
    where a.depth<32
  ) select coalesce(jsonb_agg(jsonb_build_object('nodeId',node_id,'parentNodeId',parent_node_id,'code',code,'taxonomy',taxonomy) order by depth desc),'[]'::jsonb)
    into v_ancestors from ancestors;

  loop
    v_result:=jsonb_build_object('schemaVersion','portal.public-navigation.v1','countBasis','public_versions',
      'dimension',p_dimension,'kind',p_kind,'totals',v_totals,'parent',v_parent,'ancestors',v_ancestors,'nodes',v_nodes,
      'nextCursor',case when v_next is null then null else private.display_cursor_encode_v1(jsonb_build_object(
        'v',1,'fp',p_fingerprint,'dimension',p_dimension,'kind',p_kind,'parent',p_parent_node_id,'node',v_next)) end);
    if not p_include_totals then v_result:=v_result-'totals'; end if;
    exit when octet_length(v_result::text)<=65536;
    if jsonb_array_length(v_nodes)<=1 then
      raise exception using errcode='54000',message='Portal navigation response exceeds its byte budget';
    end if;
    v_nodes:=v_nodes-(jsonb_array_length(v_nodes)-1);
    v_next:=v_nodes->(jsonb_array_length(v_nodes)-1)->>'nodeId';
  end loop;
  return v_result;
end;
$$;

ALTER FUNCTION "private"."display_navigation_impl_v1"("p_kind" "text", "p_query" "text", "p_filters" "jsonb", "p_dimension" "text", "p_parent_node_id" "text", "p_cursor_node_id" "text", "p_limit" integer, "p_fingerprint" "text", "p_include_totals" boolean) OWNER TO "portal_display_executor";

REVOKE ALL ON FUNCTION "private"."display_navigation_impl_v1"("p_kind" "text", "p_query" "text", "p_filters" "jsonb", "p_dimension" "text", "p_parent_node_id" "text", "p_cursor_node_id" "text", "p_limit" integer, "p_fingerprint" "text", "p_include_totals" boolean) FROM PUBLIC;

GRANT ALL ON FUNCTION "private"."display_navigation_impl_v1"("p_kind" "text", "p_query" "text", "p_filters" "jsonb", "p_dimension" "text", "p_parent_node_id" "text", "p_cursor_node_id" "text", "p_limit" integer, "p_fingerprint" "text", "p_include_totals" boolean) TO "postgres";

CREATE OR REPLACE FUNCTION "private"."display_navigation_impl_v1"("p_kind" "text", "p_query" "text", "p_filters" "jsonb", "p_dimension" "text", "p_parent_node_id" "text", "p_cursor_node_id" "text", "p_limit" integer, "p_fingerprint" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER PARALLEL RESTRICTED
    SET "search_path" TO ''
    SET "row_security" TO 'on'
    SET "plan_cache_mode" TO 'force_custom_plan'
    SET "statement_timeout" TO '8s'
    SET "work_mem" TO '32MB'
    AS $$
begin
  return private.display_navigation_impl_v1(p_kind,p_query,p_filters,p_dimension,p_parent_node_id,p_cursor_node_id,p_limit,p_fingerprint,true);
end;
$$;

ALTER FUNCTION "private"."display_navigation_impl_v1"("p_kind" "text", "p_query" "text", "p_filters" "jsonb", "p_dimension" "text", "p_parent_node_id" "text", "p_cursor_node_id" "text", "p_limit" integer, "p_fingerprint" "text") OWNER TO "portal_display_executor";

REVOKE ALL ON FUNCTION "private"."display_navigation_impl_v1"("p_kind" "text", "p_query" "text", "p_filters" "jsonb", "p_dimension" "text", "p_parent_node_id" "text", "p_cursor_node_id" "text", "p_limit" integer, "p_fingerprint" "text") FROM PUBLIC;

GRANT ALL ON FUNCTION "private"."display_navigation_impl_v1"("p_kind" "text", "p_query" "text", "p_filters" "jsonb", "p_dimension" "text", "p_parent_node_id" "text", "p_cursor_node_id" "text", "p_limit" integer, "p_fingerprint" "text") TO "postgres";

CREATE OR REPLACE FUNCTION "private"."display_navigation_v1"("p_kind" "text", "p_query" "text", "p_filters" "jsonb", "p_dimension" "text", "p_parent_node_id" "text", "p_cursor" "text", "p_limit" integer, "p_include_totals" boolean) RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE PARALLEL RESTRICTED
    SET "search_path" TO ''
    AS $_$
declare
  v_query text:=lower(btrim(coalesce(p_query,'')));
  v_filters jsonb;
  v_limit integer:=coalesce(p_limit,100);
  v_fingerprint text;
  v_cursor jsonb;
  v_cursor_node text;
begin
  if p_dimension is null or p_dimension not in ('classification','geography')
    or v_limit<1 or v_limit>500 then
    raise exception using errcode='22023',message='invalid portal request';
  end if;
  perform private.display_validate_search_v3(p_kind,coalesce(p_query,''),coalesce(p_filters,'{}'::jsonb),'relevance',1);
  v_filters:=private.display_normalize_filters_v1(p_filters);
  v_fingerprint:=encode(extensions.digest(convert_to(
    'portal-navigation-v1:' || (select asset_sha256 from private.display_read_navigation_contract_v1 where contract_version=1) || ':' ||
    private.display_query_fingerprint_v1(p_kind,v_query,v_filters,p_dimension || ':' || coalesce(p_parent_node_id,'')),
    'UTF8'),'sha256'),'hex');
  if p_cursor is not null then
    v_cursor:=private.display_cursor_decode_v1(p_cursor);
    if v_cursor is null or jsonb_typeof(v_cursor)<>'object'
      or (select count(*) from jsonb_object_keys(v_cursor))<>6
      or v_cursor->>'v' is distinct from '1' or v_cursor->>'fp' is distinct from v_fingerprint
      or v_cursor->>'kind' is distinct from p_kind or v_cursor->>'dimension' is distinct from p_dimension
      or v_cursor->>'parent' is distinct from p_parent_node_id
      or coalesce(v_cursor->>'node','') !~ '^[a-z][a-z0-9-]*:[!-~]{1,96}$'
    then raise exception using errcode='22023',message='invalid portal request'; end if;
    v_cursor_node:=v_cursor->>'node';
  end if;
  return private.display_navigation_impl_v1(p_kind,v_query,v_filters,p_dimension,p_parent_node_id,v_cursor_node,v_limit,v_fingerprint,p_include_totals);
end;
$_$;

ALTER FUNCTION "private"."display_navigation_v1"("p_kind" "text", "p_query" "text", "p_filters" "jsonb", "p_dimension" "text", "p_parent_node_id" "text", "p_cursor" "text", "p_limit" integer, "p_include_totals" boolean) OWNER TO "portal_display_executor";

REVOKE ALL ON FUNCTION "private"."display_navigation_v1"("p_kind" "text", "p_query" "text", "p_filters" "jsonb", "p_dimension" "text", "p_parent_node_id" "text", "p_cursor" "text", "p_limit" integer, "p_include_totals" boolean) FROM PUBLIC;

GRANT ALL ON FUNCTION "private"."display_navigation_v1"("p_kind" "text", "p_query" "text", "p_filters" "jsonb", "p_dimension" "text", "p_parent_node_id" "text", "p_cursor" "text", "p_limit" integer, "p_include_totals" boolean) TO "postgres";

CREATE OR REPLACE FUNCTION "private"."display_navigation_v1"("p_kind" "text", "p_query" "text", "p_filters" "jsonb", "p_dimension" "text", "p_parent_node_id" "text", "p_cursor" "text", "p_limit" integer) RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE PARALLEL RESTRICTED
    SET "search_path" TO ''
    AS $$
begin
  return private.display_navigation_v1(p_kind,p_query,p_filters,p_dimension,p_parent_node_id,p_cursor,p_limit,true);
end;
$$;

ALTER FUNCTION "private"."display_navigation_v1"("p_kind" "text", "p_query" "text", "p_filters" "jsonb", "p_dimension" "text", "p_parent_node_id" "text", "p_cursor" "text", "p_limit" integer) OWNER TO "portal_display_executor";

REVOKE ALL ON FUNCTION "private"."display_navigation_v1"("p_kind" "text", "p_query" "text", "p_filters" "jsonb", "p_dimension" "text", "p_parent_node_id" "text", "p_cursor" "text", "p_limit" integer) FROM PUBLIC;

GRANT ALL ON FUNCTION "private"."display_navigation_v1"("p_kind" "text", "p_query" "text", "p_filters" "jsonb", "p_dimension" "text", "p_parent_node_id" "text", "p_cursor" "text", "p_limit" integer) TO "postgres";

CREATE OR REPLACE FUNCTION "private"."display_api_navigation_v1"("p_kind" "text", "p_query" "text", "p_filters" "jsonb", "p_dimension" "text", "p_parent_node_id" "text", "p_cursor" "text", "p_limit" integer, "p_include_totals" boolean) RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    SET "statement_timeout" TO '8s'
    SET "row_security" TO 'on'
    AS $$
declare
  v_diagnostic_message text;
  v_diagnostic_context text;
  v_diagnostic_state text;
begin
  return private.display_navigation_v1(p_kind,p_query,p_filters,p_dimension,p_parent_node_id,p_cursor,p_limit,p_include_totals);
exception
  when sqlstate '22023' then
    get stacked diagnostics v_diagnostic_context = PG_EXCEPTION_CONTEXT;
    raise log using message = 'portal read failure diagnostic',
      detail = pg_catalog.jsonb_build_object(
        'schemaVersion', 'portal.read-failure.v1', 'rpc', 'display_navigation_v1',
        'category', 'validation', 'reason', case
          when v_diagnostic_context ~ '^PL/pgSQL function private\.display_validate_search_v1\(' then 'search_input'
          when v_diagnostic_context ~ '^PL/pgSQL function private\.display_validate_search_v3\(' then 'hierarchy_input'
          when v_diagnostic_context ~ '^PL/pgSQL function private\.display_navigation_impl_v1\(' then
            case when p_cursor is null then 'parent' else 'parent_or_cursor_node' end
          when v_diagnostic_context ~ '^PL/pgSQL function private\.display_navigation_v1\(' then
            case
              when p_dimension is null or p_dimension not in ('classification', 'geography')
                or coalesce(p_limit, 100) not between 1 and 500 then 'navigation_options'
              when p_cursor is not null then 'cursor_binding'
              else 'unknown'
            end
          else 'unknown'
        end
      )::text;
    raise exception using errcode = '22023', message = 'invalid portal request';
  when query_canceled then
    get stacked diagnostics v_diagnostic_message = MESSAGE_TEXT;
    raise log using message = 'portal read failure diagnostic',
      detail = pg_catalog.jsonb_build_object(
        'schemaVersion', 'portal.read-failure.v1', 'rpc', 'display_navigation_v1',
        'category', 'cancellation', 'reason', case v_diagnostic_message
          when 'canceling statement due to statement timeout' then 'statement_timeout'
          when 'canceling statement due to user request' then 'cancel_request'
          else 'unknown'
        end
      )::text;
    raise exception using errcode = 'P0001', message = 'portal catalog unavailable';
  when others then
    get stacked diagnostics v_diagnostic_state = RETURNED_SQLSTATE;
    raise log using message = 'portal read failure diagnostic',
      detail = pg_catalog.jsonb_build_object(
        'schemaVersion', 'portal.read-failure.v1', 'rpc', 'display_navigation_v1',
        'category', 'internal', 'reason', case v_diagnostic_state
          when '54000' then 'response_budget'
          when '55000' then 'contract_drift'
          else 'other'
        end
      )::text;
    raise exception using errcode = 'P0001', message = 'portal catalog unavailable';
end;
$$;

ALTER FUNCTION "private"."display_api_navigation_v1"("p_kind" "text", "p_query" "text", "p_filters" "jsonb", "p_dimension" "text", "p_parent_node_id" "text", "p_cursor" "text", "p_limit" integer, "p_include_totals" boolean) OWNER TO "portal_display_executor";

REVOKE ALL ON FUNCTION "private"."display_api_navigation_v1"("p_kind" "text", "p_query" "text", "p_filters" "jsonb", "p_dimension" "text", "p_parent_node_id" "text", "p_cursor" "text", "p_limit" integer, "p_include_totals" boolean) FROM PUBLIC;

GRANT ALL ON FUNCTION "private"."display_api_navigation_v1"("p_kind" "text", "p_query" "text", "p_filters" "jsonb", "p_dimension" "text", "p_parent_node_id" "text", "p_cursor" "text", "p_limit" integer, "p_include_totals" boolean) TO "portal_public_executor";

CREATE OR REPLACE FUNCTION "private"."display_api_navigation_v1"("p_kind" "text", "p_query" "text" DEFAULT ''::"text", "p_filters" "jsonb" DEFAULT '{}'::"jsonb", "p_dimension" "text" DEFAULT 'classification'::"text", "p_parent_node_id" "text" DEFAULT NULL::"text", "p_cursor" "text" DEFAULT NULL::"text", "p_limit" integer DEFAULT 100) RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    SET "statement_timeout" TO '8s'
    SET "row_security" TO 'on'
    AS $$
begin
  return private.display_api_navigation_v1(p_kind,p_query,p_filters,p_dimension,p_parent_node_id,p_cursor,p_limit,true);
end;
$$;

ALTER FUNCTION "private"."display_api_navigation_v1"("p_kind" "text", "p_query" "text", "p_filters" "jsonb", "p_dimension" "text", "p_parent_node_id" "text", "p_cursor" "text", "p_limit" integer) OWNER TO "portal_display_executor";

REVOKE ALL ON FUNCTION "private"."display_api_navigation_v1"("p_kind" "text", "p_query" "text", "p_filters" "jsonb", "p_dimension" "text", "p_parent_node_id" "text", "p_cursor" "text", "p_limit" integer) FROM PUBLIC;

GRANT ALL ON FUNCTION "private"."display_api_navigation_v1"("p_kind" "text", "p_query" "text", "p_filters" "jsonb", "p_dimension" "text", "p_parent_node_id" "text", "p_cursor" "text", "p_limit" integer) TO "portal_public_executor";

CREATE OR REPLACE FUNCTION "api"."portal_navigation_branches_v1"("p_allowed_brands" "text"[], "p_kind" "text", "p_query" "text" DEFAULT ''::"text", "p_filters" "jsonb" DEFAULT '{}'::"jsonb", "p_dimension" "text" DEFAULT 'classification'::"text", "p_parent_node_id" "text" DEFAULT NULL::"text", "p_cursor" "text" DEFAULT NULL::"text", "p_limit" integer DEFAULT 100) RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    SET "statement_timeout" TO '8s'
    AS $$ declare result jsonb; old_brands text:=current_setting('portal.display_brands',true); old_global text:=current_setting('portal.display_global',true); old_filter text:=current_setting('portal.display_filter_brand',true); begin
 perform private.portal_display_begin_request_v1(p_allowed_brands,p_filters);
 result:=jsonb_set(private.portal_display_brand_decorate_v1(private.display_api_navigation_v1(p_kind, p_query, p_filters - 'brand', p_dimension, p_parent_node_id, p_cursor, p_limit, false)),'{schemaVersion}',to_jsonb('portal.public-navigation-branches.v1'::text));
 perform set_config('portal.display_brands',coalesce(old_brands,''),true);
 perform set_config('portal.display_global',coalesce(old_global,''),true);
 perform set_config('portal.display_filter_brand',coalesce(old_filter,''),true);
 return result;
end $$;

ALTER FUNCTION "api"."portal_navigation_branches_v1"("p_allowed_brands" "text"[], "p_kind" "text", "p_query" "text", "p_filters" "jsonb", "p_dimension" "text", "p_parent_node_id" "text", "p_cursor" "text", "p_limit" integer) OWNER TO "portal_display_executor";

REVOKE ALL ON FUNCTION "api"."portal_navigation_branches_v1"("p_allowed_brands" "text"[], "p_kind" "text", "p_query" "text", "p_filters" "jsonb", "p_dimension" "text", "p_parent_node_id" "text", "p_cursor" "text", "p_limit" integer) FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."portal_navigation_branches_v1"("p_allowed_brands" "text"[], "p_kind" "text", "p_query" "text", "p_filters" "jsonb", "p_dimension" "text", "p_parent_node_id" "text", "p_cursor" "text", "p_limit" integer) TO "anon";

GRANT ALL ON FUNCTION "api"."portal_navigation_branches_v1"("p_allowed_brands" "text"[], "p_kind" "text", "p_query" "text", "p_filters" "jsonb", "p_dimension" "text", "p_parent_node_id" "text", "p_cursor" "text", "p_limit" integer) TO "authenticated";

CREATE OR REPLACE FUNCTION api.portal_catalog_totals_v1(p_allowed_brands text[])
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path='' SET row_security=on SET statement_timeout='8s'
SET plan_cache_mode='force_custom_plan'
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
ALTER FUNCTION api.portal_catalog_totals_v1(text[]) OWNER TO portal_display_executor;
REVOKE ALL ON FUNCTION api.portal_catalog_totals_v1(text[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION api.portal_catalog_totals_v1(text[]) TO anon,authenticated;

insert into private.api_capability_grants
  (routine_identity,capability_id,allow_anon,allow_authenticated,allow_service_role)
select format('%I.%I(%s)',n.nspname,p.proname,pg_catalog.oidvectortypes(p.proargtypes)),
  g.capability_id,g.allow_anon,g.allow_authenticated,g.allow_service_role
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
cross join private.api_capability_grants g
where n.nspname='api' and p.proname in ('portal_navigation_branches_v1','portal_catalog_totals_v1')
  and g.routine_identity='api.portal_navigation_v2(text[], text, text, jsonb, text, text, text, integer)'
on conflict (routine_identity) do update set capability_id=excluded.capability_id,
  allow_anon=excluded.allow_anon,allow_authenticated=excluded.allow_authenticated,
  allow_service_role=excluded.allow_service_role;
revoke create on schema private,api from portal_display_executor;
update private.portal_display_contract_manifest
set identity=private.portal_display_contract_identity_v1() where singleton;
select private.portal_display_assert_contract_v1();
commit;
