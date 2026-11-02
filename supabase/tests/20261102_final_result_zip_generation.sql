begin;
create extension if not exists pgtap with schema extensions;
set local search_path=extensions,public,pg_catalog;
select no_plan();
select ok(exists(select 1 from pg_roles where rolname='lca_result_zip_reader_g20261102' and not rolcanlogin and rolinherit and not rolsuper and not rolcreatedb and not rolcreaterole and not rolreplication and not rolbypassrls),'generation is non-login and unprivileged');
select is((select count(*) from pg_auth_members where member='lca_result_zip_reader_g20261102'::regrole),1::bigint,'generation has exactly one parent');
select ok(pg_has_role('lca_result_zip_reader_g20261102','lca_result_zip_reader','USAGE') and not pg_has_role('lca_result_zip_reader_g20261102','lca_result_zip_reader','SET'),'generation inherits bounded reads without SET to base');
select ok(pg_has_role('authenticator','lca_result_zip_reader_g20261102','SET') and not pg_has_role('authenticator','lca_result_zip_reader_g20261102','USAGE'),'gateway can SET but not inherit generation');
select ok(has_table_privilege('lca_result_zip_reader_g20261102','storage.objects','SELECT') and not has_table_privilege('lca_result_zip_reader_g20261102','storage.objects','INSERT,UPDATE,DELETE,TRUNCATE'),'generation can only read objects');
select ok(not has_schema_privilege('lca_result_zip_reader_g20261102','private','USAGE') and not has_schema_privilege('lca_result_zip_reader_g20261102','api','USAGE'),'generation cannot access application schemas');
insert into storage.buckets(id,name,public) values('lca_results','lca_results',false) on conflict(id) do nothing;
insert into storage.objects(bucket_id,name) values
 ('lca_results','lca_results/release-candidates/'||repeat('d',64)||'/result.tidas.zip'),
 ('lca_results','lca_results/release-candidates/'||repeat('d',64)||'/result.ilcd.zip'),
 ('lca_results','lca_results/release-candidates/'||repeat('d',64)||'/lci.h5');
grant usage on schema extensions to lca_result_zip_reader_g20261102;
set local role lca_result_zip_reader_g20261102;
select is((select count(*) from storage.objects),2::bigint,'generation inherits exact ZIP path RLS, not HDF5');
select throws_ok($$insert into storage.objects(bucket_id,name) values('lca_results','lca_results/release-candidates/'||repeat('e',64)||'/result.tidas.zip')$$,'42501',null,'generation cannot write');
reset role;
revoke lca_result_zip_reader_g20261102 from authenticator;
revoke lca_result_zip_reader from lca_result_zip_reader_g20261102;
select ok(not pg_has_role('authenticator','lca_result_zip_reader_g20261102','SET'),'retired token role cannot be assumed');
select ok(not has_table_privilege('lca_result_zip_reader_g20261102','storage.objects','SELECT'),'retired generation loses object reads');
select ok(has_table_privilege('lca_result_zip_reader','storage.objects','SELECT'),'generation retirement preserves base role for other generations');
select * from finish();
rollback;
