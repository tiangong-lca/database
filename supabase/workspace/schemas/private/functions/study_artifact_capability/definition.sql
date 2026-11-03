CREATE OR REPLACE FUNCTION "private"."study_artifact_capability"("p_request" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare actor uuid:=auth.uid(); client text:=nullif(auth.jwt()->>'client_id',''); sid uuid:=(p_request->>'studyId')::uuid; capability jsonb; intent uuid; expiry timestamptz;
begin
  perform private.study_require(actor is not null and not coalesce(util.is_service_request(),false),'AUTH_REQUIRED');
  perform private.study_require(private.study_keys(p_request,array['schemaVersion','requestId','operation','studyId','artifactRef'])
    and p_request->>'schemaVersion'='lca.study-api.v2' and p_request->>'operation'='artifact.read','INVALID_REQUEST');
  capability:=private.study_artifact_authorize(sid,p_request->'artifactRef',actor,client);
  perform pg_advisory_xact_lock(hashtextextended('study-artifact-intent:'||actor::text,895));
  with expired as (select id from private.study_artifact_read_intents where expires_at<=clock_timestamp()
    order by expires_at,id limit 256 for update skip locked)
    delete from private.study_artifact_read_intents i using expired e where i.id=e.id;
  perform private.study_require((select count(*) from private.study_artifact_read_intents where actor_id=actor and expires_at>clock_timestamp())<64,'CAPABILITY_UNAVAILABLE');
  insert into private.study_artifact_read_intents(study_id,artifact_id,artifact_ref,actor_id,client_id)
    values(sid,(p_request->'artifactRef'->>'id')::uuid,p_request->'artifactRef',actor,client) returning id,expires_at into intent,expiry;
  return jsonb_build_object('ok',true,'data',jsonb_build_object('kind','artifactReadIntent','intentId',intent,'expiresAt',expiry,'studyId',sid,'artifactRef',p_request->'artifactRef'));
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
when invalid_text_representation then return jsonb_build_object('ok',false,'code','INVALID_REQUEST');
end $$;

ALTER FUNCTION "private"."study_artifact_capability"("p_request" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_artifact_capability"("p_request" "jsonb") FROM PUBLIC;
