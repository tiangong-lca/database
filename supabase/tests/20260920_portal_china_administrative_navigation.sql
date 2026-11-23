-- China administrative parents: anonymous navigation, search and facets regression.
--
-- Runs after 20260920095651 has been applied, so geo:tw, geo:hk and geo:mo are
-- already children of geo:cn. Everything is read through the anonymous public
-- API, never from the private tables alone, and the whole file rolls back.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path=extensions,public;
select no_plan();
grant portal_public_executor,api_internal_executor to postgres;

create function pg_temp.nav662_payload(
  p_name text, p_geo text, p_classes jsonb, p_year integer default 2024, p_flow boolean default false)
returns jsonb language sql immutable as $$
 select jsonb_build_object(case when p_flow then 'flowDataSet' else 'processDataSet' end,
   jsonb_build_object(case when p_flow then 'flowInformation' else 'processInformation' end,
     jsonb_build_object('dataSetInformation',jsonb_build_object(
       'name',jsonb_build_object('baseName',jsonb_build_object('@xml:lang','en','#text',p_name)),
       -- A real JSON array: classification is a list of objects, not a string.
       'classificationInformation',jsonb_build_object('common:classification',jsonb_build_object('common:class',p_classes))),
       'time',jsonb_build_object('common:referenceYear',p_year),
       'geography',jsonb_build_object(case when p_flow then 'locationOfSupply' else 'locationOfOperationSupplyOrProduction' end,
         jsonb_build_object('@location',p_geo))),
     'administrativeInformation',jsonb_build_object('publicationAndOwnership',jsonb_build_object(
       'common:licenseType','Free of charge for all users and uses'))))
$$;

-- Keep a distinct lexical namespace from the original NavAlpha656 regression.
-- The local PGroonga rollback fixture can otherwise affect the first short-prefix
-- query in a later suite; this test does not change the production query kernel.
-- Suppress unrelated authoring only; every public projection writer stays enabled.
alter table public.processes disable trigger user;
alter table public.processes enable trigger portal_catalog_projection_content_sync_v2;
alter table public.flows disable trigger user;
alter table public.flows enable trigger portal_catalog_projection_content_sync_v1;
insert into public.processes(id,version,json,state_code,modified_at) values
-- One id with two historical public versions, authored in the island.
('66200000-0000-4000-8000-000000000001','01.00.000',pg_temp.nav662_payload('Administrative662TwA','TW','[{"@classId":"A"}]'),100,'2026-09-20'),
('66200000-0000-4000-8000-000000000001','01.00.001',pg_temp.nav662_payload('Administrative662TwA','TW','[{"@classId":"A"}]',2025),100,'2026-09-20'),
('66200000-0000-4000-8000-000000000002','01.00.000',pg_temp.nav662_payload('Administrative662HkB','HK','[{"@classId":"A"}]'),100,'2026-09-20'),
('66200000-0000-4000-8000-000000000003','01.00.000',pg_temp.nav662_payload('Administrative662MoC','MO','[{"@classId":"A"}]'),100,'2026-09-20'),
-- A national-only record, authored directly on the country.
('66200000-0000-4000-8000-000000000004','01.00.000',pg_temp.nav662_payload('Administrative662CnD','CN','[{"@classId":"A"}]'),100,'2026-09-20'),
-- An ordinary province, to pair with the island children under a nonmatching query.
('66200000-0000-4000-8000-000000000005','01.00.000',pg_temp.nav662_payload('Administrative662XzE','CN-XZ','[{"@classId":"A"}]'),100,'2026-09-20'),
-- A withdrawn (private) island record: never projected, never counted.
('66200000-0000-4000-8000-000000000006','01.00.000',pg_temp.nav662_payload('Administrative662PrivateG','TW','[{"@classId":"A"}]'),20,'2026-09-20');
insert into public.flows(id,version,json,state_code,modified_at) values
('66200000-0000-4000-8000-000000000007','01.00.000',pg_temp.nav662_payload('Administrative662FlowF','HK','[{"@classId":"0"}]',2024,true),100,'2026-09-20');
set constraints all immediate;

-- --- Shipped hierarchy -------------------------------------------------------
select is(
  (select array_agg(node.node_id order by node.node_id)
     from private.portal_navigation_node_v1 as node
    where node.parent_node_id = 'geo:cn' and node.node_id in ('geo:tw','geo:hk','geo:mo')),
  array['geo:hk','geo:mo','geo:tw'],
  'the three locations are children of the country node');
