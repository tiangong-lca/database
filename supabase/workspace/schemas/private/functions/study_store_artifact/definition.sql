CREATE OR REPLACE FUNCTION "private"."study_store_artifact"("p_study" "uuid", "p_ref" "jsonb", "p_bucket" "text", "p_path" "text", "p_type" "text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
declare aid uuid:=(p_ref->>'id')::uuid;
begin
  perform private.study_require(p_ref->>'type'=p_type and p_ref->>'digestScope'='artifact_bytes_sha256'
    and private.study_keys(p_ref,array['type','id','contentHash','digestScope','byteSize','mediaType','schemaVersion'])
    and private.study_text(p_ref->'id',128,'^[A-Za-z0-9][A-Za-z0-9._:-]*$')
    and private.study_text(p_ref->'contentHash',64,'^[0-9a-f]{64}$')
    and jsonb_typeof(p_ref->'byteSize')='number' and (p_ref->>'byteSize')::numeric=trunc((p_ref->>'byteSize')::numeric)
    and (p_ref->>'byteSize')::numeric between 1 and 4194304
    and p_ref->>'mediaType' in ('application/json','application/zip','text/html')
    and length(p_ref->>'schemaVersion') between 1 and 128,'REFERENCE_MISMATCH');
  perform private.study_require(p_bucket='study-artifacts' and p_path ~ ('^study/'||p_study::text||'/'||aid::text||'/[A-Za-z0-9_-]+\.(json|zip|html)$'),'REFERENCE_MISMATCH');
  insert into private.study_artifacts(id,study_id,ref,bucket,object_path) values(aid,p_study,p_ref,p_bucket,p_path)
    on conflict(id) do nothing;
  perform private.study_require(exists(select 1 from private.study_artifacts where id=aid and study_id=p_study and ref=p_ref and bucket=p_bucket and object_path=p_path),'IDEMPOTENCY_CONFLICT');
  return aid;
end $_$;

ALTER FUNCTION "private"."study_store_artifact"("p_study" "uuid", "p_ref" "jsonb", "p_bucket" "text", "p_path" "text", "p_type" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_store_artifact"("p_study" "uuid", "p_ref" "jsonb", "p_bucket" "text", "p_path" "text", "p_type" "text") FROM PUBLIC;
