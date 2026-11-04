-- SQL authorization/transaction fixtures only; no real method byte/scientific approval.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path=extensions,public,api,private,pg_temp;
select no_plan();
\ir fixtures/study906_review_fixture.sql
create function pg_temp.method_config() returns jsonb language sql as $$select jsonb_build_object('schemaVersion','lca.study-method-assessment-config.v1','baselineRunId','90400000-0000-4000-8000-000000000012','moduleRef',private.study_method_module(),
 'declarations',jsonb_build_object('productRole','finishedCementIntermediate','studyPhase','finalStudy','referenceUnitBasis','declaredMass','categoryRule',jsonb_build_object('kind','noneEstablished')),'evidenceRefs','[]'::jsonb)$$;
create function pg_temp.v6(p_op text,p_fields jsonb default '{}',p_key text default 'request') returns jsonb language sql as $$select jsonb_build_object('schemaVersion','lca.study-api.v6','requestId',p_key,'operation',p_op)||p_fields$$;
create function pg_temp.method_cmd(p_op text,p_fields jsonb default '{}',p_key text default 'request') returns jsonb language sql as $$select api.cmd_study_method_v1(pg_temp.v6(p_op,p_fields,p_key)||jsonb_build_object('idempotencyKey',p_key))$$;
create function pg_temp.method_request(p_key text,p_config jsonb default null) returns jsonb language sql as $$select pg_temp.v6('method.assessment.request',jsonb_build_object('idempotencyKey',p_key,'studyId','89400000-0000-4000-8000-000000000010','profileId','lca.study-method-pef-2021-ef31-cement-intermediate.v1','config',coalesce(p_config,pg_temp.method_config()),'configHash',private.study_method_config_hash(coalesce(p_config,pg_temp.method_config()))),p_key)$$;
create function pg_temp.mid() returns uuid language sql as $$select(pg_temp.val('method')->'data'->'value'->>'assessmentId')::uuid$$;
create function pg_temp.mjob() returns uuid language sql as $$select(pg_temp.val('method-claim')->'data'->0->>'id')::uuid$$;
create function pg_temp.mlease() returns uuid language sql as $$select(pg_temp.val('method-claim')->'data'->0->>'leaseToken')::uuid$$;
create function pg_temp.method_completion(p_hash text,p_id text default '91200000-0000-4000-8000-000000000060') returns jsonb language sql as $$select jsonb_build_object('profileId','lca.study-method-pef-2021-ef31-cement-intermediate.v1','configHash',p_hash,'selectedFactorRecordCount',2,
 'factsRef',jsonb_build_object('type','methodAssessmentFacts','id',p_id,'contentHash',repeat('f',64),'digestScope','artifact_bytes_sha256','byteSize',2,'mediaType','application/json','schemaVersion','lca.study-method-assessment-facts.v1'),
 'storageBucket','study-artifacts','storageObjectPath','study/89400000-0000-4000-8000-000000000010/'||p_id||'/method-facts.json')$$;
create function pg_temp.evidence_body() returns jsonb language sql as $$select '{"schemaVersion":"lca.study-method-evidence.v1","requirementId":"PEF-01","declaredKind":"professionalRecord","title":"Recorded declaration only","statement":"This fixture is not professional approval or method conformity.","citations":[{"kind":"normativeSource","identity":"Commission Recommendation 2021/2279 Annex I","version":"2022 corrigendum","contentHash":null,"locator":"Section 3"}]}'::jsonb$$;
select ok(private.study_method_config_valid(pg_temp.method_config()),'closed exact method config accepted');
select is(private.study_method_config_hash('{"schemaVersion": "lca.study-method-assessment-config.v1", "baselineRunId": "10000000-0000-4000-8000-000000000010", "moduleRef": {"repository": "tiangong-lca/pcr", "sourceCommit": "51c0842c67b14ba886e2edee2846e26eefac030f", "moduleId": "method.pef-2021-ef31", "moduleVersion": "0.1.0", "artifactSha256": "b19ba5754b0bc20c44c8c65966bafafd5984cd74636f2c805c0fa4373f5554ad", "reviewBasisSha256": "989391423c7f31bdf77e18ea4438fab1a27ff6708c0f44ecad8ab8813763a165", "sourceBindingsSha256": "3fd9b1dc68228db3e146b6d23daac853b27b9f504f9445a0cc5a971d53257ce2"}, "declarations": {"productRole": "finishedCementIntermediate", "studyPhase": "finalStudy", "referenceUnitBasis": "declaredMass", "categoryRule": {"kind": "noneEstablished"}}, "evidenceRefs": []}'::jsonb),'0d350c9ed228d1bbf03f23712c9a7510366f32e6d8f4182c8df0408e4e569d76','config identity equals immutable independent Worker golden');
select ok(not private.study_method_config_valid(pg_temp.method_config()||'{"approved":true}'),'caller approval property rejected');
select ok(not private.study_method_config_valid(jsonb_set(pg_temp.method_config(),'{moduleRef,artifactSha256}',to_jsonb(repeat('0',64)))),'module artifact substitution rejected');
select ok(not private.study_method_config_valid(jsonb_set(pg_temp.method_config(),'{declarations,studyPhase}','null')),'null phase cannot pass SQL UNKNOWN');
select ok(not private.study_method_config_valid(jsonb_set(pg_temp.method_config(),'{baselineRunId}','"90400000000040008000000000000012"')),'noncanonical UUID alias rejected');
select ok(private.study_method_evidence_body_valid(pg_temp.evidence_body()),'declared evidence supported without approval');
select ok(not private.study_method_evidence_body_valid(jsonb_set(pg_temp.evidence_body(),'{declaredKind}','null')),'null evidence kind rejected');
select ok(not private.study_method_evidence_body_valid(jsonb_set(pg_temp.evidence_body(),'{requirementId}','null')),'null requirement rejected');
select ok(not private.study_method_evidence_body_valid(jsonb_set(pg_temp.evidence_body(),'{citations,0,kind}','null')),'null citation kind rejected');
select ok(not private.study_method_evidence_body_valid(jsonb_set(pg_temp.evidence_body(),'{statement}',to_jsonb(E'line\ncontrol'::text))),'evidence control characters rejected by Worker byte semantics');
select ok(not private.study_method_evidence_body_valid(jsonb_set(pg_temp.evidence_body(),'{citations}',(pg_temp.evidence_body()->'citations')||(pg_temp.evidence_body()->'citations'))),'duplicate declared citations rejected');
select ok(not private.study_method_evidence_body_valid(pg_temp.evidence_body()||'{"professionalApproved":true}'),'untrusted scientific approval flag rejected');
select ok(private.study_method_evidence_body_valid(jsonb_set(pg_temp.evidence_body(),'{title}',to_jsonb(repeat('研',256)))),'evidence title limit counts Unicode codepoints');
select ok(private.study_method_evidence_body_valid(jsonb_set(pg_temp.evidence_body(),'{title}',to_jsonb(repeat('😀',256)))),'supplementary title counts Unicode codepoints');
select ok(not private.study_method_evidence_body_valid(jsonb_set(pg_temp.evidence_body(),'{title}',to_jsonb(repeat('研',257)))),'evidence title max-plus-one rejected');
select ok(private.study_method_evidence_body_valid(jsonb_set(pg_temp.evidence_body(),'{statement}',to_jsonb(repeat('研',8192)))),'evidence statement limit counts Unicode codepoints');
select ok(not private.study_method_evidence_body_valid(jsonb_set(pg_temp.evidence_body(),'{statement}',to_jsonb(repeat('研',8193)))),'evidence statement max-plus-one rejected');
select ok(not private.study_method_evidence_body_valid(jsonb_set(pg_temp.evidence_body(),'{title}',to_jsonb(U&'C1\0085control'::text))),'C1 control rejected before evidence registration');