select is(
  (select count(*)::integer
     from private.portal_navigation_node_v1 as node
    where node.node_id in ('geo:tw','geo:hk','geo:mo')
      and node.code in ('TW','HK','MO') and node.taxonomy = 'ilcd-locations'
      and node.labels->>'en' <> '' and node.labels->>'zh-CN' <> ''),
  3,
  'the three nodes keep their original codes, taxonomy and reviewed labels');
-- Closure: the writer derived the country ancestor for every authored row, and the
-- ancestor is a closure placement rather than a direct record.
select is(
  (select count(*)::integer
     from private.portal_navigation_membership_v1 as member
    where member.dataset_kind = 'process' and member.id::text like '66200000-%'
      and member.node_id in ('geo:tw','geo:hk','geo:mo')
      and not exists (
        select 1 from private.portal_navigation_membership_v1 as ancestor
        where ancestor.dataset_kind = member.dataset_kind
          and ancestor.id = member.id and ancestor.version = member.version
          and ancestor.dimension = 'geography' and ancestor.node_id = 'geo:cn')),
  0,
  'every authored island membership has the country ancestor');
select is(
  (select count(*)::integer
     from private.portal_navigation_membership_v1 as member
    where member.id::text like '66200000-%' and member.node_id = 'geo:cn' and member.direct),
  1,
  'only the national-only record is a direct country placement');
select is(
  (select count(*)::integer from private.portal_navigation_versions_v1
    where id = '66200000-0000-4000-8000-000000000006'),
  0,
  'a private island record is never projected');

-- --- Anonymous API ------------------------------------------------------------
create temp table nav662(label text primary key, payload jsonb);
grant select,insert on nav662 to anon;
set local role anon;
insert into nav662 values
('china',api.portal_navigation_v1('all','Administrative662','{}','geography','geo:cn',null,500)),
('chinaProcess',api.portal_navigation_v1('process','Administrative662','{}','geography','geo:cn',null,500)),
('chinaEmpty',api.portal_navigation_v1('all','NoSuchQuery662','{}','geography','geo:cn',null,500)),
('tw',api.portal_navigation_v1('process','Administrative662','{}','geography','geo:tw',null,500)),
('hkFlow',api.portal_navigation_v1('flow','Administrative662','{}','geography','geo:hk',null,500)),
('world1',api.portal_navigation_v1('all','','{}','geography',null,null,100)),
('searchSubtree',api.portal_search_processes_v3('Administrative662','{"geographyNodeId":"geo:cn","geographyScope":"subtree"}','relevance',null,50)),
('searchDirect',api.portal_search_processes_v3('Administrative662','{"geographyNodeId":"geo:cn","geographyScope":"direct"}','relevance',null,50)),
('searchTw',api.portal_search_processes_v3('Administrative662','{"geographyNodeId":"geo:tw","geographyScope":"subtree"}','relevance',null,50)),
('facetsSubtree',api.portal_facets_v3('process','Administrative662','{"geographyNodeId":"geo:cn","geographyScope":"subtree"}')),
('facetsDirect',api.portal_facets_v3('process','Administrative662','{"geographyNodeId":"geo:cn","geographyScope":"direct"}'));
insert into nav662 select 'world2',api.portal_navigation_v1('all','','{}','geography',null,(select payload->>'nextCursor' from nav662 where label='world1'),100);
reset role;

-- Reachability is read from the parent's own child list, not from node existence.
select is(
  (select count(*)::integer from nav662 cross join lateral jsonb_array_elements(payload->'nodes') n
    where label = 'china' and n->>'nodeId' in ('geo:tw','geo:hk','geo:mo')),
  3,
  'the country page lists all three island children');
select is(
  (select array_agg(n->>'nodeId' order by n->>'nodeId') from nav662 cross join lateral jsonb_array_elements(payload->'nodes') n
    where label = 'chinaProcess' and n->>'nodeId' in ('geo:tw','geo:hk','geo:mo') and (n->>'count')::integer = 2),
  array['geo:tw'],
  'the island with two historical versions counts both of them');
-- The islands do own the versions authored in them; what they must never own is
-- the national-only record, so that is asserted directly and by role.
select is(
  (select count(*)::integer from private.portal_navigation_membership_v1
    where id = '66200000-0000-4000-8000-000000000004'
      and node_id in ('geo:tw','geo:hk','geo:mo')),
  0,
  'the national-only record is never distributed to an island');
