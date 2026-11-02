CREATE OR REPLACE FUNCTION "api"."svc_final_result_readiness_begin_v2"("p_header" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare v_id uuid; v_run uuid; v_old jsonb; v_context jsonb; v_files jsonb; v_started timestamptz; v_checked timestamptz;
begin
 if p_header is null or jsonb_typeof(p_header)<>'object' or pg_column_size(p_header)>32768
   or octet_length(p_header::text)>32768 or (select count(*) from jsonb_object_keys(p_header))<>15
   or p_header->>'schemaVersion' is distinct from 'tiangong.final-result-readiness-attempt.v1' then
   raise exception using errcode='22023',message='Invalid final Result readiness attempt'; end if;
 v_id:=(p_header->>'verificationId')::uuid; v_run:=(p_header->>'releaseRunId')::uuid;
 if v_id is null or v_run is null then raise exception using errcode='22023',message='Invalid final Result readiness attempt'; end if;
 perform pg_advisory_xact_lock(883,hashtext(v_id::text));
 select header into v_old from private.final_result_release_verifications where id=v_id;
 if found then
   if v_old<>p_header then raise exception using errcode='23505',message='Final Result readiness attempt identity conflict'; end if;
   return jsonb_build_object('ok',true,'data',jsonb_build_object('verificationId',v_id,'releaseRunId',v_run,'reused',true,'publicationAuthorized',false));
 end if;
 v_context:=private.final_result_verification_context(v_run,p_header->>'publishPlanHash',(p_header->>'actorId')::uuid);
 if (p_header-array['schemaVersion','verificationId','startedAt','candidateFilesVerifiedAt','candidateFiles'])
    is distinct from (v_context-array['scope','publicationAuthorized']) then
   raise exception using errcode='22023',message='Final Result readiness context mismatch'; end if;
 v_started:=(p_header->>'startedAt')::timestamptz; v_checked:=(p_header->>'candidateFilesVerifiedAt')::timestamptz;
 if v_started is null or v_checked is null or not isfinite(v_started) or not isfinite(v_checked)
   or v_started<clock_timestamp()-interval '1 hour' or v_checked<v_started or v_checked>clock_timestamp()+interval '30 seconds' then
   raise exception using errcode='22023',message='Final Result file verification is stale or invalid'; end if;
 select receipt->'files' into v_files from private.final_result_candidate_storage
   where candidate_hash=p_header->>'candidateHash' and target_hash=p_header->>'targetHash';
 if p_header->'candidateFiles' is distinct from v_files then
   raise exception using errcode='22023',message='Final Result Candidate file coverage mismatch'; end if;
 insert into private.final_result_release_verifications(id,release_run_id,runtime_revision,header)
   values(v_id,v_run,(p_header->>'runtimeRevision')::uuid,p_header);
 return jsonb_build_object('ok',true,'data',jsonb_build_object('verificationId',v_id,'releaseRunId',v_run,'reused',false,'publicationAuthorized',false));
end;
$$;

ALTER FUNCTION "api"."svc_final_result_readiness_begin_v2"("p_header" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."svc_final_result_readiness_begin_v2"("p_header" "jsonb") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."svc_final_result_readiness_begin_v2"("p_header" "jsonb") TO "service_role";
