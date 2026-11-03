CREATE OR REPLACE FUNCTION "private"."study_artifact_authorize"("p_study" "uuid", "p_ref" "jsonb", "p_actor" "uuid", "p_client" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare a private.study_artifacts%rowtype; snapshot uuid; p uuid;
begin
  perform private.study_authorize(p_study,p_actor,p_client,'read');
  perform private.study_require((select disclosure_enabled from private.study_runtime_config where singleton),'CAPABILITY_UNAVAILABLE');
  perform private.study_require(p_ref->>'type' in ('modelInput','runResult'),'DISCLOSURE_DENIED');
  select * into a from private.study_artifacts where study_id=p_study and id=(p_ref->>'id')::uuid;
  perform private.study_require(found and a.ref=p_ref,'REFERENCE_MISMATCH');
  if a.ref->>'type'='modelInput' then select id into p from private.study_model_preparations where study_id=p_study and input_artifact_id=a.id;
  else select preparation_id into p from private.study_runs where study_id=p_study and result_artifact_id=a.id; end if;
  perform private.study_require(p is not null,'DISCLOSURE_DENIED'); snapshot:=private.study_preparation_snapshot(p_study,p);
  perform private.study_snapshot_rights(snapshot,p_actor,p_client);
  return jsonb_build_object('kind','artifactCapability','studyId',p_study,'artifactRef',a.ref,'storageBucket',a.bucket,'storageObjectPath',a.object_path);
end $$;

ALTER FUNCTION "private"."study_artifact_authorize"("p_study" "uuid", "p_ref" "jsonb", "p_actor" "uuid", "p_client" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_artifact_authorize"("p_study" "uuid", "p_ref" "jsonb", "p_actor" "uuid", "p_client" "text") FROM PUBLIC;
