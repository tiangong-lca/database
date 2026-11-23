-- Database #1004. Switch the legacy state-100/200 catalog in one transaction.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '120s';
-- Serialize at source before taking any child locks (including FK validation).
lock table public.processes, public.flows in share row exclusive mode;
lock table private.portal_catalog_search_rows_v1, private.portal_catalog_search_rows_v2
  in share row exclusive mode;

-- Allow replacement of existing owner-defined routines. Restore the exact
-- grant made by this grantor, including its PG17 membership options.
do $grants$
declare r text; original jsonb;
begin
  foreach r in array array['api_internal_executor', 'portal_public_executor'] loop
    select jsonb_build_object('admin',admin_option,'inherit',inherit_option,'set',set_option)
      into original from pg_auth_members
      where roleid=r::regrole and member=current_user::regrole and grantor=current_user::regrole;
    perform set_config('portal_1004.' || r, coalesce(original,'null'::jsonb)::text, true);
    execute format('grant %I to %I with inherit true', r, current_user);
  end loop;
end
$grants$;

select private.assert_portal_navigation_projection_v1();
select private.assert_portal_catalog_facet_contract_v1();
select private.assert_portal_catalog_character_contract_cn1();

-- Refuse an incomplete predecessor rather than erase evidence or expose stale
-- versions. Only names/document changed in #628; the facet inputs are shared.
do $coverage$
begin
  if (select count(*) from pg_trigger t
      where (t.tgrelid,t.tgname,t.tgfoid) in (
        ('public.processes'::regclass,'portal_catalog_projection_content_sync_v2','private.sync_portal_catalog_search_row_v2()'::regprocedure),
        ('public.flows'::regclass,'portal_catalog_projection_content_sync_v1','private.sync_portal_catalog_search_row_v1()'::regprocedure))
        and t.tgenabled='O' and t.tgtype=29 and t.tgqual is null) <> 2 then
    raise exception 'Required Portal source writers are unavailable' using errcode='55000';
  end if;
  if exists (
    select 1 from (
      select id, version::text as version, state_code, modified_at
      from public.processes
      where state_code in (100,200) and modified_at is not null
        and jsonb_typeof(json->'processDataSet')='object'
    ) source
    full join private.portal_catalog_search_rows_v2 p using (id,version)
    where source.id is null or p.id is null
       or (source.state_code,source.modified_at) is distinct from (p.state_code,p.modified_at)
  ) or exists (
    select 1 from (select * from private.portal_catalog_search_rows_v1 where dataset_kind='process') old
    full join private.portal_catalog_search_rows_v2 p using (dataset_kind,id,version)
    left join private.portal_catalog_facet_rows_v1 f on (f.dataset_kind,f.id,f.version)=(p.dataset_kind,p.id,p.version)
    left join private.portal_navigation_versions_v1 n on (n.dataset_kind,n.id,n.version)=(p.dataset_kind,p.id,p.version)
    left join private.portal_sitemap_rows_v1 s on (s.dataset_kind,s.id,s.version)=(p.dataset_kind,p.id,p.version)
    left join private.portal_catalog_character_rows_v2 c on (c.dataset_kind,c.id,c.version)=(p.dataset_kind,p.id,p.version)
    cross join lateral private.portal_catalog_facet_facts_v1(p.dataset_kind,p.card) facts
    where old.id is null or p.id is null or f.id is null or n.id is null or s.id is null or c.id is null
       or (old.state_code,old.modified_at) is distinct from (p.state_code,p.modified_at)
       or (f.state_code,f.modified_at,s.modified_at) is distinct from (p.state_code,p.modified_at,p.modified_at)
       or (f.facet_access_level,f.facet_geography,f.facet_reference_year,f.facet_process_subtype,f.facet_source)
           is distinct from (facts.facet_access_level,facts.facet_geography,facts.facet_reference_year,
                             facts.facet_process_subtype,facts.facet_source)
  ) then
    raise exception 'Incomplete Portal Process projections before contraction' using errcode='55000';
  end if;
  -- Reject unexpected inbound dependencies before the bounded legacy cleanup.
  if (select array_agg(conname::text order by conname)
      from pg_constraint where confrelid='private.portal_catalog_search_rows_v1'::regclass)
      is distinct from array['portal_catalog_character_parent_v1_fk','portal_catalog_facet_rows_projection_v1_fk',
                             'portal_navigation_versions_v1_dataset_kind_id_version_fkey'] then
    raise exception 'Unexpected Portal V1 projection dependencies' using errcode='55000';
  end if;
