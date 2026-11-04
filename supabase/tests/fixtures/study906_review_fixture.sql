-- SQL authorization/persistence fixtures only: numerical/content bytes and
-- signatures are synthetic. Never claim actual Worker or renderer proof.
\ir study904_analysis_fixture.sql
create temp table study906_results(k text primary key,v jsonb);
create function pg_temp.keep(p_key text,p_value jsonb) returns jsonb language plpgsql as $$begin insert into study906_results values(p_key,p_value) on conflict(k) do update set v=excluded.v;return p_value;end$$;
create function pg_temp.val(p_key text) returns jsonb language sql as $$select v from study906_results where k=p_key$$;
update private.study_reporting_config set analysis_enabled=true,report_enabled=true,export_enabled=true,
 export_profile=jsonb_build_object('issuerId','study906-test','keyId','study906-key','rendererVersion','1.0.0','viewModelVersion','lca.study-report-view.v1','rendererArtifactHash',repeat('a',64),'policyId','lca.study-report-disclosure.v1');
select pg_temp.study894_claim(1);
select pg_temp.keep('analysis',api.cmd_study_reporting_v1(pg_temp.study904_request('review-analysis')));
select pg_temp.study894_claim(null,null,true);
select pg_temp.keep('claim',private.worker_claim_jobs('solver','study906-sql',1,900));
select pg_temp.keep('facts',api.svc_study_analysis_complete_v1((pg_temp.val('analysis')->'data'->'value'->>'analysisId')::uuid,(pg_temp.val('claim')->'data'->0->>'id')::uuid,(pg_temp.val('claim')->'data'->0->>'leaseToken')::uuid,pg_temp.study904_completion(pg_temp.val('analysis')->'data'->'value'->>'configHash'),'review-facts'));
insert into private.study_artifacts(id,study_id,ref,bucket,object_path) values('90600000-0000-4000-8000-000000000001','89400000-0000-4000-8000-000000000010',
 '{"type":"reportContent","id":"90600000-0000-4000-8000-000000000001","contentHash":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","digestScope":"artifact_bytes_sha256","byteSize":2,"mediaType":"application/json","schemaVersion":"lca.study-report-content.v1"}',
 'study-artifacts','study/89400000-0000-4000-8000-000000000010/90600000-0000-4000-8000-000000000001/content.json');
insert into private.study_report_revisions(id,study_id,author_id,revision,status,content_hash,content_artifact_id,template_id,run_ids,analysis_ids,facts_refs,validity_snapshot,validation_evidence)
 values('90600000-0000-4000-8000-000000000002','89400000-0000-4000-8000-000000000010','89400000-0000-4000-8000-000000000001',3,'frozen',repeat('b',64),'90600000-0000-4000-8000-000000000001',
 'lca.study-report.v1',pg_temp.study904_config()->'runIds',jsonb_build_array(pg_temp.val('analysis')->'data'->'value'->'analysisId'),jsonb_build_array(pg_temp.val('facts')->'data'->'value'->'factsRef'),
 '{"status":"current","checkedAt":"2026-11-03T00:00:00Z","reasonCodes":[]}','{"syntheticSqlFixture":true,"claimCount":1}');
insert into private.study_report_runs values('89400000-0000-4000-8000-000000000010','90600000-0000-4000-8000-000000000002',1,'90400000-0000-4000-8000-000000000012');
insert into private.study_report_analyses values('89400000-0000-4000-8000-000000000010','90600000-0000-4000-8000-000000000002',1,(pg_temp.val('analysis')->'data'->'value'->>'analysisId')::uuid);
update private.studies set team_id='89400000-0000-4000-8000-000000000100' where id='89400000-0000-4000-8000-000000000010';
insert into auth.users(id,instance_id,aud,role,email,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
 select ('89400000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','study906-'||i||'@invalid.test','{}','{}',now(),now() from generate_series(4,5)i;
insert into private.users(id,raw_user_meta_data,contact) select ('89400000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,'{}',null from generate_series(4,5)i on conflict(id) do nothing;
insert into private.roles(user_id,team_id,role) select ('89400000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,'89400000-0000-4000-8000-000000000100','member' from generate_series(4,5)i;
create function pg_temp.req(p_op text,p_fields jsonb default '{}',p_key text default 'request') returns jsonb language sql as $$select jsonb_build_object('schemaVersion','lca.study-api.v4','requestId',p_key,'operation',p_op)||p_fields$$;
create function pg_temp.cmd(p_op text,p_fields jsonb default '{}',p_key text default 'request') returns jsonb language sql as $$select api.cmd_study_review_v1(pg_temp.req(p_op,p_fields,p_key)||jsonb_build_object('idempotencyKey',p_key))$$;
create function pg_temp.binding() returns jsonb language sql as $$select jsonb_build_object('reportRevisionId','90600000-0000-4000-8000-000000000002','expectedContentHash',repeat('b',64))$$;
create function pg_temp.review(p_decision text default 'approve',p_predecessor uuid default null,p_delegation uuid default null) returns jsonb language sql as $$select pg_temp.binding()||jsonb_build_object('reviewClass','internal','decision',p_decision,'comment','Actor assessment; no independent certification','predecessorReviewId',p_predecessor,'delegationId',p_delegation)$$;
create function pg_temp.finalize(p_state jsonb,p_profile text default 'lca.study-report-internal-review.v1') returns jsonb language sql as $$select jsonb_build_object('target',jsonb_build_object('type','reportRevision','id','90600000-0000-4000-8000-000000000002','expectedRevision',3),'expectedContentHash',repeat('b',64),'profileId',p_profile,'expectedReviewStateHash',p_state->>'reviewStateHash','acceptedReviewIds',case when p_profile='lca.study-report-unreviewed.v1' then '[]'::jsonb else p_state->'acceptedReviewIds' end)$$;
