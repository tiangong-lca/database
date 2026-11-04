CREATE OR REPLACE FUNCTION "private"."study_review_family"("p_request" "jsonb", "p_template" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$declare f text;rid uuid;v text;begin
 foreach f in array array['reportRevisionId','shareId','exportId','delegationId','finalizationId'] loop
  if not p_request ? f then continue;end if;v:=p_request->>f;
  if v is null then continue;end if;
  case f when 'reportRevisionId' then rid:=v::uuid;
   when 'shareId' then select report_id into rid from private.study_report_shares where id=v::uuid;
   when 'exportId' then select report_id into rid from private.study_review_exports where id=v::uuid;
   when 'delegationId' then select report_id into rid from private.study_review_delegations where id=v::uuid;
   when 'finalizationId' then select report_id into rid from private.study_report_finalizations where id=v::uuid;end case;
  perform private.study_require(exists(select 1 from private.study_report_revisions where id=rid and template_id=p_template),'FORBIDDEN');
 end loop;
 foreach f in array array['target','resource'] loop
  if not p_request ? f then continue;end if;v:=p_request->f->>'id';rid:=null;
  case p_request->f->>'type' when 'reportRevision' then rid:=v::uuid;
   when 'share' then select report_id into rid from private.study_report_shares where id=v::uuid;
   when 'export' then select report_id into rid from private.study_review_exports where id=v::uuid;
   when 'study' then continue;
   else perform private.study_require(false,'INVALID_REQUEST');end case;
  perform private.study_require(exists(select 1 from private.study_report_revisions where id=rid and template_id=p_template),'FORBIDDEN');
 end loop;
end$$;

ALTER FUNCTION "private"."study_review_family"("p_request" "jsonb", "p_template" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_review_family"("p_request" "jsonb", "p_template" "text") FROM PUBLIC;
