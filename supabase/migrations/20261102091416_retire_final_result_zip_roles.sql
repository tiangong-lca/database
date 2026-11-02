-- Database #887: existing Edge server credentials replace the unused custom signer.
-- Preserve migration history; remove only the roles/policies introduced by #887.
begin;
set local lock_timeout = '5s';
drop policy final_result_zip_reader_select on storage.objects;
drop policy final_result_zip_reader_fence on storage.objects;
drop policy final_result_zip_reader_no_insert on storage.objects;
drop policy final_result_zip_reader_no_update on storage.objects;
drop policy final_result_zip_reader_no_delete on storage.objects;
revoke select on storage.objects from lca_result_zip_reader;
do $retire$
begin
  -- Hosted Production never granted this usage; Dev and blank rebuilds did.
  if has_schema_privilege('lca_result_zip_reader', 'storage', 'USAGE') then
    revoke usage on schema storage from lca_result_zip_reader;
  end if;
end
$retire$;
revoke lca_result_zip_reader_g20261102 from authenticator;
revoke lca_result_zip_reader from lca_result_zip_reader_g20261102;
revoke lca_result_zip_reader from authenticator;
-- No CASCADE: any unexpected object dependency must stop retirement atomically.
drop role lca_result_zip_reader_g20261102;
drop role lca_result_zip_reader;
commit;