select ok(not has_table_privilege('authenticated','private.study_method_assessments','SELECT') and not has_table_privilege('service_role','private.study_method_evidence','INSERT'),'method raw relation access closed');
select ok((select relrowsecurity and relforcerowsecurity from pg_class where oid='private.study_method_assessments'::regclass),'method records force RLS');
select ok(not has_function_privilege('authenticated','api.svc_study_method_assessment_complete_v1(uuid,uuid,uuid,jsonb,text)','EXECUTE'),'completion service only');
select pg_temp.study894_claim(1);
select is(api.cmd_study_method_v1(pg_temp.method_request('off'))->>'code','CAPABILITY_UNAVAILABLE','method gate default off');
select is(api.qry_study_method_v1(pg_temp.v6('capability.read'))->'data'->'methodProfiles','[]'::jsonb,'disabled capability has no method profile');
select is((select count(*)from private.study_method_assessments),0::bigint,'disabled request creates no placeholder');
select pg_temp.study894_claim(null,null,true);
select is(api.svc_study_method_configure_v1(1,'{"executionEnabled":true,"reportEnabled":false,"maxEvidenceRefs":128,"maxSelectedFactorRecords":8192,"qualificationEvidenceRef":null}')->>'code','INVALID_REQUEST','null qualification cannot enable method');
select ok((api.svc_study_method_configure_v1(1,'{"executionEnabled":true,"reportEnabled":false,"maxEvidenceRefs":128,"maxSelectedFactorRecords":8192,"qualificationEvidenceRef":"owned.sql.synthetic-only"}')->>'ok')::boolean,'service selects bounded qualification config');
select is(api.svc_study_method_configure_v1(1,'{"executionEnabled":false,"reportEnabled":false,"maxEvidenceRefs":null,"maxSelectedFactorRecords":null,"qualificationEvidenceRef":null}')->>'code','REVISION_CONFLICT','config CAS is current');
select pg_temp.study894_claim(2);
select is(api.cmd_study_method_v1(pg_temp.method_request('foreign'))->>'code','FORBIDDEN','foreign actor denied');
select pg_temp.study894_claim(1);
select ok((pg_temp.keep('evidence-intent',pg_temp.method_cmd('method.evidence.create',jsonb_build_object('studyId','89400000-0000-4000-8000-000000000010','content',pg_temp.evidence_body()),'evidence-create'))->>'ok')::boolean,'evidence creates opaque producer intent');
select is((select count(*)from private.study_method_evidence),0::bigint,'no evidence row before immutable producer registration');
select pg_temp.study894_claim(null,null,true);
select ok((pg_temp.keep('evidence-context',api.svc_study_method_evidence_intent_resolve_v1((pg_temp.val('evidence-intent')->'data'->>'intentId')::uuid))->>'ok')::boolean,'service resolves exact evidence intent');
select ok(pg_temp.val('evidence-context')->'data' ?& array['request','studyId','actorId','clientId','evidenceId','artifactId','contentHash','byteSize','recordedAt'],'evidence context carries exact identity and canonical-byte binding');
create function pg_temp.evidence_completion(p_bad boolean default false,p_context_key text default 'evidence-context') returns jsonb language sql as $$select jsonb_build_object('artifact',jsonb_build_object('artifactRef',jsonb_build_object('type','methodEvidence','id',pg_temp.val(p_context_key)->'data'->>'artifactId','contentHash',case when p_bad then repeat('a',64)else pg_temp.val(p_context_key)->'data'->>'contentHash'end,'digestScope','artifact_bytes_sha256','byteSize',pg_temp.val(p_context_key)->'data'->'byteSize','mediaType','application/json','schemaVersion','lca.study-method-evidence.v1'),
 'storageBucket','study-artifacts','storageObjectPath','study/89400000-0000-4000-8000-000000000010/'||(pg_temp.val(p_context_key)->'data'->>'artifactId')||'/evidence.json'))$$;
select is(api.svc_study_method_evidence_intent_consume_v1((pg_temp.val('evidence-intent')->'data'->>'intentId')::uuid,pg_temp.evidence_completion(true))->>'code','REFERENCE_MISMATCH','wrong evidence byte hash rejected before registration');
select ok((pg_temp.keep('evidence',api.svc_study_method_evidence_intent_consume_v1((pg_temp.val('evidence-intent')->'data'->>'intentId')::uuid,pg_temp.evidence_completion()))->>'ok')::boolean,'canonical evidence bytes registered');
select is(pg_temp.val('evidence')->'data'->'value'->>'status','recorded_unverified','professional declaration remains unverified');
select is(api.svc_study_method_evidence_intent_consume_v1((pg_temp.val('evidence-intent')->'data'->>'intentId')::uuid,pg_temp.evidence_completion()),pg_temp.val('evidence'),'exact evidence consume recovers original');
select is(api.svc_study_method_evidence_intent_reconcile_v1((pg_temp.val('evidence-intent')->'data'->>'intentId')::uuid,(pg_temp.val('evidence-context')->'data'->>'artifactId')::uuid,pg_temp.val('evidence-context')->'data'->>'contentHash')->'data'->>'state','committed','evidence reconciliation proves exact attachment');
select pg_temp.study894_claim(1);
select is(pg_temp.method_cmd('method.evidence.create',jsonb_build_object('studyId','89400000-0000-4000-8000-000000000010','content',pg_temp.evidence_body()),'evidence-create'),pg_temp.val('evidence'),'actor retry recovers committed evidence after two-phase intent');
select is(api.qry_study_method_v1(pg_temp.v6('method.evidence.read',jsonb_build_object('evidenceId',pg_temp.val('evidence')->'data'->'value'->'evidenceId'))),pg_temp.val('evidence'),'actor reads registered evidence metadata only');
select ok((pg_temp.keep('method',api.cmd_study_method_v1(pg_temp.method_request('method')))->>'ok')::boolean,'owner admits distinct method job');
select is(api.cmd_study_method_v1(pg_temp.method_request('method')),pg_temp.val('method'),'same intent returns same assessment and job');
select is(api.cmd_study_method_v1(pg_temp.method_request('method',jsonb_set(pg_temp.method_config(),'{declarations,studyPhase}','"screening"')))->>'code','IDEMPOTENCY_CONFLICT','changed declaration cannot reuse key');
-- Action discovery must agree with actual cancellation authority, including
-- cleanup after admission/source withdrawal and archival. Every probe rolls back
-- its role/state/cancellation changes while retaining its observed DTO.
insert into private.oauth_client_registry(client_id,client_kind,enabled)
 values('study912-action-readonly','manual',true);
insert into private.oauth_client_capability_grants(client_id,capability_id)
 values('study912-action-readonly','STUDY-READ-01'),('study912-action-readonly','DB-CORE-READ-01');
