-- Database #906 / Edge #550: additive V4. Existing V2/V3 routines, snapshots
-- and manifests retain their historical interpretation. The sole legacy
-- definition delta filters eligible V2 list roles before pagination; its
-- per-resource read guard, owner, ACL and settings remain unchanged.
begin;
alter table private.study_members drop constraint study_members_role_check;
alter table private.study_members add constraint study_members_role_check check(role in ('owner','editor','reviewer','viewer'));
do $$declare definition text;needle text:='where m.actor_id=actor and private.study_team_member(actor,s.team_id) and (after_id is null or s.id>after_id)';begin
 select pg_get_functiondef('private.study_qry_core_v1(jsonb)'::regprocedure) into definition;
 perform private.study_require((length(definition)-length(replace(definition,needle,'')))/length(needle)=1,'REFERENCE_MISMATCH');
 execute replace(definition,needle,'where m.actor_id=actor and m.role in (''owner'',''editor'',''viewer'') and private.study_team_member(actor,s.team_id) and (after_id is null or s.id>after_id)');
end$$;
create table private.study_review_config (
 singleton boolean primary key default true check(singleton), revision bigint not null default 1 check(revision>0),
 enabled boolean not null default false, qualification_evidence_ref text
);
insert into private.study_review_config(singleton) values(true);
create table private.study_report_comments (
 id uuid primary key default gen_random_uuid(),study_id uuid not null,report_id uuid not null,report_hash text not null,
 actor_id uuid not null references auth.users(id),client_id text,body text not null check(length(body) between 1 and 4096),
 created_at timestamptz not null default clock_timestamp(),foreign key(study_id,report_id) references private.study_report_revisions(study_id,id)
);
create table private.study_review_delegations (
 id uuid primary key default gen_random_uuid(),study_id uuid not null,report_id uuid not null,report_hash text not null,
 actor_id uuid not null references auth.users(id),client_id text not null references private.oauth_client_registry(client_id),
 review_class text not null check(review_class='internal'),decision text not null check(decision in ('approve','reject','withdraw')),
 predecessor_id uuid,issued_at timestamptz not null default clock_timestamp(),expires_at timestamptz not null,
 revoked_at timestamptz,consumed_review_id uuid,check(expires_at>issued_at and expires_at<=issued_at+interval '15 minutes'),
 foreign key(study_id,report_id) references private.study_report_revisions(study_id,id)
);
create table private.study_report_reviews (
 id uuid primary key default gen_random_uuid(),study_id uuid not null,report_id uuid not null,report_hash text not null,
 actor_id uuid not null references auth.users(id),client_id text,review_class text not null check(review_class='internal'),
 decision text not null check(decision in ('approve','reject','withdraw')),body text not null check(length(body) between 1 and 4096),
 predecessor_id uuid references private.study_report_reviews(id),delegation_id uuid unique references private.study_review_delegations(id),
 created_at timestamptz not null default clock_timestamp(),
 check((client_id is null)=(delegation_id is null)),foreign key(study_id,report_id) references private.study_report_revisions(study_id,id)
);
alter table private.study_review_delegations add foreign key(consumed_review_id) references private.study_report_reviews(id);
alter table private.study_review_delegations add foreign key(predecessor_id) references private.study_report_reviews(id);
create table private.study_report_review_heads (
 report_id uuid not null references private.study_report_revisions(id),actor_id uuid not null references auth.users(id),
 review_class text not null check(review_class='internal'),review_id uuid not null references private.study_report_reviews(id),
 primary key(report_id,actor_id,review_class)
);
create table private.study_report_finalizations (
 id uuid primary key default gen_random_uuid(),study_id uuid not null,report_id uuid not null,report_hash text not null,
 actor_id uuid not null references auth.users(id),profile_id text not null check(profile_id in ('lca.study-report-unreviewed.v1','lca.study-report-internal-review.v1')),
 expected_review_state_hash text not null check(expected_review_state_hash ~ '^[0-9a-f]{64}$'),accepted_review_ids jsonb not null,
 finalized_at timestamptz not null default clock_timestamp(),foreign key(study_id,report_id) references private.study_report_revisions(study_id,id)
);
create table private.study_review_exports (
 id uuid primary key,study_id uuid not null,report_id uuid not null,actor_id uuid not null references auth.users(id),client_id text,
 grant_epoch bigint not null,finalization_id uuid not null references private.study_report_finalizations(id),record jsonb not null,manifest jsonb not null,
 projection_artifact_id uuid not null,resources_artifact_id uuid not null,bundle_artifact_id uuid not null,
 foreign key(study_id,report_id) references private.study_report_revisions(study_id,id),
 foreign key(study_id,projection_artifact_id) references private.study_artifacts(study_id,id),
 foreign key(study_id,resources_artifact_id) references private.study_artifacts(study_id,id),
 foreign key(study_id,bundle_artifact_id) references private.study_artifacts(study_id,id)
);
create table private.study_report_shares (
 id uuid primary key default gen_random_uuid(),study_id uuid not null,report_id uuid not null,report_hash text not null,
 export_id uuid not null references private.study_review_exports(id),finalization_id uuid not null references private.study_report_finalizations(id),
 issuer_id uuid not null references auth.users(id),issuer_client_id text,recipient_id uuid not null references auth.users(id),grant_epoch bigint not null,
 disclosure_context_hash text not null,created_at timestamptz not null default clock_timestamp(),expires_at timestamptz not null,revoked_at timestamptz,revocation_reason text,
 check(expires_at>created_at),foreign key(study_id,report_id) references private.study_report_revisions(study_id,id)
);
create table private.study_review_intents (
 id uuid primary key default gen_random_uuid(),study_id uuid not null,report_id uuid not null,actor_id uuid not null references auth.users(id),client_id text,
 operation text not null check(operation in ('report.view','export.request','export.download','share.view','share.download')),request jsonb not null,
 share_id uuid references private.study_report_shares(id),finalization_id uuid references private.study_report_finalizations(id),
 grant_epoch bigint not null,config_revision bigint not null,reporting_config_revision bigint not null,review_state_hash text not null,
 export_id uuid,projection_artifact_id uuid,resources_artifact_id uuid,bundle_artifact_id uuid,
 disclosure_context_hash text not null,created_at timestamptz not null default clock_timestamp(),expires_at timestamptz not null default clock_timestamp()+interval '2 minutes',response jsonb,
 foreign key(study_id,report_id) references private.study_report_revisions(study_id,id)
);
create index study_comment_report_idx on private.study_report_comments(study_id,report_id,id);
create index study_comment_actor_idx on private.study_report_comments(actor_id);
create index study_delegation_report_idx on private.study_review_delegations(study_id,report_id,id);
create index study_delegation_actor_idx on private.study_review_delegations(actor_id);
create index study_delegation_client_idx on private.study_review_delegations(client_id);
create index study_delegation_predecessor_idx on private.study_review_delegations(predecessor_id);
create index study_delegation_consumed_idx on private.study_review_delegations(consumed_review_id);
create index study_review_report_idx on private.study_report_reviews(study_id,report_id,id);
create index study_review_actor_idx on private.study_report_reviews(actor_id);
create index study_review_predecessor_idx on private.study_report_reviews(predecessor_id);
create index study_review_head_actor_idx on private.study_report_review_heads(actor_id);
create index study_review_head_review_idx on private.study_report_review_heads(review_id);
create index study_finalization_report_idx on private.study_report_finalizations(study_id,report_id,finalized_at,id);
create index study_finalization_actor_idx on private.study_report_finalizations(actor_id);
create index study_v4_export_report_idx on private.study_review_exports(study_id,report_id);
create index study_v4_export_actor_idx on private.study_review_exports(actor_id);
create index study_v4_export_finalization_idx on private.study_review_exports(finalization_id);
create index study_v4_export_projection_idx on private.study_review_exports(study_id,projection_artifact_id);
create index study_v4_export_resources_idx on private.study_review_exports(study_id,resources_artifact_id);
create index study_v4_export_bundle_idx on private.study_review_exports(study_id,bundle_artifact_id);
create index study_share_report_idx on private.study_report_shares(study_id,report_id,id);
create index study_share_recipient_idx on private.study_report_shares(recipient_id);
create index study_share_issuer_idx on private.study_report_shares(issuer_id);
create index study_share_export_idx on private.study_report_shares(export_id);
create index study_share_finalization_idx on private.study_report_shares(finalization_id);
create index study_review_intent_report_idx on private.study_review_intents(study_id,report_id);
create index study_review_intent_actor_idx on private.study_review_intents(actor_id,expires_at);
create index study_review_intent_share_idx on private.study_review_intents(share_id);
create index study_review_intent_finalization_idx on private.study_review_intents(finalization_id);

