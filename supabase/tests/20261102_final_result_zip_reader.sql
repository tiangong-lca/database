-- Database #887. Synthetic metadata only; transaction rolls back all fixtures.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, pg_catalog;
select no_plan();
select ok(exists(select 1 from pg_roles where rolname='lca_result_zip_reader' and not rolcanlogin and not rolinherit and not rolsuper and not rolcreatedb and not rolcreaterole and not rolreplication and not rolbypassrls), 'reader has no privileged or login flags');
select is((select count(*) from pg_auth_members where member='lca_result_zip_reader'::regrole),0::bigint,'reader inherits no roles');
select ok(pg_has_role('authenticator','lca_result_zip_reader','SET'),'gateway can SET the reader role');
select ok(has_table_privilege('lca_result_zip_reader','storage.objects','SELECT'),'object SELECT admitted');
select ok(not has_table_privilege('lca_result_zip_reader','storage.objects','INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'),'object writes denied by ACL');
select ok(not has_schema_privilege('lca_result_zip_reader','private','USAGE'),'private application schema unavailable');
select ok(not has_schema_privilege('lca_result_zip_reader','api','USAGE'),'application RPC schema unavailable');
select ok(not has_table_privilege('lca_result_zip_reader','storage.buckets','INSERT,UPDATE,DELETE,TRUNCATE'),'bucket administration denied');
select is((select count(*) from pg_policies where schemaname='storage' and tablename='objects' and roles::text[] @> array['lca_result_zip_reader']),5::bigint,'one permissive read plus four restrictive fences');
insert into storage.buckets(id,name,public) values ('lca_results','lca_results',false),('zip887_other','zip887_other',false) on conflict(id) do nothing;
insert into storage.objects(bucket_id,name) values
 ('lca_results','lca_results/release-candidates/'||repeat('a',64)||'/result.tidas.zip'),
 ('lca_results','lca_results/release-candidates/'||repeat('a',64)||'/result.ilcd.zip'),
 ('lca_results','lca_results/release-candidates/'||repeat('a',64)||'/lci.h5'),
 ('lca_results','lca_results/release-candidates/'||repeat('a',64)||'/result.tidas.zip/child'),
 ('lca_results','lca_results/release-candidates/'||repeat('A',64)||'/result.tidas.zip'),
 ('lca_results','lca_results/release-candidates/'||repeat('a',63)||'/result.tidas.zip'),
 ('lca_results','other/release-candidates/'||repeat('a',64)||'/result.tidas.zip'),
 ('zip887_other','lca_results/release-candidates/'||repeat('a',64)||'/result.tidas.zip');
-- Only test assertion helpers are added within this rollback transaction.
grant usage on schema extensions to lca_result_zip_reader;
set local role lca_result_zip_reader;
select is((select count(*) from storage.objects),2::bigint,'only the two exact ZIP formats can be read');
select throws_ok($$insert into storage.objects(bucket_id,name) values('lca_results','lca_results/release-candidates/'||repeat('b',64)||'/result.tidas.zip')$$,'42501',null,'insert denied');
select throws_ok($$update storage.objects set metadata='{}' where name like '%result.tidas.zip'$$,'42501',null,'update denied');
select throws_ok($$delete from storage.objects where name like '%result.tidas.zip'$$,'42501',null,'delete denied');
select throws_ok($$select * from api.qry_final_result_download_v2('00000000-0000-4000-8000-000000000001','tidas')$$,'42501',null,'reader cannot become an application actor');
reset role;
-- Future permissive PUBLIC policy cannot widen the exact-path read boundary.
create policy zip887_public_test on storage.objects for select to public using(true);
set local role lca_result_zip_reader;
select is((select count(*) from storage.objects),2::bigint,'restrictive fence survives permissive PUBLIC read policy');
reset role;
-- Even accidentally broader future ACL/policies still cannot admit writes.
grant insert,update,delete on storage.objects to lca_result_zip_reader;
create policy zip887_public_write_test on storage.objects for all to public using(true) with check(true);
set local role lca_result_zip_reader;
select throws_ok($$insert into storage.objects(bucket_id,name) values('lca_results','lca_results/release-candidates/'||repeat('b',64)||'/result.tidas.zip')$$,'42501',null,'insert fence survives broader grants');
with changed as (update storage.objects set metadata='{}' returning id) select is(count(*),0::bigint,'update fence rejects every row') from changed;
-- Match the Storage API's transaction-local delete guard before testing the RLS fence.
select set_config('storage.allow_delete_query','true',true);
with removed as (delete from storage.objects returning id) select is(count(*),0::bigint,'delete fence rejects every row') from removed;
reset role;
select * from finish();
rollback;