create function pg_temp.method_action_case(p_state text,p_role text,p_readonly boolean) returns jsonb
language plpgsql as $$declare actions jsonb;cancel jsonb;begin
 begin
  update private.study_members set role=p_role where study_id='89400000-0000-4000-8000-000000000010' and actor_id='89400000-0000-4000-8000-000000000001';
  if p_state='admission_off' then update private.study_method_config set execution_enabled=false;end if;
  if p_state='source_withdrawn' then update public.lifecyclemodels set state_code=20 where id='89400000-0000-4000-8000-000000000101';end if;
  if p_state='archived' then update private.studies set status='archived' where id='89400000-0000-4000-8000-000000000010';end if;
  perform pg_temp.study894_claim(1,case when p_readonly then 'study912-action-readonly' end);
  actions:=api.qry_study_method_v1(pg_temp.v6('resource.actions',jsonb_build_object('resource',jsonb_build_object('type','methodAssessment','id',pg_temp.mid()))));
  cancel:=pg_temp.method_cmd('task.cancel',jsonb_build_object('studyId','89400000-0000-4000-8000-000000000010','resource',jsonb_build_object('type','methodAssessment','id',pg_temp.mid()),'reason','Action authority matrix'),'action-matrix');
  raise exception using errcode='ZX912',message='rollback action authority probe';
 exception when sqlstate 'ZX912' then null;end;
 return jsonb_build_object('ok',actions->'ok','actions',actions->'data'->'actions','corePermissions',actions->'data'->'corePermissions',
  'allowedMemberRoles',actions->'data'->'allowedMemberRoles','cancelOk',cancel->'ok','cancelCode',cancel->'code');
end$$;
with cases as materialized(select state,member_role,readonly,pg_temp.method_action_case(state,member_role,readonly) observed
 from unnest(array['active','admission_off','source_withdrawn','archived'])state
 cross join unnest(array['owner','editor','viewer'])member_role cross join unnest(array[false,true])readonly)
select is(observed,jsonb_build_object('ok',true,
 'actions','["task.read"]'::jsonb||case when member_role in('owner','editor') and not readonly then '["task.cancel"]'::jsonb else '[]'::jsonb end||case when state<>'source_withdrawn' then '["method.assessment.read"]'::jsonb else '[]'::jsonb end,
 'corePermissions',jsonb_build_object('read',true,'write',member_role in('owner','editor') and not readonly and state<>'archived'),
 'allowedMemberRoles','[]'::jsonb,'cancelOk',member_role in('owner','editor') and not readonly,'cancelCode',case when member_role='viewer' or readonly then 'FORBIDDEN' end),
 'actual method actions/cancel/core permissions: '||state||'/'||member_role||case when readonly then '/readonly-client' else '/first-party' end)
from cases;
select pg_temp.study894_claim(null,null,true);
select pg_temp.keep('method-claim',private.worker_claim_jobs('solver','study912-sql',1,900));
select ok((pg_temp.keep('method-input',api.svc_study_method_assessment_read_input_v1(pg_temp.mid(),pg_temp.mjob(),pg_temp.mlease()))->>'ok')::boolean,'canonical current lease resolves source-bound method input');
select is(pg_temp.val('method-input')->'data'->>'schemaVersion','lca.study-method-job-context.v1','budget wrapper family exact');
select is(pg_temp.val('method-input')->'data'->'input'->>'schemaVersion','lca.study-method-assessment-input.v1','inner frozen input family unchanged');
select is(pg_temp.val('method-input')->'data'->'budget','{"maxSelectedFactorRecords":8192,"maxFactsBytes":4194304}'::jsonb,'admitted immutable selected-factor budget returned');
select is(pg_temp.val('method-input')->'data'->'input'->'baseline'->'run'->>'runId','90400000-0000-4000-8000-000000000012','exact original baseline retained');
select is(api.svc_study_method_assessment_read_input_v1(pg_temp.mid(),pg_temp.mjob(),gen_random_uuid())->>'code','FORBIDDEN','foreign lease denied');
select is(api.svc_study_analysis_advanced_read_input_v1(pg_temp.mid(),pg_temp.mjob(),pg_temp.mlease())->>'code','REFERENCE_MISMATCH','V5 producer cannot interpret method job');
savepoint method_withdrawn;
update public.lifecyclemodels set state_code=20 where id='89400000-0000-4000-8000-000000000101';
select is(api.svc_study_method_assessment_read_input_v1(pg_temp.mid(),pg_temp.mjob(),pg_temp.mlease())->>'code','DISCLOSURE_DENIED','source withdrawal denies private input');
select is(api.svc_study_method_assessment_complete_v1(pg_temp.mid(),pg_temp.mjob(),pg_temp.mlease(),pg_temp.method_completion(pg_temp.val('method')->'data'->'value'->>'configHash'),'method-complete')->>'code','DISCLOSURE_DENIED','source withdrawal fences complete');
update private.study_method_config set execution_enabled=false;
select pg_temp.study894_claim(1);
select ok((api.qry_study_method_v1(pg_temp.v6('task.read',jsonb_build_object('studyId','89400000-0000-4000-8000-000000000010','resource',jsonb_build_object('type','methodAssessment','id',pg_temp.mid()))))->>'ok')::boolean,'minimal status remains under source withdrawal and admission off');
select is(api.qry_study_method_v1(pg_temp.v6('method.assessment.read',jsonb_build_object('assessmentId',pg_temp.mid())))->>'code','DISCLOSURE_DENIED','full method record still requires source rights');
select ok((pg_temp.method_cmd('task.cancel',jsonb_build_object('studyId','89400000-0000-4000-8000-000000000010','resource',jsonb_build_object('type','methodAssessment','id',pg_temp.mid()),'reason','Owned cancellation after withdrawal'),'method-cancel')->>'ok')::boolean,'cleanup cancellation survives source withdrawal and admission off');
rollback to method_withdrawn;
select pg_temp.study894_claim(null,null,true);
select is(api.svc_study_method_assessment_complete_v1(pg_temp.mid(),pg_temp.mjob(),pg_temp.mlease(),jsonb_set(pg_temp.method_completion(pg_temp.val('method')->'data'->'value'->>'configHash'),'{selectedFactorRecordCount}','8193'),'over-factor-count')->>'code','REFERENCE_MISMATCH','complete cannot exceed admitted selected factor ceiling');
select ok((pg_temp.keep('method-completed',api.svc_study_method_assessment_complete_v1(pg_temp.mid(),pg_temp.mjob(),pg_temp.mlease(),pg_temp.method_completion(pg_temp.val('method')->'data'->'value'->>'configHash'),'method-complete'))->>'ok')::boolean,'completion atomically registers distinct method facts and terminal receipt');
select is(api.svc_study_method_assessment_complete_v1(pg_temp.mid(),pg_temp.mjob(),pg_temp.mlease(),pg_temp.method_completion(pg_temp.val('method')->'data'->'value'->>'configHash'),'method-complete'),pg_temp.val('method-completed'),'exact completed receipt replay succeeds');
select is(api.svc_study_task_reconcile_v1('methodAssessment',pg_temp.mid(),pg_temp.mjob(),pg_temp.mlease(),'method-complete')->'data'->>'state','committed','generic exact method reconciliation recovers terminal receipt');
select is(api.svc_study_task_reconcile_v1('methodAssessment',gen_random_uuid(),pg_temp.mjob(),pg_temp.mlease(),'method-complete')->>'code','REFERENCE_MISMATCH','generic dispatch rejects wrong method resource');
select throws_ok('update private.study_method_assessments set config_hash=repeat(''a'',64)','P0001','FROZEN_REVISION','issued method configuration immutable');
select pg_temp.study894_claim(1);
select ok((pg_temp.keep('method-read',api.qry_study_method_v1(pg_temp.v6('method.assessment.read',jsonb_build_object('assessmentId',pg_temp.mid()))))->>'ok')::boolean,'current owner reads complete method metadata');
select ok(not(pg_temp.val('method-read')->'data'->'value' ?|array['storageBucket','storageObjectPath','requestedBy','requestedClientId','sourceAuthorization']),'public method record carries no private locator/authority');
select is(api.qry_study_advanced_v1(jsonb_set(pg_temp.v6('method.assessment.read',jsonb_build_object('assessmentId',pg_temp.mid())),'{schemaVersion}','"lca.study-api.v5"'))->>'code','CAPABILITY_UNAVAILABLE','old V5 cannot read method family');
select is(api.qry_study_advanced_v1(jsonb_set(pg_temp.v6('task.read',jsonb_build_object('studyId','89400000-0000-4000-8000-000000000010','resource',jsonb_build_object('type','methodAssessment','id',pg_temp.mid()))),'{schemaVersion}','"lca.study-api.v5"'))->>'code','INVALID_REQUEST','old V5 task grammar excludes method resource');
update private.study_runtime_config set disclosure_enabled=true;
select ok((pg_temp.keep('method-artifact',api.qry_study_method_v1(pg_temp.v6('artifact.read',jsonb_build_object('studyId','89400000-0000-4000-8000-000000000010','artifactRef',pg_temp.val('method-completed')->'data'->'value'->'factsRef'))))->>'ok')::boolean,'method artifact gets separate family opaque intent');
select is(api.qry_study_advanced_v1(jsonb_set(pg_temp.v6('artifact.read',jsonb_build_object('studyId','89400000-0000-4000-8000-000000000010','artifactRef',pg_temp.val('method-completed')->'data'->'value'->'factsRef')),'{schemaVersion}','"lca.study-api.v5"'))->>'code','DISCLOSURE_DENIED','old V5 artifact path refuses method facts');
select pg_temp.study894_claim(null,null,true);
select ok((api.svc_study_artifact_read_resolve_v1((pg_temp.val('method-artifact')->'data'->>'intentId')::uuid)->>'ok')::boolean,'generic artifact resolver rechecks exact method family authority');

