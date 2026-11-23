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

ALTER FUNCTION "private"."assert_portal_navigation_projection_v1"() OWNER TO "portal_public_executor";

REVOKE ALL ON FUNCTION "private"."assert_portal_navigation_projection_v1"() FROM PUBLIC;

GRANT ALL ON FUNCTION "private"."assert_portal_navigation_projection_v1"() TO "api_internal_executor";
