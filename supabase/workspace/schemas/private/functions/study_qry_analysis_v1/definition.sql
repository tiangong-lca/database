CREATE OR REPLACE FUNCTION "private"."study_qry_analysis_v1"("p_request" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare client text:=nullif(auth.jwt()->>'client_id',''); actor uuid:=auth.uid(); a private.study_analyses%rowtype; ops jsonb; cfg private.study_reporting_config%rowtype; begin
 perform private.study_reporting_envelope(p_request,false);
 perform private.study_require(private.study_client_allowed(client,'STUDY-READ-01'),'FORBIDDEN');
 case p_request->>'operation'
 when 'capability.read' then
  perform private.study_require(private.study_keys(p_request,array['schemaVersion','requestId','operation']),'INVALID_REQUEST');
  select * into cfg from private.study_reporting_config where singleton;
  ops:=jsonb_build_array('capability.read','analysis.read','task.read');
  if private.study_client_allowed(client,'STUDY-WRITE-01') then
   ops:=ops||jsonb_build_array('task.cancel');
   if cfg.analysis_enabled and private.study_client_allowed(client,'DB-CORE-READ-01') then ops:=ops||jsonb_build_array('analysis.request'); end if;
  end if;
  if (select disclosure_enabled from private.study_runtime_config where singleton) and private.study_client_allowed(client,'DB-CORE-READ-01') then ops:=ops||jsonb_build_array('artifact.read'); end if;
  return jsonb_build_object('ok',true,'data',jsonb_build_object('type','capabilities','contractVersion','3.0.0','runtimeEnabled',cfg.analysis_enabled or cfg.report_enabled or cfg.export_enabled,'operations',ops,'analysisProfiles',case when cfg.analysis_enabled then jsonb_build_array('lca.study-analysis-explicit-v1') else '[]'::jsonb end,'reportTemplates',case when cfg.report_enabled then jsonb_build_array('lca.study-report.v1') else '[]'::jsonb end));
 when 'analysis.read' then
  perform private.study_require(private.study_keys(p_request,array['schemaVersion','requestId','operation','analysisId']),'INVALID_REQUEST');
  select * into a from private.study_analyses where id=(p_request->>'analysisId')::uuid;
  perform private.study_require(found,'FORBIDDEN'); perform private.study_authorize(a.study_id,actor,client,'read');
  perform private.study_analysis_rights(a.study_id,a.config,actor,client);
  return jsonb_build_object('ok',true,'data',jsonb_build_object('type','analysis','value',private.study_analysis_record(a.id)));
 when 'task.read' then return private.study_reporting_task(p_request);
 when 'artifact.read' then return private.study_reporting_artifact_intent(p_request);
 else return jsonb_build_object('ok',false,'code','CAPABILITY_UNAVAILABLE');
 end case;
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
when invalid_text_representation or invalid_parameter_value then return jsonb_build_object('ok',false,'code','INVALID_REQUEST');
end $$;

ALTER FUNCTION "private"."study_qry_analysis_v1"("p_request" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_qry_analysis_v1"("p_request" "jsonb") FROM PUBLIC;
