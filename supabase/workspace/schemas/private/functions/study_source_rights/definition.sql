CREATE OR REPLACE FUNCTION "private"."study_source_rights"("p_scope" "jsonb", "p_actor" "uuid", "p_client" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$ declare d jsonb; actual jsonb; captured_owner uuid; begin
  perform private.study_require(jsonb_typeof(p_scope)='array' and jsonb_array_length(p_scope) between 1 and 512,'DISCLOSURE_DENIED');
  for d in select * from jsonb_array_elements(p_scope) loop
    actual:=private.study_source_document(d->>'kind',coalesce(d->>'id',d->'identity'->>'id'),coalesce(d->>'version',d->'identity'->>'version'),p_actor,p_client);
    captured_owner:=nullif(d->>'ownerActorId','')::uuid;
    -- Current visibility does not retroactively publish historical draft bytes.
    -- Captured private data remains owner-bound. A nonowner may read captured
    -- public bytes only while the exact captured bytes are still public now.
    perform private.study_require(
      ((d->>'stateCode')::integer=0 and captured_owner=p_actor and nullif(actual->>'ownerActorId','')::uuid=p_actor)
      or ((d->>'stateCode')::integer=100 and (
        ((actual->>'stateCode')::integer=100 and actual->>'sha256'=d->>'sha256')
        or (captured_owner=p_actor and nullif(actual->>'ownerActorId','')::uuid=p_actor))),
      'DISCLOSURE_DENIED');
  end loop;
end $$;

ALTER FUNCTION "private"."study_source_rights"("p_scope" "jsonb", "p_actor" "uuid", "p_client" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_source_rights"("p_scope" "jsonb", "p_actor" "uuid", "p_client" "text") FROM PUBLIC;
