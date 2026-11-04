CREATE OR REPLACE FUNCTION "api"."qry_study_advanced_v1"("p_request" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$declare actor uuid:=auth.uid();client text:=nullif(auth.jwt()->>'client_id','');a private.study_advanced_analyses%rowtype;r private.study_report_revisions%rowtype;
 cfg private.study_advanced_config%rowtype;ops jsonb;profiles jsonb:='[]'::jsonb;begin
 perform private.study_advanced_envelope(p_request,false);perform private.study_require(private.study_client_allowed(client,'STUDY-READ-01'),'FORBIDDEN');
 case p_request->>'operation'
 when 'capability.read' then
  perform private.study_require(private.study_keys(p_request,array['schemaVersion','requestId','operation']),'INVALID_REQUEST');select * into cfg from private.study_advanced_config where singleton;
  ops:='["capability.read","analysis.read","task.read","report.read","study.resources.list"]';
  if private.study_client_allowed(client,'STUDY-WRITE-01') then ops:=ops||'["task.cancel"]'::jsonb;end if;
  if private.study_client_allowed(client,'DB-CORE-READ-01') then
   ops:=ops||'["analysis.parameters.read"]'::jsonb;
   if (select disclosure_enabled from private.study_runtime_config where singleton) then ops:=ops||'["artifact.read"]'::jsonb;end if;
   if private.study_client_allowed(client,'STUDY-WRITE-01') then
    if cfg.sensitivity_enabled or cfg.uncertainty_enabled then ops:=ops||'["analysis.request"]'::jsonb;end if;
    if cfg.report_enabled then ops:=ops||'["report.create","report.save","report.freeze"]'::jsonb;end if;
   end if;
  end if;
  if cfg.sensitivity_enabled then profiles:=profiles||'["lca.study-sensitivity-oat.v1"]'::jsonb;end if;
  if cfg.uncertainty_enabled then profiles:=profiles||'["lca.study-uncertainty-bounded.v1"]'::jsonb;end if;
  return jsonb_build_object('ok',true,'data',jsonb_build_object('type','capabilities','contractVersion','5.0.0','runtimeEnabled',cfg.sensitivity_enabled or cfg.uncertainty_enabled or cfg.report_enabled,
   'operations',ops,'analysisProfiles',profiles,'reportTemplates',case when cfg.report_enabled then '["lca.study-report.v2"]'::jsonb else '[]'::jsonb end));
 when 'analysis.read' then
  perform private.study_require(private.study_keys(p_request,array['schemaVersion','requestId','operation','analysisId']),'INVALID_REQUEST');select * into a from private.study_advanced_analyses where id=(p_request->>'analysisId')::uuid;
  perform private.study_require(found,'FORBIDDEN');perform private.study_advanced_rights(a.study_id,a.baseline_run_id,actor,client);
  return jsonb_build_object('ok',true,'data',jsonb_build_object('type','analysis','value',private.study_advanced_record(a.id)));
 when 'report.read' then
  perform private.study_require(private.study_keys(p_request,array['schemaVersion','requestId','operation','reportRevisionId']),'INVALID_REQUEST');select * into r from private.study_report_revisions where id=(p_request->>'reportRevisionId')::uuid;
  perform private.study_require(found and r.template_id='lca.study-report.v2','FORBIDDEN');perform private.study_report_advanced_rights(r.study_id,r.run_ids,r.analysis_ids,actor,client);
  return jsonb_build_object('ok',true,'data',jsonb_build_object('type','reportRevision','value',private.study_report_record(r.id)));
 when 'analysis.parameters.read' then return private.study_advanced_parameters(p_request);
 when 'task.read' then return private.study_advanced_task(p_request);
 when 'study.resources.list' then return private.study_advanced_list(p_request);
 when 'artifact.read' then return private.study_advanced_artifact_intent(p_request);
 else return jsonb_build_object('ok',false,'code','CAPABILITY_UNAVAILABLE');end case;
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
when invalid_text_representation or invalid_parameter_value or numeric_value_out_of_range then return jsonb_build_object('ok',false,'code','INVALID_REQUEST');end$$;

ALTER FUNCTION "api"."qry_study_advanced_v1"("p_request" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."qry_study_advanced_v1"("p_request" "jsonb") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."qry_study_advanced_v1"("p_request" "jsonb") TO "authenticated";