create function private.study_review_envelope(p_request jsonb,p_write boolean) returns void
language plpgsql set search_path='' as $$begin
 perform private.study_require(auth.uid() is not null and not coalesce(util.is_service_request(),false),'AUTH_REQUIRED');
 perform private.study_require(p_request->>'schemaVersion'='lca.study-api.v4' and octet_length(p_request::text)<=262144
  and private.study_text(p_request->'requestId',128,'^[A-Za-z0-9][A-Za-z0-9._:-]*$'),'INVALID_REQUEST');
 if p_write then perform private.study_require(private.study_text(p_request->'idempotencyKey',128,'^[A-Za-z0-9][A-Za-z0-9._:-]*$'),'INVALID_REQUEST');end if;
end$$;
create function private.study_review_share_check(p_share uuid,p_actor uuid,p_client text,p_bytes boolean) returns private.study_report_shares
language plpgsql security definer set search_path='' as $$declare s private.study_report_shares%rowtype;st jsonb;e private.study_review_exports%rowtype;begin
 select * into s from private.study_report_shares where id=p_share;perform private.study_require(found,'FORBIDDEN');
 perform 1 from private.studies where id=s.study_id for update;
 select * into s from private.study_report_shares where id=p_share;
 perform private.study_require(p_actor in (s.issuer_id,s.recipient_id) and private.study_client_allowed(p_client,'STUDY-READ-01'),'FORBIDDEN');
 if p_bytes then
  perform private.study_require(p_actor=s.recipient_id,'FORBIDDEN');
  perform private.study_require(s.revoked_at is null and s.expires_at>clock_timestamp(),'DISCLOSURE_DENIED');
  perform private.study_review_authorize(s.study_id,s.issuer_id,s.issuer_client_id,'manage');
  select * into e from private.study_review_exports where id=s.export_id;
  perform private.study_require(private.study_client_allowed(e.client_id,'STUDY-WRITE-01'),'DISCLOSURE_DENIED');
  perform private.study_require(s.grant_epoch=(select grant_epoch from private.studies where id=s.study_id),'DISCLOSURE_DENIED');
  perform private.study_review_disclosure(s.report_id);st:=private.study_review_state(s.report_id);
  perform private.study_require(st->>'acceptance'='current' and st->'finalization'->>'finalizationId'=s.finalization_id::text,'DISCLOSURE_DENIED');
 end if;return s;
end$$;
create function private.study_review_share_record(p_share uuid) returns jsonb
language plpgsql security definer set search_path='' as $$declare s private.study_report_shares%rowtype;e private.study_review_exports%rowtype;status text:='active';begin
 select * into s from private.study_report_shares where id=p_share;if not found then return null;end if;select * into e from private.study_review_exports where id=s.export_id;
 if s.revoked_at is not null then status:='revoked';elsif s.expires_at<=clock_timestamp() then status:='expired';else
  begin perform private.study_review_share_check(s.id,s.recipient_id,null,true);exception when raise_exception then status:='invalidated';end;
 end if;
 return jsonb_build_object('studyId',s.study_id,'reportRevisionId',s.report_id,'reportContentHash',s.report_hash,'shareId',s.id,'exportId',s.export_id,
 'finalizationId',s.finalization_id,'issuerId',s.issuer_id,'recipientId',s.recipient_id,'disclosurePolicyId','lca.study-report-summary-share.v1',
 'disclosureContextHash',s.disclosure_context_hash,'grantEpoch',s.grant_epoch,'projectionRef',e.record->'projectionRef','bundleRef',e.record->'bundleRef',
 'createdAt',s.created_at,'expiresAt',s.expires_at,'revokedAt',s.revoked_at,'status',status);
end$$;
create function private.study_review_export_check(p_export uuid,p_actor uuid,p_client text) returns private.study_review_exports
language plpgsql security definer set search_path='' as $$declare e private.study_review_exports%rowtype;begin
 select * into e from private.study_review_exports where id=p_export;perform private.study_require(found,'FORBIDDEN');
 perform private.study_review_authorize(e.study_id,p_actor,p_client,'manage');
 select * into e from private.study_review_exports where id=p_export;
 perform private.study_require(e.actor_id=p_actor and private.study_client_allowed(e.client_id,'STUDY-WRITE-01')
  and e.grant_epoch=(select grant_epoch from private.studies where id=e.study_id),'FORBIDDEN');
 perform private.study_review_disclosure(e.report_id);return e;
end$$;
create function private.study_review_new_intent(p_request jsonb,p_report uuid,p_share uuid default null,p_export uuid default null) returns jsonb
language plpgsql security definer set search_path='' as $$declare r private.study_report_revisions%rowtype;e private.study_review_exports%rowtype;i private.study_review_intents%rowtype;st jsonb;cfg private.study_review_config%rowtype;actor uuid:=auth.uid();client text:=nullif(auth.jwt()->>'client_id','');op text:=p_request->>'operation';begin
 select * into r from private.study_report_revisions where id=p_report;
 if p_share is not null then perform private.study_review_share_check(p_share,actor,client,true);
 elsif op='export.download' then
  e:=private.study_review_export_check(p_export,actor,client);perform private.study_require(e.report_id=p_report,'REFERENCE_MISMATCH');
 else perform private.study_review_authorize(r.study_id,actor,client,case when op='export.request' then 'manage' else 'read' end);perform private.study_review_disclosure(r.id);end if;
 st:=private.study_review_state(r.id);
 if op='export.request' then
  perform private.study_require(st->>'acceptance'='current' and st->'finalization'->>'finalizationId'=p_request->>'finalizationId'
   and st->>'reviewStateHash'=p_request->>'expectedReviewStateHash','REVISION_CONFLICT');
  perform private.study_analysis_require_current(r.study_id,jsonb_build_object('runIds',r.run_ids));
  perform private.study_require((select export_enabled and export_profile is not null from private.study_reporting_config where singleton),'CAPABILITY_UNAVAILABLE');
 end if;
 select * into cfg from private.study_review_config where singleton for share;perform private.study_require(cfg.enabled,'CAPABILITY_UNAVAILABLE');
 perform pg_advisory_xact_lock(hashtextextended('study-review-intent:'||actor::text,906));
 perform private.study_require((select count(*) from private.study_review_intents where actor_id=actor and response is null and expires_at>clock_timestamp())<64,'CAPABILITY_UNAVAILABLE');
 insert into private.study_review_intents(study_id,report_id,actor_id,client_id,operation,request,share_id,finalization_id,grant_epoch,config_revision,reporting_config_revision,review_state_hash,
 export_id,projection_artifact_id,resources_artifact_id,bundle_artifact_id,disclosure_context_hash)
 values(r.study_id,r.id,actor,client,op,p_request,p_share,case when op='export.download' then e.finalization_id else (st->'finalization'->>'finalizationId')::uuid end,
 (select grant_epoch from private.studies where id=r.study_id),cfg.revision,(select revision from private.study_reporting_config where singleton),st->>'reviewStateHash',
 case when op='export.request' then gen_random_uuid() when op='export.download' then e.id end,case when op='export.request' then gen_random_uuid() end,
 case when op='export.request' then gen_random_uuid() end,case when op='export.request' then gen_random_uuid() end,
 private.study_reporting_digest('lca.study-review-disclosure.v1',jsonb_build_object('actorId',actor,'clientId',client,'reportRevisionId',r.id,'reportContentHash',r.content_hash,'reviewStateHash',st->>'reviewStateHash','shareId',p_share,'nonce',gen_random_uuid()))) returning * into i;
 return jsonb_build_object('ok',true,'data',jsonb_build_object('kind','studyReviewIntent','intentId',i.id,'operation',i.operation,'expiresAt',i.expires_at));
