begin;
set local lock_timeout = '5s';
-- A credential names its own non-login generation. Revoking this membership and
-- its authenticator admission invalidates that generation without rotating JWT keys.
create role lca_result_zip_reader_g20261102 nologin inherit nosuperuser nocreatedb nocreaterole noreplication nobypassrls;
grant lca_result_zip_reader to lca_result_zip_reader_g20261102 with inherit true, set false;
grant lca_result_zip_reader_g20261102 to authenticator with inherit false;
comment on role lca_result_zip_reader is 'Base final Result ZIP SELECT permission. Credentials use individually revocable non-login generation roles; never grant application roles or writes.';
comment on role lca_result_zip_reader_g20261102 is 'ZIP credential generation 20261102. Retire by revoking this role from authenticator and its lca_result_zip_reader membership. Never reuse retired generation names.';
commit;
