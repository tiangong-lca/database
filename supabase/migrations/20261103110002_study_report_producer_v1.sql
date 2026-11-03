-- Database #904: report bytes are registered only by a bounded Edge producer.
-- Public inline content is an untrusted draft; it never carries trusted facts.
begin;
alter table private.study_reporting_config add column export_profile jsonb;
create table private.study_report_revisions (
 id uuid primary key, study_id uuid not null references private.studies(id), parent_report_id uuid,
 author_id uuid not null references auth.users(id), revision bigint not null default 1 check(revision between 1 and 9007199254740991),
 status text not null default 'draft' check(status in ('draft','frozen')), content_hash text not null check(content_hash ~ '^[0-9a-f]{64}$'),
 content_artifact_id uuid not null, template_id text not null check(template_id='lca.study-report.v1'),
 run_ids jsonb not null, analysis_ids jsonb not null, facts_refs jsonb not null,
 validity_snapshot jsonb not null, unique(study_id,id),
 foreign key(study_id,parent_report_id) references private.study_report_revisions(study_id,id),
 foreign key(study_id,content_artifact_id) references private.study_artifacts(study_id,id),check(parent_report_id is distinct from id)
);
create table private.study_report_runs (
 study_id uuid not null, report_id uuid not null, ordinal integer not null check(ordinal between 1 and 2),run_id uuid not null,
 primary key(report_id,ordinal),unique(report_id,run_id),foreign key(study_id,report_id) references private.study_report_revisions(study_id,id),foreign key(study_id,run_id) references private.study_runs(study_id,id)
);
create table private.study_report_analyses (
 study_id uuid not null, report_id uuid not null,ordinal integer not null check(ordinal between 1 and 2),analysis_id uuid not null,
 primary key(report_id,ordinal),unique(report_id,analysis_id),foreign key(study_id,report_id) references private.study_report_revisions(study_id,id),foreign key(study_id,analysis_id) references private.study_analyses(study_id,id)
);
create table private.study_report_exports (
 id uuid primary key,study_id uuid not null references private.studies(id),report_id uuid not null,actor_id uuid not null references auth.users(id),client_id text,
 grant_epoch bigint not null,record jsonb not null,manifest jsonb not null,projection_artifact_id uuid not null,resources_artifact_id uuid not null,bundle_artifact_id uuid not null,
 foreign key(study_id,report_id) references private.study_report_revisions(study_id,id),
 foreign key(study_id,projection_artifact_id) references private.study_artifacts(study_id,id),foreign key(study_id,resources_artifact_id) references private.study_artifacts(study_id,id),foreign key(study_id,bundle_artifact_id) references private.study_artifacts(study_id,id),
 check(record->>'exportId'=id::text),check(record->>'studyId'=study_id::text),check(record->>'reportRevisionId'=report_id::text),check(record->>'actorId'=actor_id::text),check((record->>'grantEpoch')::bigint=grant_epoch)
);
create table private.study_report_intents (
 id uuid primary key default gen_random_uuid(),study_id uuid not null references private.studies(id),actor_id uuid not null references auth.users(id),client_id text,
 operation text not null check(operation in ('report.create','report.save','report.freeze','export.request')),request jsonb not null,
 report_id uuid not null,content_artifact_id uuid,export_id uuid,projection_artifact_id uuid,resources_artifact_id uuid,bundle_artifact_id uuid,
 grant_epoch bigint not null,config_revision bigint not null,report_snapshot jsonb,
 created_at timestamptz not null default clock_timestamp(),expires_at timestamptz not null default clock_timestamp()+interval '2 minutes',response jsonb
);
create index study_report_parent_idx on private.study_report_revisions(parent_report_id);
create index study_report_author_idx on private.study_report_revisions(author_id);
create index study_report_content_idx on private.study_report_revisions(content_artifact_id);
create index study_report_run_idx on private.study_report_runs(study_id,run_id);
create index study_report_run_study_idx on private.study_report_runs(study_id,report_id);
create index study_report_analysis_idx on private.study_report_analyses(study_id,analysis_id);
create index study_report_analysis_study_idx on private.study_report_analyses(study_id,report_id);
create index study_export_report_idx on private.study_report_exports(study_id,report_id);
create index study_export_actor_idx on private.study_report_exports(actor_id);
create index study_export_projection_idx on private.study_report_exports(projection_artifact_id);
create index study_export_resources_idx on private.study_report_exports(resources_artifact_id);
create index study_export_bundle_idx on private.study_report_exports(bundle_artifact_id);
create index study_report_intent_study_idx on private.study_report_intents(study_id);
create index study_report_intent_actor_idx on private.study_report_intents(actor_id);
create index study_report_intent_expiry_idx on private.study_report_intents(expires_at,id);

