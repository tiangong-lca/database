-- Database #887: server-only ZIP signing identity, never an application actor.
begin;
set local lock_timeout = '5s';
create role lca_result_zip_reader nologin noinherit nosuperuser nocreatedb nocreaterole noreplication nobypassrls;
comment on role lca_result_zip_reader is 'Dedicated server-side final Result ZIP reader. No application-role membership. Revoke its separately managed API key to retire a credential.';
grant lca_result_zip_reader to authenticator with inherit false;
grant usage on schema storage to lca_result_zip_reader;
grant select on storage.objects to lca_result_zip_reader;
create policy final_result_zip_reader_select on storage.objects
  for select to lca_result_zip_reader
  using (
    bucket_id = 'lca_results'
    and name ~ '^lca_results/release-candidates/[0-9a-f]{64}/result[.](tidas|ilcd)[.]zip$'
  );
-- The restrictive fence also survives any future permissive PUBLIC policy.
create policy final_result_zip_reader_fence on storage.objects
  as restrictive for select to lca_result_zip_reader
  using (
    bucket_id = 'lca_results'
    and name ~ '^lca_results/release-candidates/[0-9a-f]{64}/result[.](tidas|ilcd)[.]zip$'
  );
create policy final_result_zip_reader_no_insert on storage.objects
  as restrictive for insert to lca_result_zip_reader with check (false);
create policy final_result_zip_reader_no_update on storage.objects
  as restrictive for update to lca_result_zip_reader using (false) with check (false);
create policy final_result_zip_reader_no_delete on storage.objects
  as restrictive for delete to lca_result_zip_reader using (false);
commit;
