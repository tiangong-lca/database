CREATE OR REPLACE FUNCTION "private"."study_qry_core_v1"("p_request" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    SET "statement_timeout" TO '15s'
    AS $_$
declare op text:=p_request->>'operation'; actor uuid:=auth.uid(); client text:=nullif(auth.jwt()->>'client_id',''); sid uuid; rid uuid; kind text; v jsonb; items jsonb; lim integer; after_id uuid; ids uuid[]; more boolean; cursor_row private.study_cursors%rowtype; cursor_id uuid; selection jsonb; epoch text; operations jsonb; allowed text[];
begin
  perform private.study_require(actor is not null and not coalesce(util.is_service_request(),false),'AUTH_REQUIRED');
  perform private.study_require(private.study_client_allowed(client,'STUDY-READ-01'),'FORBIDDEN');
  perform private.study_require(jsonb_typeof(p_request)='object' and p_request->>'schemaVersion'='lca.study-api.v2'
    and octet_length(p_request::text)<=262144 and length(p_request->>'requestId') between 1 and 128,'INVALID_REQUEST');
  case op
    when 'capability.read' then allowed:='{}';
    when 'study.list' then allowed:=array['cursor','limit'];
    when 'study.read' then allowed:=array['studyId'];
    when 'study.resources.list' then allowed:=array['studyId','kind','cursor','limit'];
    when 'revision.read' then allowed:=array['revisionId'];
    when 'scenario.read' then allowed:=array['scenarioRevisionId'];
    when 'model.read' then allowed:=array['preparationId'];
    when 'model.source.read' then allowed:=array['acquisitionId'];
    when 'run.read' then allowed:=array['runId'];
    else perform private.study_require(false,'CAPABILITY_UNAVAILABLE');
  end case;
  perform private.study_require(not exists(select 1 from jsonb_object_keys(p_request) k where k<>all(allowed||array['operation','schemaVersion','requestId'])),'INVALID_REQUEST');
  if op='capability.read' then
    operations:=jsonb_build_array('capability.read','study.read','study.list','study.resources.list','revision.read','scenario.read','model.read','model.source.read','run.read');
    if private.study_client_allowed(client,'STUDY-WRITE-01') then
      operations:=operations||jsonb_build_array('study.create','study.archive','study.select_revision','member.set','revision.create','revision.save','revision.freeze','scenario.create','scenario.save','scenario.freeze');
    end if;
    return jsonb_build_object('ok',true,'data',jsonb_build_object('type','capabilities','contractVersion','2.0.0','runtimeEnabled',true,
      'operations',operations,'profiles','[]'::jsonb));
  end if;
  if op in ('study.list','study.resources.list') then
    lim:=(p_request->>'limit')::integer; perform private.study_require(lim between 1 and 100,'INVALID_REQUEST');
    if op='study.resources.list' then sid:=(p_request->>'studyId')::uuid; perform private.study_authorize(sid,actor,client,'read'); end if;
    selection:=p_request-'requestId'-'cursor'; epoch:=private.study_access_epoch(actor,sid);
    if p_request->>'cursor' is not null then
      perform private.study_require(p_request->>'cursor' ~ '^[0-9a-f]{32}$','INVALID_REQUEST');
      select * into cursor_row from private.study_cursors where id=(p_request->>'cursor')::uuid;
      perform private.study_require(found and cursor_row.actor_id=actor and cursor_row.client_id is not distinct from client
        and cursor_row.selection=selection and cursor_row.access_epoch=epoch and cursor_row.expires_at>clock_timestamp(),'FORBIDDEN');
      after_id:=cursor_row.after_id;
    end if;
  end if;
  if op='study.list' then
    select array_agg(id order by id) into ids from(select s.id from private.studies s join private.study_members m on m.study_id=s.id where m.actor_id=actor and m.role in ('owner','editor','viewer') and private.study_team_member(actor,s.team_id) and (after_id is null or s.id>after_id) order by s.id limit lim+1)t;
    more:=cardinality(ids)>lim; ids:=ids[1:lim];
    -- Recheck and lock every selected Study before returning its current projection.
    foreach rid in array coalesce(ids,'{}') loop perform private.study_authorize(rid,actor,client,'read'); end loop;
    select coalesce(jsonb_agg(private.study_record('study',id) order by id),'[]'::jsonb) into items from unnest(ids)id;
    if more then insert into private.study_cursors(actor_id,client_id,selection,access_epoch,after_id) values(actor,client,selection,epoch,ids[lim]) returning id into cursor_id; end if;
    v:=jsonb_build_object('type','studyPage','items',items,'nextCursor',case when more then replace(cursor_id::text,'-','') else null end);
  else
    case op
      when 'study.read','study.resources.list' then sid:=(p_request->>'studyId')::uuid; kind:='study'; rid:=sid;
      when 'revision.read' then rid:=(p_request->>'revisionId')::uuid; select study_id into sid from private.study_revisions where id=rid; kind:='studyRevision';
      when 'scenario.read' then rid:=(p_request->>'scenarioRevisionId')::uuid; select study_id into sid from private.study_scenarios where id=rid; kind:='scenarioRevision';
      when 'model.read' then rid:=(p_request->>'preparationId')::uuid; select study_id into sid from private.study_model_preparations where id=rid; kind:='modelPreparation';
      when 'model.source.read' then rid:=(p_request->>'acquisitionId')::uuid; select study_id into sid from private.study_source_acquisitions where id=rid; kind:='modelSourceAcquisition';
      when 'run.read' then rid:=(p_request->>'runId')::uuid; select study_id into sid from private.study_runs where id=rid; kind:='run';
      else perform private.study_require(false,'CAPABILITY_UNAVAILABLE');
    end case;
    perform private.study_authorize(sid,actor,client,'read');
    if op='study.resources.list' then
      kind:=p_request->>'kind';
      select array_agg(id order by id) into ids from (
        select id from (
          select id from private.study_revisions where study_id=sid and kind='studyRevision'
          union all select id from private.study_scenarios where study_id=sid and kind='scenarioRevision'
          union all select id from private.study_source_snapshots where study_id=sid and kind='modelSourceSnapshot'
          union all select id from private.study_source_acquisitions where study_id=sid and kind='modelSourceAcquisition'
          union all select id from private.study_model_preparations where study_id=sid and kind='modelPreparation'
          union all select id from private.study_runs where study_id=sid and kind='run'
        )u where after_id is null or id>after_id order by id limit lim+1)t;
      perform private.study_require(kind in ('studyRevision','scenarioRevision','modelSourceSnapshot','modelSourceAcquisition','modelPreparation','run'),'CAPABILITY_UNAVAILABLE');
      more:=cardinality(ids)>lim; ids:=ids[1:lim];
      select coalesce(jsonb_agg(jsonb_build_object('type',kind,'value',private.study_record(kind,id)) order by id),'[]'::jsonb) into items from unnest(ids)id;
      if more then insert into private.study_cursors(actor_id,client_id,selection,access_epoch,after_id) values(actor,client,selection,epoch,ids[lim]) returning id into cursor_id; end if;
      v:=jsonb_build_object('type','resourcePage','studyId',sid,'kind',kind,'items',items,'nextCursor',case when more then replace(cursor_id::text,'-','') else null end);
    else v:=jsonb_build_object('type',kind,'value',private.study_record(kind,rid)); end if;
  end if;
  return jsonb_build_object('ok',true,'data',v);
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
when invalid_text_representation or invalid_parameter_value or numeric_value_out_of_range then return jsonb_build_object('ok',false,'code','INVALID_REQUEST');
end $_$;

ALTER FUNCTION "private"."study_qry_core_v1"("p_request" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_qry_core_v1"("p_request" "jsonb") FROM PUBLIC;