end
$coverage$;

-- MATCH SIMPLE skips the other kind's NULL version. The child primary keys
-- already index (dataset_kind,id), the selective prefix for both cascades.
alter table private.portal_catalog_facet_rows_v1
  add column flow_version text generated always as (case when dataset_kind='flow' then version end) stored,
  add column process_version text generated always as (case when dataset_kind='process' then version end) stored,
  drop constraint portal_catalog_facet_rows_projection_v1_fk,
  add constraint portal_facet_flow_parent_fk foreign key (dataset_kind,id,flow_version)
    references private.portal_catalog_search_rows_v1(dataset_kind,id,version) on update restrict on delete cascade,
  add constraint portal_facet_process_parent_fk foreign key (dataset_kind,id,process_version)
    references private.portal_catalog_search_rows_v2(dataset_kind,id,version) on update restrict on delete cascade;

-- The original four navigation backfill shards SET CONSTRAINTS by both names.
-- Preserve those names and the existing deferred, Process-only V2 FK.
alter table private.portal_navigation_versions_v1
  add column flow_version text generated always as (case when dataset_kind='flow' then version end) stored,
  drop constraint portal_navigation_versions_v1_dataset_kind_id_version_fkey,
  add constraint portal_navigation_versions_v1_dataset_kind_id_version_fkey foreign key (dataset_kind,id,flow_version)
    references private.portal_catalog_search_rows_v1(dataset_kind,id,version)
    on delete cascade deferrable initially deferred;

create trigger portal_catalog_facet_sync_v2
after insert or update of dataset_kind,id,version,state_code,modified_at,card
on private.portal_catalog_search_rows_v2
for each row execute function private.sync_portal_catalog_facet_row_v1();

drop trigger portal_catalog_projection_content_sync_v1 on public.processes;
delete from private.portal_catalog_search_rows_v1 where dataset_kind='process';
alter table private.portal_catalog_search_rows_v1
  drop constraint portal_catalog_search_rows_v1_dataset_kind_check,
  add constraint portal_catalog_search_rows_v1_dataset_kind_check check (dataset_kind='flow');

CREATE OR REPLACE FUNCTION "private"."assert_portal_catalog_facet_contract_v1"() RETURNS "void"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER PARALLEL RESTRICTED
    SET "search_path" TO ''
    SET "row_security" TO 'on'
    AS $$
declare
  v_expected_identities constant text[] := array[
    'private.portal_catalog_facet_facts_v1(text,jsonb)',
    'private.sync_portal_catalog_facet_row_v1()'
  ]::text[];
  v_expected_digest constant text :=
    'b238e9573ef08a9339062a2fa3092c0776318d13979ec8bf54ffc7a1ba0c7e3a';
  v_live_digest text;