end$$;
create function private.study_review_intent_check(p_id uuid) returns private.study_review_intents
language plpgsql security definer set search_path='' as $$declare i private.study_review_intents%rowtype;st jsonb;cfg private.study_review_config%rowtype;begin
 select * into i from private.study_review_intents where id=p_id;perform private.study_require(found,'CAPABILITY_UNAVAILABLE');
 perform 1 from private.studies where id=i.study_id for update;
 select * into i from private.study_review_intents where id=p_id;
 if i.share_id is not null then perform private.study_review_share_check(i.share_id,i.actor_id,i.client_id,true);
 elsif i.operation='export.download' then perform private.study_review_export_check(i.export_id,i.actor_id,i.client_id);
 else perform private.study_review_authorize(i.study_id,i.actor_id,i.client_id,case when i.operation='export.request' then 'manage' else 'read' end);perform private.study_review_disclosure(i.report_id);end if;
 if i.response is not null then return i;end if;
 select * into cfg from private.study_review_config where singleton for share;
 perform private.study_require(cfg.enabled and cfg.revision=i.config_revision and i.expires_at>clock_timestamp(),'CAPABILITY_UNAVAILABLE');
 perform private.study_require(i.grant_epoch=(select grant_epoch from private.studies where id=i.study_id),'FORBIDDEN');
 if i.operation='export.request' then
  st:=private.study_review_state(i.report_id);
  perform private.study_require(st->>'acceptance'='current' and st->'finalization'->>'finalizationId'=i.finalization_id::text and st->>'reviewStateHash'=i.review_state_hash,'REVISION_CONFLICT');
  perform private.study_analysis_require_current(i.study_id,jsonb_build_object('runIds',(select run_ids from private.study_report_revisions where id=i.report_id)));
  perform private.study_require((select export_enabled and export_profile is not null and revision=i.reporting_config_revision from private.study_reporting_config where singleton),'CAPABILITY_UNAVAILABLE');
 end if;return i;
end$$;
-- All V4 transitions acquire Study first. Existing V2 authorization stays
-- unchanged, so reviewer membership never implies raw Study/source authority.
create function private.study_review_authorize(p_study uuid,p_actor uuid,p_client text,p_action text) returns text
language plpgsql security definer set search_path='' as $$declare s private.studies%rowtype;r text;begin
 perform private.study_require(p_actor is not null,'AUTH_REQUIRED');
 select * into s from private.studies where id=p_study for update;perform private.study_require(found,'FORBIDDEN');
 perform private.study_require(private.study_client_allowed(p_client,case when p_action='read' then 'STUDY-READ-01' else 'STUDY-WRITE-01' end),'FORBIDDEN');
 select role into r from private.study_members where study_id=p_study and actor_id=p_actor;
 if s.team_id is not null then
  perform 1 from private.roles where user_id=p_actor and team_id=s.team_id and role in ('owner','admin','member') for share;
  perform private.study_require(found,'FORBIDDEN');
 end if;
 perform private.study_require(case p_action when 'read' then r in ('owner','editor','reviewer','viewer')
  when 'comment' then r in ('owner','editor','reviewer') when 'review' then r='reviewer' when 'manage' then r='owner' else false end,'FORBIDDEN');return r;
