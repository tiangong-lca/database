CREATE OR REPLACE FUNCTION "private"."study_advanced_parameters"("p_request" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$declare actor uuid:=auth.uid();client text:=nullif(auth.jwt()->>'client_id','');sid uuid:=(p_request->>'studyId')::uuid;rid uuid:=(p_request->>'baselineRunId')::uuid;snapshot uuid;intent uuid;expiry timestamptz;begin
 perform private.study_advanced_envelope(p_request,false);
 perform private.study_require(private.study_keys(p_request,array['schemaVersion','requestId','operation','studyId','baselineRunId']) and p_request->>'operation'='analysis.parameters.read','INVALID_REQUEST');
 snapshot:=private.study_advanced_rights(sid,rid,actor,client);
 perform pg_advisory_xact_lock(hashtextextended('study-advanced-parameter-intent:'||actor::text,909));
 with expired as(select id from private.study_advanced_parameter_intents where expires_at<=clock_timestamp() order by expires_at,id limit 256 for update skip locked)
 delete from private.study_advanced_parameter_intents i using expired e where i.id=e.id;
 perform private.study_require((select count(*) from private.study_advanced_parameter_intents where actor_id=actor and expires_at>clock_timestamp())<64,'CAPABILITY_UNAVAILABLE');
 insert into private.study_advanced_parameter_intents(study_id,baseline_run_id,source_snapshot_id,actor_id,client_id) values(sid,rid,snapshot,actor,client) returning id,expires_at into intent,expiry;
 return jsonb_build_object('ok',true,'data',jsonb_build_object('kind','advancedParameterIntent','intentId',intent,'expiresAt',expiry,'studyId',sid,'baselineRunId',rid));
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
when invalid_text_representation then return jsonb_build_object('ok',false,'code','INVALID_REQUEST');end$$;

ALTER FUNCTION "private"."study_advanced_parameters"("p_request" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_advanced_parameters"("p_request" "jsonb") FROM PUBLIC;
