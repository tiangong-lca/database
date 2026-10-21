-- Database #801: old-query parity and bounded name hydration.

begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, api, private, auth;
select no_plan();

create temporary table open_data_webhook_calls (
  edge_function text not null,
  body jsonb not null,
  timeout_milliseconds integer not null
) on commit drop;

create or replace function util.invoke_edge_function(
  name text,
  body jsonb,
  timeout_milliseconds integer default ((5 * 60) * 1000)
) returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into pg_temp.open_data_webhook_calls(edge_function, body, timeout_milliseconds)
  values (name, body, timeout_milliseconds);
end;
$$;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at, is_sso_user, is_anonymous
) values
  ('00000000-0000-0000-0000-000000000000','71200000-0000-4000-8000-000000000001',
   'authenticated','authenticated','open-data-manager@example.invalid','x',now(),'{}','{}',now(),now(),false,false),
  ('00000000-0000-0000-0000-000000000000','71200000-0000-4000-8000-000000000002',
   'authenticated','authenticated','open-data-owner@example.invalid','x',now(),'{}','{}',now(),now(),false,false);

insert into private.users(id, raw_user_meta_data, contact) values
  ('71200000-0000-4000-8000-000000000001','{}',null),
  ('71200000-0000-4000-8000-000000000002','{}',null);
insert into private.teams(id, json, rank, is_public)
values ('00000000-0000-0000-0000-000000000000','{"name":"System"}',0,false)
on conflict (id) do nothing;
insert into private.roles(user_id, team_id, role) values
  ('71200000-0000-4000-8000-000000000001','00000000-0000-0000-0000-000000000000','data_product_manager');