select pg_temp.study894_claim(1);
create function pg_temp.config_with_evidence() returns jsonb language sql as $$select jsonb_set(pg_temp.method_config(),'{evidenceRefs}',jsonb_build_array(jsonb_build_object('requirementId','PEF-01','declaredKind','professionalRecord','artifactRef',pg_temp.val('evidence')->'data'->'value'->'artifactRef')))$$;
select ok((pg_temp.keep('method-with-evidence',api.cmd_study_method_v1(pg_temp.method_request('with-evidence',pg_temp.config_with_evidence())))->>'ok')::boolean,'registered declared evidence admitted without professional approval');
select is(pg_temp.val('method-with-evidence')->'data'->'value'->'config'->'evidenceRefs',pg_temp.config_with_evidence()->'evidenceRefs','exact evidence reference retained in immutable config');
select is(api.cmd_study_method_v1(pg_temp.method_request('unregistered-evidence',jsonb_set(pg_temp.config_with_evidence(),'{evidenceRefs,0,artifactRef,id}','"91200000-0000-4000-8000-000000000099"')))->>'code','REFERENCE_MISMATCH','arbitrary caller evidence ref cannot stand in for registered evidence');
select is(api.cmd_study_method_v1(pg_temp.method_request('wrong-evidence-kind',jsonb_set(pg_temp.config_with_evidence(),'{evidenceRefs,0,declaredKind}','"sourceRecord"')))->>'code','REFERENCE_MISMATCH','evidence kind must match its registered record');
select is(api.cmd_study_method_v1(pg_temp.method_request('wrong-evidence-requirement',jsonb_set(pg_temp.config_with_evidence(),'{evidenceRefs,0,requirementId}','"PEF-02"')))->>'code','REFERENCE_MISMATCH','evidence requirement must match its registered record');
select pg_temp.study894_claim(2);
select is(api.qry_study_method_v1(pg_temp.v6('method.evidence.read',jsonb_build_object('evidenceId',pg_temp.val('evidence')->'data'->'value'->'evidenceId')))->>'code','FORBIDDEN','foreign actor cannot read declared evidence metadata');
select pg_temp.study894_claim(1);
select ok(not private.study_method_config_valid(jsonb_set(pg_temp.config_with_evidence(),'{evidenceRefs}',(pg_temp.config_with_evidence()->'evidenceRefs')||(pg_temp.config_with_evidence()->'evidenceRefs'))),'duplicate evidence reference pair rejected');
select ok((pg_temp.keep('app-evidence-intent',pg_temp.method_cmd('method.evidence.create',jsonb_build_object('studyId','89400000-0000-4000-8000-000000000010','content',jsonb_set(pg_temp.evidence_body(),'{declaredKind}','"applicabilityRecord"')),'app-evidence-create'))->>'ok')::boolean,'applicability declaration gets distinct evidence identity');
select pg_temp.study894_claim(null,null,true);
select pg_temp.keep('app-evidence-context',api.svc_study_method_evidence_intent_resolve_v1((pg_temp.val('app-evidence-intent')->'data'->>'intentId')::uuid));
select ok((pg_temp.keep('app-evidence',api.svc_study_method_evidence_intent_consume_v1((pg_temp.val('app-evidence-intent')->'data'->>'intentId')::uuid,pg_temp.evidence_completion(false,'app-evidence-context')))->>'ok')::boolean,'applicability evidence recorded without approval');
create function pg_temp.category_config(p_artifact_identity boolean default false) returns jsonb language sql as $$select jsonb_set(jsonb_set(pg_temp.method_config(),'{evidenceRefs}',jsonb_build_array(jsonb_build_object('requirementId','PEF-01','declaredKind','applicabilityRecord','artifactRef',pg_temp.val('app-evidence')->'data'->'value'->'artifactRef'))),'{declarations,categoryRule}',jsonb_build_object('kind','commissionDeveloped','referenceId','Declared category rule','version','candidate-v1','evidenceId',case when p_artifact_identity then pg_temp.val('app-evidence')->'data'->'value'->'artifactRef'->'id'else pg_temp.val('app-evidence')->'data'->'value'->'evidenceId'end))$$;
select pg_temp.study894_claim(1);
select ok((api.cmd_study_method_v1(pg_temp.method_request('category-rule-record',pg_temp.category_config()))->>'ok')::boolean,'category declaration binds logical same-Study applicability evidence record');
select is(api.cmd_study_method_v1(pg_temp.method_request('category-rule-artifact-alias',pg_temp.category_config(true)))->>'code','REFERENCE_MISMATCH','artifact UUID cannot substitute for logical evidence record identity');
select is(api.cmd_study_method_v1(pg_temp.method_request('category-rule-wrong-kind',jsonb_set(pg_temp.config_with_evidence(),'{declarations,categoryRule}',jsonb_build_object('kind','commissionDeveloped','referenceId','Unverified reference','version','candidate-v1','evidenceId',pg_temp.val('evidence')->'data'->'value'->'evidenceId'))))->>'code','REFERENCE_MISMATCH','professional-record label cannot substitute for category applicability declaration');
select pg_temp.study894_claim(null,null,true);