begin
  select private.portal_catalog_facet_manifest_sha256_v1()
  into v_live_digest;

  if v_live_digest is distinct from v_expected_digest
     or (
       select count(*)
       from private.portal_catalog_facet_contract_v1 as contract
       where contract.contract_version = 1
         and contract.manifest_schema =
           'portal.catalog-facet-function-manifest.v1'
         and contract.function_identities = v_expected_identities
         and contract.manifest_sha256 = v_expected_digest
         and contract.created_by_migration = '20260827020000'
     ) <> 1
     or (
       select count(*)
       from private.portal_catalog_facet_contract_v1
     ) <> 1
     or (
       select not relation.relrowsecurity
         or not relation.relforcerowsecurity
         or relation.relowner <> 'postgres'::regrole
       from pg_catalog.pg_class as relation
       where relation.oid =
         'private.portal_catalog_facet_contract_v1'::regclass
     ) is not false
     or (
       select not relation.relrowsecurity
         or not relation.relforcerowsecurity
         or relation.relowner <> 'postgres'::regrole
       from pg_catalog.pg_class as relation
       where relation.oid =
         'private.portal_catalog_facet_rows_v1'::regclass
     ) is not false
     or (
       select count(*)
       from pg_catalog.pg_trigger as trigger
       where (trigger.tgrelid,trigger.tgname) in (
           ('private.portal_catalog_search_rows_v1'::regclass,'portal_catalog_facet_sync_v1'),
           ('private.portal_catalog_search_rows_v2'::regclass,'portal_catalog_facet_sync_v2')
         )
         and trigger.tgqual is null
         and trigger.tgfoid =
           'private.sync_portal_catalog_facet_row_v1()'::regprocedure
         and trigger.tgenabled = 'O'
         and not trigger.tgisinternal
         and trigger.tgtype = 21
         and array(
           select attribute.attname
           from unnest(trigger.tgattr::smallint[])
             with ordinality as trigger_column(attnum, ordinality)
           join pg_catalog.pg_attribute as attribute
             on attribute.attrelid = trigger.tgrelid
            and attribute.attnum = trigger_column.attnum
           order by trigger_column.ordinality
         ) = array[
           'dataset_kind',
           'id',
           'version',
           'state_code',
           'modified_at',
           'card'
         ]::name[]
     ) <> 2
     or exists (
       select 1
       from pg_catalog.pg_constraint as constraint_catalog
       where constraint_catalog.conrelid in (
           'private.portal_catalog_facet_contract_v1'::regclass,
           'private.portal_catalog_facet_rows_v1'::regclass
         )
         and not constraint_catalog.convalidated
     )
     or (
       select count(*) from pg_catalog.pg_constraint fk
       join pg_catalog.pg_attribute v on v.attrelid=fk.conrelid and v.attnum=fk.conkey[3]
       where fk.conrelid='private.portal_catalog_facet_rows_v1'::regclass
         and (fk.confrelid,fk.conname,v.attname) in (
           ('private.portal_catalog_search_rows_v1'::regclass,'portal_facet_flow_parent_fk','flow_version'),
           ('private.portal_catalog_search_rows_v2'::regclass,'portal_facet_process_parent_fk','process_version'))
         and fk.contype='f' and fk.convalidated and fk.confupdtype='r' and fk.confdeltype='c'
         and fk.conkey = array[1,2,v.attnum]::smallint[] and fk.confkey=array[1,2,3]::smallint[]
         and v.attgenerated='s'
     ) <> 2
     or not exists (
       select 1
       from pg_catalog.pg_constraint as contract_fk
       where contract_fk.conrelid =
           'private.portal_catalog_facet_rows_v1'::regclass
         and contract_fk.confrelid =
           'private.portal_catalog_facet_contract_v1'::regclass
         and contract_fk.conname =
           'portal_catalog_facet_rows_contract_version_v1_fk'
         and contract_fk.contype = 'f'
         and contract_fk.convalidated
         and contract_fk.confupdtype = 'r'
         and contract_fk.confdeltype = 'r'
     ) then
    raise exception using
      errcode = '55000',
      message = 'Portal facet derivation contract drifted';
  end if;
end
$$;

CREATE OR REPLACE FUNCTION "private"."assert_portal_navigation_projection_v1"() RETURNS "void"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    SET "row_security" TO 'on'
    AS $$
