begin;
create extension if not exists pgtap with schema extensions;
set local search_path=extensions,public,api,private,auth;
select no_plan();
create temp table upgraded_rows as
select 'contacts'::text table_name,to_jsonb(c) row_data from public.contacts c where id in ('85510000-0000-4000-8000-000000000101','85510000-0000-4000-8000-000000000105')
union all select 'sources',to_jsonb(s) from public.sources s where id='85510000-0000-4000-8000-000000000102'
union all select 'processes',to_jsonb(p) from public.processes p where id='85510000-0000-4000-8000-000000000103'
union all select 'flows',to_jsonb(f) from public.flows f where id='85510000-0000-4000-8000-000000000104';
select is((select jsonb_agg(to_jsonb(x) order by table_name,row_data->>'id',row_data->>'version') from upgraded_rows x),
 (select jsonb_agg(to_jsonb(x) order by table_name,row_data->>'id',row_data->>'version') from private.stable_draft_855_upgrade_evidence x),
 'additive migration preserves whole historical rows, duplicates and mixed groups');
select is((select count(*) from public.contacts where id='85510000-0000-4000-8000-000000000101' and state_code=0),2::bigint,
 'historical owner duplicate set remains intact');
select is((select count(*) from public.sources where id='85510000-0000-4000-8000-000000000102' and state_code=0),2::bigint,
 'never-published historical draft family is not assigned a fictitious publication');
select set_config('request.jwt.claim.sub','85510000-0000-4000-8000-000000000001',true);
create temp table upgrade_requests(name text primary key,request jsonb,response jsonb);
insert into upgrade_requests(name,request)
select 'many',jsonb_build_object('table','contacts','id','85510000-0000-4000-8000-000000000101',
 'expectedActorId','85510000-0000-4000-8000-000000000001','expectedDrafts',
 (select jsonb_agg(jsonb_build_object('version',version,'jsonOrdered',json_ordered::jsonb) order by version) from public.contacts where id='85510000-0000-4000-8000-000000000101' and state_code=0),
 'source',jsonb_build_object('version',c.version,'userId',c.user_id,'stateCode',c.state_code,'jsonOrdered',c.json_ordered::jsonb))
from public.contacts c where id='85510000-0000-4000-8000-000000000101' and version='01.00.000';
insert into upgrade_requests(name,request)
select 'mixed',jsonb_build_object('table','processes','id','85510000-0000-4000-8000-000000000103',
 'expectedActorId','85510000-0000-4000-8000-000000000001','expectedDrafts',
 (select jsonb_agg(jsonb_build_object('version',version,'jsonOrdered',json_ordered::jsonb) order by version) from public.processes where id='85510000-0000-4000-8000-000000000103' and state_code=0),
 'source',jsonb_build_object('version',p.version,'userId',p.user_id,'stateCode',p.state_code,'jsonOrdered',p.json_ordered::jsonb))
from public.processes p where id='85510000-0000-4000-8000-000000000103' and version='01.00.000';
insert into upgrade_requests(name,request)
select 'flow-mixed',jsonb_build_object('table','flows','id','85510000-0000-4000-8000-000000000104',
 'expectedActorId','85510000-0000-4000-8000-000000000001','expectedDrafts',
 (select jsonb_agg(jsonb_build_object('version',version,'jsonOrdered',json_ordered::jsonb) order by version) from public.flows where id='85510000-0000-4000-8000-000000000104' and state_code=0),
 'source',jsonb_build_object('version',f.version,'userId',f.user_id,'stateCode',f.state_code,'jsonOrdered',f.json_ordered::jsonb))
from public.flows f where id='85510000-0000-4000-8000-000000000104' and version='01.00.000';
insert into upgrade_requests(name,request)
select 'review',jsonb_build_object('table','contacts','id','85510000-0000-4000-8000-000000000105',
 'expectedActorId','85510000-0000-4000-8000-000000000001','expectedDrafts','[]'::jsonb,
 'source',jsonb_build_object('version',c.version,'userId',c.user_id,'stateCode',c.state_code,'jsonOrdered',c.json_ordered::jsonb))