-- Method report bindings and producer metadata. No content/HTML/signature bytes are fabricated as actual proof.
create function pg_temp.method_report_draft(p_title text default 'Source-bound method assessment') returns jsonb language sql as $$select jsonb_build_object(
 'schemaVersion','lca.study-method-report-draft.v1','title',p_title,'claims',jsonb_build_array(jsonb_build_object('claimId','method-category','bundleRef',pg_temp.val('method-completed')->'data'->'value'->'factsRef','factId','category:sql-method:characterised','canonicalValue','1','unit','kg','display',jsonb_build_object('style','exact'))),
 'sections',jsonb_build_array(jsonb_build_object('sectionId','scope','title','Machine and professional states','paragraphs',jsonb_build_array('Mandatory method requirements and professional states are generated from exact facts; no scientific approval is claimed.'),'claimIds',jsonb_build_array('method-category'))),
 'tables','[]'::jsonb,'charts','[]'::jsonb,'additionalLimitations',jsonb_build_array('SQL metadata fixture only.'))$$;
create function pg_temp.method_report_request(p_key text) returns jsonb language sql as $$select pg_temp.v6('report.create',jsonb_build_object('idempotencyKey',p_key,'studyId','89400000-0000-4000-8000-000000000010','parentReportRevisionId',null,
 'runIds',jsonb_build_array('90400000-0000-4000-8000-000000000012'),'methodAssessmentIds',jsonb_build_array(pg_temp.mid()),'templateId','lca.study-method-report.v1','content',pg_temp.method_report_draft()),p_key)$$;
create function pg_temp.method_report_artifact(p_context jsonb,p_hash text) returns jsonb language sql as $$select jsonb_build_object('studyId',p_context->'studyId','artifactRef',jsonb_build_object('type','reportContent','id',p_context->>'contentArtifactId','contentHash',p_hash,'digestScope','artifact_bytes_sha256','byteSize',2,'mediaType','application/json','schemaVersion','lca.study-method-report-content.v1'),
 'storageBucket','study-artifacts','storageObjectPath','study/'||(p_context->>'studyId')||'/'||(p_context->>'contentArtifactId')||'/content.json')$$;
create function pg_temp.method_report_validation(p_context jsonb,p_hash text) returns jsonb language sql as $$select jsonb_build_object('schemaVersion','lca.study-method-report-validation.v1','profileId','lca.study-method-report-claims.v1','reportRevisionId',p_context->>'reportRevisionId','contentHash',p_hash,'claimCount',1,'factsBindingHash',p_context->>'factsBindingHash',
 'methodAssessmentId',p_context->'methodAssessments'->0->'assessment'->>'assessmentId','configHash',p_context->'methodAssessments'->0->'assessment'->>'configHash','requirementCount',20,'categoryCount',25,'factCount',58)$$;
