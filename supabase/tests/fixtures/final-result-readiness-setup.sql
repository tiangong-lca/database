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
create temporary table readiness_fixture(header jsonb,proofs jsonb);
insert into readiness_fixture(header)
 select ((p#>'{data}')-array['scope','publicationAuthorized','artifacts','nextArtifactCursor'])||jsonb_build_object(
   'schemaVersion','tiangong.final-result-readiness-attempt.v1','verificationId','87950000-0000-4000-8000-000000000001',
   'startedAt',clock_timestamp()-interval '2 seconds','candidateFilesVerifiedAt',clock_timestamp()-interval '1 second',
   'candidateFiles',(select receipt->'files' from private.final_result_candidate_storage limit 1))
 from (select api.qry_final_result_release_probe_page_v2('87930000-0000-4000-8000-000000000010',pg_temp.final_plan_hash()) p) x;
update readiness_fixture set proofs=(select jsonb_agg(jsonb_build_object('artifact',a.artifact_ref,'selectedResultCount',1,
  'files',s.receipt->'files','filesVerifiedAt',clock_timestamp(),'probes',jsonb_build_array(
    (api.qry_final_result_release_probe_v2(m.release_run_id,pg_temp.final_plan_hash(),'87940000-0000-4000-8000-000000000001',m.result_id,m.result_version)->'data')||
    jsonb_build_object('schemaVersion','tiangong.final-result-reader-probe.v1','startedAt',clock_timestamp(),'verifiedAt',clock_timestamp(),
      'lciNonzeroCount',1,'lciPageCount',1,'lciaCount',a.impact_count,'queryCount',2+case when a.impact_count>0 then 1 else 0 end,'observationsSha256',repeat('a',64))
  )) order by m.artifact_id) from private.final_result_release_members m join private.final_result_query_artifacts a on a.id=m.artifact_id
  join private.final_result_query_seals s on s.artifact_id=a.id where m.release_run_id='87930000-0000-4000-8000-000000000010');
grant select on readiness_fixture to authenticated,service_role;
create function pg_temp.readiness_header(p_patch jsonb default '{}') returns jsonb language sql as $$ select header||p_patch from readiness_fixture $$;
create function pg_temp.readiness_proofs() returns jsonb language sql as $$ select proofs from readiness_fixture $$;
grant execute on function pg_temp.readiness_header(jsonb),pg_temp.readiness_proofs() to authenticated,service_role;