from public.contacts c where id='85510000-0000-4000-8000-000000000105' and version='01.00.000';
grant select,update on upgrade_requests to authenticated;
set local role authenticated;
update upgrade_requests set response=api.cmd_dataset_prepare_stable_draft('85510000-0000-4000-8000-000000001001',request) where name='many';
select is((select response->>'code' from upgrade_requests where name='many'),'DATASET_DRAFT_CONFLICT','many drafts returns an explicit conflict');
select is((select response#>'{details,draftVersions}' from upgrade_requests where name='many'),'["01.00.001","01.00.002"]'::jsonb,
 'conflict contains the complete ordered draft identity set');
select is((select response#>'{details,drafts}' from upgrade_requests where name='many'),
 (select request->'expectedDrafts' from upgrade_requests where name='many'),
 'conflict includes the full eligible before-content set');
update upgrade_requests set response=api.cmd_dataset_prepare_stable_draft('85510000-0000-4000-8000-000000001002',
 request||'{"selectedVersion":"01.00.001"}'::jsonb) where name='many';
select is((select response#>>'{data,outcome}' from upgrade_requests where name='many'),'selected','reviewed explicit selection is distinct from ordinary reuse');
select is((select response#>>'{data,version}' from upgrade_requests where name='many'),'01.00.001','explicit selection retains the fixed reviewed version');
select is((select count(*) from public.contacts where id='85510000-0000-4000-8000-000000000101' and state_code=0 and rule_verification is true),2::bigint,
 'explicit selection leaves both historical draft verification flags untouched');
select is(api.cmd_dataset_prepare_stable_draft('85510000-0000-4000-8000-000000001003',
 (select jsonb_set(request,'{expectedDrafts}',jsonb_build_array(request#>'{expectedDrafts,0}'))||'{"selectedVersion":"01.00.001"}'::jsonb from upgrade_requests where name='many'))->>'code',
 'DATASET_DRAFT_CENSUS_CHANGED','selected version cannot hide a sibling from the complete expected set');
select is(api.cmd_dataset_prepare_stable_draft('85510000-0000-4000-8000-000000001004',
 (select request||'{"selectedVersion":"01.00.009"}'::jsonb from upgrade_requests where name='many'))->>'code',
 'DATASET_DRAFT_SELECTION_INVALID','selection outside the actual conflict set fails closed');
select is(api.cmd_dataset_prepare_stable_draft('85510000-0000-4000-8000-000000001005',
 (select request from upgrade_requests where name='mixed'))->>'code','LIFECYCLEMODEL_BUNDLE_REQUIRED','historical mixed model-bound family is not claimed as supported');
select is(api.cmd_dataset_prepare_stable_draft('85510000-0000-4000-8000-000000001006',
 (select request from upgrade_requests where name='flow-mixed'))#>'{details,draftVersions}','["01.00.001","01.00.002"]'::jsonb,
 'Flow conflicts retain the unselected Elementary sibling in the complete set');
select is(api.cmd_dataset_prepare_stable_draft('85510000-0000-4000-8000-000000001007',
 (select request||'{"selectedVersion":"01.00.001"}' from upgrade_requests where name='flow-mixed'))#>>'{data,outcome}','selected',
 'reviewed Product draft can be explicitly selected without touching its Elementary sibling');
select is(api.cmd_dataset_prepare_stable_draft('85510000-0000-4000-8000-000000001008',
 (select request||'{"selectedVersion":"01.00.002"}' from upgrade_requests where name='flow-mixed'))->>'code','DATASET_REFERENCE_ONLY',
 'Elementary sibling cannot itself become the selected generic draft');
select is(api.cmd_dataset_prepare_stable_draft('85510000-0000-4000-8000-000000001009',
 (select request from upgrade_requests where name='review'))->>'code','DATASET_REVIEW_IN_PROGRESS',
 'pre-existing review blocks creation after additive upgrade');
select is(api.cmd_dataset_create('contacts','85510000-0000-4000-8000-000000000101',
 '{"contactDataSet":{"administrativeInformation":{"publicationAndOwnership":{"common:dataSetVersion":"01.00.003"}}}}')->>'message',
 'DATASET_DRAFT_CONFLICT','historical duplicates cannot grow through legacy create');
select is(api.cmd_dataset_save_draft_guarded('contacts','85510000-0000-4000-8000-000000000101','01.00.001',
 (select request#>'{expectedDrafts,0,jsonOrdered}' from upgrade_requests where name='many'),
 (select request#>'{expectedDrafts,0,jsonOrdered}' from upgrade_requests where name='many'))->>'ok','true',
 'existing exact-row guarded saves are not silently changed into consolidation');
reset role;
select is((select count(*) from private.command_audit_log where command='cmd_dataset_create_version' and target_id='85510000-0000-4000-8000-000000000101'),0::bigint,
 'explicit selection and every conflict dispatch zero version creates');
select is((select count(*) from public.contacts where id='85510000-0000-4000-8000-000000000101'),3::bigint,
 'no hidden creation or deletion occurred');
select is((select jsonb_agg(to_jsonb(f) order by version) from public.flows f where id='85510000-0000-4000-8000-000000000104'),
 (select jsonb_agg(row_data order by row_data->>'version') from private.stable_draft_855_upgrade_evidence where table_name='flows'),
 'explicit Product selection leaves every Product/Elementary sibling byte-value unchanged');
select is((select count(*) from public.contacts where id='85510000-0000-4000-8000-000000000105' and state_code=0),0::bigint,
 'historical in-progress review cannot acquire a post-upgrade draft');
select * from finish();
rollback;