create function pg_temp.method_report_completion(p_context jsonb,p_hash text) returns jsonb language sql as $$select jsonb_build_object('kind','validatedContent','contentArtifact',pg_temp.method_report_artifact(p_context,p_hash),'factsRefs',jsonb_build_array(pg_temp.val('method-completed')->'data'->'value'->'factsRef'),'validation',pg_temp.method_report_validation(p_context,p_hash))$$;
create function pg_temp.mrid() returns uuid language sql as $$select(pg_temp.val('method-report')->'data'->'value'->>'reportRevisionId')::uuid$$;
create function pg_temp.method_review_cmd(p_op text,p_fields jsonb default '{}',p_key text default 'request') returns jsonb language sql as $$select api.cmd_study_method_review_v1(pg_temp.v6(p_op,p_fields,p_key)||jsonb_build_object('idempotencyKey',p_key))$$;
select pg_temp.study894_claim(1);
select is(api.cmd_study_method_v1(pg_temp.method_report_request('method-report-off'))->>'code','CAPABILITY_UNAVAILABLE','report admission default off separately');
select pg_temp.study894_claim(null,null,true);
select ok((api.svc_study_method_configure_v1(2,'{"executionEnabled":true,"reportEnabled":true,"maxEvidenceRefs":128,"maxSelectedFactorRecords":8192,"qualificationEvidenceRef":"owned.sql.report-only"}')->>'ok')::boolean,'method report qualification independently enabled');
select pg_temp.study894_claim(1);
select ok((pg_temp.keep('method-report-intent',api.cmd_study_method_v1(pg_temp.method_report_request('method-report')))->>'ok')::boolean,'method report authoring issues opaque exact intent');
select is((select count(*)from private.study_report_revisions where template_id='lca.study-method-report.v1'),0::bigint,'no report row before validated byte registration');
select is(api.cmd_study_advanced_v1(jsonb_set(pg_temp.method_report_request('wrong-family'),'{schemaVersion}','"lca.study-api.v5"'))->>'code','INVALID_REQUEST','V5 cannot create method report through wrong family');
select pg_temp.study894_claim(null,null,true);
select ok((pg_temp.keep('method-report-context',api.svc_study_report_method_intent_resolve_v1((pg_temp.val('method-report-intent')->'data'->>'intentId')::uuid))->>'ok')::boolean,'method report resolver issues protected exact context');
select is(pg_temp.val('method-report-context')->'data'->>'kind','reportMethodCommandContext','context discriminates method producer');
select is(pg_temp.val('method-report-context')->'data'->'request',pg_temp.method_report_request('method-report'),'producer retains exact original public V6 request');
select is(pg_temp.val('method-report-context')->'data'->'methodAssessments'->0->'assessment'->>'assessmentId',pg_temp.mid()::text,'producer binds exact completed method assessment');
select ok(pg_temp.val('method-report-context')->'data'->'methodAssessments'->0 ? 'sourceSnapshotRef','producer binds registered source snapshot reference separately');
select is(api.svc_study_report_advanced_intent_resolve_v1((pg_temp.val('method-report-intent')->'data'->>'intentId')::uuid)->>'code','CAPABILITY_UNAVAILABLE','old service cannot resolve method report intent');
select is(api.svc_study_report_method_intent_consume_v1((pg_temp.val('method-report-intent')->'data'->>'intentId')::uuid,jsonb_set(pg_temp.method_report_completion(pg_temp.val('method-report-context')->'data',repeat('b',64)),'{validation,requirementCount}','19'))->>'code','REFERENCE_MISMATCH','missing mandatory requirement count rejected before report registration');
select is(api.svc_study_report_method_intent_consume_v1((pg_temp.val('method-report-intent')->'data'->>'intentId')::uuid,jsonb_set(pg_temp.method_report_completion(pg_temp.val('method-report-context')->'data',repeat('b',64)),'{validation,categoryCount}','24'))->>'code','REFERENCE_MISMATCH','missing category count rejected');
select is(api.svc_study_report_method_intent_consume_v1((pg_temp.val('method-report-intent')->'data'->>'intentId')::uuid,jsonb_set(pg_temp.method_report_completion(pg_temp.val('method-report-context')->'data',repeat('b',64)),'{validation,factCount}','57'))->>'code','REFERENCE_MISMATCH','missing catalog count rejected');
select is(api.svc_study_report_method_intent_consume_v1((pg_temp.val('method-report-intent')->'data'->>'intentId')::uuid,jsonb_set(pg_temp.method_report_completion(pg_temp.val('method-report-context')->'data',repeat('b',64)),'{validation,methodAssessmentId}',to_jsonb(gen_random_uuid())))->>'code','REFERENCE_MISMATCH','cross-assessment validation rejected');
select is(api.svc_study_report_method_intent_consume_v1((pg_temp.val('method-report-intent')->'data'->>'intentId')::uuid,jsonb_set(pg_temp.method_report_completion(pg_temp.val('method-report-context')->'data',repeat('b',64)),'{validation,configHash}',to_jsonb(repeat('0',64))))->>'code','REFERENCE_MISMATCH','wrong frozen configuration hash rejected');
select is(api.svc_study_report_method_intent_consume_v1((pg_temp.val('method-report-intent')->'data'->>'intentId')::uuid,jsonb_set(pg_temp.method_report_completion(pg_temp.val('method-report-context')->'data',repeat('b',64)),'{validation,factsBindingHash}',to_jsonb(repeat('0',64))))->>'code','REFERENCE_MISMATCH','wrong baseline and facts binding hash rejected');
select is(api.svc_study_report_method_intent_consume_v1((pg_temp.val('method-report-intent')->'data'->>'intentId')::uuid,jsonb_set(pg_temp.method_report_completion(pg_temp.val('method-report-context')->'data',repeat('b',64)),'{validation,professionalApproved}','true'))->>'code','REFERENCE_MISMATCH','unknown professional approval field cannot become validation authority');
select ok((pg_temp.keep('method-report',api.svc_study_report_method_intent_consume_v1((pg_temp.val('method-report-intent')->'data'->>'intentId')::uuid,pg_temp.method_report_completion(pg_temp.val('method-report-context')->'data',repeat('b',64))))->>'ok')::boolean,'validated method content registers atomic report row');
select ok(not(pg_temp.val('method-report')->'data'->'value' ? 'analysisIds'),'public method report does not relabel assessment as analysis');
select is(pg_temp.val('method-report')->'data'->'value'->'methodAssessmentIds',jsonb_build_array(pg_temp.mid()),'public method report retains separate assessment selection');
select is((select analysis_ids from private.study_report_revisions where id=pg_temp.mrid()),'[]'::jsonb,'legacy analysis association remains empty on method report');
select pg_temp.study894_claim(1);
select is(api.cmd_study_method_v1(pg_temp.method_report_request('method-report')),pg_temp.val('method-report'),'actor same-key recovery returns committed report');
select ok((pg_temp.keep('method-freeze-intent',pg_temp.method_cmd('report.freeze',jsonb_build_object('target',jsonb_build_object('type','reportRevision','id',pg_temp.mrid(),'expectedRevision',1),'expectedContentHash',repeat('b',64)),'method-freeze'))->>'ok')::boolean,'exact method draft freeze admitted');
select pg_temp.study894_claim(null,null,true);
select pg_temp.keep('method-freeze-context',api.svc_study_report_method_intent_resolve_v1((pg_temp.val('method-freeze-intent')->'data'->>'intentId')::uuid));
select ok((pg_temp.keep('method-frozen',api.svc_study_report_method_intent_consume_v1((pg_temp.val('method-freeze-intent')->'data'->>'intentId')::uuid,jsonb_build_object('kind','validatedFreeze','contentRef',pg_temp.val('method-report')->'data'->'value'->'contentRef','validation',pg_temp.method_report_validation(pg_temp.val('method-freeze-context')->'data',repeat('b',64)))))->>'ok')::boolean,'method freeze uses exact original content identity and mandatory counts');
select is(pg_temp.val('method-frozen')->'data'->'value'->>'status','frozen','method report status frozen');
select throws_ok('update private.study_report_revisions set method_assessment_ids=''[]''::jsonb where id=pg_temp.mrid()','P0001','FROZEN_REVISION','frozen method association immutable');
select pg_temp.study894_claim(1);
select is(api.qry_study_advanced_v1(jsonb_set(pg_temp.v6('report.read',jsonb_build_object('reportRevisionId',pg_temp.mrid())),'{schemaVersion}','"lca.study-api.v5"'))->>'code','FORBIDDEN','old V5 direct report lookup rejects method family');
select is(api.qry_study_review_v1(pg_temp.req('report.current',jsonb_build_object('reportRevisionId',pg_temp.mrid(),'expectedContentHash',repeat('b',64))))->>'code','FORBIDDEN','old V4 indirect review rejects method family');
select is(api.qry_study_advanced_review_v1(jsonb_set(pg_temp.v6('report.current',jsonb_build_object('reportRevisionId',pg_temp.mrid(),'expectedContentHash',repeat('b',64))),'{schemaVersion}','"lca.study-api.v5"'))->>'code','FORBIDDEN','old V5 indirect review rejects method family');
select is(api.qry_study_method_review_v1(pg_temp.v6('capability.read'))->'data'->>'runtimeEnabled','false','method review default off');
select pg_temp.study894_claim(null,null,true);
select ok((api.svc_study_review_method_configure_v1(1,jsonb_build_object('qualificationVersion','lca.study-method-review-qualification.v1','enabled',true,'exportEnabled',true,'exportProfile',jsonb_build_object('issuerId','study912-sql','keyId','study912-sql-key','rendererVersion','3.0.0','viewModelVersion','lca.study-report-view.v3','rendererArtifactHash',repeat('a',64),'policyId','lca.study-report-disclosure.v1'),'evidenceRef','owned.sql.review-metadata-only'))->>'ok')::boolean,'separate method review/export qualification bound to renderer3');
update private.study_review_config set enabled=true;
select pg_temp.study894_claim(1);
select ok((pg_temp.cmd('member.set',jsonb_build_object('target',jsonb_build_object('type','study','id','89400000-0000-4000-8000-000000000010','expectedRevision',(select revision from private.studies where id='89400000-0000-4000-8000-000000000010')),'memberId','89400000-0000-4000-8000-000000000002','role','reviewer'),'method-reviewer')->>'ok')::boolean,'retained V4 independently grants report reviewer');
select is(pg_temp.method_review_cmd('member.set','{}','method-no-member')->>'code','CAPABILITY_UNAVAILABLE','V6 exposes no duplicate Study membership operation');
select pg_temp.study894_claim(2);
select ok((pg_temp.keep('method-review',pg_temp.method_review_cmd('review.record',jsonb_build_object('reportRevisionId',pg_temp.mrid(),'expectedContentHash',repeat('b',64),'reviewClass','internal','decision','approve','comment','Internal actor review; not scientific approval','predecessorReviewId',null,'delegationId',null),'method-approve'))->>'ok')::boolean,'method report permits exact first-party internal review');
select ok((pg_temp.keep('method-preview-intent',api.qry_study_method_review_v1(pg_temp.v6('report.view',jsonb_build_object('reportRevisionId',pg_temp.mrid(),'expectedContentHash',repeat('b',64)))))->>'ok')::boolean,'report-only reviewer receives opaque preview intent');
select pg_temp.study894_claim(null,null,true);
select ok((pg_temp.keep('method-preview-context',api.svc_study_review_method_intent_resolve_v1((pg_temp.val('method-preview-intent')->'data'->>'intentId')::uuid))->>'ok')::boolean,'review preview resolves protected producer context');
select is(pg_temp.val('method-preview-context')->'data'->'producerContext'->>'operation','report.view','preview does not impersonate export request');
select is(pg_temp.val('method-preview-context')->'data'->'producerContext'->'request',pg_temp.val('method-preview-context')->'data'->'request','preview keeps exact original V6 view request');
select is(pg_temp.val('method-preview-context')->'data'->'producerContext'->'exportId','null'::jsonb,'preview allocates no export identity');
select is(pg_temp.val('method-preview-context')->'data'->'producerContext'->'projectionArtifactId','null'::jsonb,'preview allocates no projection artifact');
select is(pg_temp.val('method-preview-context')->'data'->'producerContext'->'factsBindingHash',pg_temp.val('method-report-context')->'data'->'factsBindingHash','report/view contexts bind identical immutable baseline and method facts');
select is(api.svc_study_review_advanced_intent_resolve_v1((pg_temp.val('method-preview-intent')->'data'->>'intentId')::uuid)->>'code','CAPABILITY_UNAVAILABLE','old V5 service cannot resolve new preview');
select pg_temp.study894_claim(3);
select is(api.qry_study_method_review_v1(pg_temp.v6('resource.actions',jsonb_build_object('resource',jsonb_build_object('type','reportRevision','id',pg_temp.mrid()))))->>'code','FORBIDDEN','foreign report action lookup denies without existence disclosure');
select pg_temp.study894_claim(1);
select is(pg_temp.method_review_cmd('review.record',jsonb_build_object('reportRevisionId',pg_temp.mrid(),'expectedContentHash',repeat('b',64),'reviewClass','internal','decision','approve','comment','Self approval denied','predecessorReviewId',null,'delegationId',null),'method-self')->>'code','FORBIDDEN','report author cannot self approve');
select pg_temp.keep('method-current',api.qry_study_method_review_v1(pg_temp.v6('report.current',jsonb_build_object('reportRevisionId',pg_temp.mrid(),'expectedContentHash',repeat('b',64)))));
select ok((pg_temp.keep('method-finalization',pg_temp.method_review_cmd('report.finalize',jsonb_build_object('target',jsonb_build_object('type','reportRevision','id',pg_temp.mrid(),'expectedRevision',2),'expectedContentHash',repeat('b',64),'expectedReviewStateHash',pg_temp.val('method-current')->'data'->'value'->>'reviewStateHash','profileId','lca.study-report-internal-review.v1','acceptedReviewIds',jsonb_build_array(pg_temp.val('method-review')->'data'->'value'->'reviewId')),'method-finalize'))->>'ok')::boolean,'method finalization binds exact qualifying internal review');
select pg_temp.keep('method-final-current',api.qry_study_method_review_v1(pg_temp.v6('report.current',jsonb_build_object('reportRevisionId',pg_temp.mrid(),'expectedContentHash',repeat('b',64)))));
select ok((pg_temp.keep('method-export-intent',pg_temp.method_review_cmd('export.request',jsonb_build_object('reportRevisionId',pg_temp.mrid(),'expectedContentHash',repeat('b',64),'finalizationId',pg_temp.val('method-finalization')->'data'->'value'->'finalizationId','expectedReviewStateHash',pg_temp.val('method-final-current')->'data'->'value'->>'reviewStateHash','rendererVersion','3.0.0','viewModelVersion','lca.study-report-view.v3'),'method-export'))->>'ok')::boolean,'method export requires current finalization and renderer3');
select pg_temp.study894_claim(null,null,true);
select ok((pg_temp.keep('method-export-context',api.svc_study_review_method_intent_resolve_v1((pg_temp.val('method-export-intent')->'data'->>'intentId')::uuid))->>'ok')::boolean,'method export resolves original exact producer request');
select is(pg_temp.val('method-export-context')->'data'->'producerContext'->'request',pg_temp.val('method-export-context')->'data'->'request','export inner request preserves finalization and review hash fields');
select is(pg_temp.val('method-export-context')->'data'->'producerContext'->>'operation','export.request','export context has actual export operation');
select ok(pg_temp.val('method-export-context')->'data'->'producerContext'->'request' ?& array['finalizationId','expectedReviewStateHash'],'new export producer has no legacy reduced pseudo-request');

