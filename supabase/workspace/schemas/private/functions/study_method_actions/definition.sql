CREATE OR REPLACE FUNCTION "private"."study_method_actions"("p_resource" "jsonb", "p_actor" "uuid", "p_client" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$declare a private.study_method_assessments%rowtype;ops jsonb;role text;full_rights boolean:=false;begin
 perform private.study_require(private.study_keys(p_resource,array['type','id']) and p_resource->>'type'='methodAssessment' and private.study_method_uuid(p_resource->'id'),'INVALID_REQUEST');
 select * into a from private.study_method_assessments where id=(p_resource->>'id')::uuid;perform private.study_require(found,'FORBIDDEN');role:=private.study_authorize(a.study_id,p_actor,p_client,'read');
 ops:='["task.read"]'::jsonb;
 if role in('owner','editor') and private.study_client_allowed(p_client,'STUDY-WRITE-01') then ops:=ops||'["task.cancel"]'::jsonb;end if;
 begin
  perform private.study_advanced_rights(a.study_id,a.baseline_run_id,p_actor,p_client);perform private.study_method_evidence_refs(a.study_id,a.config,p_actor,p_client);full_rights:=true;
 exception when raise_exception then null;end;
 if full_rights then
  ops:=ops||'["method.assessment.read"]'::jsonb;
  if a.facts_artifact_id is not null and(select disclosure_enabled from private.study_runtime_config where singleton) then ops:=ops||'["artifact.read"]'::jsonb;end if;
 end if;
 return jsonb_build_object('ok',true,'data',jsonb_build_object('type','actions','resource',p_resource,'actions',ops,
 'corePermissions',jsonb_build_object('read',true,'write',role in('owner','editor') and private.study_client_allowed(p_client,'STUDY-WRITE-01') and(select status='active'from private.studies where id=a.study_id)),'allowedMemberRoles','[]'::jsonb));
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);end$$;

ALTER FUNCTION "private"."study_method_actions"("p_resource" "jsonb", "p_actor" "uuid", "p_client" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_method_actions"("p_resource" "jsonb", "p_actor" "uuid", "p_client" "text") FROM PUBLIC;
