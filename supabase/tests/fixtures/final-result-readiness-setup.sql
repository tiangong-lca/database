-- Caller owns BEGIN / ROLLBACK. Only synthetic service attestations, not actual
-- external file/numeric qualification. Release owns the real reader integration.
\ir final-result-release-setup.sql
set local role authenticated;
select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claim.sub','87930000-0000-4000-8000-000000000001',true);
select api.cmd_final_result_release_prepare_v2(pg_temp.final_release_plan(),'synthetic-readiness');
select api.cmd_final_result_release_members_v2('87930000-0000-4000-8000-000000000010',pg_temp.final_plan_hash(),'[{"uuid":"87920000-0000-4000-8000-000000000010","version":"01.00.000"},{"uuid":"87920000-0000-4000-8000-000000000012","version":"01.00.000"}]');
select api.cmd_final_result_release_seal_v2('87930000-0000-4000-8000-000000000010',pg_temp.final_plan_hash());
reset role;
set local role service_role;
select api.svc_result_query_runtime_configure_v2('87940000-0000-4000-8000-000000000001',null,repeat('d',64),repeat('c',64),true,'synthetic readiness reader');
reset role;
\ir final-result-probe-evidence.sql
