CREATE OR REPLACE FUNCTION "private"."study_method_report_content_valid"("p_value" "jsonb") RETURNS boolean
    LANGUAGE "plpgsql" STABLE
    SET "search_path" TO ''
    AS $_$
declare c jsonb;r jsonb;section jsonb;typ text;idkey text;claimids jsonb;seen text[];v text;
begin
 if not private.study_keys(p_value,array['schemaVersion','title','claims','sections','tables','charts','additionalLimitations'])
 or p_value->>'schemaVersion' is distinct from 'lca.study-method-report-draft.v1' or not private.study_report_plain(p_value->'title',256)
 or jsonb_typeof(p_value->'claims') is distinct from 'array' then return false;end if;
 if jsonb_array_length(p_value->'claims') not between 1 and 256 then return false;end if;
 claimids:='[]';
 for c in select * from jsonb_array_elements(p_value->'claims') loop
  if not private.study_keys(c,array['claimId','bundleRef','factId','canonicalValue','unit','display'])
  or not private.study_text(c->'claimId',128,'^[A-Za-z0-9][A-Za-z0-9._:-]*$') or not private.study_text(c->'factId',128,'^[A-Za-z0-9][A-Za-z0-9._:-]*$')
  or not private.study_report_plain(c->'unit',128) or c->'display'<>'{"style":"exact"}'::jsonb
  or not private.study_keys(c->'bundleRef',array['type','id','contentHash','digestScope','byteSize','mediaType','schemaVersion'])
  or c->'bundleRef'->>'type' is distinct from 'methodAssessmentFacts' or c->'bundleRef'->>'schemaVersion' is distinct from 'lca.study-method-assessment-facts.v1'
  or c->'bundleRef'->>'mediaType' is distinct from 'application/json' then return false;end if;
  if c->'canonicalValue'<>'null'::jsonb then
   v:=c->>'canonicalValue';
   if not private.study_text(c->'canonicalValue',64,'^-?(0|[1-9][0-9]*)(\.[0-9]*[1-9])?(e-?[1-9][0-9]{0,2})?$')
   or (v ~ '^-?0(e.*)?$' and v<>'0') or (v like '%e%' and abs(split_part(v,'e',2)::integer)>324) then return false;end if;
  end if;
  claimids:=claimids||jsonb_build_array(c->'claimId');
 end loop;
 if not private.study_report_ids(claimids,1,256) then return false;end if;
 foreach typ in array array['sections','tables','charts'] loop
  if jsonb_typeof(p_value->typ) is distinct from 'array' then return false;end if;
  if jsonb_array_length(p_value->typ)>32 then return false;end if;
  idkey:=case typ when 'sections' then 'sectionId' when 'tables' then 'tableId' else 'chartId' end;seen:='{}'::text[];
  for r in select * from jsonb_array_elements(p_value->typ) loop
   if not private.study_keys(r,case when typ='sections' then array[idkey,'title','paragraphs','claimIds'] else array[idkey,'title','claimIds'] end)
   or not private.study_text(r->idkey,128,'^[A-Za-z0-9][A-Za-z0-9._:-]*$') or (r->>idkey)=any(seen)
   or not private.study_report_plain(r->'title',256) or not private.study_report_ids(r->'claimIds',case when typ='sections' then 0 else 1 end,case when typ='charts' then 64 else 256 end)
   or not (r->'claimIds')<@claimids then return false;end if;seen:=seen||(r->>idkey);
   if typ='sections' then
    if jsonb_typeof(r->'paragraphs') is distinct from 'array' then return false;end if;
    if jsonb_array_length(r->'paragraphs')>32 then return false;end if;
    for section in select * from jsonb_array_elements(r->'paragraphs') loop if not private.study_report_plain(section,2048) then return false;end if;end loop;
   end if;
  end loop;
 end loop;
 if jsonb_typeof(p_value->'additionalLimitations') is distinct from 'array' then return false;end if;
 if jsonb_array_length(p_value->'additionalLimitations')>32 then return false;end if;
 for r in select * from jsonb_array_elements(p_value->'additionalLimitations') loop if not private.study_report_plain(r,2048) then return false;end if;end loop;
 return true;
exception when invalid_text_representation then return false;
end$_$;

ALTER FUNCTION "private"."study_method_report_content_valid"("p_value" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_method_report_content_valid"("p_value" "jsonb") FROM PUBLIC;
