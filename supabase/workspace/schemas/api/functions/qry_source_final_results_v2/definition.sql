CREATE OR REPLACE FUNCTION "api"."qry_source_final_results_v2"("p_source_id" "uuid", "p_source_version" "text", "p_after_key" "text" DEFAULT NULL::"text", "p_limit" integer DEFAULT 100, "p_publication_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
declare v_publication private.lca_release_publications%rowtype; v_format text; v_rows jsonb; v_next text;
begin
 if auth.uid() is null then return private.lca_release_error('auth_required',401,'Authentication required'); end if;
 if p_source_id is null or coalesce(p_source_version,'') !~ '^[0-9]{2}\.[0-9]{2}\.[0-9]{3}$'
   or p_limit is null or p_limit not between 1 and 100 or (p_after_key is not null and (p_publication_id is null or p_after_key !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}@[0-9]{2}\.[0-9]{2}\.[0-9]{3}$')) then
   raise exception using errcode='22023',message='Invalid bounded exact source Result lookup'; end if;
 if not private.final_result_source_readable(p_source_id,p_source_version) then
   return private.lca_release_error('source_not_available',404,'Exact source Process is not readable'); end if;
 select p.* into v_publication from private.lca_release_publications p where p.publication_series_key='global' and p.publication_channel='public'
   and p.visibility_scope='public' and p.is_current and p.status='current';
 if not found then
   if p_publication_id is not null then return private.lca_release_error('publication_changed',409,'Restart source Result selection against current publication'); end if;
   return jsonb_build_object('ok',true,'data',jsonb_build_object('publication',null,'results','[]'::jsonb,'nextResultKey',null));
 end if;
 if p_publication_id is not null and p_publication_id<>v_publication.id then return private.lca_release_error('publication_changed',409,'Restart source Result selection against current publication'); end if;
 select publication_format into v_format from private.lca_release_runs where id=v_publication.release_run_id;
 if v_format='final-result-pair.v2' then
   with chosen as (select m.result_id,m.result_version,m.result_id::text||'@'||m.result_version key,a.impact_count
     from private.final_result_publication_bindings b join private.final_result_release_members m on m.release_run_id=v_publication.release_run_id
     join private.final_result_query_rows q on q.artifact_id=m.artifact_id and q.row_ordinal=m.row_ordinal and q.result_id=m.result_id and q.result_version=m.result_version and q.relation_kind='direct'
     join private.final_result_query_sources s on s.artifact_id=q.artifact_id and s.row_ordinal=q.row_ordinal and s.source_id=p_source_id and s.source_version=p_source_version
     join private.final_result_query_artifacts a on a.id=m.artifact_id where b.publication_id=v_publication.id
       and (p_after_key is null or (m.result_id::text||'@'||m.result_version) collate "C">p_after_key collate "C")
     order by m.result_id,m.result_version collate "C" limit p_limit+1),
   numbered as (select *,row_number() over(order by key collate "C") n from chosen)
   select coalesce(jsonb_agg(jsonb_build_object('uuid',result_id,'version',result_version,'relationKind','direct','lciAvailable',true,'lciaAvailable',impact_count>0)
     order by key collate "C") filter(where n<=p_limit),'[]'::jsonb),case when count(*)>p_limit then max(key collate "C") filter(where n=p_limit) else null end
     into v_rows,v_next from numbered;
 end if;
 return jsonb_build_object('ok',true,'data',jsonb_build_object('publication',jsonb_build_object('publicationId',v_publication.id,
   'releaseVersion',v_publication.release_version,'format',v_format),'results',coalesce(v_rows,'[]'::jsonb),'nextResultKey',v_next));
end;
$_$;

ALTER FUNCTION "api"."qry_source_final_results_v2"("p_source_id" "uuid", "p_source_version" "text", "p_after_key" "text", "p_limit" integer, "p_publication_id" "uuid") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."qry_source_final_results_v2"("p_source_id" "uuid", "p_source_version" "text", "p_after_key" "text", "p_limit" integer, "p_publication_id" "uuid") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."qry_source_final_results_v2"("p_source_id" "uuid", "p_source_version" "text", "p_after_key" "text", "p_limit" integer, "p_publication_id" "uuid") TO "authenticated";
