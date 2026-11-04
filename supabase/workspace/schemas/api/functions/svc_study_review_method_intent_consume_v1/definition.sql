CREATE OR REPLACE FUNCTION "api"."svc_study_review_method_intent_consume_v1"("p_intent_id" "uuid", "p_completion" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$declare i private.study_review_intents%rowtype;r private.study_report_revisions%rowtype;f jsonb;manifest jsonb;receipt jsonb;profile jsonb;record jsonb;result jsonb;projection uuid;resources uuid;bundle uuid;begin
 perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');i:=private.study_method_review_intent_check(p_intent_id);
 select * into i from private.study_review_intents where id=p_intent_id for update;
 if i.response is not null then return i.response;end if;
 perform private.study_require(i.operation='export.request','INVALID_REQUEST');select * into r from private.study_report_revisions where id=i.report_id;
 f:=private.study_finalization_record(i.finalization_id);
 select export_profile into profile from private.study_method_review_config where singleton;
 perform private.study_require(private.study_keys(p_completion,array['kind','projectionArtifact','resourcesArtifact','bundleArtifact','manifest','receipt']) and p_completion->>'kind'='validatedReviewExport','REFERENCE_MISMATCH');
 manifest:=p_completion->'manifest';receipt:=p_completion->'receipt';
 perform private.study_require(private.study_keys(manifest,array['schemaVersion','issuerId','exportId','studyId','reportRevisionId','reportContentHash','actorId','clientId','grantEpoch','policyId','disclosureContextHash','generatedAt','validitySnapshot','reviewIds','finalization','renderer','files'])
  and manifest->>'schemaVersion'='lca.study-export-manifest.v4' and manifest->>'issuerId'=profile->>'issuerId' and manifest->>'exportId'=i.export_id::text
  and manifest->>'studyId'=i.study_id::text and manifest->>'reportRevisionId'=r.id::text and manifest->>'reportContentHash'=r.content_hash
  and manifest->>'actorId'=i.actor_id::text and (manifest->>'clientId') is not distinct from i.client_id
  and jsonb_typeof(manifest->'grantEpoch')='number' and (manifest->>'grantEpoch')::numeric=i.grant_epoch
  and manifest->>'policyId'='lca.study-report-disclosure.v1' and manifest->>'disclosureContextHash'=i.disclosure_context_hash
  and (manifest->>'generatedAt')::timestamptz=i.created_at and manifest->'validitySnapshot'=private.study_method_report_record(r.id)->'validitySnapshot'
  and manifest->'finalization'=f and manifest->'reviewIds'=f->'acceptedReviewIds' and (f->>'finalizedAt')::timestamptz<=i.created_at
  and manifest->'renderer'=jsonb_build_object('version','3.0.0','viewModelVersion','lca.study-report-view.v3','artifactHash',profile->>'rendererArtifactHash'),'REFERENCE_MISMATCH');
 perform private.study_require(jsonb_typeof(manifest->'files')='array' and jsonb_array_length(manifest->'files')=2
  and private.study_keys(manifest->'files'->0,array['path','mediaType','sha256','byteSize']) and private.study_keys(manifest->'files'->1,array['path','mediaType','sha256','byteSize'])
  and manifest->'files'->0->>'path'='report.html' and manifest->'files'->0->>'mediaType'='text/html' and manifest->'files'->0->>'sha256' ~ '^[0-9a-f]{64}$'
  and manifest->'files'->1->>'path'='projection.json' and manifest->'files'->1->>'mediaType'='application/json'
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
 projection:=private.study_report_store_produced(i.study_id,p_completion->'projectionArtifact',i.projection_artifact_id,'reportProjection','lca.study-report-view.v3','projection');
 resources:=private.study_report_store_produced(i.study_id,p_completion->'resourcesArtifact',i.resources_artifact_id,'renderResources','lca.study-export-manifest.v4','resources');
 bundle:=private.study_report_store_produced(i.study_id,p_completion->'bundleArtifact',i.bundle_artifact_id,'reportExportBundle','lca.study-export-bundle.v4','bundle');
 record:=jsonb_build_object('studyId',i.study_id,'reportRevisionId',r.id,'reportContentHash',r.content_hash,'exportId',i.export_id,'finalization',f,'generatedAt',i.created_at,
  'projectionRef',p_completion->'projectionArtifact'->'artifactRef','resourcesRef',p_completion->'resourcesArtifact'->'artifactRef','bundleRef',p_completion->'bundleArtifact'->'artifactRef','receipt',receipt);
 insert into private.study_review_exports(id,study_id,report_id,actor_id,client_id,grant_epoch,finalization_id,record,manifest,projection_artifact_id,resources_artifact_id,bundle_artifact_id)
  values(i.export_id,i.study_id,r.id,i.actor_id,i.client_id,i.grant_epoch,i.finalization_id,record,manifest,projection,resources,bundle);
 result:=jsonb_build_object('ok',true,'data',jsonb_build_object('type','export','value',record));update private.study_review_intents set response=result where id=i.id;
 update private.study_command_receipts set response=result where actor_id=i.actor_id and operation=i.operation and scope='v6:'||i.study_id::text and idempotency_key=i.request->>'idempotencyKey';return result;
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
when invalid_text_representation or invalid_parameter_value or numeric_value_out_of_range or check_violation or not_null_violation or invalid_datetime_format then return jsonb_build_object('ok',false,'code','INVALID_REQUEST');
when foreign_key_violation or unique_violation then return jsonb_build_object('ok',false,'code','REFERENCE_MISMATCH');end$_$;

ALTER FUNCTION "api"."svc_study_review_method_intent_consume_v1"("p_intent_id" "uuid", "p_completion" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."svc_study_review_method_intent_consume_v1"("p_intent_id" "uuid", "p_completion" "jsonb") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."svc_study_review_method_intent_consume_v1"("p_intent_id" "uuid", "p_completion" "jsonb") TO "service_role";
