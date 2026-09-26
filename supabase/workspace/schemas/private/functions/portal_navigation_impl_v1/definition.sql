CREATE OR REPLACE FUNCTION "private"."portal_navigation_impl_v1"("p_kind" "text", "p_query" "text", "p_filters" "jsonb", "p_dimension" "text", "p_parent_node_id" "text", "p_cursor_node_id" "text", "p_limit" integer, "p_fingerprint" "text") RETURNS "jsonb"
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
  perform private.assert_portal_navigation_contract_v1();
  if p_parent_node_id is not null and not exists (
    select 1 from private.portal_navigation_node_v1 n
    where n.node_id=p_parent_node_id and n.dimension=p_dimension
      and (n.source_file is not null or n.node_id in ('class:isic','class:cpc','class:elementary','geo:unmapped')
        or exists(select 1 from private.portal_navigation_membership_v1 m where m.node_id=n.node_id))
  ) then raise exception using errcode='22023',message='invalid portal request'; end if;
  if p_cursor_node_id is not null then
    select n.code into v_after_code from private.portal_navigation_node_v1 n
    where n.node_id=p_cursor_node_id and n.dimension=p_dimension
      and n.parent_node_id is not distinct from p_parent_node_id;
    if not found then raise exception using errcode='22023',message='invalid portal request'; end if;
  end if;

  with matched as materialized (
    select * from private.portal_navigation_matched_versions_v1('all',p_query,p_filters)
  ), children as materialized (
    select n.* from private.portal_navigation_node_v1 n
    where n.dimension=p_dimension and n.parent_node_id is not distinct from p_parent_node_id
      and (n.source_file is not null or n.node_id in ('class:isic','class:cpc','class:elementary','geo:unmapped') or exists (
        select 1 from private.portal_navigation_membership_v1 m
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
    select n.* from private.portal_navigation_node_v1 n where n.node_id=p_parent_node_id
  ), counted as materialized (
    select m.node_id,count(*) as count,count(*) filter(where m.direct) as direct_count
    from private.portal_navigation_membership_v1 m
    where m.dimension=p_dimension and (p_kind='all' or m.dataset_kind=p_kind)
      and ((p_query='' and p_filters='{}'::jsonb)
        or (m.dataset_kind,m.id,m.version) in (select dataset_kind,id,version from matched))
      and m.node_id in(select n.node_id from targets n)
    group by m.node_id
  ), decorated as materialized (
    select n.node_id,n.code,jsonb_build_object(
      'nodeId',n.node_id,'parentNodeId',n.parent_node_id,'code',n.code,'taxonomy',n.taxonomy,
      'count',coalesce(c.count,0),'directCount',coalesce(c.direct_count,0),
      'hasChildren',exists(select 1 from private.portal_navigation_node_v1 child where child.parent_node_id=n.node_id
        and (child.source_file is not null or exists(select 1 from private.portal_navigation_membership_v1 m where m.node_id=child.node_id)))
    ) as value from targets n left join counted c on c.node_id=n.node_id
  ), paged as (
    select d.*,row_number() over(order by d.code collate "C",d.node_id collate "C") as rn
    from decorated d where d.node_id is distinct from p_parent_node_id
  ) select
    coalesce((select jsonb_agg(value order by rn) from paged where rn<=p_limit),'[]'::jsonb),
    (select case when count(*)>p_limit then (array_agg(node_id order by rn))[p_limit] else null end from paged),
    (select value from decorated where node_id=p_parent_node_id),
    (select jsonb_build_object('process',count(*) filter(where dataset_kind='process'),'flow',count(*) filter(where dataset_kind='flow')) from matched)
  into v_nodes,v_next,v_parent,v_totals;

  with recursive ancestors as (
    select n.node_id,n.parent_node_id,n.code,n.taxonomy,1 as depth
    from private.portal_navigation_node_v1 n
    where n.node_id=(select p.parent_node_id from private.portal_navigation_node_v1 p where p.node_id=p_parent_node_id)
    union all
    select n.node_id,n.parent_node_id,n.code,n.taxonomy,a.depth+1
    from ancestors a join private.portal_navigation_node_v1 n on n.node_id=a.parent_node_id
    where a.depth<32
  ) select coalesce(jsonb_agg(jsonb_build_object('nodeId',node_id,'parentNodeId',parent_node_id,'code',code,'taxonomy',taxonomy) order by depth desc),'[]'::jsonb)
    into v_ancestors from ancestors;

  loop
    v_result:=jsonb_build_object('schemaVersion','portal.public-navigation.v1','countBasis','public_versions',
      'dimension',p_dimension,'kind',p_kind,'totals',v_totals,'parent',v_parent,'ancestors',v_ancestors,'nodes',v_nodes,
      'nextCursor',case when v_next is null then null else private.portal_cursor_encode_v1(jsonb_build_object(
        'v',1,'fp',p_fingerprint,'dimension',p_dimension,'kind',p_kind,'parent',p_parent_node_id,'node',v_next)) end);
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

ALTER FUNCTION "private"."portal_navigation_impl_v1"("p_kind" "text", "p_query" "text", "p_filters" "jsonb", "p_dimension" "text", "p_parent_node_id" "text", "p_cursor_node_id" "text", "p_limit" integer, "p_fingerprint" "text") OWNER TO "portal_public_executor";

REVOKE ALL ON FUNCTION "private"."portal_navigation_impl_v1"("p_kind" "text", "p_query" "text", "p_filters" "jsonb", "p_dimension" "text", "p_parent_node_id" "text", "p_cursor_node_id" "text", "p_limit" integer, "p_fingerprint" "text") FROM PUBLIC;
