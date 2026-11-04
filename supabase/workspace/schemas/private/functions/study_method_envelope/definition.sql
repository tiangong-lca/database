CREATE OR REPLACE FUNCTION "private"."study_method_envelope"("p_request" "jsonb", "p_write" boolean) RETURNS "void"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $_$declare field text;value jsonb;entry jsonb;begin
 perform private.study_require(auth.uid() is not null and not coalesce(util.is_service_request(),false),'AUTH_REQUIRED');
 perform private.study_require(jsonb_typeof(p_request)='object' and p_request->>'schemaVersion'='lca.study-api.v6' and octet_length(p_request::text)<=262144
 and private.study_text(p_request->'requestId',128,'^[A-Za-z0-9][A-Za-z0-9._:-]*$'),'INVALID_REQUEST');
 if p_write then perform private.study_require(private.study_text(p_request->'idempotencyKey',128,'^[A-Za-z0-9][A-Za-z0-9._:-]*$'),'INVALID_REQUEST');end if;
 foreach field in array array['target','resource','artifactRef'] loop
  if p_request ? field then perform private.study_require(jsonb_typeof(p_request->field)='object' and private.study_method_uuid(p_request->field->'id'),'INVALID_REQUEST');end if;
 end loop;
 foreach field in array array['studyId','assessmentId','evidenceId','baselineRunId','reportRevisionId','parentReportRevisionId','cursor'] loop
  if not p_request ? field then continue;end if;value:=p_request->field;
  if value='null'::jsonb and field in('parentReportRevisionId','cursor') then continue;end if;
  perform private.study_require(private.study_method_uuid(value),'INVALID_REQUEST');
 end loop;
 foreach field in array array['runIds','methodAssessmentIds'] loop
  if not p_request ? field then continue;end if;
  perform private.study_require(jsonb_typeof(p_request->field)='array','INVALID_REQUEST');
  perform private.study_require(jsonb_array_length(p_request->field)<=1,'INVALID_REQUEST');
  for entry in select * from jsonb_array_elements(p_request->field) loop perform private.study_require(private.study_method_uuid(entry),'INVALID_REQUEST');end loop;
 end loop;
end$_$;

ALTER FUNCTION "private"."study_method_envelope"("p_request" "jsonb", "p_write" boolean) OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_method_envelope"("p_request" "jsonb", "p_write" boolean) FROM PUBLIC;
