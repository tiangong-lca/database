CREATE OR REPLACE FUNCTION "api"."svc_result_query_runtime_read_v2"() RETURNS "jsonb"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select jsonb_build_object('ok',true,'data',(select jsonb_build_object('runtimeRevision',r.id,'targetHash',r.target_hash,
    'readerSha256',r.reader_sha256,'enabled',r.enabled,'publicationAuthorized',false)
    from private.final_result_query_runtime_head h join private.final_result_query_runtime_revisions r on r.id=h.revision_id where h.singleton));
$$;

ALTER FUNCTION "api"."svc_result_query_runtime_read_v2"() OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."svc_result_query_runtime_read_v2"() FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."svc_result_query_runtime_read_v2"() TO "service_role";
