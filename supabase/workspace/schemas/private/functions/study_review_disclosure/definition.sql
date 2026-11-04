CREATE OR REPLACE FUNCTION "private"."study_review_disclosure"("p_report" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$declare r private.study_report_revisions%rowtype;issuer uuid;rid text;scope jsonb;begin
 select * into r from private.study_report_revisions where id=p_report;perform private.study_require(found and r.status='frozen','REFERENCE_MISMATCH');
 select owner_id into issuer from private.studies where id=r.study_id;
 perform private.study_require(private.study_report_rights(r.study_id,r.run_ids,r.analysis_ids,issuer,null)=r.facts_refs,'REFERENCE_MISMATCH');
 for rid in select jsonb_array_elements_text(r.run_ids) loop
  select ss.source_authorization->'sourceScope' into scope from private.study_runs rn
   join private.study_source_snapshots ss on ss.id=private.study_preparation_snapshot(r.study_id,rn.preparation_id) where rn.id=rid::uuid and rn.study_id=r.study_id;
  perform private.study_require(jsonb_typeof(scope)='array' and not exists(select 1 from jsonb_array_elements(scope)d
   where coalesce((d->>'stateCode')::integer not in (0,100),true) or ((d->>'stateCode')::integer=0 and (d->>'ownerActorId') is distinct from issuer::text)),'DISCLOSURE_DENIED');
 end loop;
end$$;

ALTER FUNCTION "private"."study_review_disclosure"("p_report" "uuid") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_review_disclosure"("p_report" "uuid") FROM PUBLIC;
