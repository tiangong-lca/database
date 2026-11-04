CREATE OR REPLACE FUNCTION "api"."qry_study_reporting_v1"("p_request" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$declare op text:=p_request->>'operation';actor uuid:=auth.uid();client text:=nullif(auth.jwt()->>'client_id','');r private.study_report_revisions%rowtype;e private.study_report_exports%rowtype;result jsonb;ops jsonb;cfg private.study_reporting_config%rowtype;begin
 perform private.study_reporting_envelope(p_request,false);
 if op='artifact.read' then perform private.study_require(p_request->'artifactRef'->>'type' in ('analysisFacts','reportContent','reportProjection','renderResources','reportExportBundle'),'INVALID_REQUEST');end if;
 if op='study.resources.list' then return private.study_reporting_list(p_request);end if;
 if op='report.read' then
  perform private.study_require(private.study_keys(p_request,array['schemaVersion','requestId','operation','reportRevisionId']),'INVALID_REQUEST');
  select * into r from private.study_report_revisions where id=(p_request->>'reportRevisionId')::uuid;perform private.study_require(found and r.template_id='lca.study-report.v1','FORBIDDEN');
  perform private.study_report_rights(r.study_id,r.run_ids,r.analysis_ids,actor,client);
  return jsonb_build_object('ok',true,'data',jsonb_build_object('type','reportRevision','value',private.study_report_record(r.id)));
 elsif op='export.read' then
  perform private.study_require(private.study_keys(p_request,array['schemaVersion','requestId','operation','exportId']),'INVALID_REQUEST');e:=private.study_report_export_authorize((p_request->>'exportId')::uuid,actor,client);
  return jsonb_build_object('ok',true,'data',jsonb_build_object('type','export','value',e.record));
 end if;
 result:=private.study_qry_analysis_v1(p_request);
 if op='capability.read' and result->>'ok'='true' then
  ops:=result->'data'->'operations'||jsonb_build_array('study.resources.list','report.read','export.read');select * into cfg from private.study_reporting_config where singleton;
  if private.study_client_allowed(client,'STUDY-WRITE-01') and private.study_client_allowed(client,'DB-CORE-READ-01') then
   if cfg.report_enabled then ops:=ops||jsonb_build_array('report.create','report.save','report.freeze');end if;
   if cfg.export_enabled then ops:=ops||jsonb_build_array('export.request');end if;
  end if;
  result:=jsonb_set(jsonb_set(result,'{data,operations}',ops),'{data,runtimeEnabled}',to_jsonb(jsonb_array_length(ops)>1));
 end if;return result;
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
when invalid_text_representation or invalid_parameter_value then return jsonb_build_object('ok',false,'code','INVALID_REQUEST');
end$$;

ALTER FUNCTION "api"."qry_study_reporting_v1"("p_request" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."qry_study_reporting_v1"("p_request" "jsonb") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."qry_study_reporting_v1"("p_request" "jsonb") TO "authenticated";
