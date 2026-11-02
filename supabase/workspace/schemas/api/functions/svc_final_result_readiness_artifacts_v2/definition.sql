CREATE OR REPLACE FUNCTION "api"."svc_final_result_readiness_artifacts_v2"("p_verification_id" "uuid", "p_proofs" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
declare v_attempt private.final_result_release_verifications%rowtype; v_context jsonb; v_proof jsonb; v_old jsonb;
 v_id uuid; v_artifact private.final_result_query_artifacts%rowtype; v_files jsonb; v_probe jsonb; v_expected jsonb;
 v_first text; v_last text; v_count bigint; v_keys text[]; v_actual text[]; v_started timestamptz; v_checked timestamptz;
 v_n bigint; v_pages integer; v_impact integer; v_inserted integer:=0;
begin
 if p_verification_id is null or p_proofs is null or jsonb_typeof(p_proofs)<>'array' or jsonb_array_length(p_proofs) not between 1 and 100
   or pg_column_size(p_proofs)>1048576 or octet_length(p_proofs::text)>1048576 then
   raise exception using errcode='22023',message='Invalid bounded final Result readiness batch'; end if;
 perform pg_advisory_xact_lock(883,hashtext(p_verification_id::text));
 select * into v_attempt from private.final_result_release_verifications where id=p_verification_id;
 if not found then raise exception using errcode='55000',message='Final Result readiness attempt is absent'; end if;
 for v_proof in select value from jsonb_array_elements(p_proofs) loop
   if jsonb_typeof(v_proof)<>'object' or (select count(*) from jsonb_object_keys(v_proof))<>5
     or pg_column_size(v_proof)>65536 or octet_length(v_proof::text)>65536 then
     raise exception using errcode='22023',message='Invalid final Result artifact proof'; end if;
   v_id:=(v_proof#>>'{artifact,artifactId}')::uuid;
   select proof into v_old from private.final_result_release_artifact_proofs where verification_id=p_verification_id and artifact_id=v_id;
   if found then
     if v_old<>v_proof then raise exception using errcode='23505',message='Final Result artifact proof identity conflict'; end if;
     continue;
   end if;
   if exists(select 1 from private.final_result_release_readiness where verification_id=p_verification_id) then
     raise exception using errcode='55000',message='Final Result readiness is sealed'; end if;
   v_context:=private.final_result_verification_context(v_attempt.release_run_id,v_attempt.header->>'publishPlanHash',(v_attempt.header->>'actorId')::uuid);
   if (v_attempt.header-array['schemaVersion','verificationId','startedAt','candidateFilesVerifiedAt','candidateFiles'])
       is distinct from (v_context-array['scope','publicationAuthorized']) then
     raise exception using errcode='55000',message='Final Result verification context changed'; end if;
   select * into v_artifact from private.final_result_query_artifacts where id=v_id;
   select min((result_id::text||'@'||result_version) collate "C"),max((result_id::text||'@'||result_version) collate "C"),count(*)
     into v_first,v_last,v_count from private.final_result_release_members where release_run_id=v_attempt.release_run_id and artifact_id=v_id;
   if v_artifact.id is null or v_count=0 or v_proof->'artifact' is distinct from v_artifact.artifact_ref
     or v_proof->'selectedResultCount' is distinct from to_jsonb(v_count) then
     raise exception using errcode='22023',message='Final Result artifact selection mismatch'; end if;
   select receipt->'files' into v_files from private.final_result_query_seals where artifact_id=v_id and target_hash=v_context->>'targetHash';
   if v_proof->'files' is distinct from v_files then
     raise exception using errcode='22023',message='Final Result artifact file coverage mismatch'; end if;
   v_checked:=(v_proof->>'filesVerifiedAt')::timestamptz;
   if v_checked is null or not isfinite(v_checked) or v_checked<(v_attempt.header->>'startedAt')::timestamptz
     or (v_attempt.header->>'startedAt')::timestamptz<clock_timestamp()-interval '1 hour' or v_checked>clock_timestamp()+interval '30 seconds' then
     raise exception using errcode='22023',message='Final Result file verification is stale or invalid'; end if;
   v_keys:=case when v_first=v_last then array[v_first] else array[v_first,v_last] end;
   if jsonb_typeof(v_proof->'probes') is distinct from 'array' or jsonb_array_length(v_proof->'probes')<>cardinality(v_keys) then
     raise exception using errcode='22023',message='Final Result probe coverage mismatch'; end if;
   select array_agg((value#>>'{result,uuid}')||'@'||(value#>>'{result,version}') order by ((value#>>'{result,uuid}')||'@'||(value#>>'{result,version}')) collate "C")
     into v_actual from jsonb_array_elements(v_proof->'probes');
   if v_actual is distinct from v_keys then raise exception using errcode='22023',message='Final Result probe coverage mismatch'; end if;
   for v_probe in select value from jsonb_array_elements(v_proof->'probes') loop
     select v_context||jsonb_build_object('artifact',v_artifact.artifact_ref,'result',jsonb_build_object('uuid',m.result_id,'version',m.result_version),
       'contentHash',q.content_hash,'lciAvailable',true,'lciaAvailable',v_artifact.impact_count>0)
       into v_expected from private.final_result_release_members m join private.final_result_query_rows q
       on q.artifact_id=m.artifact_id and q.row_ordinal=m.row_ordinal and q.result_id=m.result_id and q.result_version=m.result_version
       join private.final_result_identities i on i.result_id=q.result_id and i.result_version=q.result_version
       and i.registration_id=q.registration_id and i.content_hash=q.content_hash and i.registration_kind='registered'
       where m.release_run_id=v_attempt.release_run_id and m.artifact_id=v_id and m.result_id=(v_probe#>>'{result,uuid}')::uuid and m.result_version=v_probe#>>'{result,version}';
     if v_expected is null or v_probe->>'schemaVersion' is distinct from 'tiangong.final-result-reader-probe.v1'
       or (v_probe-array['schemaVersion','startedAt','verifiedAt','lciNonzeroCount','lciPageCount','lciaCount','queryCount','observationsSha256']) is distinct from v_expected
       or coalesce(v_probe->>'observationsSha256','') !~ '^[0-9a-f]{64}$' then
       raise exception using errcode='22023',message='Final Result reader probe binding mismatch'; end if;
     v_started:=(v_probe->>'startedAt')::timestamptz; v_checked:=(v_probe->>'verifiedAt')::timestamptz;
     if v_started is null or v_checked is null or not isfinite(v_started) or not isfinite(v_checked)
       or v_started<greatest(clock_timestamp()-interval '15 minutes',(v_attempt.header->>'startedAt')::timestamptz)
       or v_checked<v_started or v_checked>clock_timestamp()+interval '30 seconds' then
       raise exception using errcode='22023',message='Final Result reader verification is stale or invalid'; end if;
     if jsonb_typeof(v_probe->'lciNonzeroCount') is distinct from 'number' or coalesce(v_probe->>'lciNonzeroCount','') !~ '^[0-9]+$' then
       raise exception using errcode='22023',message='Final Result probe count mismatch'; end if;
     v_n:=(v_probe->>'lciNonzeroCount')::bigint;
     v_pages:=1+ceil(greatest(v_n-1,0)::numeric/1000)::integer;
     v_impact:=v_artifact.impact_count;
     if v_n>2000000 or v_probe->'lciPageCount' is distinct from to_jsonb(v_pages)
       or v_probe->'lciaCount' is distinct from to_jsonb(v_impact)
       or v_probe->'queryCount' is distinct from to_jsonb(v_pages+1+case when v_impact>0 then 1 else 0 end) then
       raise exception using errcode='22023',message='Final Result probe count mismatch'; end if;
   end loop;
   insert into private.final_result_release_artifact_proofs(verification_id,artifact_id,proof,proof_sha256)
     values(p_verification_id,v_id,v_proof,encode(extensions.digest(convert_to(v_proof::text,'UTF8'),'sha256'),'hex'));
   v_inserted:=v_inserted+1;
 end loop;
 return jsonb_build_object('ok',true,'data',jsonb_build_object('verificationId',p_verification_id,'insertedArtifactCount',v_inserted,'publicationAuthorized',false));
end;
$_$;

ALTER FUNCTION "api"."svc_final_result_readiness_artifacts_v2"("p_verification_id" "uuid", "p_proofs" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."svc_final_result_readiness_artifacts_v2"("p_verification_id" "uuid", "p_proofs" "jsonb") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."svc_final_result_readiness_artifacts_v2"("p_verification_id" "uuid", "p_proofs" "jsonb") TO "service_role";
