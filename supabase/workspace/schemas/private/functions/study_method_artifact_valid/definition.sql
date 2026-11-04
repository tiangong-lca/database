CREATE OR REPLACE FUNCTION "private"."study_method_artifact_valid"("p_ref" "jsonb", "p_type" "text", "p_schema" "text", "p_max" integer DEFAULT 4194304) RETURNS boolean
    LANGUAGE "plpgsql" IMMUTABLE
    SET "search_path" TO ''
    AS $_$begin
 return coalesce(private.study_keys(p_ref,array['type','id','contentHash','digestScope','byteSize','mediaType','schemaVersion'])
 and private.study_method_uuid(p_ref->'id') and p_ref->>'type'=p_type and p_ref->>'schemaVersion'=p_schema
 and p_ref->>'digestScope'='artifact_bytes_sha256' and p_ref->>'mediaType'='application/json'
 and private.study_text(p_ref->'contentHash',64,'^[0-9a-f]{64}$') and private.study_method_uint(p_ref->'byteSize',1,p_max),false);
 exception when invalid_text_representation or numeric_value_out_of_range then return false;end$_$;

ALTER FUNCTION "private"."study_method_artifact_valid"("p_ref" "jsonb", "p_type" "text", "p_schema" "text", "p_max" integer) OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_method_artifact_valid"("p_ref" "jsonb", "p_type" "text", "p_schema" "text", "p_max" integer) FROM PUBLIC;
