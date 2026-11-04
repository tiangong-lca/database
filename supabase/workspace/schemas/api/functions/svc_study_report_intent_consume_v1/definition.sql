CREATE OR REPLACE FUNCTION "api"."svc_study_report_intent_consume_v1"("p_intent_id" "uuid", "p_completion" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
declare i private.study_report_intents%rowtype;r private.study_report_revisions%rowtype;refs jsonb;contentref jsonb;artifact uuid;result jsonb;validation jsonb;claimcount integer;
 manifest jsonb;receipt jsonb;profile jsonb;projection uuid;resources uuid;bundle uuid;record jsonb;validity jsonb;
begin
 perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');
 perform private.study_require(exists(select 1 from private.study_report_intents where id=p_intent_id and family='legacy'),'CAPABILITY_UNAVAILABLE');i:=private.study_report_intent_check(p_intent_id);
 select * into i from private.study_report_intents where id=i.id for update;
 if i.response is not null then return i.response;end if;
 if i.operation='report.create' then
  refs:=private.study_report_rights(i.study_id,i.request->'runIds',i.request->'analysisIds',i.actor_id,i.client_id);claimcount:=jsonb_array_length(i.request->'content'->'claims');
 else
  select * into r from private.study_report_revisions where id=i.report_id for update;
  refs:=private.study_report_rights(i.study_id,r.run_ids,r.analysis_ids,i.actor_id,i.client_id);
  claimcount:=case when i.operation='report.save' then jsonb_array_length(i.request->'content'->'claims') else (r.validation_evidence->>'claimCount')::integer end;
 end if;
 validation:=p_completion->'validation';
 if i.operation in ('report.create','report.save') then
  perform private.study_require(private.study_keys(p_completion,array['kind','contentArtifact','factsRefs','validation']) and p_completion->>'kind'='validatedContent'
   and p_completion->'factsRefs'=refs,'REFERENCE_MISMATCH');
  contentref:=p_completion->'contentArtifact'->'artifactRef';
  perform private.study_report_validation_check(validation,i.report_id,contentref->>'contentHash',claimcount,refs);
  artifact:=private.study_report_store_produced(i.study_id,p_completion->'contentArtifact',i.content_artifact_id,'reportContent','lca.study-report-content.v1','content');
  if i.operation='report.create' then
   insert into private.study_report_revisions(id,study_id,parent_report_id,author_id,content_hash,content_artifact_id,template_id,run_ids,analysis_ids,facts_refs,validity_snapshot,validation_evidence)
   values(i.report_id,i.study_id,(i.request->>'parentReportRevisionId')::uuid,i.actor_id,contentref->>'contentHash',artifact,i.request->>'templateId',i.request->'runIds',i.request->'analysisIds',refs,
   private.study_report_validity_snapshot(i.study_id,i.request->'runIds',i.created_at),validation);
   insert into private.study_report_runs select i.study_id,i.report_id,n,v::uuid from jsonb_array_elements_text(i.request->'runIds') with ordinality e(v,n);
   insert into private.study_report_analyses select i.study_id,i.report_id,n,v::uuid from jsonb_array_elements_text(i.request->'analysisIds') with ordinality e(v,n);
  else update private.study_report_revisions set revision=revision+1,content_hash=contentref->>'contentHash',content_artifact_id=artifact,validation_evidence=validation where id=i.report_id;end if;
  result:=jsonb_build_object('ok',true,'data',jsonb_build_object('type','reportRevision','value',private.study_report_record(i.report_id)));
 elsif i.operation='report.freeze' then
  select ref into contentref from private.study_artifacts where id=r.content_artifact_id;
  perform private.study_require(private.study_keys(p_completion,array['kind','contentRef','validation']) and p_completion->>'kind'='validatedFreeze' and p_completion->'contentRef'=contentref,'REFERENCE_MISMATCH');
  perform private.study_report_validation_check(validation,r.id,r.content_hash,claimcount,refs);
  update private.study_report_revisions set status='frozen',revision=revision+1,validation_evidence=validation where id=r.id;
  result:=jsonb_build_object('ok',true,'data',jsonb_build_object('type','reportRevision','value',private.study_report_record(r.id)));
 else
  perform private.study_require(private.study_keys(p_completion,array['kind','projectionArtifact','resourcesArtifact','bundleArtifact','manifest','receipt']) and p_completion->>'kind'='validatedExport','REFERENCE_MISMATCH');
  manifest:=p_completion->'manifest';receipt:=p_completion->'receipt';select export_profile into profile from private.study_reporting_config where singleton;
  perform private.study_require(private.study_keys(manifest,array['schemaVersion','issuerId','exportId','studyId','reportRevisionId','reportContentHash','actorId','clientId','grantEpoch','policyId','disclosureContextHash','generatedAt','validitySnapshot','reviewIds','renderer','files'])
   and manifest->>'schemaVersion'='lca.study-export-manifest.v1' and manifest->>'issuerId'=profile->>'issuerId'
   and manifest->>'exportId'=i.export_id::text and manifest->>'studyId'=i.study_id::text and manifest->>'reportRevisionId'=i.report_id::text
   and manifest->>'reportContentHash'=r.content_hash and manifest->>'actorId'=i.actor_id::text and (manifest->>'clientId') is not distinct from i.client_id
   and jsonb_typeof(manifest->'grantEpoch')='number' and (manifest->>'grantEpoch')::numeric=i.grant_epoch
   and manifest->>'policyId'='lca.study-report-disclosure.v1' and manifest->>'disclosureContextHash'=private.study_report_disclosure_context(i)
   and (manifest->>'generatedAt')::timestamptz=i.created_at and manifest->'validitySnapshot'=i.report_snapshot->'validitySnapshot' and manifest->'reviewIds'='[]'::jsonb
   and manifest->'renderer'=jsonb_build_object('version','1.0.0','viewModelVersion','lca.study-report-view.v1','artifactHash',profile->>'rendererArtifactHash'),'REFERENCE_MISMATCH');
  perform private.study_require(jsonb_typeof(manifest->'files')='array' and jsonb_array_length(manifest->'files')=2
   and private.study_keys(manifest->'files'->0,array['path','mediaType','sha256','byteSize']) and private.study_keys(manifest->'files'->1,array['path','mediaType','sha256','byteSize'])
   and manifest->'files'->0->>'path'='report.html' and manifest->'files'->0->>'mediaType'='text/html'
   and manifest->'files'->1->>'path'='projection.json' and manifest->'files'->1->>'mediaType'='application/json'
   and manifest->'files'->0->>'sha256' ~ '^[0-9a-f]{64}$'
   and jsonb_typeof(manifest->'files'->0->'byteSize')='number' and jsonb_typeof(manifest->'files'->1->'byteSize')='number'
   and (manifest->'files'->0->>'byteSize')::numeric=trunc((manifest->'files'->0->>'byteSize')::numeric)
   and (manifest->'files'->1->>'byteSize')::numeric=trunc((manifest->'files'->1->>'byteSize')::numeric)
   and (manifest->'files'->0->>'byteSize')::numeric between 1 and 4194304 and (manifest->'files'->1->>'byteSize')::numeric between 1 and 4194304
   and (manifest->'files'->0->>'byteSize')::numeric+(manifest->'files'->1->>'byteSize')::numeric<=4194304
   and manifest->'files'->1->>'sha256'=p_completion->'projectionArtifact'->'artifactRef'->>'contentHash'
   and (manifest->'files'->1->>'byteSize')::numeric=(p_completion->'projectionArtifact'->'artifactRef'->>'byteSize')::numeric,'REFERENCE_MISMATCH');
  perform private.study_require(p_completion->'resourcesArtifact'->'artifactRef'->>'contentHash'=private.study_reporting_digest(null,manifest)
   and (p_completion->'resourcesArtifact'->'artifactRef'->>'byteSize')::numeric=octet_length(private.study_reporting_canonical(manifest))
   and private.study_keys(receipt,array['schemaVersion','manifestHash','keyId','algorithm','signature']) and receipt->>'schemaVersion'='lca.study-export-receipt.v2'
   and receipt->>'manifestHash'=private.study_reporting_digest('lca.study-export-signature.v1',manifest) and receipt->>'keyId'=profile->>'keyId'
   and receipt->>'algorithm'='Ed25519' and private.study_text(receipt->'signature',86,'^[A-Za-z0-9_-]{85}[AQgw]$'),'REFERENCE_MISMATCH');
  projection:=private.study_report_store_produced(i.study_id,p_completion->'projectionArtifact',i.projection_artifact_id,'reportProjection','lca.study-report-view.v1','projection');
  resources:=private.study_report_store_produced(i.study_id,p_completion->'resourcesArtifact',i.resources_artifact_id,'renderResources','lca.study-export-manifest.v1','resources');
  bundle:=private.study_report_store_produced(i.study_id,p_completion->'bundleArtifact',i.bundle_artifact_id,'reportExportBundle','lca.study-export-bundle.v1','bundle');
  record:=jsonb_build_object('exportId',i.export_id,'studyId',i.study_id,'reportRevisionId',i.report_id,'reportContentHash',r.content_hash,'status','ready',
   'projectionRef',p_completion->'projectionArtifact'->'artifactRef','grantEpoch',i.grant_epoch,'factsRefs',refs,'rendererVersion','1.0.0','viewModelVersion','lca.study-report-view.v1',
   'resourcesRef',p_completion->'resourcesArtifact'->'artifactRef','actorId',i.actor_id,'policyId','lca.study-report-disclosure.v1','disclosureContextHash',manifest->>'disclosureContextHash',
   'disclosureDecision','allowed','generatedAt',i.created_at,'validitySnapshot',i.report_snapshot->'validitySnapshot','reviewIds','[]'::jsonb,'receipt',receipt,'bundleRef',p_completion->'bundleArtifact'->'artifactRef');
  insert into private.study_report_exports(id,study_id,report_id,actor_id,client_id,grant_epoch,record,manifest,projection_artifact_id,resources_artifact_id,bundle_artifact_id) values(i.export_id,i.study_id,i.report_id,i.actor_id,i.client_id,i.grant_epoch,record,manifest,projection,resources,bundle);
  result:=jsonb_build_object('ok',true,'data',jsonb_build_object('type','export','value',record));
 end if;
 update private.study_report_intents set response=result where id=i.id;
 update private.study_command_receipts set response=result where actor_id=i.actor_id and operation=i.operation and scope=i.study_id::text and idempotency_key=i.request->>'idempotencyKey';return result;
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
when invalid_text_representation or invalid_parameter_value or numeric_value_out_of_range or check_violation or not_null_violation or invalid_datetime_format then return jsonb_build_object('ok',false,'code','INVALID_REQUEST');
when foreign_key_violation or unique_violation then return jsonb_build_object('ok',false,'code','REFERENCE_MISMATCH');
end$_$;

ALTER FUNCTION "api"."svc_study_report_intent_consume_v1"("p_intent_id" "uuid", "p_completion" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."svc_study_report_intent_consume_v1"("p_intent_id" "uuid", "p_completion" "jsonb") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."svc_study_report_intent_consume_v1"("p_intent_id" "uuid", "p_completion" "jsonb") TO "service_role";
