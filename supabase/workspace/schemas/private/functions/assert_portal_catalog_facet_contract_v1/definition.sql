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

ALTER FUNCTION "private"."assert_portal_catalog_facet_contract_v1"() OWNER TO "api_internal_executor";

REVOKE ALL ON FUNCTION "private"."assert_portal_catalog_facet_contract_v1"() FROM PUBLIC;

GRANT ALL ON FUNCTION "private"."assert_portal_catalog_facet_contract_v1"() TO "portal_public_executor";
