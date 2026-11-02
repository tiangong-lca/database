CREATE OR REPLACE FUNCTION "api"."svc_final_result_readiness_seal_v2"("p_verification_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare v_attempt private.final_result_release_verifications%rowtype; v_context jsonb; v_receipt jsonb;
 v_count bigint; v_expected bigint; v_probe_count bigint; v_files bigint; v_expires timestamptz; v_hash text;
begin
 if p_verification_id is null then raise exception using errcode='22023',message='Final Result verification identity is required'; end if;
 perform pg_advisory_xact_lock(883,hashtext(p_verification_id::text));
 select receipt into v_receipt from private.final_result_release_readiness where verification_id=p_verification_id;
 if found then return jsonb_build_object('ok',true,'data',v_receipt); end if;
 select * into v_attempt from private.final_result_release_verifications where id=p_verification_id;
 if not found then raise exception using errcode='55000',message='Final Result readiness attempt is absent'; end if;
 v_context:=private.final_result_verification_context(v_attempt.release_run_id,v_attempt.header->>'publishPlanHash',(v_attempt.header->>'actorId')::uuid);
 if (v_attempt.header-array['schemaVersion','verificationId','startedAt','candidateFilesVerifiedAt','candidateFiles'])
     is distinct from (v_context-array['scope','publicationAuthorized']) then
   raise exception using errcode='55000',message='Final Result verification context changed'; end if;
 select count(distinct artifact_id) into v_expected from private.final_result_release_members where release_run_id=v_attempt.release_run_id;
 select count(*),coalesce(sum(jsonb_array_length(proof->'probes')),0),coalesce(sum(jsonb_array_length(proof->'files')),0)+4
   into v_count,v_probe_count,v_files from private.final_result_release_artifact_proofs where verification_id=p_verification_id;
 if v_count<>v_expected or v_count=0 then raise exception using errcode='55000',message='Final Result readiness coverage is incomplete'; end if;
 select least((v_attempt.header->>'startedAt')::timestamptz+interval '1 hour',min((p.value->>'startedAt')::timestamptz)+interval '15 minutes')
   into v_expires from private.final_result_release_artifact_proofs a cross join lateral jsonb_array_elements(a.proof->'probes') p
   where verification_id=p_verification_id;
 if v_expires<=clock_timestamp() then raise exception using errcode='55000',message='Final Result readiness evidence expired'; end if;
 -- Database-only JSONB proof hashes, never represented as canonical content/JCS.
 with numbered as (select artifact_id,proof_sha256,(row_number() over(order by artifact_id)-1)/500 block
   from private.final_result_release_artifact_proofs where verification_id=p_verification_id),
 blocks as (select block,encode(extensions.digest(convert_to(string_agg(artifact_id::text||'@'||proof_sha256||E'\n','' order by artifact_id),'UTF8'),'sha256'),'hex') hash
   from numbered group by block)
 select encode(extensions.digest(convert_to('tiangong.final-result-readiness-coverage.jsonb.v1'||E'\n'||string_agg(hash||E'\n','' order by block),'UTF8'),'sha256'),'hex') into v_hash from blocks;
 v_receipt:=v_context||jsonb_build_object('schemaVersion','tiangong.final-result-readiness.v1','verificationId',p_verification_id,
   'artifactCount',v_count,'probeCount',v_probe_count,'fileCount',v_files,'coverageHash',v_hash,'expiresAt',v_expires,'sealedAt',clock_timestamp());
 insert into private.final_result_release_readiness(verification_id,receipt,expires_at) values(p_verification_id,v_receipt,v_expires);
 return jsonb_build_object('ok',true,'data',v_receipt);
end;
$$;

ALTER FUNCTION "api"."svc_final_result_readiness_seal_v2"("p_verification_id" "uuid") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."svc_final_result_readiness_seal_v2"("p_verification_id" "uuid") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."svc_final_result_readiness_seal_v2"("p_verification_id" "uuid") TO "service_role";