declare e record;
begin
  perform private.assert_portal_catalog_projection_contract_cn1();
  if (select count(*) from private.portal_navigation_projection_contract_v1)<>12 then
    raise exception 'Portal navigation derivation contract is absent' using errcode='55000';
  end if;
  for e in select * from private.portal_navigation_projection_contract_v1 loop
    if to_regprocedure(e.routine_identity) is null or not exists(
      select 1 from pg_proc p where p.oid=to_regprocedure(e.routine_identity)
      and pg_get_userbyid(p.proowner)=e.owner_name
      and encode(extensions.digest(convert_to(pg_get_functiondef(p.oid),'UTF8'),'sha256'),'hex')=e.definition_sha256
    ) then raise exception 'Portal navigation derivation contract drifted' using errcode='55000'; end if;
  end loop;
  if (select count(*) from pg_class c where c.oid in (
      'private.portal_navigation_versions_v1'::regclass,'private.portal_navigation_membership_v1'::regclass)
      and c.relrowsecurity and c.relforcerowsecurity and pg_get_userbyid(c.relowner)='postgres')<>2
    or (select count(*) from pg_constraint c where c.contype='f' and c.convalidated and c.confdeltype='c'
      and ((c.conrelid='private.portal_navigation_versions_v1'::regclass and c.condeferrable and c.condeferred and (
        (c.confrelid='private.portal_catalog_search_rows_v1'::regclass and c.conname='portal_navigation_versions_v1_dataset_kind_id_version_fkey'
         and c.conkey=array[1,2,(select attnum from pg_attribute where attrelid=c.conrelid and attname='flow_version' and attgenerated='s')]::smallint[])
        or (c.confrelid='private.portal_catalog_search_rows_v2'::regclass and c.conkey=array[1,4,5]::smallint[]))
        and c.confkey=array[1,2,3]::smallint[])
        or (c.conrelid='private.portal_navigation_membership_v1'::regclass and c.confrelid='private.portal_navigation_versions_v1'::regclass)))<>3
    or not exists(select 1 from pg_trigger t where t.tgrelid='private.portal_catalog_search_rows_v1'::regclass
      and t.tgname='portal_navigation_flow_sync_v1' and t.tgenabled='O' and t.tgtype=21 and t.tgattr::text='6' and not t.tgdeferrable and not t.tginitdeferred and t.tgfoid='private.sync_portal_navigation_row_v1()'::regprocedure)
    or not exists(select 1 from pg_trigger t where t.tgrelid='private.portal_catalog_search_rows_v2'::regclass
      and t.tgname='portal_navigation_process_sync_v1' and t.tgenabled='O' and t.tgtype=29 and t.tgattr::text='6' and not t.tgdeferrable and not t.tginitdeferred and t.tgfoid='private.sync_portal_navigation_row_v1()'::regprocedure)
  then raise exception 'Portal navigation projection boundary drifted' using errcode='55000'; end if;
end;
$$;

-- Keep the earlier private exact fallback callable on the same eligible keys.
CREATE OR REPLACE FUNCTION "private"."portal_projection_semantic_process_exact_v1"("p_query_embedding" "extensions"."vector") RETURNS TABLE("id" "uuid", "version" "text", "semantic_distance" double precision)
    LANGUAGE "sql" STABLE SECURITY DEFINER PARALLEL RESTRICTED
    SET "search_path" TO ''
    SET "statement_timeout" TO '20s'
    SET "plan_cache_mode" TO 'force_custom_plan'
    SET "work_mem" TO '32MB'
    SET "enable_hashjoin" TO 'on'
    SET "enable_nestloop" TO 'off'
    SET "enable_mergejoin" TO 'off'
    SET "enable_sort" TO 'on'
    SET "max_parallel_workers_per_gather" TO '0'
    SET "jit" TO 'off'
    SET "row_security" TO 'on'
    AS $$
  select * from private.portal_projection_semantic_process_exact_cn1(p_query_embedding)
$$;

select private.assert_portal_catalog_facet_contract_v1();
select private.assert_portal_navigation_projection_v1();

do $restore$
declare r text; original jsonb;
begin
  foreach r in array array['api_internal_executor','portal_public_executor'] loop
    original := current_setting('portal_1004.' || r)::jsonb;
    if original='null'::jsonb then
      execute format('revoke %I from %I',r,current_user);
    else
      execute format('grant %I to %I with admin %s, inherit %s, set %s',
        r,current_user,original->>'admin',original->>'inherit',original->>'set');
    end if;
  end loop;
end
$restore$;
commit;
