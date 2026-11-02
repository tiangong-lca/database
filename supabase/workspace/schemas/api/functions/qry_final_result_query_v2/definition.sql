CREATE OR REPLACE FUNCTION "api"."qry_final_result_query_v2"("p_result_id" "uuid", "p_result_version" "text", "p_publication_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
declare v_data jsonb; v_target text; v_runtime private.final_result_query_runtime_revisions%rowtype;
begin
 if auth.uid() is null then return private.lca_release_error('auth_required',401,'Authentication required'); end if;
 if p_result_id is null or coalesce(p_result_version,'') !~ '^[0-9]{2}\.[0-9]{2}\.[0-9]{3}$' then
   raise exception using errcode='22023',message='Exact final Result identity is required'; end if;
 select jsonb_build_object('publicationId',p.id,'releaseVersion',p.release_version,'scope',jsonb_build_object('kind','publication','publicationId',p.id),
   'artifact',a.artifact_ref,'result',jsonb_build_object('uuid',m.result_id,'version',m.result_version),'relationKind',q.relation_kind,
   'lciAvailable',true,'lciaAvailable',a.impact_count>0),plan.target_hash into v_data,v_target
 from private.lca_release_publications p join private.final_result_publication_bindings binding on binding.publication_id=p.id
 join private.lca_release_runs r on r.id=p.release_run_id and r.publication_format='final-result-pair.v2' and r.status in ('published','readback_verified')
 join private.final_result_release_plans plan on plan.release_run_id=r.id
 join private.final_result_release_members m on m.release_run_id=r.id and m.result_id=p_result_id and m.result_version=p_result_version
 join private.final_result_query_artifacts a on a.id=m.artifact_id
 join private.final_result_query_rows q on q.artifact_id=m.artifact_id and q.row_ordinal=m.row_ordinal and q.result_id=m.result_id and q.result_version=m.result_version
 join private.final_result_identities i on i.result_id=q.result_id and i.result_version=q.result_version and i.registration_id=q.registration_id
   and i.content_hash=q.content_hash and i.registration_kind='registered'
 where p.publication_series_key='global' and p.publication_channel='public' and p.visibility_scope='public' and p.is_current and p.status='current'
   and (p_publication_id is null or p.id=p_publication_id);
 if v_data is null then return private.lca_release_error('published_result_not_available',404,'Exact Result is not in the current publication'); end if;
 select rev.* into v_runtime from private.final_result_query_runtime_head h join private.final_result_query_runtime_revisions rev on rev.id=h.revision_id where h.singleton;
 if not found or not v_runtime.enabled or v_runtime.target_hash<>v_target then
   return private.lca_release_error('result_query_runtime_unavailable',503,'Published Result reader is unavailable'); end if;
 return jsonb_build_object('ok',true,'data',v_data||jsonb_build_object('runtimeRevision',v_runtime.id,'readerSha256',v_runtime.reader_sha256));
end;
$_$;

ALTER FUNCTION "api"."qry_final_result_query_v2"("p_result_id" "uuid", "p_result_version" "text", "p_publication_id" "uuid") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."qry_final_result_query_v2"("p_result_id" "uuid", "p_result_version" "text", "p_publication_id" "uuid") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."qry_final_result_query_v2"("p_result_id" "uuid", "p_result_version" "text", "p_publication_id" "uuid") TO "authenticated";