create function pg_temp.produced(p_id text,p_type text,p_schema text,p_name text,p_hash text,p_size integer default 2) returns jsonb language sql as $$select jsonb_build_object('studyId','89400000-0000-4000-8000-000000000010','artifactRef',jsonb_build_object('type',p_type,'id',p_id,'contentHash',p_hash,'digestScope','artifact_bytes_sha256','byteSize',p_size,'mediaType','application/json','schemaVersion',p_schema),'storageBucket','study-artifacts','storageObjectPath','study/89400000-0000-4000-8000-000000000010/'||p_id||'/'||p_name||'.json')$$;
create function pg_temp.manifest() returns jsonb language sql as $$select jsonb_build_object('schemaVersion','lca.study-export-manifest.v4','issuerId','study912-sql','exportId',pg_temp.val('method-export-context')->'data'->'producerContext'->'exportId','studyId','89400000-0000-4000-8000-000000000010','reportRevisionId',pg_temp.val('method-export-context')->'data'->'currentState'->'reportRevisionId','reportContentHash',repeat('b',64),'actorId','89400000-0000-4000-8000-000000000001','clientId',pg_temp.val('method-export-context')->'data'->'clientId','grantEpoch',pg_temp.val('method-export-context')->'data'->'producerContext'->'grantEpoch','policyId','lca.study-report-disclosure.v1','disclosureContextHash',pg_temp.val('method-export-context')->'data'->'producerContext'->'disclosureContextHash','generatedAt',pg_temp.val('method-export-context')->'data'->'producerContext'->'generatedAt','validitySnapshot',pg_temp.val('method-export-context')->'data'->'producerContext'->'report'->'validitySnapshot','reviewIds',pg_temp.val('method-export-context')->'data'->'currentState'->'finalization'->'acceptedReviewIds','finalization',pg_temp.val('method-export-context')->'data'->'currentState'->'finalization','renderer',jsonb_build_object('version','3.0.0','viewModelVersion','lca.study-report-view.v3','artifactHash',repeat('a',64)),'files',jsonb_build_array(jsonb_build_object('path','report.html','mediaType','text/html','sha256',repeat('d',64),'byteSize',2),jsonb_build_object('path','projection.json','mediaType','application/json','sha256',repeat('e',64),'byteSize',2)))$$;
create function pg_temp.export_completion() returns jsonb language sql as $$select jsonb_build_object('kind','validatedReviewExport','projectionArtifact',pg_temp.produced(pg_temp.val('method-export-context')->'data'->'producerContext'->>'projectionArtifactId','reportProjection','lca.study-report-view.v3','projection',repeat('e',64)),'resourcesArtifact',pg_temp.produced(pg_temp.val('method-export-context')->'data'->'producerContext'->>'resourcesArtifactId','renderResources','lca.study-export-manifest.v4','resources',private.study_reporting_digest(null,pg_temp.manifest()),octet_length(private.study_reporting_canonical(pg_temp.manifest()))),'bundleArtifact',pg_temp.produced(pg_temp.val('method-export-context')->'data'->'producerContext'->>'bundleArtifactId','reportExportBundle','lca.study-export-bundle.v4','bundle',repeat('f',64)),'manifest',pg_temp.manifest(),'receipt',jsonb_build_object('schemaVersion','lca.study-export-receipt.v2','manifestHash',private.study_reporting_digest('lca.study-export-signature.v1',pg_temp.manifest()),'keyId','study912-sql-key','algorithm','Ed25519','signature',repeat('A',86)))$$;

