-- Synthetic attestation fixture for an already sealed selection and admitted runtime.
create temporary table readiness_fixture(header jsonb,proofs jsonb);
insert into readiness_fixture(header)
 select ((p#>'{data}')-array['scope','publicationAuthorized','artifacts','nextArtifactCursor'])||jsonb_build_object(
   'schemaVersion','tiangong.final-result-readiness-attempt.v1','verificationId','87950000-0000-4000-8000-000000000001',
   'startedAt',clock_timestamp()-interval '2 seconds','candidateFilesVerifiedAt',clock_timestamp()-interval '1 second',
   'candidateFiles',(select receipt->'files' from private.final_result_candidate_storage limit 1))
 from (select api.qry_final_result_release_probe_page_v2('87930000-0000-4000-8000-000000000010',pg_temp.final_plan_hash()) p) x;
update readiness_fixture set proofs=(select jsonb_agg(jsonb_build_object('artifact',a.artifact_ref,'selectedResultCount',selected.n,
  'files',s.receipt->'files','filesVerifiedAt',clock_timestamp(),'probes',(
    select jsonb_agg((api.qry_final_result_release_probe_v2(m.release_run_id,pg_temp.final_plan_hash(),'87940000-0000-4000-8000-000000000001',m.result_id,m.result_version)->'data')||
      jsonb_build_object('schemaVersion','tiangong.final-result-reader-probe.v1','startedAt',clock_timestamp(),'verifiedAt',clock_timestamp(),
      'lciNonzeroCount',case when (a.manifest->>'inventoryCount')::integer=0 then 0 else 1 end,'lciPageCount',1,'lciaCount',a.impact_count,
      'queryCount',2+case when a.impact_count>0 then 1 else 0 end,'observationsSha256',repeat('a',64)) order by m.result_id,m.result_version)
    from private.final_result_release_members m where m.release_run_id='87930000-0000-4000-8000-000000000010' and m.artifact_id=a.id
      and m.result_id::text||'@'||m.result_version in(selected.first_key,selected.last_key)
  )) order by a.id)
 from (select artifact_id,count(*) n,min(result_id::text||'@'||result_version collate "C") first_key,max(result_id::text||'@'||result_version collate "C") last_key
   from private.final_result_release_members where release_run_id='87930000-0000-4000-8000-000000000010' group by artifact_id) selected
 join private.final_result_query_artifacts a on a.id=selected.artifact_id join private.final_result_query_seals s on s.artifact_id=a.id);
grant select on readiness_fixture to authenticated,service_role;
create function pg_temp.readiness_header(p_patch jsonb default '{}') returns jsonb language sql as $$ select header||p_patch from readiness_fixture $$;
create function pg_temp.readiness_proofs() returns jsonb language sql as $$ select proofs from readiness_fixture $$;
grant execute on function pg_temp.readiness_header(jsonb),pg_temp.readiness_proofs() to authenticated,service_role;