select is(
  (select sum((n->>'directCount')::integer)::integer from nav662 cross join lateral jsonb_array_elements(payload->'nodes') n
    where label = 'chinaProcess' and n->>'nodeId' in ('geo:tw','geo:hk','geo:mo')),
  4,
  'each island direct count is exactly its own authored process versions');

-- Counts come from the parent, and a nonmatching query keeps every child reachable.
select is((select (payload#>>'{parent,count}')::integer from nav662 where label='hkFlow'),1,
  'a flow authored in an island is counted through that island');
select is((select (payload#>>'{parent,count}')::integer from nav662 where label='china'),7,
  'the country subtree counts both historical versions, both other islands, the national record and the flow');
select is((select (payload#>>'{parent,directCount}')::integer from nav662 where label='china'),1,
  'the national-only record is counted directly and is not distributed to a child');
select is((select (payload#>>'{totals,process}')::integer from nav662 where label='china'),6,
  'kind totals measure both kinds independently of the requested branch');
select is((select (payload#>>'{totals,flow}')::integer from nav662 where label='china'),1,
  'a process branch still measures the flow total');
select is((select (payload#>>'{parent,count}')::integer from nav662 where label='chinaProcess'),6,
  'a process-only branch counts only process versions');
select is((select (payload#>>'{parent,count}')::integer from nav662 where label='chinaEmpty'),0,
  'a nonmatching query counts nothing');
select is(
  (select array_agg(n->>'nodeId' order by n->>'nodeId') from nav662 cross join lateral jsonb_array_elements(payload->'nodes') n
    where label = 'chinaEmpty' and n->>'nodeId' in ('geo:tw','geo:hk','geo:mo','geo:cn-xz')),
  array['geo:cn-xz','geo:hk','geo:mo','geo:tw'],
  'with no matches the three islands and an ordinary province are all still reachable at count zero');
select is(
  (select bool_and((n->>'count')::integer = 0) from nav662 cross join lateral jsonb_array_elements(payload->'nodes') n
    where label = 'chinaEmpty' and n->>'nodeId' in ('geo:tw','geo:hk','geo:mo','geo:cn-xz')),
  true,
  'zero is reported, never invented as a presence');

-- The world level must not list them a second time.
select is(
  (select count(*)::integer from nav662 cross join lateral jsonb_array_elements(payload->'nodes') n
    where label in ('world1','world2') and n->>'nodeId' in ('geo:tw','geo:hk','geo:mo')),
  0,
  'the world level does not repeat the island children');
select is(
  (select count(*)::integer from nav662 cross join lateral jsonb_array_elements(payload->'nodes') n
    where label in ('world1','world2') and n->>'nodeId' = 'geo:cn'),
  1,
  'the country appears exactly once at the world level');
select is(
  (select count(distinct n->>'nodeId') from nav662 cross join lateral jsonb_array_elements(payload->'nodes') n
    where label in ('world1','world2')),
  (select count(*) from nav662 cross join lateral jsonb_array_elements(payload->'nodes') n where label in ('world1','world2')),
  'no paged world node is listed twice');

-- Historical versions stay reachable and searchable at the island itself.
select is((select (payload#>>'{parent,count}')::integer from nav662 where label='tw'),2,
  'the island own page counts both historical versions');
select is((select jsonb_array_length(payload->'items') from nav662 where label='searchTw'),2,
  'V3 search returns both historical versions of the island record');

-- Navigation counts, V3 search and V3 facets agree on the same predicate.
select is((select jsonb_array_length(payload->'items') from nav662 where label='searchSubtree'),6,
  'V3 subtree search matches the navigation subtree count');
select is((select jsonb_array_length(payload->'items') from nav662 where label='searchDirect'),1,
  'V3 direct search matches the navigation direct count');
select is(
  (select (vals.value->>'count')::integer from nav662
     cross join lateral jsonb_array_elements(payload->'groups') g
     cross join lateral jsonb_array_elements(g->'values') vals(value)
    where label = 'facetsSubtree' and g->>'id' = 'kind' and vals.value->>'value' = 'process'),
  6,
  'V3 subtree facets match the navigation subtree count');
select is(
  (select (vals.value->>'count')::integer from nav662
     cross join lateral jsonb_array_elements(payload->'groups') g
     cross join lateral jsonb_array_elements(g->'values') vals(value)
    where label = 'facetsDirect' and g->>'id' = 'kind' and vals.value->>'value' = 'process'),
  1,
  'V3 direct facets match the navigation direct count');

-- --- Original codes, permissions, guard ---------------------------------------
select is(
  (select geography_code from private.portal_navigation_versions_v1
    where id = '66200000-0000-4000-8000-000000000001' and version = '01.00.000'),
  'tw',
  'the authored island code is stored as authored, not rewritten to a country code');
select is(
  (select code from private.portal_navigation_node_v1 where node_id = 'geo:tw'),
  'TW',
  'the node keeps its original code after being re-parented');
select ok(not has_table_privilege('anon','private.portal_navigation_membership_v1','select'),
  'anonymous callers cannot read membership storage');
select ok(not has_table_privilege('anon','private.portal_navigation_node_v1','select'),
  'anonymous callers cannot read the node table directly');
select ok(not has_table_privilege('authenticated','private.portal_navigation_versions_v1','select'),
  'authenticated callers cannot read the private narrow storage');
set local role anon;
select throws_ok($$select count(*) from private.portal_navigation_membership_v1$$,'42501',null,
  'anonymous callers cannot select the membership projection');
reset role;
-- The revision re-enabled the seed guard in its own transaction.
select throws_ok($$update private.portal_navigation_node_v1 set parent_node_id = null where node_id = 'geo:tw'$$,
  '55000','Seeded navigation vocabulary is immutable',
  'the seeded vocabulary stays immutable after the revision');
select throws_ok($$delete from private.portal_navigation_node_v1 where node_id = 'geo:hk'$$,
  '55000','Seeded navigation vocabulary is immutable',
  'the revision did not weaken the delete guard either');

-- --- Publish / withdraw / move -------------------------------------------------
-- Withdrawing one historical island version removes exactly that version.
update public.processes set state_code = 20
 where id = '66200000-0000-4000-8000-000000000001' and version = '01.00.001';
select is(
  (select (api.portal_navigation_v1('process','Administrative662','{}','geography','geo:tw')->'parent'->>'count')::integer),
  1,
  'withdrawing one island version leaves the other reachable');
select is(
  (select count(*)::integer from private.portal_navigation_membership_v1
    where id = '66200000-0000-4000-8000-000000000001' and version = '01.00.001'),
  0,
  'a withdrawal cascades every membership of that version');
select is(
  (select (api.portal_navigation_v1('all','Administrative662','{}','geography','geo:cn')->'parent'->>'count')::integer),
  6,
  'the country subtree immediately reflects the withdrawal');
-- Moving the island record to an ordinary province removes the island placement.
update public.processes set json = pg_temp.nav662_payload('Administrative662TwA','CN-SD-JNA','[{"@classId":"A"}]')
 where id = '66200000-0000-4000-8000-000000000001' and version = '01.00.000';
select is(
  (select count(*)::integer from private.portal_navigation_membership_v1
    where id = '66200000-0000-4000-8000-000000000001' and node_id = 'geo:tw'),
  0,
  'moving the source geography removes the island membership');
select is(
  (select count(*)::integer from private.portal_navigation_membership_v1 m
    join private.portal_navigation_node_v1 n using(node_id)
    where m.id = '66200000-0000-4000-8000-000000000001'
      and n.code = 'CN-SD-JNA' and n.parent_node_id = 'geo:cn-sd' and m.direct),
  1,
  'the moved record is placed directly in its new province family');
select is(
  (select (api.portal_navigation_v1('process','Administrative662','{}','geography','geo:cn-sd')->'parent'->>'count')::integer),
  1,
  'the new province reaches the moved record through the anonymous API');
select is(
  (select (api.portal_navigation_v1('process','Administrative662','{}','geography','geo:tw')->'parent'->>'count')::integer),
  0,
  'the island stops counting the moved record');
-- Publishing the private island record brings it into the same closure.
update public.processes set state_code = 100
 where id = '66200000-0000-4000-8000-000000000006';
select is(
  (select (api.portal_navigation_v1('process','Administrative662','{}','geography','geo:tw')->'parent'->>'count')::integer),
  1,
  'publishing the private island record makes it reachable through the island');
select is(
  (select count(*)::integer from private.portal_navigation_membership_v1
    where id = '66200000-0000-4000-8000-000000000006' and node_id = 'geo:cn' and not direct),
  1,
  'the newly published record gains the country ancestor as closure');

select lives_ok('select private.assert_portal_navigation_projection_v1()',
  'the independent navigation derivation guard still passes');
select * from finish();
rollback;