select is(api.svc_study_review_intent_consume_v1((pg_temp.val('method-export-intent')->'data'->>'intentId')::uuid,pg_temp.export_completion())->>'code','CAPABILITY_UNAVAILABLE','old service consume cannot register method-family export');
select is(api.svc_study_review_method_intent_consume_v1((pg_temp.val('method-export-intent')->'data'->>'intentId')::uuid,jsonb_set(pg_temp.export_completion(),'{manifest,schemaVersion}','"lca.study-export-manifest.v2"'))->>'code','REFERENCE_MISMATCH','new service refuses old manifest family');
select is(api.svc_study_review_advanced_intent_consume_v1((pg_temp.val('method-export-intent')->'data'->>'intentId')::uuid,pg_temp.export_completion())->>'code','CAPABILITY_UNAVAILABLE','V5 service consume cannot register method export');
select is(api.svc_study_review_method_intent_consume_v1((pg_temp.val('method-export-intent')->'data'->>'intentId')::uuid,jsonb_set(pg_temp.export_completion(),'{manifest,schemaVersion}','"lca.study-export-manifest.v3"'))->>'code','REFERENCE_MISMATCH','method export cannot reuse closest previous manifest3');
select ok((pg_temp.keep('method-export',api.svc_study_review_method_intent_consume_v1((pg_temp.val('method-export-intent')->'data'->>'intentId')::uuid,pg_temp.export_completion()))->>'ok')::boolean,'synthetic manifest v4 binds exact renderer/finalization and registers export');
select is(pg_temp.val('method-export')->'data'->'value'->'resourcesRef'->>'schemaVersion','lca.study-export-manifest.v4','registered resources use manifest v4');
select is(pg_temp.val('method-export')->'data'->'value'->'bundleRef'->>'schemaVersion','lca.study-export-bundle.v4','registered bundle uses family v4');
select is(api.svc_study_review_method_intent_consume_v1((pg_temp.val('method-export-intent')->'data'->>'intentId')::uuid,'{}'),pg_temp.val('method-export'),'unknown outcome recovers exact immutable export');
select pg_temp.study894_claim(1);
select is(api.qry_study_review_v1(pg_temp.req('export.read',jsonb_build_object('exportId',pg_temp.val('method-export')->'data'->'value'->'exportId')))->>'code','FORBIDDEN','V4 direct export read refuses method bundle family');
select ok((api.qry_study_method_review_v1(pg_temp.v6('export.read',jsonb_build_object('exportId',pg_temp.val('method-export')->'data'->'value'->'exportId')))->>'ok')::boolean,'V5 direct export read uses negotiated family');
select ok((pg_temp.keep('method-share',pg_temp.method_review_cmd('share.create',jsonb_build_object('reportRevisionId',pg_temp.mrid(),'expectedContentHash',repeat('b',64),'exportId',pg_temp.val('method-export')->'data'->'value'->'exportId','recipientId','89400000-0000-4000-8000-000000000003','disclosurePolicyId','lca.study-report-summary-share.v1','expiresAt',clock_timestamp()+interval '1 hour'),'method-share'))->>'ok')::boolean,'method-family export can issue named bounded share');
select pg_temp.study894_claim(3);
select is(api.qry_study_review_v1(pg_temp.req('share.read',jsonb_build_object('shareId',pg_temp.val('method-share')->'data'->'value'->'shareId')))->>'code','FORBIDDEN','V4 indirect named share refuses advanced report');
select ok((api.qry_study_method_review_v1(pg_temp.v6('share.read',jsonb_build_object('shareId',pg_temp.val('method-share')->'data'->'value'->'shareId')))->>'ok')::boolean,'named recipient reads negotiated share metadata');
select is(api.qry_study_method_v1(pg_temp.v6('method.assessment.read',jsonb_build_object('assessmentId',pg_temp.mid())))->>'code','FORBIDDEN','summary recipient does not acquire raw Study/analysis authority');
select ok((pg_temp.keep('method-share-view',api.qry_study_method_review_v1(pg_temp.v6('share.view',jsonb_build_object('shareId',pg_temp.val('method-share')->'data'->'value'->'shareId'))))->>'ok')::boolean,'named recipient view receives opaque advanced-family intent');
select pg_temp.study894_claim(null,null,true);
select ok((pg_temp.keep('method-share-context',api.svc_study_review_method_intent_resolve_v1((pg_temp.val('method-share-view')->'data'->>'intentId')::uuid))->>'ok')::boolean,'share resolver rechecks original current recipient/share/client');
select is(pg_temp.val('method-share-context')->'data'->'artifact'->'artifactRef'->>'type','reportProjection','summary view receives only projection capability');
select ok(pg_temp.val('method-share-context')->'data'->'producerContext'='null'::jsonb,'recipient gets no private numerical producer context');
savepoint expired_share;
update private.study_report_shares set created_at=clock_timestamp()-interval '2 hours',expires_at=clock_timestamp()-interval '1 hour' where id=(pg_temp.val('method-share')->'data'->'value'->>'shareId')::uuid;
select is(api.svc_study_review_method_intent_resolve_v1((pg_temp.val('method-share-view')->'data'->>'intentId')::uuid)->>'code','DISCLOSURE_DENIED','expiry between actor admission and service resolve blocks bytes');
rollback to expired_share;
select pg_temp.study894_claim(1);
select ok((pg_temp.method_review_cmd('share.revoke',jsonb_build_object('shareId',pg_temp.val('method-share')->'data'->'value'->'shareId','reason','Synthetic expiry/revoke test'),'method-share-revoke')->>'ok')::boolean,'owner explicitly revokes method share');
select pg_temp.study894_claim(null,null,true);
select is(api.svc_study_review_method_intent_resolve_v1((pg_temp.val('method-share-view')->'data'->>'intentId')::uuid)->>'code','DISCLOSURE_DENIED','revocation between stages blocks old admitted bytes');


select pg_temp.study894_claim(2);
select ok((pg_temp.method_review_cmd('review.record',jsonb_build_object('reportRevisionId',pg_temp.mrid(),'expectedContentHash',repeat('b',64),'reviewClass','internal','decision','withdraw','comment','Internal review withdrawal','predecessorReviewId',pg_temp.val('method-review')->'data'->'value'->'reviewId','delegationId',null),'method-review-withdraw')->>'ok')::boolean,'withdrawal retains historical method finalization');
select pg_temp.study894_claim(1);
select is(api.qry_study_method_review_v1(pg_temp.v6('report.current',jsonb_build_object('reportRevisionId',pg_temp.mrid(),'expectedContentHash',repeat('b',64))))->'data'->'value'->>'acceptance','invalidated','withdrawal invalidates current method acceptance without rewriting export');
select is((select count(*)from private.study_review_exports where report_id=pg_temp.mrid()),1::bigint,'historical method export retained after withdrawal');
select pg_temp.study894_claim(null,null,true);
select is(api.svc_study_report_method_intent_reconcile_v1((pg_temp.val('method-report-intent')->'data'->>'intentId')::uuid,(pg_temp.val('method-report')->'data'->'value'->'contentRef'->>'id')::uuid,repeat('b',64))->'data'->>'state','committed','method report historical reconcile proves exact content attachment');
select is(api.svc_study_review_method_intent_reconcile_v1((pg_temp.val('method-export-intent')->'data'->>'intentId')::uuid,(pg_temp.val('method-export')->'data'->'value'->'projectionRef'->>'id')::uuid,repeat('e',64))->'data'->>'schemaVersion','lca.study-method-review-reconcile.v1','method review reconciliation has distinct schema');
select is(api.svc_study_review_method_intent_reconcile_v1((pg_temp.val('method-export-intent')->'data'->>'intentId')::uuid,(pg_temp.val('method-export')->'data'->'value'->'projectionRef'->>'id')::uuid,repeat('e',64))->'data'->'deletionPermitted','false'::jsonb,'historical reconcile grants no deletion authority');
select * from finish();
rollback;
