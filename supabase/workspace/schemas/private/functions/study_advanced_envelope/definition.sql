CREATE OR REPLACE FUNCTION "private"."study_advanced_envelope"("p_request" "jsonb", "p_write" boolean) RETURNS "void"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $_$declare field text;value jsonb;entry jsonb;pattern text:='^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';begin
 perform private.study_require(auth.uid() is not null and not coalesce(util.is_service_request(),false),'AUTH_REQUIRED');
 perform private.study_require(p_request->>'schemaVersion'='lca.study-api.v5' and octet_length(p_request::text)<=262144
  and private.study_text(p_request->'requestId',128,'^[A-Za-z0-9][A-Za-z0-9._:-]*$'),'INVALID_REQUEST');
 if p_write then perform private.study_require(private.study_text(p_request->'idempotencyKey',128,'^[A-Za-z0-9][A-Za-z0-9._:-]*$'),'INVALID_REQUEST');end if;
 -- Issued domain references are opaque exact identities. PostgreSQL accepts
 -- UUID aliases, but resolving an alias would change the response binding
 -- after effects. Reject it before every domain cast, receipt or intent.
 foreach field in array array['target','resource','artifactRef'] loop
  if p_request ? field then
   perform private.study_require(jsonb_typeof(p_request->field)='object'
    and private.study_text(p_request->field->'id',36,pattern),'INVALID_REQUEST');
  end if;
 end loop;
 foreach field in array array['studyId','analysisId','baselineRunId','reportRevisionId','parentReportRevisionId','cursor'] loop
  if not p_request ? field then continue;end if;value:=p_request->field;
  if value='null'::jsonb and field in ('parentReportRevisionId','cursor') then continue;end if;
  perform private.study_require(private.study_text(value,36,pattern),'INVALID_REQUEST');
 end loop;
 if p_request ? 'runIds' or p_request ? 'analysisIds' then
 foreach field in array array['runIds','analysisIds'] loop
 if not p_request ? field then continue;end if;
  perform private.study_require(jsonb_typeof(p_request->field)='array','INVALID_REQUEST');
  perform private.study_require(jsonb_array_length(p_request->field)<=64,'INVALID_REQUEST');
  for entry in select * from jsonb_array_elements(p_request->field) loop
   perform private.study_require(private.study_text(entry,36,pattern),'INVALID_REQUEST');
  end loop;
 end loop;
 end if;
end$_$;

ALTER FUNCTION "private"."study_advanced_envelope"("p_request" "jsonb", "p_write" boolean) OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_advanced_envelope"("p_request" "jsonb", "p_write" boolean) FROM PUBLIC;
