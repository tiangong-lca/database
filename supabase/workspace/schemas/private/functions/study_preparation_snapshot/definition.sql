CREATE OR REPLACE FUNCTION "private"."study_preparation_snapshot"("p_study" "uuid", "p_preparation" "uuid") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare p private.study_model_preparations%rowtype; v_id uuid:=p_preparation; seen uuid[]:='{}'; result uuid;
begin
  loop
    perform private.study_require(v_id is not null and not v_id=any(seen) and cardinality(seen)<512,'REFERENCE_MISMATCH'); seen:=seen||v_id;
    select * into p from private.study_model_preparations where study_id=p_study and study_model_preparations.id=v_id;
    perform private.study_require(found,'REFERENCE_MISMATCH');
    if p.source_snapshot_id is not null then return p.source_snapshot_id; end if;
    select preparation_id into v_id from private.study_revisions where study_id=p_study and study_revisions.id=p.source_study_revision_id and status='frozen';
  end loop;
end $$;

ALTER FUNCTION "private"."study_preparation_snapshot"("p_study" "uuid", "p_preparation" "uuid") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_preparation_snapshot"("p_study" "uuid", "p_preparation" "uuid") FROM PUBLIC;
