CREATE OR REPLACE FUNCTION "api"."qry_study_v1"("p_request" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare result jsonb; ops jsonb; profiles jsonb:='[]'; cfg private.study_runtime_config%rowtype; client text:=nullif(auth.jwt()->>'client_id','');
begin
  if p_request->>'operation'='task.read' then return private.study_task_control(p_request); end if;
  if p_request->>'operation'='artifact.read' then return private.study_artifact_capability(p_request); end if;
  result:=private.study_qry_core_v1(p_request);
  if p_request->>'operation'='capability.read' and result->>'ok'='true' then
    select * into cfg from private.study_runtime_config where singleton;
    ops:=result->'data'->'operations'||jsonb_build_array('task.read');
    if private.study_client_allowed(client,'STUDY-WRITE-01') then
      ops:=ops||jsonb_build_array('run.cancel','task.cancel');
      if private.study_client_allowed(client,'DB-CORE-READ-01') then
        if cfg.source_enabled then ops:=ops||jsonb_build_array('model.source.resolve'); end if;
        if cfg.compute_enabled then ops:=ops||jsonb_build_array('model.prepare','run.submit'); end if;
      end if;
    end if;
    if cfg.disclosure_enabled and private.study_client_allowed(client,'DB-CORE-READ-01') then ops:=ops||jsonb_build_array('artifact.read'); end if;
    if cfg.compute_enabled then
      select coalesce(jsonb_agg(jsonb_build_object('profileId',profile_id,'calculationContractRef',jsonb_build_object('kind','calculation_contract','schema','lca.calculation-contract.v1','sha256',calculation_fingerprint))),'[]') into profiles from private.study_profiles where enabled;
    end if;
    result:=jsonb_set(jsonb_set(result,'{data,operations}',ops),'{data,profiles}',profiles);
  end if;
  return result;
end $$;

ALTER FUNCTION "api"."qry_study_v1"("p_request" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."qry_study_v1"("p_request" "jsonb") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."qry_study_v1"("p_request" "jsonb") TO "authenticated";