create function private.study_report_plain(p_value jsonb,p_max integer) returns boolean
language sql immutable set search_path='' as $$select private.study_text(p_value,p_max) and (p_value#>>'{}') !~ '[<>]' and (p_value#>>'{}') !~* '(https?|javascript|data|file|blob):'$$;
create function private.study_report_ids(p_ids jsonb,p_min integer,p_max integer) returns boolean
language plpgsql immutable set search_path='' as $$declare x jsonb;seen text[]:='{}'::text[];begin
 if jsonb_typeof(p_ids) is distinct from 'array' then return false;end if;
 if jsonb_array_length(p_ids) not between p_min and p_max then return false;end if;
 for x in select * from jsonb_array_elements(p_ids) loop
  if not private.study_text(x,128,'^[A-Za-z0-9][A-Za-z0-9._:-]*$') or (x#>>'{}')=any(seen) then return false;end if;seen:=seen||(x#>>'{}');
 end loop;return true;
end$$;
create function private.study_report_content_valid(p_value jsonb) returns boolean
language plpgsql stable set search_path='' as $$
declare c jsonb;r jsonb;section jsonb;typ text;idkey text;claimids jsonb;seen text[];v text;
begin
 if not private.study_keys(p_value,array['schemaVersion','title','claims','sections','tables','charts','additionalLimitations'])
 or p_value->>'schemaVersion' is distinct from 'lca.study-report-draft.v1' or not private.study_report_plain(p_value->'title',256)
 or jsonb_typeof(p_value->'claims') is distinct from 'array' then return false;end if;
 if jsonb_array_length(p_value->'claims') not between 1 and 256 then return false;end if;
 claimids:='[]';
 for c in select * from jsonb_array_elements(p_value->'claims') loop
  if not private.study_keys(c,array['claimId','bundleRef','factId','canonicalValue','unit','display'])
  or not private.study_text(c->'claimId',128,'^[A-Za-z0-9][A-Za-z0-9._:-]*$') or not private.study_text(c->'factId',128,'^[A-Za-z0-9][A-Za-z0-9._:-]*$')
  or not private.study_report_plain(c->'unit',128) or c->'display'<>'{"style":"exact"}'::jsonb
  or not private.study_keys(c->'bundleRef',array['type','id','contentHash','digestScope','byteSize','mediaType','schemaVersion'])
  or c->'bundleRef'->>'type' is distinct from 'analysisFacts' or c->'bundleRef'->>'schemaVersion' is distinct from 'lca.study-analysis-facts.v1'
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
end$$;
-- Read metadata reflects persisted Run validity; no read invents a new
-- scientific check time. Stored report/export receipts remain historical.
create function private.study_report_validity_snapshot(p_study uuid,p_runs jsonb,p_bound_at timestamptz) returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object('status',case when bool_or(r.validity='withdrawn') then 'withdrawn'
  when bool_or(r.validity='superseded') then 'superseded'
  when count(r.id)=0 or count(r.id)<>jsonb_array_length(p_runs) or bool_or(r.validity='unknown') then 'unknown' else 'current' end,
  'checkedAt',coalesce(min(r.validity_checked_at),p_bound_at),
  'reasonCodes',to_jsonb(array_remove(array[
   case when bool_or(r.validity='withdrawn') then 'run_withdrawn' end,
   case when bool_or(r.validity='superseded') then 'run_superseded' end,
   case when bool_or(r.validity='unknown') then 'run_validity_unknown' end,
   case when count(r.id)=0 or count(r.id)<>jsonb_array_length(p_runs) then 'run_missing' end],null)))
 from jsonb_array_elements_text(p_runs)e(id) left join private.study_runs r on r.study_id=p_study and r.id=e.id::uuid
$$;
create function private.study_report_record(p_id uuid) returns jsonb
language sql security definer set search_path='' as $$
 select jsonb_build_object('reportRevisionId',r.id,'studyId',r.study_id,'parentReportRevisionId',r.parent_report_id,'authorId',r.author_id,'revision',r.revision,'status',r.status,
 'contentHash',r.content_hash,'runIds',r.run_ids,'analysisIds',r.analysis_ids,'factsRefs',r.facts_refs,'contentRef',a.ref,'templateId',r.template_id,
 'finalization',jsonb_build_object('status','not_finalized','profileId','lca.study-report-unreviewed.v1','reviewRequirement','none','finalizedAt',null,'reviewIds','[]'::jsonb),'validitySnapshot',private.study_report_validity_snapshot(r.study_id,r.run_ids,(r.validity_snapshot->>'checkedAt')::timestamptz))
 from private.study_report_revisions r join private.study_artifacts a on a.id=r.content_artifact_id where r.id=p_id
$$;
create function private.study_report_rights(p_study uuid,p_runs jsonb,p_analyses jsonb,p_actor uuid,p_client text) returns jsonb
language plpgsql security definer set search_path='' as $$declare rid text;aid text;a private.study_analyses%rowtype;refs jsonb:='[]'::jsonb;begin
 perform private.study_authorize(p_study,p_actor,p_client,'read');
 perform private.study_require(private.study_report_ids(p_runs,1,2) and private.study_report_ids(p_analyses,1,2),'INVALID_REQUEST');
 for rid in select jsonb_array_elements_text(p_runs) loop
  perform private.study_analysis_rights(p_study,jsonb_build_object('runIds',jsonb_build_array(rid)),p_actor,p_client);
 end loop;
 for aid in select jsonb_array_elements_text(p_analyses) loop
  select * into a from private.study_analyses where study_id=p_study and id=aid::uuid;
  perform private.study_require(found and a.facts_artifact_id is not null and exists(select 1 from private.worker_jobs where id=a.job_id and status='completed')
   and a.config->'runIds'<@p_runs,'REFERENCE_MISMATCH');
  perform private.study_analysis_rights(p_study,a.config,p_actor,p_client);
  refs:=refs||jsonb_build_array((select ref from private.study_artifacts where id=a.facts_artifact_id));
 end loop;return refs;
end$$;
create function private.study_report_intent_check(p_id uuid) returns private.study_report_intents
language plpgsql security definer set search_path='' as $$declare i private.study_report_intents%rowtype;r private.study_report_revisions%rowtype;cfg private.study_reporting_config%rowtype;refs jsonb;begin
 select * into i from private.study_report_intents where id=p_id;
 perform private.study_require(found,'CAPABILITY_UNAVAILABLE');
 perform private.study_authorize(i.study_id,i.actor_id,i.client_id,case when i.operation='export.request' then 'read' else 'write' end);
 select * into i from private.study_report_intents where id=p_id;
 perform private.study_require((select grant_epoch from private.studies where id=i.study_id)=i.grant_epoch,'FORBIDDEN');
 if i.operation='report.create' then
  refs:=private.study_report_rights(i.study_id,i.request->'runIds',i.request->'analysisIds',i.actor_id,i.client_id);
 else
  select * into r from private.study_report_revisions where study_id=i.study_id and id=i.report_id;
  perform private.study_require(found,'REFERENCE_MISMATCH');
  refs:=private.study_report_rights(i.study_id,r.run_ids,r.analysis_ids,i.actor_id,i.client_id);
  perform private.study_require(refs=r.facts_refs,'REFERENCE_MISMATCH');
 end if;
 if i.response is not null then return i;end if;
 perform private.study_analysis_require_current(i.study_id,jsonb_build_object('runIds',case when i.operation='report.create' then i.request->'runIds' else r.run_ids end));
 perform private.study_require(i.expires_at>clock_timestamp(),'CAPABILITY_UNAVAILABLE');
 select * into cfg from private.study_reporting_config where singleton for share;
 perform private.study_require(cfg.revision=i.config_revision and case when i.operation='export.request' then cfg.export_enabled else cfg.report_enabled end,'CAPABILITY_UNAVAILABLE');
 perform private.study_require((select status='active' from private.studies where id=i.study_id),'FROZEN_REVISION');
 if i.operation<>'report.create' then
  perform private.study_require(private.study_report_record(r.id)=i.report_snapshot,'REVISION_CONFLICT');
 end if;return i;
end$$;
create function private.study_report_command(p_request jsonb) returns jsonb
language plpgsql security definer set search_path='' set statement_timeout='15s' as $$
declare op text:=p_request->>'operation';actor uuid:=auth.uid();client text:=nullif(auth.jwt()->>'client_id','');sid uuid;rid uuid;
 r private.study_report_revisions%rowtype;i private.study_report_intents%rowtype;cfg private.study_reporting_config%rowtype;previous private.study_command_receipts%rowtype;
 req jsonb:=p_request-'schemaVersion'-'requestId'-'idempotencyKey';refs jsonb;result jsonb;allowed text[];parent uuid;
begin
 perform private.study_reporting_envelope(p_request,true);
 perform private.study_require(private.study_client_allowed(client,'STUDY-WRITE-01'),'FORBIDDEN');
 case op
 when 'report.create' then
  allowed:=array['schemaVersion','requestId','idempotencyKey','operation','studyId','parentReportRevisionId','runIds','analysisIds','content','templateId'];sid:=(p_request->>'studyId')::uuid;
 when 'report.save','report.freeze' then
  allowed:=array['schemaVersion','requestId','idempotencyKey','operation','target']||case when op='report.save' then array['content'] else array['expectedContentHash'] end;
  perform private.study_require(private.study_keys(p_request->'target',array['type','id','expectedRevision']) and p_request->'target'->>'type'='reportRevision'
   and jsonb_typeof(p_request->'target'->'expectedRevision')='number' and (p_request->'target'->>'expectedRevision')::numeric between 1 and 9007199254740991
   and trunc((p_request->'target'->>'expectedRevision')::numeric)=(p_request->'target'->>'expectedRevision')::numeric,'INVALID_REQUEST');
  rid:=(p_request->'target'->>'id')::uuid;select study_id into sid from private.study_report_revisions where id=rid;
 when 'export.request' then
  allowed:=array['schemaVersion','requestId','idempotencyKey','operation','reportRevisionId','expectedContentHash','rendererVersion','viewModelVersion'];
  rid:=(p_request->>'reportRevisionId')::uuid;select study_id into sid from private.study_report_revisions where id=rid;
 else perform private.study_require(false,'CAPABILITY_UNAVAILABLE');end case;
 perform private.study_require(private.study_keys(p_request,allowed),'INVALID_REQUEST');
 perform private.study_authorize(sid,actor,client,case when op='export.request' then 'read' else 'write' end);
 -- The first lookup routes only by immutable Study ownership. A command may
 -- have waited for a producer holding the Study lock; reload and lock the
 -- mutable report before rights, replay recovery, CAS/hash checks or snapshot.
 if op<>'report.create' then
  select * into r from private.study_report_revisions where study_id=sid and id=rid for update;
  perform private.study_require(found,'NOT_FOUND');
 end if;
 if op='report.create' then refs:=private.study_report_rights(sid,p_request->'runIds',p_request->'analysisIds',actor,client);
 else refs:=private.study_report_rights(sid,r.run_ids,r.analysis_ids,actor,client);end if;
 select * into previous from private.study_command_receipts where actor_id=actor and operation=op and scope=sid::text and idempotency_key=p_request->>'idempotencyKey';
 if found then
  perform private.study_require(previous.request=req,'IDEMPOTENCY_CONFLICT');
  if previous.response->'data'->>'kind'='reportCommandIntent' then
   i:=private.study_report_intent_check((previous.response->'data'->>'intentId')::uuid);if i.response is not null then return i.response;end if;
  end if;
  if op='export.request' then perform private.study_report_export_authorize((previous.response->'data'->'value'->>'exportId')::uuid,actor,client);end if;return previous.response;
 end if;
 perform private.study_analysis_require_current(sid,jsonb_build_object('runIds',case when op='report.create' then p_request->'runIds' else r.run_ids end));
 perform private.study_require((select status='active' from private.studies where id=sid),'FROZEN_REVISION');
 select * into cfg from private.study_reporting_config where singleton for share;
 perform private.study_require(case when op='export.request' then cfg.export_enabled else cfg.report_enabled end,'CAPABILITY_UNAVAILABLE');
 if op in ('report.create','report.save') then
  perform private.study_require(private.study_report_content_valid(p_request->'content'),'INVALID_REQUEST');
  perform private.study_require(not exists(select 1 from jsonb_array_elements(p_request->'content'->'claims')c where not refs @> jsonb_build_array(c->'bundleRef')),'REFERENCE_MISMATCH');
 end if;
 if op='report.create' then
  perform private.study_require(p_request->>'templateId'='lca.study-report.v1','INVALID_REQUEST');parent:=(p_request->>'parentReportRevisionId')::uuid;
  if parent is not null then perform private.study_require(exists(select 1 from private.study_report_revisions where study_id=sid and id=parent and status='frozen'),'REFERENCE_MISMATCH');end if;
  rid:=gen_random_uuid();
 else
  if op='export.request' then
   perform private.study_require(r.status='frozen' and r.content_hash=p_request->>'expectedContentHash','REFERENCE_MISMATCH');
   perform private.study_require(p_request->>'rendererVersion'='1.0.0' and p_request->>'viewModelVersion'='lca.study-report-view.v1' and cfg.export_profile is not null,'CAPABILITY_UNAVAILABLE');
  else
   perform private.study_require(r.revision=(p_request->'target'->>'expectedRevision')::bigint,'REVISION_CONFLICT');
   perform private.study_require(r.status='draft','FROZEN_REVISION');
   if op='report.freeze' then perform private.study_require(r.content_hash=p_request->>'expectedContentHash','REFERENCE_MISMATCH');end if;
  end if;
 end if;
 -- Bounded, actor-serialized intent retention. No placeholder public row exists.
 perform pg_advisory_xact_lock(hashtextextended('study-report-intent:'||actor::text,904));
 perform private.study_require((select count(*) from private.study_report_intents where actor_id=actor and expires_at>clock_timestamp() and response is null)<64,'CAPABILITY_UNAVAILABLE');
 insert into private.study_report_intents(study_id,actor_id,client_id,operation,request,report_id,content_artifact_id,export_id,projection_artifact_id,resources_artifact_id,bundle_artifact_id,grant_epoch,config_revision,report_snapshot)
 values(sid,actor,client,op,p_request,rid,case when op in ('report.create','report.save') then gen_random_uuid() end,
 case when op='export.request' then gen_random_uuid() end,case when op='export.request' then gen_random_uuid() end,
 case when op='export.request' then gen_random_uuid() end,case when op='export.request' then gen_random_uuid() end,
 (select grant_epoch from private.studies where id=sid),cfg.revision,case when op<>'report.create' then private.study_report_record(rid) end) returning * into i;
 result:=jsonb_build_object('ok',true,'data',jsonb_build_object('kind','reportCommandIntent','intentId',i.id,'expiresAt',i.expires_at,'operation',op));
 insert into private.study_command_receipts values(actor,op,sid::text,p_request->>'idempotencyKey',req,result,clock_timestamp());return result;
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
when invalid_text_representation or invalid_parameter_value or numeric_value_out_of_range or check_violation or not_null_violation then return jsonb_build_object('ok',false,'code','INVALID_REQUEST');
when foreign_key_violation or unique_violation then return jsonb_build_object('ok',false,'code','REFERENCE_MISMATCH');
end$$;
create function private.study_report_disclosure_context(p_intent private.study_report_intents) returns text
language sql stable security definer set search_path='' as $$select private.study_content_hash('lca.study-report-security-context.v1',jsonb_build_object(
 'intentId',p_intent.id,'actorId',p_intent.actor_id,'clientId',p_intent.client_id,'grantEpoch',p_intent.grant_epoch,'configRevision',p_intent.config_revision,
 'report',p_intent.report_snapshot,'accessEpoch',private.study_access_epoch(p_intent.actor_id,p_intent.study_id)))$$;
create function api.svc_study_report_intent_resolve_v1(p_intent_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare i private.study_report_intents%rowtype;r private.study_report_revisions%rowtype;runids jsonb;analysisids jsonb;runs jsonb;analyses jsonb;begin
 perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');i:=private.study_report_intent_check(p_intent_id);
 if i.response is not null then return i.response;end if;
 if i.operation='report.create' then runids:=i.request->'runIds';analysisids:=i.request->'analysisIds';
 else select * into r from private.study_report_revisions where id=i.report_id;runids:=r.run_ids;analysisids:=r.analysis_ids;end if;
 select jsonb_agg(jsonb_build_object('run',private.study_record('run',rn.id),'revision',private.study_record('studyRevision',rn.study_revision_id),
 'scenario',private.study_record('scenarioRevision',rn.scenario_id),'preparation',private.study_record('modelPreparation',rn.preparation_id),
 'preparedArtifact',private.study_private_artifact(i.study_id,p.input_artifact_id),'resultArtifact',private.study_private_artifact(i.study_id,rn.result_artifact_id)) order by e.n)
 into runs from jsonb_array_elements_text(runids) with ordinality e(v,n) join private.study_runs rn on rn.id=e.v::uuid and rn.study_id=i.study_id
 join private.study_model_preparations p on p.id=rn.preparation_id;
 select jsonb_agg(jsonb_build_object('analysis',private.study_analysis_record(a.id),'factsArtifact',private.study_private_artifact(i.study_id,a.facts_artifact_id)) order by e.n)
 into analyses from jsonb_array_elements_text(analysisids) with ordinality e(v,n) join private.study_analyses a on a.id=e.v::uuid and a.study_id=i.study_id;
 return jsonb_build_object('ok',true,'data',jsonb_build_object('kind','reportCommandContext','intentId',i.id,'expiresAt',i.expires_at,'operation',i.operation,
 'request',i.request,'studyId',i.study_id,'actorId',i.actor_id,'clientId',i.client_id,'grantEpoch',i.grant_epoch,'generatedAt',i.created_at,
 'reportRevisionId',i.report_id,'contentArtifactId',i.content_artifact_id,'exportId',i.export_id,'projectionArtifactId',i.projection_artifact_id,
 'resourcesArtifactId',i.resources_artifact_id,'bundleArtifactId',i.bundle_artifact_id,'report',i.report_snapshot,
 'contentArtifact',case when r.id is not null then private.study_private_artifact(i.study_id,r.content_artifact_id) end,'runs',runs,'analyses',analyses,
 'exportProfile',case when i.operation='export.request' then (select export_profile from private.study_reporting_config where singleton) end,
 'disclosureContextHash',case when i.operation='export.request' then private.study_report_disclosure_context(i) end,
 'factsBindingHash',private.study_reporting_digest('lca.study-report-facts-binding.v1',private.study_report_rights(i.study_id,runids,analysisids,i.actor_id,i.client_id))));
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
end$$;
-- This canonicalizer is used only on closed service records with fixed ASCII
-- object keys, safe integers and strings. Scientific decimal values stay strings.
create function private.study_reporting_canonical(p_value jsonb) returns text
language plpgsql stable set search_path='' as $$declare result text;begin
 case jsonb_typeof(p_value)
 when 'object' then select '{'||coalesce(string_agg(to_jsonb(k)::text||':'||private.study_reporting_canonical(v),',' order by k collate "C"),'')||'}' into result from jsonb_each(p_value)e(k,v);
 when 'array' then select '['||coalesce(string_agg(private.study_reporting_canonical(v),',' order by n),'')||']' into result from jsonb_array_elements(p_value) with ordinality e(v,n);
 when 'number' then
  if (p_value::text)::numeric<>trunc((p_value::text)::numeric) or abs((p_value::text)::numeric)>9007199254740991 then raise exception 'REFERENCE_MISMATCH';end if;
  result:=((p_value::text)::numeric::bigint)::text;
 else result:=p_value::text;end case;return result;
end$$;
create function private.study_reporting_digest(p_domain text,p_value jsonb) returns text
language sql stable set search_path='' as $$select encode(extensions.digest(case when p_domain is null then ''::bytea else convert_to(p_domain,'UTF8')||decode('00','hex') end||convert_to(private.study_reporting_canonical(p_value),'UTF8'),'sha256'),'hex')$$;
create function private.study_report_validation_check(p_validation jsonb,p_report uuid,p_hash text,p_count integer,p_refs jsonb) returns void
language plpgsql set search_path='' as $$begin
 perform private.study_require(private.study_keys(p_validation,array['schemaVersion','profileId','reportRevisionId','contentHash','claimCount','factsBindingHash'])
 and p_validation->>'schemaVersion'='lca.study-report-validation.v1' and p_validation->>'profileId'='lca.study-report-claims.v1'
 and p_validation->>'reportRevisionId'=p_report::text and p_validation->>'contentHash'=p_hash
 and jsonb_typeof(p_validation->'claimCount')='number' and (p_validation->>'claimCount')::numeric=p_count
 and p_validation->>'factsBindingHash'=private.study_reporting_digest('lca.study-report-facts-binding.v1',p_refs),'REFERENCE_MISMATCH');
end$$;
create function private.study_report_store_produced(p_study uuid,p_artifact jsonb,p_id uuid,p_type text,p_schema text,p_name text) returns uuid
language plpgsql security definer set search_path='' as $$begin
 perform private.study_require(private.study_keys(p_artifact,array['studyId','artifactRef','storageBucket','storageObjectPath'])
 and p_artifact->>'studyId'=p_study::text and p_artifact->'artifactRef'->>'id'=p_id::text and p_artifact->'artifactRef'->>'schemaVersion'=p_schema
 and p_artifact->'artifactRef'->>'mediaType'='application/json' and p_artifact->>'storageBucket'='study-artifacts'
 and p_artifact->>'storageObjectPath'='study/'||p_study::text||'/'||p_id::text||'/'||p_name||'.json','REFERENCE_MISMATCH');
 return private.study_store_artifact(p_study,p_artifact->'artifactRef',p_artifact->>'storageBucket',p_artifact->>'storageObjectPath',p_type);
end$$;
alter table private.study_report_revisions add column validation_evidence jsonb not null;
create function api.svc_study_report_intent_consume_v1(p_intent_id uuid,p_completion jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare i private.study_report_intents%rowtype;r private.study_report_revisions%rowtype;refs jsonb;contentref jsonb;artifact uuid;result jsonb;validation jsonb;claimcount integer;
 manifest jsonb;receipt jsonb;profile jsonb;projection uuid;resources uuid;bundle uuid;record jsonb;validity jsonb;
begin
 perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');
 i:=private.study_report_intent_check(p_intent_id);
 select * into i from private.study_report_intents where id=i.id for update;
 if i.response is not null then return i.response;end if;
 if i.operation='report.create' then
  refs:=private.study_report_rights(i.study_id,i.request->'runIds',i.request->'analysisIds',i.actor_id,i.client_id);claimcount:=jsonb_array_length(i.request->'content'->'claims');
 else
  select * into r from private.study_report_revisions where id=i.report_id for update;
  refs:=private.study_report_rights(i.study_id,r.run_ids,r.analysis_ids,i.actor_id,i.client_id);
  claimcount:=case when i.operation='report.save' then jsonb_array_length(i.request->'content'->'claims') else (r.validation_evidence->>'claimCount')::integer end;
 end if;
 validation:=p_completion->'validation';
 if i.operation in ('report.create','report.save') then
  perform private.study_require(private.study_keys(p_completion,array['kind','contentArtifact','factsRefs','validation']) and p_completion->>'kind'='validatedContent'
   and p_completion->'factsRefs'=refs,'REFERENCE_MISMATCH');
  contentref:=p_completion->'contentArtifact'->'artifactRef';
  perform private.study_report_validation_check(validation,i.report_id,contentref->>'contentHash',claimcount,refs);
  artifact:=private.study_report_store_produced(i.study_id,p_completion->'contentArtifact',i.content_artifact_id,'reportContent','lca.study-report-content.v1','content');
  if i.operation='report.create' then
   insert into private.study_report_revisions(id,study_id,parent_report_id,author_id,content_hash,content_artifact_id,template_id,run_ids,analysis_ids,facts_refs,validity_snapshot,validation_evidence)
   values(i.report_id,i.study_id,(i.request->>'parentReportRevisionId')::uuid,i.actor_id,contentref->>'contentHash',artifact,i.request->>'templateId',i.request->'runIds',i.request->'analysisIds',refs,
   private.study_report_validity_snapshot(i.study_id,i.request->'runIds',i.created_at),validation);
   insert into private.study_report_runs select i.study_id,i.report_id,n,v::uuid from jsonb_array_elements_text(i.request->'runIds') with ordinality e(v,n);
   insert into private.study_report_analyses select i.study_id,i.report_id,n,v::uuid from jsonb_array_elements_text(i.request->'analysisIds') with ordinality e(v,n);
  else update private.study_report_revisions set revision=revision+1,content_hash=contentref->>'contentHash',content_artifact_id=artifact,validation_evidence=validation where id=i.report_id;end if;
  result:=jsonb_build_object('ok',true,'data',jsonb_build_object('type','reportRevision','value',private.study_report_record(i.report_id)));
 elsif i.operation='report.freeze' then
  select ref into contentref from private.study_artifacts where id=r.content_artifact_id;
  perform private.study_require(private.study_keys(p_completion,array['kind','contentRef','validation']) and p_completion->>'kind'='validatedFreeze' and p_completion->'contentRef'=contentref,'REFERENCE_MISMATCH');
  perform private.study_report_validation_check(validation,r.id,r.content_hash,claimcount,refs);
  update private.study_report_revisions set status='frozen',revision=revision+1,validation_evidence=validation where id=r.id;
  result:=jsonb_build_object('ok',true,'data',jsonb_build_object('type','reportRevision','value',private.study_report_record(r.id)));
 else
  perform private.study_require(private.study_keys(p_completion,array['kind','projectionArtifact','resourcesArtifact','bundleArtifact','manifest','receipt']) and p_completion->>'kind'='validatedExport','REFERENCE_MISMATCH');
  manifest:=p_completion->'manifest';receipt:=p_completion->'receipt';select export_profile into profile from private.study_reporting_config where singleton;
  perform private.study_require(private.study_keys(manifest,array['schemaVersion','issuerId','exportId','studyId','reportRevisionId','reportContentHash','actorId','clientId','grantEpoch','policyId','disclosureContextHash','generatedAt','validitySnapshot','reviewIds','renderer','files'])
   and manifest->>'schemaVersion'='lca.study-export-manifest.v1' and manifest->>'issuerId'=profile->>'issuerId'
   and manifest->>'exportId'=i.export_id::text and manifest->>'studyId'=i.study_id::text and manifest->>'reportRevisionId'=i.report_id::text
   and manifest->>'reportContentHash'=r.content_hash and manifest->>'actorId'=i.actor_id::text and (manifest->>'clientId') is not distinct from i.client_id
   and jsonb_typeof(manifest->'grantEpoch')='number' and (manifest->>'grantEpoch')::numeric=i.grant_epoch
   and manifest->>'policyId'='lca.study-report-disclosure.v1' and manifest->>'disclosureContextHash'=private.study_report_disclosure_context(i)
   and (manifest->>'generatedAt')::timestamptz=i.created_at and manifest->'validitySnapshot'=i.report_snapshot->'validitySnapshot' and manifest->'reviewIds'='[]'::jsonb
   and manifest->'renderer'=jsonb_build_object('version','1.0.0','viewModelVersion','lca.study-report-view.v1','artifactHash',profile->>'rendererArtifactHash'),'REFERENCE_MISMATCH');
  perform private.study_require(jsonb_typeof(manifest->'files')='array' and jsonb_array_length(manifest->'files')=2
   and private.study_keys(manifest->'files'->0,array['path','mediaType','sha256','byteSize']) and private.study_keys(manifest->'files'->1,array['path','mediaType','sha256','byteSize'])
   and manifest->'files'->0->>'path'='report.html' and manifest->'files'->0->>'mediaType'='text/html'
   and manifest->'files'->1->>'path'='projection.json' and manifest->'files'->1->>'mediaType'='application/json'
   and manifest->'files'->0->>'sha256' ~ '^[0-9a-f]{64}$'
   and jsonb_typeof(manifest->'files'->0->'byteSize')='number' and jsonb_typeof(manifest->'files'->1->'byteSize')='number'
   and (manifest->'files'->0->>'byteSize')::numeric=trunc((manifest->'files'->0->>'byteSize')::numeric)
   and (manifest->'files'->1->>'byteSize')::numeric=trunc((manifest->'files'->1->>'byteSize')::numeric)
   and (manifest->'files'->0->>'byteSize')::numeric between 1 and 4194304 and (manifest->'files'->1->>'byteSize')::numeric between 1 and 4194304
   and (manifest->'files'->0->>'byteSize')::numeric+(manifest->'files'->1->>'byteSize')::numeric<=4194304
   and manifest->'files'->1->>'sha256'=p_completion->'projectionArtifact'->'artifactRef'->>'contentHash'
   and (manifest->'files'->1->>'byteSize')::numeric=(p_completion->'projectionArtifact'->'artifactRef'->>'byteSize')::numeric,'REFERENCE_MISMATCH');
  perform private.study_require(p_completion->'resourcesArtifact'->'artifactRef'->>'contentHash'=private.study_reporting_digest(null,manifest)
   and (p_completion->'resourcesArtifact'->'artifactRef'->>'byteSize')::numeric=octet_length(private.study_reporting_canonical(manifest))
   and private.study_keys(receipt,array['schemaVersion','manifestHash','keyId','algorithm','signature']) and receipt->>'schemaVersion'='lca.study-export-receipt.v2'
   and receipt->>'manifestHash'=private.study_reporting_digest('lca.study-export-signature.v1',manifest) and receipt->>'keyId'=profile->>'keyId'
   and receipt->>'algorithm'='Ed25519' and private.study_text(receipt->'signature',86,'^[A-Za-z0-9_-]{85}[AQgw]$'),'REFERENCE_MISMATCH');
  projection:=private.study_report_store_produced(i.study_id,p_completion->'projectionArtifact',i.projection_artifact_id,'reportProjection','lca.study-report-view.v1','projection');
  resources:=private.study_report_store_produced(i.study_id,p_completion->'resourcesArtifact',i.resources_artifact_id,'renderResources','lca.study-export-manifest.v1','resources');
  bundle:=private.study_report_store_produced(i.study_id,p_completion->'bundleArtifact',i.bundle_artifact_id,'reportExportBundle','lca.study-export-bundle.v1','bundle');
  record:=jsonb_build_object('exportId',i.export_id,'studyId',i.study_id,'reportRevisionId',i.report_id,'reportContentHash',r.content_hash,'status','ready',
   'projectionRef',p_completion->'projectionArtifact'->'artifactRef','grantEpoch',i.grant_epoch,'factsRefs',refs,'rendererVersion','1.0.0','viewModelVersion','lca.study-report-view.v1',
   'resourcesRef',p_completion->'resourcesArtifact'->'artifactRef','actorId',i.actor_id,'policyId','lca.study-report-disclosure.v1','disclosureContextHash',manifest->>'disclosureContextHash',
   'disclosureDecision','allowed','generatedAt',i.created_at,'validitySnapshot',i.report_snapshot->'validitySnapshot','reviewIds','[]'::jsonb,'receipt',receipt,'bundleRef',p_completion->'bundleArtifact'->'artifactRef');
  insert into private.study_report_exports(id,study_id,report_id,actor_id,client_id,grant_epoch,record,manifest,projection_artifact_id,resources_artifact_id,bundle_artifact_id) values(i.export_id,i.study_id,i.report_id,i.actor_id,i.client_id,i.grant_epoch,record,manifest,projection,resources,bundle);
  result:=jsonb_build_object('ok',true,'data',jsonb_build_object('type','export','value',record));
 end if;
 update private.study_report_intents set response=result where id=i.id;
 update private.study_command_receipts set response=result where actor_id=i.actor_id and operation=i.operation and scope=i.study_id::text and idempotency_key=i.request->>'idempotencyKey';return result;
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
when invalid_text_representation or invalid_parameter_value or numeric_value_out_of_range or check_violation or not_null_violation or invalid_datetime_format then return jsonb_build_object('ok',false,'code','INVALID_REQUEST');
when foreign_key_violation or unique_violation then return jsonb_build_object('ok',false,'code','REFERENCE_MISMATCH');
end$$;
create function private.study_report_export_authorize(p_id uuid,p_actor uuid,p_client text) returns private.study_report_exports
language plpgsql security definer set search_path='' as $$declare e private.study_report_exports%rowtype;r private.study_report_revisions%rowtype;begin
 select * into e from private.study_report_exports where id=p_id;
 perform private.study_require(found,'FORBIDDEN');perform private.study_authorize(e.study_id,p_actor,p_client,'read');
 perform private.study_require(e.actor_id=p_actor and e.client_id is not distinct from p_client
 and e.grant_epoch=(select grant_epoch from private.studies where id=e.study_id),'FORBIDDEN');
 select * into r from private.study_report_revisions where id=e.report_id;
 perform private.study_require(private.study_report_rights(e.study_id,r.run_ids,r.analysis_ids,p_actor,p_client)=r.facts_refs,'REFERENCE_MISMATCH');return e;
end$$;
alter function private.study_reporting_artifact_authorize(uuid,jsonb,uuid,text) rename to study_analysis_artifact_authorize;
create function private.study_reporting_artifact_authorize(p_study uuid,p_ref jsonb,p_actor uuid,p_client text) returns jsonb
language plpgsql security definer set search_path='' as $$declare r private.study_report_revisions%rowtype;e private.study_report_exports%rowtype;a private.study_artifacts%rowtype;begin
 if p_ref->>'type' not in ('reportContent','reportProjection','renderResources','reportExportBundle') then return private.study_analysis_artifact_authorize(p_study,p_ref,p_actor,p_client);end if;
 perform private.study_authorize(p_study,p_actor,p_client,'read');
 perform private.study_require((select disclosure_enabled from private.study_runtime_config where singleton),'CAPABILITY_UNAVAILABLE');
 select * into a from private.study_artifacts where study_id=p_study and id=(p_ref->>'id')::uuid;perform private.study_require(found and a.ref=p_ref,'REFERENCE_MISMATCH');
 if p_ref->>'type'='reportContent' then
  select * into r from private.study_report_revisions where study_id=p_study and content_artifact_id=a.id;
  perform private.study_require(found,'DISCLOSURE_DENIED');perform private.study_report_rights(p_study,r.run_ids,r.analysis_ids,p_actor,p_client);
 else
  select * into e from private.study_report_exports where study_id=p_study and (projection_artifact_id=a.id or resources_artifact_id=a.id or bundle_artifact_id=a.id);
  perform private.study_require(found,'DISCLOSURE_DENIED');perform private.study_report_export_authorize(e.id,p_actor,p_client);
 end if;
 return jsonb_build_object('kind','artifactCapability','studyId',p_study,'artifactRef',a.ref,'storageBucket',a.bucket,'storageObjectPath',a.object_path);
end$$;
-- PL/pgSQL name resolution remains deliberately through the current dispatcher.
create or replace function api.svc_study_reporting_configure_v1(p_expected_revision bigint,p_configuration jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$declare cfg private.study_reporting_config%rowtype;p jsonb:=p_configuration->'exportProfile';begin
 perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');
 perform private.study_require(private.study_keys(p_configuration,array['schemaVersion','analysisEnabled','reportEnabled','exportEnabled','qualificationEvidenceRef','exportProfile'])
 and p_configuration->>'schemaVersion'='lca.study-reporting-qualification.v1' and jsonb_typeof(p_configuration->'analysisEnabled')='boolean'
 and jsonb_typeof(p_configuration->'reportEnabled')='boolean' and jsonb_typeof(p_configuration->'exportEnabled')='boolean'
 and private.study_text(p_configuration->'qualificationEvidenceRef',128,'^[A-Za-z0-9][A-Za-z0-9._:-]*$'),'INVALID_REQUEST');
 if p<>'null'::jsonb then
  perform private.study_require(private.study_keys(p,array['issuerId','keyId','rendererVersion','viewModelVersion','rendererArtifactHash','policyId'])
  and private.study_text(p->'issuerId',128,'^[A-Za-z0-9][A-Za-z0-9._:-]*$') and private.study_text(p->'keyId',128,'^[A-Za-z0-9][A-Za-z0-9._:-]*$')
  and p->>'rendererVersion'='1.0.0' and p->>'viewModelVersion'='lca.study-report-view.v1'
  and private.study_text(p->'rendererArtifactHash',64,'^[0-9a-f]{64}$') and p->>'policyId'='lca.study-report-disclosure.v1','INVALID_REQUEST');
 end if;
 perform private.study_require(not (p_configuration->>'exportEnabled')::boolean or p<>'null'::jsonb,'CAPABILITY_UNAVAILABLE');
 select * into cfg from private.study_reporting_config where singleton for update;perform private.study_require(cfg.revision=p_expected_revision,'REVISION_CONFLICT');
 update private.study_reporting_config set revision=revision+1,analysis_enabled=(p_configuration->>'analysisEnabled')::boolean,report_enabled=(p_configuration->>'reportEnabled')::boolean,
 export_enabled=(p_configuration->>'exportEnabled')::boolean,qualification_evidence_ref=p_configuration->>'qualificationEvidenceRef',export_profile=nullif(p,'null'::jsonb) where singleton;
 return jsonb_build_object('ok',true,'data',jsonb_build_object('revision',cfg.revision+1));
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
end$$;

create function private.study_reporting_list(p_request jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare sid uuid:=(p_request->>'studyId')::uuid;actor uuid:=auth.uid();client text:=nullif(auth.jwt()->>'client_id','');kind text:=p_request->>'kind';lim integer;
 selection jsonb;cur private.study_cursors%rowtype;after_id uuid;ids uuid[];resource_id uuid;items jsonb:='[]'::jsonb;v jsonb;nextid uuid;more boolean;epoch text;r private.study_report_revisions%rowtype;a private.study_analyses%rowtype;e private.study_report_exports%rowtype;
begin
 perform private.study_reporting_envelope(p_request,false);
 perform private.study_require(private.study_keys(p_request,array['schemaVersion','requestId','operation','studyId','kind','limit','cursor']) and kind in ('analysis','reportRevision','export')
 and jsonb_typeof(p_request->'limit')='number' and (p_request->>'limit')::numeric between 1 and 100 and (p_request->>'limit')::numeric=trunc((p_request->>'limit')::numeric),'INVALID_REQUEST');lim:=(p_request->>'limit')::integer;
 perform private.study_authorize(sid,actor,client,'read');epoch:=private.study_access_epoch(actor,sid);
 selection:=p_request-'requestId'-'cursor';
 if p_request->'cursor'<>'null'::jsonb then
  select * into cur from private.study_cursors where study_cursors.id=(p_request->>'cursor')::uuid;
  perform private.study_require(found and cur.actor_id=actor and cur.client_id is not distinct from client and cur.selection=selection and cur.access_epoch=epoch and cur.expires_at>clock_timestamp(),'INVALID_REQUEST');after_id:=cur.after_id;
 end if;
 if kind='analysis' then select array_agg(t.id order by t.id) into ids from(select study_analyses.id from private.study_analyses where study_id=sid and (after_id is null or study_analyses.id>after_id) order by study_analyses.id limit lim+1)t;
 elsif kind='reportRevision' then select array_agg(t.id order by t.id) into ids from(select study_report_revisions.id from private.study_report_revisions where study_id=sid and (after_id is null or study_report_revisions.id>after_id) order by study_report_revisions.id limit lim+1)t;
 else select array_agg(t.id order by t.id) into ids from(select study_report_exports.id from private.study_report_exports where study_id=sid and actor_id=actor and client_id is not distinct from client and grant_epoch=(select grant_epoch from private.studies where studies.id=sid) and (after_id is null or study_report_exports.id>after_id) order by study_report_exports.id limit lim+1)t;end if;
 more:=coalesce(cardinality(ids)>lim,false);
 foreach resource_id in array coalesce(ids[1:lim],'{}') loop
  if kind='analysis' then select * into a from private.study_analyses where study_analyses.id=resource_id;perform private.study_analysis_rights(sid,a.config,actor,client);v:=private.study_analysis_record(resource_id);
  elsif kind='reportRevision' then select * into r from private.study_report_revisions where study_report_revisions.id=resource_id;perform private.study_report_rights(sid,r.run_ids,r.analysis_ids,actor,client);v:=private.study_report_record(resource_id);
  else e:=private.study_report_export_authorize(resource_id,actor,client);v:=e.record;end if;
  items:=items||jsonb_build_array(jsonb_build_object('type',kind,'value',v));
 end loop;
 if more then
  insert into private.study_cursors(actor_id,client_id,selection,access_epoch,after_id) values(actor,client,selection,epoch,ids[lim]) returning study_cursors.id into nextid;
 end if;
 return jsonb_build_object('ok',true,'data',jsonb_build_object('type','resourcePage','studyId',sid,'kind',kind,'items',items,'nextCursor',nextid));
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
when invalid_text_representation or invalid_parameter_value or numeric_value_out_of_range then return jsonb_build_object('ok',false,'code','INVALID_REQUEST');
end$$;

-- Closed additive v3 dispatch; the reviewed v2 surface is unchanged.
alter function api.qry_study_reporting_v1(jsonb) rename to study_qry_analysis_v1;
alter function api.study_qry_analysis_v1(jsonb) set schema private;
create function api.qry_study_reporting_v1(p_request jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$declare op text:=p_request->>'operation';actor uuid:=auth.uid();client text:=nullif(auth.jwt()->>'client_id','');r private.study_report_revisions%rowtype;e private.study_report_exports%rowtype;result jsonb;ops jsonb;cfg private.study_reporting_config%rowtype;begin
 perform private.study_reporting_envelope(p_request,false);
 if op='artifact.read' then perform private.study_require(p_request->'artifactRef'->>'type' in ('analysisFacts','reportContent','reportProjection','renderResources','reportExportBundle'),'INVALID_REQUEST');end if;
 if op='study.resources.list' then return private.study_reporting_list(p_request);end if;
 if op='report.read' then
  perform private.study_require(private.study_keys(p_request,array['schemaVersion','requestId','operation','reportRevisionId']),'INVALID_REQUEST');
  select * into r from private.study_report_revisions where id=(p_request->>'reportRevisionId')::uuid;perform private.study_require(found,'FORBIDDEN');
  perform private.study_report_rights(r.study_id,r.run_ids,r.analysis_ids,actor,client);
  return jsonb_build_object('ok',true,'data',jsonb_build_object('type','reportRevision','value',private.study_report_record(r.id)));
 elsif op='export.read' then
  perform private.study_require(private.study_keys(p_request,array['schemaVersion','requestId','operation','exportId']),'INVALID_REQUEST');e:=private.study_report_export_authorize((p_request->>'exportId')::uuid,actor,client);
  return jsonb_build_object('ok',true,'data',jsonb_build_object('type','export','value',e.record));
 end if;
 result:=private.study_qry_analysis_v1(p_request);
 if op='capability.read' and result->>'ok'='true' then
  ops:=result->'data'->'operations'||jsonb_build_array('study.resources.list','report.read','export.read');select * into cfg from private.study_reporting_config where singleton;
  if private.study_client_allowed(client,'STUDY-WRITE-01') and private.study_client_allowed(client,'DB-CORE-READ-01') then
   if cfg.report_enabled then ops:=ops||jsonb_build_array('report.create','report.save','report.freeze');end if;
   if cfg.export_enabled then ops:=ops||jsonb_build_array('export.request');end if;
  end if;
  result:=jsonb_set(jsonb_set(result,'{data,operations}',ops),'{data,runtimeEnabled}',to_jsonb(jsonb_array_length(ops)>1));
 end if;return result;
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
when invalid_text_representation or invalid_parameter_value then return jsonb_build_object('ok',false,'code','INVALID_REQUEST');
end$$;
create or replace function api.cmd_study_reporting_v1(p_request jsonb) returns jsonb language plpgsql security definer set search_path='' as $$begin
 if p_request->>'operation'='analysis.request' then return private.study_analysis_request(p_request);end if;
 if p_request->>'operation'='task.cancel' then return private.study_reporting_task(p_request);end if;
 if p_request->>'operation' in ('report.create','report.save','report.freeze','export.request') then return private.study_report_command(p_request);end if;
 return jsonb_build_object('ok',false,'code','CAPABILITY_UNAVAILABLE');
exception when invalid_text_representation or invalid_parameter_value or numeric_value_out_of_range then return jsonb_build_object('ok',false,'code','INVALID_REQUEST');
end$$;

-- Locator-free audit recovery cannot authorize an actor read or object deletion.
-- Study then intent locks serialize this observation with a possible consume.
create function api.svc_study_report_intent_reconcile_v1(p_intent_id uuid,p_artifact_id uuid,p_content_hash text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare i private.study_report_intents%rowtype;a private.study_artifacts%rowtype;expected_ref jsonb;state text:='unknown';begin
 perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');
 perform private.study_require(p_intent_id is not null and p_artifact_id is not null and private.study_text(to_jsonb(p_content_hash),64,'^[0-9a-f]{64}$'),'INVALID_REQUEST');
 select * into i from private.study_report_intents where id=p_intent_id;
 if found then
  perform 1 from private.studies where id=i.study_id for update;
  select * into i from private.study_report_intents where id=p_intent_id for update;
  if p_artifact_id=any(array[i.content_artifact_id,i.projection_artifact_id,i.resources_artifact_id,i.bundle_artifact_id]) then
   select * into a from private.study_artifacts where id=p_artifact_id;
   if found then
    expected_ref:=case when p_artifact_id=i.content_artifact_id then i.response->'data'->'value'->'contentRef'
     when p_artifact_id=i.projection_artifact_id then i.response->'data'->'value'->'projectionRef'
     when p_artifact_id=i.resources_artifact_id then i.response->'data'->'value'->'resourcesRef'
     else i.response->'data'->'value'->'bundleRef' end;
    if i.response->>'ok'='true' and a.study_id=i.study_id and a.ref=expected_ref and a.ref->>'contentHash'=p_content_hash then state:='committed';
    else state:='referenced';end if;
   elsif i.response is null and i.expires_at<=clock_timestamp() then state:='expired_unreferenced';
   elsif i.response is null then state:='pending';end if;
  end if;
 end if;
 return jsonb_build_object('ok',true,'data',jsonb_build_object('schemaVersion','lca.study-report-reconcile.v1','intentId',p_intent_id,'artifactId',p_artifact_id,'state',state,'deletionPermitted',false));
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
end$$;

create function private.study_report_immutable() returns trigger language plpgsql set search_path='' as $$begin
 if tg_op='DELETE' or tg_table_name<>'study_report_revisions' then raise exception 'FROZEN_REVISION';end if;
 if old.status='frozen' then raise exception 'FROZEN_REVISION';end if;
 if (to_jsonb(old)-'revision'-'status'-'content_hash'-'content_artifact_id'-'validation_evidence') is distinct from (to_jsonb(new)-'revision'-'status'-'content_hash'-'content_artifact_id'-'validation_evidence') then raise exception 'REFERENCE_MISMATCH';end if;return new;
end$$;
create trigger study_report_immutable before update or delete on private.study_report_revisions for each row execute function private.study_report_immutable();
create trigger study_report_runs_immutable before update or delete on private.study_report_runs for each row execute function private.study_report_immutable();
create trigger study_report_analyses_immutable before update or delete on private.study_report_analyses for each row execute function private.study_report_immutable();
create trigger study_export_immutable before update or delete on private.study_report_exports for each row execute function private.study_report_immutable();

do $$declare n text;f record;ident text;begin
 foreach n in array array['study_report_revisions','study_report_runs','study_report_analyses','study_report_exports','study_report_intents'] loop
  execute format('alter table private.%I enable row level security',n);execute format('alter table private.%I force row level security',n);execute format('revoke all on private.%I from public,anon,authenticated,service_role',n);
 end loop;
 for f in select p.oid::regprocedure id from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname like 'study_%' and p.proname<>'study_source_visible_row' loop execute format('revoke all on function %s from public,anon,authenticated,service_role',f.id);end loop;
 for f in select p.oid::regprocedure id,p.proname,pg_catalog.oidvectortypes(p.proargtypes) args from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='api' and p.proname in ('cmd_study_reporting_v1','qry_study_reporting_v1','svc_study_report_intent_resolve_v1','svc_study_report_intent_consume_v1','svc_study_report_intent_reconcile_v1') loop
  execute format('revoke all on function %s from public,anon,authenticated,service_role',f.id);execute format('grant execute on function %s to %I',f.id,case when f.proname like 'svc_%' then 'service_role' else 'authenticated' end);
  ident:=format('api.%I(%s)',f.proname,f.args);insert into private.api_capability_grants values(ident,case when f.proname like 'svc_%' then 'STUDY-SERVICE-01' when f.proname like 'cmd_%' then 'STUDY-WRITE-01' else 'STUDY-READ-01' end,false,f.proname not like 'svc_%',f.proname like 'svc_%') on conflict(routine_identity) do nothing;
 end loop;
end$$;
notify pgrst,'reload schema';
commit;