end$$;
-- Summary redistribution is explicit: Study owner must retain actual source
-- rights and own every captured private source. Read permission is insufficient.
create function private.study_review_disclosure(p_report uuid) returns void
language plpgsql security definer set search_path='' as $$declare r private.study_report_revisions%rowtype;issuer uuid;rid text;scope jsonb;begin
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
create function private.study_review_record(p_id uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('studyId',study_id,'reportRevisionId',report_id,'reportContentHash',report_hash,'reviewId',id,'actorId',actor_id,'clientId',client_id,
 'reviewClass',review_class,'decision',decision,'comment',body,'predecessorReviewId',predecessor_id,'delegationId',delegation_id,
 'authorityKind',case when client_id is null then 'first_party_actor' else 'oauth_delegated_actor' end,'createdAt',created_at) from private.study_report_reviews where id=p_id
$$;
create function private.study_comment_record(p_id uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('studyId',study_id,'reportRevisionId',report_id,'reportContentHash',report_hash,'commentId',id,'actorId',actor_id,'clientId',client_id,'text',body,'createdAt',created_at)
 from private.study_report_comments where id=p_id
$$;
create function private.study_delegation_record(p_id uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('studyId',study_id,'reportRevisionId',report_id,'reportContentHash',report_hash,'delegationId',id,'actorId',actor_id,'clientId',client_id,
 'reviewClass',review_class,'decision',decision,'predecessorReviewId',predecessor_id,'issuedAt',issued_at,'expiresAt',expires_at,'revokedAt',revoked_at,'consumedReviewId',consumed_review_id)
 from private.study_review_delegations where id=p_id
$$;
create function private.study_finalization_record(p_id uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('studyId',study_id,'reportRevisionId',report_id,'reportContentHash',report_hash,'finalizationId',id,'actorId',actor_id,'profileId',profile_id,
 'expectedReviewStateHash',expected_review_state_hash,'acceptedReviewIds',accepted_review_ids,'finalizedAt',finalized_at) from private.study_report_finalizations where id=p_id
$$;
-- Expiry limits delegation admission. After consumption, live revocation,
-- exact consumption, reviewer/team membership and client grants govern acceptance.
create function private.study_review_current(p_id uuid) returns boolean
language plpgsql security definer set search_path='' as $$declare r private.study_report_reviews%rowtype;s private.studies%rowtype;d private.study_review_delegations%rowtype;begin
 select * into r from private.study_report_reviews where id=p_id;if not found then return false;end if;
 select * into s from private.studies where id=r.study_id;
 if not exists(select 1 from private.study_report_review_heads where report_id=r.report_id and actor_id=r.actor_id and review_class=r.review_class and review_id=r.id)
  or not exists(select 1 from private.study_members where study_id=r.study_id and actor_id=r.actor_id and role='reviewer') or not private.study_team_member(r.actor_id,s.team_id) then return false;end if;
 if s.team_id is not null then perform 1 from private.roles where user_id=r.actor_id and team_id=s.team_id and role in ('owner','admin','member') for share;if not found then return false;end if;end if;
 if not private.study_client_allowed(r.client_id,'STUDY-WRITE-01') then return false;end if;
 if r.client_id is not null then
  select * into d from private.study_review_delegations where id=r.delegation_id;
  if not found or d.revoked_at is not null or d.consumed_review_id is distinct from r.id or d.actor_id<>r.actor_id or d.client_id<>r.client_id
   or d.report_id<>r.report_id or d.report_hash<>r.report_hash or d.review_class<>r.review_class or d.decision<>r.decision or d.predecessor_id is distinct from r.predecessor_id then return false;end if;
 end if;return true;
end$$;
create function private.study_review_state(p_report uuid) returns jsonb
language plpgsql security definer set search_path='' as $$declare r private.study_report_revisions%rowtype;heads jsonb:='[]'::jsonb;currentids jsonb:='[]'::jsonb;accepted jsonb:='[]'::jsonb;h record;valid boolean;digest text;f private.study_report_finalizations%rowtype;begin
 select * into r from private.study_report_revisions where id=p_report;perform private.study_require(found,'FORBIDDEN');
 for h in select v.* from private.study_report_review_heads x join private.study_report_reviews v on v.id=x.review_id where x.report_id=r.id order by v.actor_id,v.review_class loop
  valid:=private.study_review_current(h.id);heads:=heads||jsonb_build_array(jsonb_build_object('review',private.study_review_record(h.id),'current',valid));
  currentids:=currentids||jsonb_build_array(h.id);
  if valid and h.decision='approve' and h.actor_id<>r.author_id then accepted:=accepted||jsonb_build_array(h.id);end if;
 end loop;
 digest:=private.study_reporting_digest('lca.study-review-state.v1',jsonb_build_object('reportRevisionId',r.id,'reportContentHash',r.content_hash,'heads',heads));
 select * into f from private.study_report_finalizations where report_id=r.id order by finalized_at desc,id desc limit 1;
 return jsonb_build_object('studyId',r.study_id,'reportRevisionId',r.id,'reportContentHash',r.content_hash,'reportRevision',r.revision,'authorId',r.author_id,
 'reviewStateHash',digest,'currentReviewIds',currentids,'acceptedReviewIds',accepted,'finalization',private.study_finalization_record(f.id),
 'acceptance',case when f.id is null then 'not_finalized' when f.profile_id='lca.study-report-unreviewed.v1' or
 (f.expected_review_state_hash=digest and jsonb_array_length(f.accepted_review_ids)>0 and f.accepted_review_ids<@accepted) then 'current' else 'invalidated' end,
 'validity',private.study_report_validity_snapshot(r.study_id,r.run_ids,(r.validity_snapshot->>'checkedAt')::timestamptz),'checkedAt',clock_timestamp());
end$$;
create function api.svc_study_review_intent_resolve_v1(p_intent_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$declare i private.study_review_intents%rowtype;r private.study_report_revisions%rowtype;s private.study_report_shares%rowtype;e private.study_review_exports%rowtype;
 st jsonb;producer jsonb;runs jsonb;analyses jsonb;issuer uuid;artifact jsonb;begin
 perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');i:=private.study_review_intent_check(p_intent_id);
 if i.response is not null then return i.response;end if;
 select * into r from private.study_report_revisions where id=i.report_id;st:=jsonb_set(private.study_review_state(r.id),'{checkedAt}',to_jsonb(i.created_at));
 if i.operation='export.download' then
  select * into e from private.study_review_exports where id=i.export_id;
  artifact:=private.study_private_artifact(i.study_id,e.bundle_artifact_id)||jsonb_build_object('kind','artifactCapability');
 elsif i.share_id is null then
  select owner_id into issuer from private.studies where id=i.study_id;
  select jsonb_agg(jsonb_build_object('run',private.study_record('run',rn.id),'revision',private.study_record('studyRevision',rn.study_revision_id),
   'scenario',private.study_record('scenarioRevision',rn.scenario_id),'preparation',private.study_record('modelPreparation',rn.preparation_id),
   'preparedArtifact',private.study_private_artifact(i.study_id,p.input_artifact_id),'resultArtifact',private.study_private_artifact(i.study_id,rn.result_artifact_id)) order by x.n)
   into runs from jsonb_array_elements_text(r.run_ids) with ordinality x(v,n) join private.study_runs rn on rn.id=x.v::uuid and rn.study_id=i.study_id join private.study_model_preparations p on p.id=rn.preparation_id;
  select jsonb_agg(jsonb_build_object('analysis',private.study_analysis_record(a.id),'factsArtifact',private.study_private_artifact(i.study_id,a.facts_artifact_id)) order by x.n)
   into analyses from jsonb_array_elements_text(r.analysis_ids) with ordinality x(v,n) join private.study_analyses a on a.id=x.v::uuid and a.study_id=i.study_id;
  producer:=jsonb_build_object('kind','reportCommandContext','intentId',i.id,'expiresAt',i.expires_at,'operation','export.request',
   'request',jsonb_build_object('schemaVersion','lca.study-api.v3','requestId',i.request->>'requestId','idempotencyKey',coalesce(i.request->>'idempotencyKey',i.id::text),
    'operation','export.request','reportRevisionId',r.id,'expectedContentHash',r.content_hash,'rendererVersion','1.0.0','viewModelVersion','lca.study-report-view.v1'),
   'studyId',i.study_id,'actorId',issuer,'clientId',null,'grantEpoch',i.grant_epoch,'generatedAt',i.created_at,'reportRevisionId',r.id,'contentArtifactId',null,
   'exportId',i.export_id,'projectionArtifactId',i.projection_artifact_id,'resourcesArtifactId',i.resources_artifact_id,'bundleArtifactId',i.bundle_artifact_id,
   'report',private.study_report_record(r.id),'contentArtifact',private.study_private_artifact(i.study_id,r.content_artifact_id),'runs',runs,'analyses',analyses,
   'factsBindingHash',private.study_reporting_digest('lca.study-report-facts-binding.v1',r.facts_refs),'disclosureContextHash',i.disclosure_context_hash,
   'exportProfile',(select export_profile from private.study_reporting_config where singleton));
 else
  select * into s from private.study_report_shares where id=i.share_id;select * into e from private.study_review_exports where id=s.export_id;
  artifact:=private.study_private_artifact(i.study_id,case when i.operation='share.view' then e.projection_artifact_id else e.bundle_artifact_id end)||jsonb_build_object('kind','artifactCapability');
 end if;
 return jsonb_build_object('ok',true,'data',jsonb_build_object('kind','studyReviewContext','intentId',i.id,'expiresAt',i.expires_at,'operation',i.operation,'actorId',i.actor_id,'clientId',i.client_id,
 'request',i.request,'currentState',st,'producerContext',producer,'share',private.study_review_share_record(s.id),'export',e.record,'artifact',artifact));
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
end$$;
create function api.svc_study_review_configure_v1(p_expected_revision bigint,p_configuration jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$declare cfg private.study_review_config%rowtype;begin
 perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');
 perform private.study_require(private.study_keys(p_configuration,array['qualificationVersion','enabled','evidenceRef'])
  and p_configuration->>'qualificationVersion'='lca.study-review-qualification.v1' and jsonb_typeof(p_configuration->'enabled')='boolean'
  and private.study_text(p_configuration->'evidenceRef',512),'INVALID_REQUEST');
 select * into cfg from private.study_review_config where singleton for update;perform private.study_require(cfg.revision=p_expected_revision,'REVISION_CONFLICT');
 update private.study_review_config set revision=revision+1,enabled=(p_configuration->>'enabled')::boolean,qualification_evidence_ref=p_configuration->>'evidenceRef' where singleton returning * into cfg;
 return jsonb_build_object('ok',true,'data',jsonb_build_object('revision',cfg.revision,'enabled',cfg.enabled,'qualificationVersion','lca.study-review-qualification.v1','evidenceRef',cfg.qualification_evidence_ref));
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);end$$;
create function api.cmd_study_review_v1(p_request jsonb) returns jsonb
language plpgsql security definer set search_path='' set statement_timeout='15s' as $$
declare op text:=p_request->>'operation';actor uuid:=auth.uid();client text:=nullif(auth.jwt()->>'client_id','');sid uuid;rid uuid;member uuid;newid uuid;head uuid;allowed text[];
 req jsonb:=(p_request-'schemaVersion'-'requestId'-'idempotencyKey')||jsonb_build_object('_verifiedClientId',client);prev private.study_command_receipts%rowtype;r private.study_report_revisions%rowtype;d private.study_review_delegations%rowtype;
 s private.study_report_shares%rowtype;e private.study_review_exports%rowtype;study private.studies%rowtype;st jsonb;result jsonb;value jsonb;ts timestamptz;
begin
 perform private.study_review_envelope(p_request,true);
 case op
 when 'member.set' then allowed:=array['target','memberId','role'];sid:=(p_request->'target'->>'id')::uuid;
 when 'review.delegation.revoke' then allowed:=array['delegationId'];select study_id,report_id into sid,rid from private.study_review_delegations where id=(p_request->>'delegationId')::uuid;
 when 'share.revoke' then allowed:=array['shareId','reason'];select study_id,report_id into sid,rid from private.study_report_shares where id=(p_request->>'shareId')::uuid;
 when 'report.finalize' then allowed:=array['target','expectedContentHash','expectedReviewStateHash','profileId','acceptedReviewIds'];rid:=(p_request->'target'->>'id')::uuid;
 when 'comment.append' then allowed:=array['reportRevisionId','expectedContentHash','text'];rid:=(p_request->>'reportRevisionId')::uuid;
 when 'review.record' then allowed:=array['reportRevisionId','expectedContentHash','reviewClass','decision','comment','predecessorReviewId','delegationId'];rid:=(p_request->>'reportRevisionId')::uuid;
 when 'review.delegation.issue' then allowed:=array['reportRevisionId','expectedContentHash','clientId','reviewClass','decision','predecessorReviewId','expiresAt'];rid:=(p_request->>'reportRevisionId')::uuid;
 when 'export.request' then allowed:=array['reportRevisionId','expectedContentHash','finalizationId','expectedReviewStateHash','rendererVersion','viewModelVersion'];rid:=(p_request->>'reportRevisionId')::uuid;
 when 'share.create' then allowed:=array['reportRevisionId','expectedContentHash','exportId','recipientId','disclosurePolicyId','expiresAt'];rid:=(p_request->>'reportRevisionId')::uuid;
 else perform private.study_require(false,'CAPABILITY_UNAVAILABLE');end case;
 perform private.study_require(private.study_keys(p_request,allowed||array['schemaVersion','requestId','idempotencyKey','operation']),'INVALID_REQUEST');
 if sid is null and rid is not null then select study_id into sid from private.study_report_revisions where id=rid;end if;
 perform private.study_review_authorize(sid,actor,client,case when op in ('member.set','report.finalize','export.request','share.create','share.revoke') then 'manage'
 when op in ('review.record','review.delegation.issue','review.delegation.revoke') then 'review' else 'comment' end);
 select * into study from private.studies where id=sid;
 -- Withdrawal and explicit revoke remain possible even when disclosure ceased.
 if rid is not null and op not in ('share.revoke','review.delegation.revoke') then
  select * into r from private.study_report_revisions where id=rid and study_id=sid;
  perform private.study_require(found and r.status='frozen' and r.content_hash=p_request->>'expectedContentHash','REFERENCE_MISMATCH');
  perform private.study_review_disclosure(r.id);
 end if;
 if op in ('review.delegation.issue','review.delegation.revoke') then perform private.study_require(client is null,'FORBIDDEN');end if;
 if op='review.delegation.revoke' then select * into d from private.study_review_delegations where id=(p_request->>'delegationId')::uuid;perform private.study_require(d.actor_id=actor,'FORBIDDEN');end if;
 if op='share.revoke' then select * into s from private.study_report_shares where id=(p_request->>'shareId')::uuid;perform private.study_require(s.issuer_id=actor,'FORBIDDEN');end if;
 select * into prev from private.study_command_receipts where actor_id=actor and operation=op and scope='v4:'||sid::text and idempotency_key=p_request->>'idempotencyKey';
 if found then
  perform private.study_require(prev.request=req,'IDEMPOTENCY_CONFLICT');
  if op='review.record' and client is not null then
   select * into d from private.study_review_delegations where id=(p_request->>'delegationId')::uuid;
   perform private.study_require(d.actor_id=actor and d.client_id=client and d.revoked_at is null and d.consumed_review_id::text=prev.response->'data'->'value'->>'reviewId','FORBIDDEN');
  end if;
  if op='export.request' and prev.response->'data'->>'kind'='studyReviewIntent' then
   declare oldintent private.study_review_intents%rowtype;begin oldintent:=private.study_review_intent_check((prev.response->'data'->>'intentId')::uuid);if oldintent.response is not null then return oldintent.response;end if;end;
  end if;return private.study_review_refresh(prev.response);
 end if;
 perform private.study_require(study.status='active','FROZEN_REVISION');
 perform 1 from private.study_review_config where singleton and enabled for share;perform private.study_require(found,'CAPABILITY_UNAVAILABLE');
 if op='member.set' then
  perform private.study_require(private.study_keys(p_request->'target',array['type','id','expectedRevision']) and p_request->'target'->>'type'='study'
   and jsonb_typeof(p_request->'target'->'expectedRevision')='number' and (p_request->'target'->>'expectedRevision')::numeric=study.revision,'REVISION_CONFLICT');
  member:=(p_request->>'memberId')::uuid;
  perform private.study_require(member<>study.owner_id,'FORBIDDEN');
  perform private.study_require(p_request->'role'='null'::jsonb or p_request->>'role' in ('editor','reviewer','viewer'),'INVALID_REQUEST');
  perform private.study_require(study.team_id is not null or p_request->'role'='null'::jsonb or p_request->>'role'='reviewer','CAPABILITY_UNAVAILABLE');
  if p_request->'role'='null'::jsonb then delete from private.study_members where study_id=sid and actor_id=member;
  else
   if study.team_id is not null then perform 1 from private.roles where user_id=member and team_id=study.team_id and role in ('owner','admin','member') for share;perform private.study_require(found,'FORBIDDEN');end if;
   insert into private.study_members values(sid,member,p_request->>'role') on conflict(study_id,actor_id) do update set role=excluded.role;end if;
  update private.studies set revision=revision+1,grant_epoch=grant_epoch+1 where id=sid returning * into study;
  value:=jsonb_build_object('type','member','studyId',sid,'studyRevision',study.revision,'memberId',member,'role',p_request->'role');
 elsif op='comment.append' then
  perform private.study_require(private.study_text(p_request->'text',4096) and p_request->>'text' !~ '[<>]','INVALID_REQUEST');
  insert into private.study_report_comments(study_id,report_id,report_hash,actor_id,client_id,body) values(sid,r.id,r.content_hash,actor,client,p_request->>'text') returning id into newid;
  value:=jsonb_build_object('type','comment','value',private.study_comment_record(newid));
 elsif op in ('review.record','review.delegation.issue') then
  perform private.study_require(p_request->>'reviewClass'='internal' and p_request->>'decision' in ('approve','reject','withdraw'),'INVALID_REQUEST');
  select review_id into head from private.study_report_review_heads where report_id=r.id and actor_id=actor and review_class='internal';
  perform private.study_require(head is not distinct from (p_request->>'predecessorReviewId')::uuid,'REVISION_CONFLICT');
  perform private.study_require(p_request->>'decision'<>'withdraw' or head is not null,'REVISION_CONFLICT');
  if op='review.delegation.issue' then
   perform private.study_require((p_request->>'clientId') ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' and private.study_client_allowed(p_request->>'clientId','STUDY-WRITE-01'),'FORBIDDEN');
   ts:=(p_request->>'expiresAt')::timestamptz;perform private.study_require(ts>clock_timestamp() and ts<=clock_timestamp()+interval '15 minutes','INVALID_REQUEST');
   insert into private.study_review_delegations(study_id,report_id,report_hash,actor_id,client_id,review_class,decision,predecessor_id,expires_at)
   values(sid,r.id,r.content_hash,actor,p_request->>'clientId','internal',p_request->>'decision',head,ts) returning id into newid;
   value:=jsonb_build_object('type','delegation','value',private.study_delegation_record(newid));
  else
   perform private.study_require(private.study_text(p_request->'comment',4096) and p_request->>'comment' !~ '[<>]','INVALID_REQUEST');
   perform private.study_require(head is not null or (select count(*) from private.study_report_review_heads where report_id=r.id)<64,'CAPABILITY_UNAVAILABLE');
   if client is null then perform private.study_require(p_request->'delegationId'='null'::jsonb,'FORBIDDEN');
   else
    select * into d from private.study_review_delegations where id=(p_request->>'delegationId')::uuid for update;
    perform private.study_require(found and d.actor_id=actor and d.client_id=client and d.report_id=r.id and d.report_hash=r.content_hash and d.review_class='internal'
     and d.decision=p_request->>'decision' and d.predecessor_id is not distinct from head and d.revoked_at is null and d.consumed_review_id is null and d.expires_at>clock_timestamp(),'FORBIDDEN');
   end if;
   insert into private.study_report_reviews(study_id,report_id,report_hash,actor_id,client_id,review_class,decision,body,predecessor_id,delegation_id)
    values(sid,r.id,r.content_hash,actor,client,'internal',p_request->>'decision',p_request->>'comment',head,d.id) returning id into newid;
   insert into private.study_report_review_heads values(r.id,actor,'internal',newid) on conflict(report_id,actor_id,review_class) do update set review_id=excluded.review_id;
   if d.id is not null then update private.study_review_delegations set consumed_review_id=newid where id=d.id;end if;
   value:=jsonb_build_object('type','review','value',private.study_review_record(newid),'state',private.study_review_state(r.id));
  end if;
 elsif op='review.delegation.revoke' then
  update private.study_review_delegations set revoked_at=coalesce(revoked_at,clock_timestamp()) where id=d.id;
  value:=jsonb_build_object('type','delegation','value',private.study_delegation_record(d.id));
 elsif op='report.finalize' then
  perform private.study_require(private.study_keys(p_request->'target',array['type','id','expectedRevision']) and p_request->'target'->>'type'='reportRevision'
   and jsonb_typeof(p_request->'target'->'expectedRevision')='number' and (p_request->'target'->>'expectedRevision')::numeric=r.revision,'REVISION_CONFLICT');
  st:=private.study_review_state(r.id);perform private.study_require(st->>'reviewStateHash'=p_request->>'expectedReviewStateHash','REVISION_CONFLICT');
  perform private.study_require(p_request->>'profileId' in ('lca.study-report-unreviewed.v1','lca.study-report-internal-review.v1')
   and private.study_report_ids(p_request->'acceptedReviewIds',0,64),'INVALID_REQUEST');
  perform private.study_require(case when p_request->>'profileId'='lca.study-report-unreviewed.v1' then p_request->'acceptedReviewIds'='[]'::jsonb
   else jsonb_array_length(p_request->'acceptedReviewIds')>0 and (p_request->'acceptedReviewIds')<@(st->'acceptedReviewIds') end,'FORBIDDEN');
  insert into private.study_report_finalizations(study_id,report_id,report_hash,actor_id,profile_id,expected_review_state_hash,accepted_review_ids)
   values(sid,r.id,r.content_hash,actor,p_request->>'profileId',p_request->>'expectedReviewStateHash',p_request->'acceptedReviewIds') returning id into newid;
  value:=jsonb_build_object('type','finalization','value',private.study_finalization_record(newid),'state',private.study_review_state(r.id));
 elsif op='export.request' then
  perform private.study_require(p_request->>'rendererVersion'='1.0.0' and p_request->>'viewModelVersion'='lca.study-report-view.v1','CAPABILITY_UNAVAILABLE');
  result:=private.study_review_new_intent(p_request,r.id);value:=result->'data';
 elsif op='share.create' then
  select * into e from private.study_review_exports where id=(p_request->>'exportId')::uuid;
  st:=private.study_review_state(r.id);
  perform private.study_require(found and e.report_id=r.id and e.actor_id=actor and e.grant_epoch=study.grant_epoch and st->>'acceptance'='current'
   and st->'finalization'->>'finalizationId'=e.finalization_id::text and private.study_client_allowed(e.client_id,'STUDY-WRITE-01'),'DISCLOSURE_DENIED');
  perform private.study_require(p_request->>'disclosurePolicyId'='lca.study-report-summary-share.v1','INVALID_REQUEST');
  ts:=(p_request->>'expiresAt')::timestamptz;perform private.study_require(ts>clock_timestamp() and ts<=clock_timestamp()+interval '30 days','INVALID_REQUEST');
  insert into private.study_report_shares(study_id,report_id,report_hash,export_id,finalization_id,issuer_id,issuer_client_id,recipient_id,grant_epoch,disclosure_context_hash,expires_at)
   values(sid,r.id,r.content_hash,e.id,e.finalization_id,actor,client,(p_request->>'recipientId')::uuid,study.grant_epoch,
   private.study_reporting_digest('lca.study-summary-share.v1',jsonb_build_object('exportId',e.id,'recipientId',p_request->>'recipientId','grantEpoch',study.grant_epoch,'nonce',gen_random_uuid())),ts) returning id into newid;
  value:=jsonb_build_object('type','share','value',private.study_review_share_record(newid));
 elsif op='share.revoke' then
  perform private.study_require(private.study_text(p_request->'reason',4096) and p_request->>'reason' !~ '[<>]','INVALID_REQUEST');
  update private.study_report_shares set revoked_at=coalesce(revoked_at,clock_timestamp()),revocation_reason=coalesce(revocation_reason,p_request->>'reason') where id=s.id;
  value:=jsonb_build_object('type','share','value',private.study_review_share_record(s.id));
 end if;
 result:=jsonb_build_object('ok',true,'data',value);
 insert into private.study_command_receipts values(actor,op,'v4:'||sid::text,p_request->>'idempotencyKey',req,result,clock_timestamp());return result;
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
when invalid_text_representation or invalid_parameter_value or numeric_value_out_of_range or check_violation or not_null_violation or invalid_datetime_format then return jsonb_build_object('ok',false,'code','INVALID_REQUEST');
when foreign_key_violation or unique_violation then return jsonb_build_object('ok',false,'code','REFERENCE_MISMATCH');end$$;
-- Persisted command responses are immutable commit observations. Replays retain
-- their original result identity while separately projecting current authority.
create function private.study_review_refresh(p_response jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$declare kind text:=p_response->'data'->>'type';rid uuid;value jsonb;begin
 if kind='review' then
  rid:=(p_response->'data'->'value'->>'reportRevisionId')::uuid;
  return jsonb_set(p_response,'{data,state}',private.study_review_state(rid),true);
 elsif kind='finalization' then
  rid:=(p_response->'data'->'value'->>'reportRevisionId')::uuid;
  return jsonb_set(p_response,'{data,state}',private.study_review_state(rid),true);
 elsif kind='share' then
  value:=private.study_review_share_record((p_response->'data'->'value'->>'shareId')::uuid);
  return jsonb_set(p_response,'{data,value}',value);
 elsif kind='delegation' then
  value:=private.study_delegation_record((p_response->'data'->'value'->>'delegationId')::uuid);
  return jsonb_set(p_response,'{data,value}',value);
 end if;return p_response;
end$$;
create function private.study_review_actions(p_type text,p_id uuid,p_actor uuid,p_client text) returns jsonb
language plpgsql security definer set search_path='' as $$declare r private.study_report_revisions%rowtype;role text;ops jsonb:='[]'::jsonb;st jsonb;s private.study_report_shares%rowtype;begin
 if p_type='share' then
  s:=private.study_review_share_check(p_id,p_actor,p_client,false);ops:='["share.read"]';
  if s.issuer_id=p_actor and private.study_client_allowed(p_client,'STUDY-WRITE-01') then
   begin perform private.study_review_authorize(s.study_id,p_actor,p_client,'manage');ops:=ops||jsonb_build_array('share.revoke');exception when raise_exception then null;end;
  end if;
  begin perform private.study_review_share_check(p_id,p_actor,p_client,true);ops:=ops||jsonb_build_array('share.view','share.download');exception when raise_exception then null;end;return ops;
 elsif p_type='study' then
  role:=private.study_review_authorize(p_id,p_actor,p_client,'read');
  if role='owner' and private.study_client_allowed(p_client,'STUDY-WRITE-01') then ops:=jsonb_build_array('member.set');end if;return ops;
 elsif p_type='export' then
  perform private.study_review_export_check(p_id,p_actor,p_client);return '["export.read","export.download"]'::jsonb;
 end if;
 perform private.study_require(p_type='reportRevision','INVALID_REQUEST');select * into r from private.study_report_revisions where id=p_id;
 role:=private.study_review_authorize(r.study_id,p_actor,p_client,'read');perform private.study_review_disclosure(r.id);
 ops:='["report.current","report.view","comment.list","review.list"]';
 if private.study_client_allowed(p_client,'STUDY-WRITE-01') then
  if role in ('owner','editor','reviewer') then ops:=ops||jsonb_build_array('comment.append');end if;
  if role='reviewer' then ops:=ops||jsonb_build_array('review.record','review.delegation.list');if p_client is null then ops:=ops||jsonb_build_array('review.delegation.issue','review.delegation.revoke');end if;end if;
  if role='owner' then
   ops:=ops||jsonb_build_array('report.finalize','share.list');st:=private.study_review_state(r.id);
   if st->>'acceptance'='current' then
    if (select export_enabled and export_profile is not null from private.study_reporting_config where singleton) and not exists(select 1 from private.study_runs where id in(select jsonb_array_elements_text(r.run_ids)::uuid) and validity<>'current') then ops:=ops||jsonb_build_array('export.request');end if;
    if exists(select 1 from private.study_review_exports e where e.report_id=r.id and e.finalization_id=(st->'finalization'->>'finalizationId')::uuid and e.actor_id=p_actor
     and e.grant_epoch=(select grant_epoch from private.studies where id=r.study_id) and private.study_client_allowed(e.client_id,'STUDY-WRITE-01')) then ops:=ops||jsonb_build_array('share.create');end if;
   end if;
  end if;
 end if;return ops;
exception when raise_exception then return '[]'::jsonb;end$$;
create function api.qry_study_review_v1(p_request jsonb) returns jsonb
language plpgsql security definer set search_path='' set statement_timeout='15s' as $$
declare op text:=p_request->>'operation';actor uuid:=auth.uid();client text:=nullif(auth.jwt()->>'client_id','');allowed text[];rid uuid;r private.study_report_revisions%rowtype;
 s private.study_report_shares%rowtype;e private.study_review_exports%rowtype;value jsonb;ops jsonb;allowed_member_roles jsonb:='[]'::jsonb;core_read boolean:=false;core_write boolean:=false;kind text;lim integer;afterid uuid;nextid uuid;ids uuid[];resource_id uuid;
 selection jsonb;epoch text;cur private.study_cursors%rowtype;items jsonb:='[]'::jsonb;more boolean;
begin
 perform private.study_review_envelope(p_request,false);perform private.study_require(private.study_client_allowed(client,'STUDY-READ-01'),'FORBIDDEN');
 if op='capability.read' then
  perform private.study_require(private.study_keys(p_request,array['schemaVersion','requestId','operation']),'INVALID_REQUEST');
  if not(select enabled from private.study_review_config where singleton) then
   value:=jsonb_build_object('type','capabilities','contractVersion','4.0.0','runtimeEnabled',false,'operations',jsonb_build_array('capability.read'),'finalizationProfiles','[]'::jsonb,'reviewClasses','[]'::jsonb,'disclosurePolicies','[]'::jsonb);
  else
   ops:='["capability.read","resource.actions","comment.list","review.list","review.delegation.list","report.current","report.view","export.read","export.download","share.read","share.view","share.download","share.list"]';
   if private.study_client_allowed(client,'STUDY-WRITE-01') then
    ops:=ops||'["member.set","comment.append","review.record","report.finalize","export.request","share.create","share.revoke"]'::jsonb;
    if client is null then ops:=ops||'["review.delegation.issue","review.delegation.revoke"]'::jsonb;end if;
   end if;
   value:=jsonb_build_object('type','capabilities','contractVersion','4.0.0','runtimeEnabled',true,'operations',ops,
   'finalizationProfiles',jsonb_build_array('lca.study-report-unreviewed.v1','lca.study-report-internal-review.v1'),'reviewClasses',jsonb_build_array('internal'),'disclosurePolicies',jsonb_build_array('lca.study-report-summary-share.v1'));
  end if;return jsonb_build_object('ok',true,'data',value);
 end if;
 perform private.study_require((select enabled from private.study_review_config where singleton),'CAPABILITY_UNAVAILABLE');
 case op
 when 'resource.actions' then
  perform private.study_require(private.study_keys(p_request,array['schemaVersion','requestId','operation','resource']) and private.study_keys(p_request->'resource',array['type','id'])
   and p_request->'resource'->>'type' in ('study','reportRevision','share','export'),'INVALID_REQUEST');
  ops:=private.study_review_actions(p_request->'resource'->>'type',(p_request->'resource'->>'id')::uuid,actor,client);
  if p_request->'resource'->>'type'='study' and ops ? 'member.set' then
   select case when team_id is null then '["reviewer"]'::jsonb else '["editor","reviewer","viewer"]'::jsonb end into allowed_member_roles
    from private.studies where id=(p_request->'resource'->>'id')::uuid;
  end if;
  -- Coarse Study permissions reuse the existing authority. They do not confer
  -- rights to a particular revision, source, target or artifact.
  if p_request->'resource'->>'type'='study' then
   begin
    perform private.study_authorize((p_request->'resource'->>'id')::uuid,actor,client,'read');core_read:=true;
   exception when raise_exception then null;end;
   begin
    perform private.study_authorize((p_request->'resource'->>'id')::uuid,actor,client,'write');
    select status='active' into core_write from private.studies where id=(p_request->'resource'->>'id')::uuid;
   exception when raise_exception then null;end;
  end if;
  return jsonb_build_object('ok',true,'data',jsonb_build_object('type','actions','resource',p_request->'resource','actions',ops,'allowedMemberRoles',allowed_member_roles,
   'corePermissions',jsonb_build_object('read',core_read,'write',coalesce(core_write,false))));
 when 'share.read','share.view','share.download' then
  perform private.study_require(private.study_keys(p_request,array['schemaVersion','requestId','operation','shareId']),'INVALID_REQUEST');
  s:=private.study_review_share_check((p_request->>'shareId')::uuid,actor,client,op<>'share.read');
  if op='share.read' then value:=jsonb_build_object('type','share','value',private.study_review_share_record(s.id));else return private.study_review_new_intent(p_request,s.report_id,s.id);end if;
  return jsonb_build_object('ok',true,'data',value);
 when 'export.read','export.download' then
  perform private.study_require(private.study_keys(p_request,array['schemaVersion','requestId','operation','exportId']),'INVALID_REQUEST');
  e:=private.study_review_export_check((p_request->>'exportId')::uuid,actor,client);
  if op='export.download' then return private.study_review_new_intent(p_request,e.report_id,null,e.id);end if;
  return jsonb_build_object('ok',true,'data',jsonb_build_object('type','export','value',e.record));
 when 'report.current','report.view' then allowed:=array['reportRevisionId','expectedContentHash'];
 when 'comment.list','review.list','review.delegation.list','share.list' then allowed:=array['reportRevisionId','expectedContentHash','cursor','limit'];
 else perform private.study_require(false,'CAPABILITY_UNAVAILABLE');end case;
 perform private.study_require(private.study_keys(p_request,allowed||array['schemaVersion','requestId','operation']),'INVALID_REQUEST');
 rid:=(p_request->>'reportRevisionId')::uuid;select * into r from private.study_report_revisions where study_report_revisions.id=rid;
 perform private.study_review_authorize(r.study_id,actor,client,case when op='share.list' then 'manage' when op='review.delegation.list' then 'review' else 'read' end);
 perform private.study_require(r.status='frozen' and r.content_hash=p_request->>'expectedContentHash','REFERENCE_MISMATCH');perform private.study_review_disclosure(r.id);
 if op='report.current' then return jsonb_build_object('ok',true,'data',jsonb_build_object('type','reportState','value',private.study_review_state(r.id)));end if;
 if op='report.view' then return private.study_review_new_intent(p_request,r.id);end if;
 perform private.study_require(jsonb_typeof(p_request->'limit')='number' and (p_request->>'limit')::numeric between 1 and 100 and (p_request->>'limit')::numeric=trunc((p_request->>'limit')::numeric),'INVALID_REQUEST');lim:=(p_request->>'limit')::integer;
 selection:=p_request-'requestId'-'cursor';epoch:=private.study_access_epoch(actor,r.study_id);
 if p_request->'cursor'<>'null'::jsonb then
  select * into cur from private.study_cursors where study_cursors.id=(p_request->>'cursor')::uuid;
  perform private.study_require(found and cur.actor_id=actor and cur.client_id is not distinct from client and cur.selection=selection and cur.access_epoch=epoch and cur.expires_at>clock_timestamp(),'INVALID_REQUEST');afterid:=cur.after_id;
 end if;
 kind:=case op when 'comment.list' then 'comment' when 'review.list' then 'review' when 'review.delegation.list' then 'delegation' else 'share' end;
 select array_agg(x.id order by x.id) into ids from(
  select c.id from private.study_report_comments c where kind='comment' and c.report_id=r.id and(afterid is null or c.id>afterid)
  union all select c.id from private.study_report_reviews c where kind='review' and c.report_id=r.id and(afterid is null or c.id>afterid)
  union all select c.id from private.study_review_delegations c where kind='delegation' and c.report_id=r.id and c.actor_id=actor and(afterid is null or c.id>afterid)
  union all select c.id from private.study_report_shares c where kind='share' and c.report_id=r.id and c.issuer_id=actor and(afterid is null or c.id>afterid)
  order by id limit lim+1)x;
 more:=coalesce(cardinality(ids)>lim,false);
 foreach resource_id in array coalesce(ids[1:lim],'{}') loop
  items:=items||jsonb_build_array(case kind when 'comment' then private.study_comment_record(resource_id) when 'review' then private.study_review_record(resource_id) when 'delegation' then private.study_delegation_record(resource_id) else private.study_review_share_record(resource_id) end);
 end loop;
 if more then insert into private.study_cursors(actor_id,client_id,selection,access_epoch,after_id) values(actor,client,selection,epoch,ids[lim]) returning study_cursors.id into nextid;end if;
 value:=jsonb_build_object('type','history','studyId',r.study_id,'reportRevisionId',r.id,'reportContentHash',r.content_hash,'kind',kind,'items',items,'nextCursor',nextid);
 return jsonb_build_object('ok',true,'data',value);
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
when invalid_text_representation or invalid_parameter_value or numeric_value_out_of_range then return jsonb_build_object('ok',false,'code','INVALID_REQUEST');end$$;
create function api.svc_study_review_intent_consume_v1(p_intent_id uuid,p_completion jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$declare i private.study_review_intents%rowtype;r private.study_report_revisions%rowtype;f jsonb;manifest jsonb;receipt jsonb;profile jsonb;record jsonb;result jsonb;projection uuid;resources uuid;bundle uuid;begin
 perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');i:=private.study_review_intent_check(p_intent_id);
 select * into i from private.study_review_intents where id=p_intent_id for update;
 if i.response is not null then return i.response;end if;
 perform private.study_require(i.operation='export.request','INVALID_REQUEST');select * into r from private.study_report_revisions where id=i.report_id;
 f:=private.study_finalization_record(i.finalization_id);
 select export_profile into profile from private.study_reporting_config where singleton;
 perform private.study_require(private.study_keys(p_completion,array['kind','projectionArtifact','resourcesArtifact','bundleArtifact','manifest','receipt']) and p_completion->>'kind'='validatedReviewExport','REFERENCE_MISMATCH');
 manifest:=p_completion->'manifest';receipt:=p_completion->'receipt';
 perform private.study_require(private.study_keys(manifest,array['schemaVersion','issuerId','exportId','studyId','reportRevisionId','reportContentHash','actorId','clientId','grantEpoch','policyId','disclosureContextHash','generatedAt','validitySnapshot','reviewIds','finalization','renderer','files'])
  and manifest->>'schemaVersion'='lca.study-export-manifest.v2' and manifest->>'issuerId'=profile->>'issuerId' and manifest->>'exportId'=i.export_id::text
  and manifest->>'studyId'=i.study_id::text and manifest->>'reportRevisionId'=r.id::text and manifest->>'reportContentHash'=r.content_hash
  and manifest->>'actorId'=i.actor_id::text and (manifest->>'clientId') is not distinct from i.client_id
  and jsonb_typeof(manifest->'grantEpoch')='number' and (manifest->>'grantEpoch')::numeric=i.grant_epoch
  and manifest->>'policyId'='lca.study-report-disclosure.v1' and manifest->>'disclosureContextHash'=i.disclosure_context_hash
  and (manifest->>'generatedAt')::timestamptz=i.created_at and manifest->'validitySnapshot'=private.study_report_record(r.id)->'validitySnapshot'
  and manifest->'finalization'=f and manifest->'reviewIds'=f->'acceptedReviewIds' and (f->>'finalizedAt')::timestamptz<=i.created_at
  and manifest->'renderer'=jsonb_build_object('version','1.0.0','viewModelVersion','lca.study-report-view.v1','artifactHash',profile->>'rendererArtifactHash'),'REFERENCE_MISMATCH');
 perform private.study_require(jsonb_typeof(manifest->'files')='array' and jsonb_array_length(manifest->'files')=2
  and private.study_keys(manifest->'files'->0,array['path','mediaType','sha256','byteSize']) and private.study_keys(manifest->'files'->1,array['path','mediaType','sha256','byteSize'])
  and manifest->'files'->0->>'path'='report.html' and manifest->'files'->0->>'mediaType'='text/html' and manifest->'files'->0->>'sha256' ~ '^[0-9a-f]{64}$'
  and manifest->'files'->1->>'path'='projection.json' and manifest->'files'->1->>'mediaType'='application/json'
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
 resources:=private.study_report_store_produced(i.study_id,p_completion->'resourcesArtifact',i.resources_artifact_id,'renderResources','lca.study-export-manifest.v2','resources');
 bundle:=private.study_report_store_produced(i.study_id,p_completion->'bundleArtifact',i.bundle_artifact_id,'reportExportBundle','lca.study-export-bundle.v2','bundle');
 record:=jsonb_build_object('studyId',i.study_id,'reportRevisionId',r.id,'reportContentHash',r.content_hash,'exportId',i.export_id,'finalization',f,'generatedAt',i.created_at,
  'projectionRef',p_completion->'projectionArtifact'->'artifactRef','resourcesRef',p_completion->'resourcesArtifact'->'artifactRef','bundleRef',p_completion->'bundleArtifact'->'artifactRef','receipt',receipt);
 insert into private.study_review_exports(id,study_id,report_id,actor_id,client_id,grant_epoch,finalization_id,record,manifest,projection_artifact_id,resources_artifact_id,bundle_artifact_id)
  values(i.export_id,i.study_id,r.id,i.actor_id,i.client_id,i.grant_epoch,i.finalization_id,record,manifest,projection,resources,bundle);
 result:=jsonb_build_object('ok',true,'data',jsonb_build_object('type','export','value',record));update private.study_review_intents set response=result where id=i.id;
 update private.study_command_receipts set response=result where actor_id=i.actor_id and operation=i.operation and scope='v4:'||i.study_id::text and idempotency_key=i.request->>'idempotencyKey';return result;
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
when invalid_text_representation or invalid_parameter_value or numeric_value_out_of_range or check_violation or not_null_violation or invalid_datetime_format then return jsonb_build_object('ok',false,'code','INVALID_REQUEST');
when foreign_key_violation or unique_violation then return jsonb_build_object('ok',false,'code','REFERENCE_MISMATCH');end$$;
-- Every durable decision/finalization/export is append-only. Consumption and
-- revoke pointers are separate mutable authority; no frozen report is rewritten.
create function private.study_review_immutable() returns trigger language plpgsql set search_path='' as $$begin raise exception 'FROZEN_REVISION';end$$;
create trigger study_comment_immutable before update or delete on private.study_report_comments for each row execute function private.study_review_immutable();
create trigger study_review_immutable before update or delete on private.study_report_reviews for each row execute function private.study_review_immutable();
create trigger study_finalization_immutable before update or delete on private.study_report_finalizations for each row execute function private.study_review_immutable();
create trigger study_v4_export_immutable before update or delete on private.study_review_exports for each row execute function private.study_review_immutable();
do $$declare n text;f record;begin
 foreach n in array array['study_review_config','study_report_comments','study_review_delegations','study_report_reviews','study_report_review_heads','study_report_finalizations','study_review_exports','study_report_shares','study_review_intents'] loop
  execute format('alter table private.%I enable row level security',n);execute format('alter table private.%I force row level security',n);
  execute format('revoke all on private.%I from public,anon,authenticated,service_role',n);
 end loop;
 for f in select p.oid,p.oid::regprocedure::text identity,p.proname,n.nspname,pg_catalog.oidvectortypes(p.proargtypes) args from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname in ('api','private') and (p.proname like 'study_review_%' or p.proname in ('study_comment_record','study_delegation_record','study_finalization_record','cmd_study_review_v1','qry_study_review_v1','svc_study_review_configure_v1','svc_study_review_intent_resolve_v1','svc_study_review_intent_consume_v1')) loop
  execute format('revoke all on function %s from public,anon,authenticated,service_role',f.identity);
  if f.nspname='api' then
   execute format('grant execute on function %s to %I',f.identity,case when f.proname like 'svc_%' then 'service_role' else 'authenticated' end);
   insert into private.api_capability_grants(routine_identity,capability_id,allow_anon,allow_authenticated,allow_service_role)
    values(format('api.%I(%s)',f.proname,f.args),case when f.proname like 'svc_%' then 'STUDY-SERVICE-01' when f.proname like 'cmd_%' then 'STUDY-WRITE-01' else 'STUDY-READ-01' end,false,f.proname not like 'svc_%',f.proname like 'svc_%');
  end if;
 end loop;
end$$;
notify pgrst,'reload schema';
commit;
