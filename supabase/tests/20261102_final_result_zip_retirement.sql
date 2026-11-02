begin;
select plan(5);
select is((select count(*) from pg_roles where rolname in (
  'lca_result_zip_reader', 'lca_result_zip_reader_g20261102'
)), 0::bigint, 'custom ZIP roles are retired');
select is((select count(*) from pg_policies where schemaname = 'storage'
  and tablename = 'objects' and policyname in (
    'final_result_zip_reader_select', 'final_result_zip_reader_fence',
    'final_result_zip_reader_no_insert', 'final_result_zip_reader_no_update',
    'final_result_zip_reader_no_delete'
  )), 0::bigint, 'only the custom ZIP policies are retired');
select ok(has_schema_privilege('service_role', 'storage', 'USAGE'),
  'existing service Storage schema access remains');
select ok(has_table_privilege('service_role', 'storage.objects', 'SELECT'),
  'existing service Storage read access remains');
select ok((select relrowsecurity from pg_class where oid = 'storage.objects'::regclass),
  'Storage RLS remains enabled');
select * from finish();
rollback;
