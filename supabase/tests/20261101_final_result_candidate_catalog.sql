begin;
create extension if not exists pgtap with schema extensions;
set local search_path=extensions,public,api,private,auth;
select no_plan();
\ir fixtures/final-result-candidate-setup.sql
select ok(not has_function_privilege('authenticated','api.svc_result_candidate_register_v2(text,text,jsonb)','execute') and not has_function_privilege('anon','api.svc_result_candidate_describe_v2(text,text)','execute'),'Candidate service RPCs are closed to browser roles');
select is((select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='private' and c.relname in ('final_result_candidates','final_result_candidate_artifacts','final_result_candidate_members','final_result_candidate_storage') and c.relrowsecurity),4::bigint,'all Candidate metadata relations retain RLS');
select ok(not has_table_privilege('service_role','private.final_result_candidate_members','select,insert,update,delete'),'raw Candidate membership remains closed');
set local role service_role;
select is(api.svc_result_query_describe_v2('87920000-0000-4000-8000-000000000001',repeat('d',64))#>>'{data,readbackReceipt,readbackId}','87920000-0000-4000-8000-000000000040','query reconciliation recovers original target seal');
select is(api.svc_result_query_describe_v2('87920000-0000-4000-8000-000000000001',repeat('b',64))#>'{data,readbackReceipt}','null'::jsonb,'another target never borrows a seal');
select is(api.svc_result_query_describe_v2('87920000-0000-4000-8000-000000000099',repeat('d',64))->'data','null'::jsonb,'unknown artifact lookup has a bounded empty result');
select throws_ok($q$select pg_temp.register_candidate('{"profile":"standalone-lifecyclemodel-result-full-closure.v1"}')$q$,'22023','Final Result Candidate/catalog binding mismatch','legacy four-package profile is not reinterpreted');
select throws_ok($q$select pg_temp.register_candidate('{"publicationAuthorized":true}')$q$,'22023','Final Result Candidate/catalog binding mismatch','Candidate cannot self-authorize publication');
select throws_ok($q$select pg_temp.register_candidate('{"candidateQualified":false}')$q$,'22023','Final Result Candidate/catalog binding mismatch','unqualified producer output is rejected');
select throws_ok($q$select pg_temp.register_candidate('{"unknown":true}')$q$,'22023','Final Result Candidate/catalog binding mismatch','unknown Candidate fields are rejected');
select throws_ok($q$select pg_temp.register_candidate('{}','{}',jsonb_build_object('targetHash',repeat('b',64)))$q$,'22023','Final Result Candidate artifact is not sealed for this input and target','all artifacts require this exact target seal');
select throws_ok($q$select pg_temp.register_candidate(jsonb_build_object('queryArtifacts',jsonb_set((pg_temp.candidate_fixture()->>'candidateText')::jsonb->'queryArtifacts','{0,manifestSha256}',to_jsonb(repeat('b',64)))))$q$,'22023','Final Result Candidate artifact is not sealed for this input and target','changed artifact digest is rejected');
select throws_ok($q$select pg_temp.register_candidate(jsonb_build_object('queryArtifacts',jsonb_build_array((pg_temp.candidate_fixture()->>'candidateText')::jsonb#>'{queryArtifacts,0}',(pg_temp.candidate_fixture()->>'candidateText')::jsonb#>'{queryArtifacts,0}')))$q$,'22023','Duplicate or oversized final Result Candidate artifact set','one artifact cannot be counted twice');
select throws_ok($q$select pg_temp.register_candidate(jsonb_build_object('packages',jsonb_set((pg_temp.candidate_fixture()->>'candidateText')::jsonb->'packages','{0,format}','"tidas"')))$q$,'22023','Final Result Candidate requires the exact Result-only ZIP pair','TIDAS and ILCD are both required');
select throws_ok($q$select pg_temp.register_candidate('{}','{}','{"files":[]}')$q$,'22023','Final Result Candidate package readback mismatch','all ZIP and metadata files require readback');
select throws_ok($q$select pg_temp.register_candidate('{}','{}',jsonb_build_object('verifiedAt',clock_timestamp()-interval '1 hour'))$q$,'22023','Final Result Candidate readback is not fresh','stale first Candidate storage proof is rejected');
select throws_ok($q$select pg_temp.register_candidate('{}',jsonb_build_object('datasets',jsonb_set((pg_temp.candidate_fixture()->>'catalogText')::jsonb->'datasets','{1,canonicalContentHash}',to_jsonb(repeat('d',64)))))$q$,'22023','Final Result Candidate has mismatched or duplicated registered Results','Result canonical content must agree with the global registration');
select throws_ok($q$select pg_temp.register_candidate('{}',jsonb_build_object('datasets',jsonb_set((pg_temp.candidate_fixture()->>'catalogText')::jsonb->'datasets','{1,references}','["flow:87920000-0000-4000-8000-000000000099@01.00.000"]')))$q$,'22023','Final Result Candidate closure reference is absent','ZIP closure cannot refer to an absent member');
select throws_ok($q$select pg_temp.register_candidate('{}',jsonb_build_object('datasets',jsonb_set(jsonb_set(jsonb_set((pg_temp.candidate_fixture()->>'catalogText')::jsonb->'datasets','{1,references}','[]'),'{2,references}','[]'),'{3,references}','[]')))$q$,'22023','Final Result Candidate contains unreachable package members','unrelated support documents cannot be smuggled into ZIP scope');
select throws_ok($q$select pg_temp.register_candidate('{}',jsonb_build_object('datasets',jsonb_set((pg_temp.candidate_fixture()->>'catalogText')::jsonb->'datasets','{1,references}','[{"target":"flow:87920000-0000-4000-8000-000000000050@01.00.000"}]')))$q$,'22023','Final Result Candidate closure reference is absent','consumer follows the real exact-key reference array contract');
create temporary table registered_candidate as select api.svc_result_candidate_register_v2(a->>'candidateText',a->>'catalogText',a->'receipt') response from original_args;
select is((select response#>>'{data,memberCount}' from registered_candidate),'4','complete Candidate closure is registered');
select is((select response#>>'{data,resultCount}' from registered_candidate),'3','multiple artifacts cover all three final Results');
select is((select response#>>'{data,publicationAuthorized}' from registered_candidate),'false','Candidate storage evidence grants no publication');
select is((select api.svc_result_candidate_register_v2(a->>'candidateText',a->>'catalogText',a->'receipt') from original_args),(select response from registered_candidate),'lost-ACK retry returns the original exact storage binding');
select is(api.svc_result_candidate_describe_v2((select response#>>'{data,candidateHash}' from registered_candidate),repeat('d',64))#>>'{data,readbackReceipt,readbackId}','87920000-0000-4000-8000-000000000060','bounded reconciliation returns the original Candidate receipt');
select is(api.svc_result_candidate_describe_v2((select response#>>'{data,candidateHash}' from registered_candidate),repeat('b',64))#>'{data,readbackReceipt}','null'::jsonb,'Candidate known on one target does not imply storage on another');
select throws_ok($q$select api.svc_result_candidate_register_v2(a->>'candidateText',a->>'catalogText',jsonb_set(a->'receipt','{readbackId}','"87920000-0000-4000-8000-000000000061"')) from original_args$q$,'23505','Final Result Candidate storage identity conflict','storage receipt cannot be replaced after sealing');
-- A second storage target must independently attest every shared query file.
select lives_ok($q$select api.svc_result_query_seal_v2('87920000-0000-4000-8000-000000000001',
  (pg_temp.candidate_fixture()#>'{queries,0,receipt}')||jsonb_build_object('targetHash',repeat('b',64),'readbackId','87920000-0000-4000-8000-000000000070','verifiedAt',clock_timestamp()))$q$,'first artifact can be verified on a second target');
select throws_ok($q$select api.svc_result_candidate_register_v2(a->>'candidateText',a->>'catalogText',
  (a->'receipt')||jsonb_build_object('targetHash',repeat('b',64),'readbackId','87920000-0000-4000-8000-000000000072')) from original_args$q$,
  '22023','Final Result Candidate artifact is not sealed for this input and target','partial target replication cannot qualify a Candidate');
select lives_ok($q$select api.svc_result_query_seal_v2('87920000-0000-4000-8000-000000000002',
  (pg_temp.candidate_fixture()#>'{queries,1,receipt}')||jsonb_build_object('targetHash',repeat('b',64),'readbackId','87920000-0000-4000-8000-000000000071','verifiedAt',clock_timestamp()))$q$,'second artifact completes independent target evidence');
select is((select api.svc_result_candidate_register_v2(a->>'candidateText',a->>'catalogText',
  (a->'receipt')||jsonb_build_object('targetHash',repeat('b',64),'readbackId','87920000-0000-4000-8000-000000000072'))#>>'{data,candidateHash}' from original_args),
  (select response#>>'{data,candidateHash}' from registered_candidate),'same immutable Candidate can be qualified on another target');
select is(api.svc_result_candidate_describe_v2((select response#>>'{data,candidateHash}' from registered_candidate),repeat('d',64))#>>'{data,readbackReceipt,readbackId}',
  '87920000-0000-4000-8000-000000000060','replication preserves the original target receipt');
select is((select api.svc_result_candidate_register_v2(a->>'candidateText',a->>'catalogText',
  (a->'receipt')||jsonb_build_object('targetHash',repeat('b',64),'readbackId','87920000-0000-4000-8000-000000000072'))#>>'{data,readbackId}' from original_args),
  '87920000-0000-4000-8000-000000000072','second-target lost ACK is independently recoverable');
select is(pg_temp.register_candidate('{"releaseVersion":"2026.11.2"}','{}',
  '{"readbackId":"87920000-0000-4000-8000-000000000073"}')#>>'{data,resultCount}','3','another Candidate can reuse the exact registered Results and query artifacts');
reset role;
select is((select count(*) from private.final_result_candidate_storage where candidate_hash=(select response#>>'{data,candidateHash}' from registered_candidate)),2::bigint,'replication adds target evidence without duplicating immutable Candidate membership');
select is((select count(*) from private.final_result_query_artifacts where id in ('87920000-0000-4000-8000-000000000001','87920000-0000-4000-8000-000000000002')),2::bigint,'Candidate reuse does not duplicate query files');
select is((select count(*) from private.final_result_candidate_artifacts where candidate_hash=(select response#>>'{data,candidateHash}' from registered_candidate)),2::bigint,'both artifact bindings remain immutable Candidate members');
select throws_ok($q$delete from private.final_result_candidate_members where dataset_id='87920000-0000-4000-8000-000000000050'$q$,'55000','Result query evidence is immutable','package membership cannot be edited after registration');
select is((select count(*) from private.lca_release_publications),0::bigint,'storage qualification does not activate a release');
select * from finish();
rollback;