do $$ declare k text; t text; path text[]; n integer; v text; name jsonb; doc jsonb; begin
 foreach k in array array['lifecyclemodel','process','flow','flowproperty','unitgroup','source','contact'] loop
  t:=case k when 'lifecyclemodel' then 'lifecyclemodels' when 'process' then 'processes' when 'flow' then 'flows' when 'flowproperty' then 'flowproperties' when 'unitgroup' then 'unitgroups' when 'source' then 'sources' else 'contacts' end;
  path:=case k
   when 'lifecyclemodel' then array['lifeCycleModelDataSet','lifeCycleModelInformation','dataSetInformation','name']
   when 'process' then array['processDataSet','processInformation','dataSetInformation','name']
   when 'flow' then array['flowDataSet','flowInformation','dataSetInformation','name']
   when 'flowproperty' then array['flowPropertyDataSet','flowPropertiesInformation','dataSetInformation','common:name']
   when 'unitgroup' then array['unitGroupDataSet','unitGroupInformation','dataSetInformation','common:name']
   when 'source' then array['sourceDataSet','sourceInformation','dataSetInformation','common:shortName']
   else array['contactDataSet','contactInformation','dataSetInformation','common:name'] end;
  for n in 1..3 loop
   -- Odd families retain published history plus one current draft; even
   -- families retain both review versions. Display identities are unchanged.
   foreach v in array array['01.00.000','02.00.000'] loop
    name:=jsonb_build_object('@xml:lang','zh','#text',case when n=3 then repeat('长',6000) else k||' 测试 100% _ '||chr(39)||' '||n||' '||v end);
    if k in ('lifecyclemodel','process','flow') then name:=jsonb_build_object('baseName',name);end if;
    doc:=jsonb_build_object(path[1],jsonb_build_object(path[2],jsonb_build_object(path[3],jsonb_build_object(path[4],name))));
    execute format('insert into public.%I(id,version,state_code,user_id,json) values($1,$2,$3,$4,$5)',t)
      using ('80100000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,v::character(9),case when n%2=0 then 20 when v='01.00.000' then 100 else 0 end,'71200000-0000-4000-8000-000000000002'::uuid,doc;
    insert into private.dataset_display_settings(dataset_kind,dataset_id,dataset_version,is_visible)
      values(k,('80100000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,v::character(9),n%2=0);
   end loop;
  end loop;
 end loop;
end $$;
select set_config('request.jwt.claim.sub','71200000-0000-4000-8000-000000000001',true);
create function pg_temp.display_baseline801(p_kind text,p_visibility text,p_query text,p_page_size integer,p_page integer,p_candidates boolean)
returns jsonb language plpgsql as $$ declare v_result jsonb; begin
  with eligible as materialized (
    select c.dataset_kind,c.dataset_id,c.dataset_version,
      case when octet_length(c.name::text)<=16384 then c.name else null end as name,
      coalesce(s.is_visible,false) as is_visible
    from private.dataset_display_catalog c
    left join private.dataset_display_settings s using(dataset_kind,dataset_id,dataset_version)
    where (p_kind='all' or c.dataset_kind=p_kind)
      and (p_candidates or s.is_visible)
      and (p_visibility='all' or (p_visibility='visible' and s.is_visible) or (p_visibility='hidden' and not coalesce(s.is_visible,false)))
      and (p_query='' or strpos(lower(coalesce(c.name::text,'')),lower(p_query))>0 or strpos(c.dataset_id::text,lower(p_query))>0)
  ), page as (
    select * from eligible order by dataset_kind,dataset_id,dataset_version desc
    limit p_page_size offset (p_page::bigint-1)*p_page_size
  )
  select jsonb_build_object('data',coalesce((select jsonb_agg(
    case when p_candidates then to_jsonb(page) else to_jsonb(page)-'is_visible' end
    order by dataset_kind,dataset_id,dataset_version desc) from page),'[]'::jsonb),
    'total',(select count(*) from eligible)) into v_result;
  return v_result;
end; $$;

create function pg_temp.parity801() returns setof text language plpgsql as $$
declare k text; vis text; q text; pg integer; expected jsonb; actual jsonb; begin
 foreach k in array array['all','lifecyclemodel','process','flow','flowproperty','unitgroup','source','contact'] loop
  foreach vis in array array['all','visible','hidden'] loop
   foreach q in array array['','测试','100% _ '||chr(39),'80100000','长','no-such-name', chr(39)||'); select 1; --'] loop
    foreach pg in array array[1,2,10,1000000] loop
     expected:=pg_temp.display_baseline801(k,vis,q,3,pg,true);
     actual:=api.list_dataset_display_candidates(k,vis,q,3,pg);
     return next extensions.is(actual,expected,'candidate parity: '||k||'/'||vis||'/'||q||'/page'||pg);
    end loop;
   end loop;
  end loop;
  foreach q in array array['','测试','80100000','长','no-such-name'] loop
   foreach pg in array array[1,2,10] loop
    return next extensions.is(api.list_displayed_datasets(k,q,2,pg),pg_temp.display_baseline801(k,'visible',q,2,pg,false),'display parity: '||k||'/'||q||'/page'||pg);
   end loop;
  end loop;
 end loop;
end $$;
select * from pg_temp.parity801();
-- Reject off-page name evaluation rather than relying on timing alone.
create temporary table hydration_allowed801(dataset_kind text,dataset_id uuid,dataset_version text) on commit drop;
insert into hydration_allowed801
select dataset_kind,dataset_id,dataset_version from private.dataset_display_catalog
order by dataset_kind,dataset_id,dataset_version desc limit 3;
create function pg_temp.guard_name801(k text,i uuid,v text,n jsonb) returns jsonb
language plpgsql stable as $$ begin
 if not exists(select 1 from pg_temp.hydration_allowed801 a where a.dataset_kind=k and a.dataset_id=i and a.dataset_version=v) then
  raise exception 'off-page name hydration';
 end if;
 return n;
end $$;
do $$ declare definition text;begin
 definition:=pg_get_viewdef('private.dataset_display_catalog'::regclass,true);
 execute 'create or replace view private.dataset_display_catalog as select dataset_kind,dataset_id,dataset_version,pg_temp.guard_name801(dataset_kind,dataset_id,dataset_version,name) as name,state_code from ('||rtrim(definition, E';\n ')||') original';
end $$;
select is(jsonb_array_length(api.list_dataset_display_candidates('all','all','',3,1)->'data'),3,'first page hydrates only its three names');
select is(api.list_dataset_display_candidates('all','all','',3,1)->>'total','42','exact count does not evaluate off-page names');
select is(jsonb_array_length(api.list_dataset_display_candidates('all','all','',3,1000000)->'data'),0,'empty deep page hydrates no name');
truncate hydration_allowed801;
insert into hydration_allowed801
select c.dataset_kind,c.dataset_id,c.dataset_version from private.dataset_display_catalog c
join private.dataset_display_settings s using(dataset_kind,dataset_id,dataset_version)
where s.is_visible order by dataset_kind,dataset_id,dataset_version desc limit 2;
select is(jsonb_array_length(api.list_displayed_datasets('all','',2,1)->'data'),2,'displayed page hydrates only its two names');
select is(api.list_displayed_datasets('all','',2,1000000)->>'total','14','deep displayed page preserves exact total without names');
select * from finish();
rollback;
