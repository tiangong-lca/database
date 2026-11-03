CREATE OR REPLACE FUNCTION "private"."study_source_ref"("p_kind" "text", "p_ref" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" IMMUTABLE
    SET "search_path" TO ''
    AS $_$ begin
  perform private.study_require(jsonb_typeof(p_ref)='object' and private.study_text(p_ref->'@refObjectId',128,'^[A-Za-z0-9][A-Za-z0-9._:-]*$')
    and private.study_text(p_ref->'@version',9,'^[0-9]{2}\.[0-9]{2}\.[0-9]{3}$'),'REFERENCE_MISMATCH');
  return jsonb_build_object('kind',p_kind,'id',p_ref->>'@refObjectId','version',p_ref->>'@version');
end $_$;

ALTER FUNCTION "private"."study_source_ref"("p_kind" "text", "p_ref" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_source_ref"("p_kind" "text", "p_ref" "jsonb") FROM PUBLIC;
