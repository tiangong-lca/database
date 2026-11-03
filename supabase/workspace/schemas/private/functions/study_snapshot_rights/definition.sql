CREATE OR REPLACE FUNCTION "private"."study_snapshot_rights"("p_snapshot" "uuid", "p_actor" "uuid", "p_client" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$ declare s private.study_source_snapshots%rowtype; begin
  select * into s from private.study_source_snapshots where id=p_snapshot;
  perform private.study_require(found,'REFERENCE_MISMATCH');
  perform private.study_source_rights(s.source_authorization->'sourceScope',p_actor,p_client);
end $$;

ALTER FUNCTION "private"."study_snapshot_rights"("p_snapshot" "uuid", "p_actor" "uuid", "p_client" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_snapshot_rights"("p_snapshot" "uuid", "p_actor" "uuid", "p_client" "text") FROM PUBLIC;
