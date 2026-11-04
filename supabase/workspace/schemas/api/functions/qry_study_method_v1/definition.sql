CREATE OR REPLACE FUNCTION "api"."qry_study_method_v1"("p_request" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$declare actor uuid:=auth.uid();client text:=nullif(auth.jwt()->>'client_id','');a private.study_method_assessments%rowtype;e private.study_method_evidence%rowtype;r private.study_report_revisions%rowtype;
 cfg private.study_method_config%rowtype;ops jsonb;profiles jsonb:='[]'::jsonb;begin
 perform private.study_method_envelope(p_request,false);perform private.study_require(private.study_client_allowed(client,'STUDY-READ-01'),'FORBIDDEN');
 case p_request->>'operation'
 when 'capability.read' then
  perform private.study_require(private.study_keys(p_request,array['schemaVersion','requestId','operation']),'INVALID_REQUEST');select * into cfg from private.study_method_config where singleton;
  ops:='["capability.read","method.assessment.read","method.evidence.read","task.read","report.read","study.resources.list","resource.actions"]'::jsonb;
  if private.study_client_allowed(client,'STUDY-WRITE-01') then
   ops:=ops||'["task.cancel"]'::jsonb;
   if cfg.execution_enabled then ops:=ops||'["method.evidence.create"]'::jsonb;end if;
  end if;
  if private.study_client_allowed(client,'DB-CORE-READ-01') then
   if(select disclosure_enabled from private.study_runtime_config where singleton) then ops:=ops||'["artifact.read"]'::jsonb;end if;
   if private.study_client_allowed(client,'STUDY-WRITE-01') then
    if cfg.execution_enabled then ops:=ops||'["method.assessment.request"]'::jsonb;end if;
    if cfg.report_enabled then ops:=ops||'["report.create","report.save","report.freeze"]'::jsonb;end if;
   end if;
  end if;
  if cfg.execution_enabled then profiles:='["lca.study-method-pef-2021-ef31-cement-intermediate.v1"]'::jsonb;end if;
  return jsonb_build_object('ok',true,'data',jsonb_build_object('type','capabilities','contractVersion','6.0.0','runtimeEnabled',cfg.execution_enabled or cfg.report_enabled,'operations',ops,'methodProfiles',profiles,
   'reportTemplates',case when cfg.report_enabled then '["lca.study-method-report.v1"]'::jsonb else '[]'::jsonb end,
   'limits',jsonb_build_object('maxEvidenceRefs',coalesce(cfg.max_evidence_refs,0),'maxSelectedFactorRecords',coalesce(cfg.max_selected_factor_records,0),'maxFactsBytes',4194304,'maxProjectionBytes',2000000)));
 when 'method.assessment.read' then
  perform private.study_require(private.study_keys(p_request,array['schemaVersion','requestId','operation','assessmentId']),'INVALID_REQUEST');select * into a from private.study_method_assessments where id=(p_request->>'assessmentId')::uuid;
  perform private.study_require(found,'FORBIDDEN');perform private.study_advanced_rights(a.study_id,a.baseline_run_id,actor,client);perform private.study_method_evidence_refs(a.study_id,a.config,actor,client);
  return jsonb_build_object('ok',true,'data',jsonb_build_object('type','methodAssessment','value',private.study_method_record(a.id)));
 when 'method.evidence.read' then
  perform private.study_require(private.study_keys(p_request,array['schemaVersion','requestId','operation','evidenceId']),'INVALID_REQUEST');select * into e from private.study_method_evidence where id=(p_request->>'evidenceId')::uuid;
  perform private.study_require(found,'FORBIDDEN');perform private.study_authorize(e.study_id,actor,client,'read');return jsonb_build_object('ok',true,'data',jsonb_build_object('type','methodEvidence','value',private.study_method_evidence_record(e.id)));
 when 'report.read' then
  perform private.study_require(private.study_keys(p_request,array['schemaVersion','requestId','operation','reportRevisionId']),'INVALID_REQUEST');select * into r from private.study_report_revisions where id=(p_request->>'reportRevisionId')::uuid;
  perform private.study_require(found and r.template_id='lca.study-method-report.v1','FORBIDDEN');perform private.study_method_report_rights(r.study_id,r.run_ids,r.method_assessment_ids,actor,client);
  return jsonb_build_object('ok',true,'data',jsonb_build_object('type','reportRevision','value',private.study_method_report_record(r.id)));
 when 'resource.actions' then
  perform private.study_require(private.study_keys(p_request,array['schemaVersion','requestId','operation','resource']),'INVALID_REQUEST');
  if p_request->'resource'->>'type'='methodAssessment' then return private.study_method_actions(p_request->'resource',actor,client);end if;
  return api.qry_study_method_review_v1(p_request);
 when 'task.read' then return private.study_method_task(p_request);
 when 'study.resources.list' then return private.study_method_list(p_request);
 when 'artifact.read' then return private.study_method_artifact_intent(p_request);
 else return jsonb_build_object('ok',false,'code','CAPABILITY_UNAVAILABLE');end case;
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
when invalid_text_representation or invalid_parameter_value or numeric_value_out_of_range then return jsonb_build_object('ok',false,'code','INVALID_REQUEST');end$$;

ALTER FUNCTION "api"."qry_study_method_v1"("p_request" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."qry_study_method_v1"("p_request" "jsonb") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."qry_study_method_v1"("p_request" "jsonb") TO "authenticated";
