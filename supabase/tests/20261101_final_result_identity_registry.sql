begin;
create extension if not exists pgtap with schema extensions;
set local search_path=extensions,public,api,private,auth;
select no_plan();
create function pg_temp.identity_request() returns jsonb language sql immutable as $$ select '{"schemaVersion":"tiangong.final-result-identity-request.v1","result":{"uuid":"87900000-0000-4000-8000-000000000001","version":"01.00.000"},"producer":"release-workflows","contentHash":"c185a7decb82b134a6b1c2b89f7f5f45df5bba2ff5f20e995591660c98e59efc","hashDomain":"tiangong.final-result-content.jcs.v1","canonicalContentHash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","semanticDependencies":[{"key":"flow:87900000-0000-4000-8000-000000000002@01.00.000","contentHash":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}]}'::jsonb $$;
create function pg_temp.changed_request() returns jsonb language sql immutable as $$ select '{"schemaVersion":"tiangong.final-result-identity-request.v1","result":{"uuid":"87900000-0000-4000-8000-000000000001","version":"01.00.000"},"producer":"release-workflows","contentHash":"9f3f46193ccfd645f9a800a9b1894e1b216b184b33c1d97ee4772dcf2b731d5c","hashDomain":"tiangong.final-result-content.jcs.v1","canonicalContentHash":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","semanticDependencies":[{"key":"flow:87900000-0000-4000-8000-000000000002@01.00.000","contentHash":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}]}'::jsonb $$;

grant execute on function pg_temp.identity_request(),pg_temp.changed_request() to service_role;

select ok(not has_table_privilege('service_role','private.final_result_identities','insert') and not has_table_privilege('authenticated','private.final_result_identities','select'),'raw identity registry remains closed');
select ok((select relrowsecurity from pg_class where oid='private.final_result_identities'::regclass),'identity registry has RLS');
select ok(has_function_privilege('service_role','api.svc_result_identity_register(jsonb)','execute') and not has_function_privilege('authenticated','api.svc_result_identity_register(jsonb)','execute') and not has_function_privilege('anon','api.svc_result_identity_versions(uuid,text,integer)','execute'),'identity RPCs are service-only');

select is((select count(*) from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace
  where t.tgname='final_result_identity_guard' and t.tgfoid='private.final_result_legacy_write_guard()'::regprocedure
    and t.tgtype=29 and t.tgenabled='O' and not t.tgdeferrable and t.tgattr=''::int2vector
    and (n.nspname,c.relname) in (('public','processes'),('private','lca_release_dataset_versions'),('private','result_process_publications'))),
  3::bigint,'all legacy producer surfaces use enabled AFTER row guards for insert/update/delete');
select ok(not has_function_privilege('service_role','private.final_result_legacy_claim(uuid,text)','execute')
  and not has_function_privilege('authenticated','private.final_result_legacy_write_guard()','execute'),
  'legacy claim helpers are owner-only');

-- Synthetic secrets exist only inside this rollback-only fixture. Webhook
-- jobs are transactional and never become visible to the network worker.
do $$ begin
  if not exists(select 1 from vault.secrets where name='project_secret_key') then
    perform vault.create_secret('test-only-invalid-service-key','project_secret_key');
  end if;
  if not exists(select 1 from vault.secrets where name='project_url') then
    perform vault.create_secret('http://127.0.0.1:1','project_url');
  end if;
end $$;

set local role service_role;
create temporary table registered as select api.svc_result_identity_register(pg_temp.identity_request()) as receipt;
select is((select receipt#>>'{data,contentHash}' from registered),pg_temp.identity_request()->>'contentHash','database JCS envelope matches independently generated golden digest');
select is(api.svc_result_identity_register(pg_temp.identity_request()),(select receipt from registered),'same identity and content reuses original receipt');
select is(api.svc_result_identity_register(jsonb_set(pg_temp.identity_request(),'{producer}','"another-producer"')),(select receipt from registered),'another producer cannot create a second identity namespace');
select throws_ok($q$select api.svc_result_identity_register(pg_temp.changed_request())$q$,'23505','Final Result identity is already bound to different content','same UUID/version different content is rejected');
select throws_ok($q$select api.svc_result_identity_register(jsonb_set(pg_temp.identity_request(),'{hashDomain}','"legacy.v1"'))$q$,'22023','Invalid final Result identity request','hash domains are never silently reinterpreted');
select throws_ok($q$select api.svc_result_identity_register(jsonb_set(pg_temp.identity_request(),'{contentHash}',to_jsonb(repeat('f',64))))$q$,'22023','Final Result content envelope hash mismatch','claimed envelope digest is independently checked');
select throws_ok($q$select api.svc_result_identity_register(jsonb_set(pg_temp.identity_request(),'{semanticDependencies}',jsonb_build_array(pg_temp.identity_request()#>'{semanticDependencies,0}',pg_temp.identity_request()#>'{semanticDependencies,0}')))$q$,'22023','Final Result dependencies must be unique and canonically ordered','duplicate dependency identities are rejected');
select throws_ok($q$select api.svc_result_identity_register('{}')$q$,'22023','Invalid final Result identity request','partial metadata cannot reserve identity');
select throws_ok($q$select api.svc_result_identity_versions('87900000-0000-4000-8000-000000000001',null,257)$q$,'22023','Invalid final Result version lookup','version lookup is bounded');
select is(api.svc_result_identity_versions('87900000-0000-4000-8000-000000000001')#>>'{data,versions,0,status}','registered','authoritative lookup reports a registered exact version');
select is(jsonb_array_length(api.svc_result_identity_versions('87900000-0000-4000-8000-000000000001','01.00.000')#>'{data,versions}'),0,'version cursor excludes the exact boundary');
reset role;
select throws_ok($q$update private.final_result_identities set content_hash=repeat('f',64)$q$,'55000','Result query evidence is immutable','registered content cannot be overwritten');
select throws_ok($q$delete from private.final_result_identities$q$,'55000','Result query evidence is immutable','failed or retired publications cannot free a claimed version');
select throws_ok($q$insert into public.processes(id,version,json_ordered) values('87900000-0000-4000-8000-000000000001','01.00.000','{"processDataSet":{"administrativeInformation":{"publicationAndOwnership":{"common:dataSetVersion":"01.00.000"}}}}')$q$,'23505','Final Result identity is registered; legacy writes require explicit equivalence migration','legacy authoring/import cannot occupy a registered identity');
select throws_ok($q$insert into public.processes(id,version,json_ordered) values('87900000-0000-4000-8000-000000000001','02.00.000','{"processDataSet":{"administrativeInformation":{"publicationAndOwnership":{"common:dataSetVersion":"01.00.000"}}}}')$q$,'23505','Final Result identity is registered; legacy writes require explicit equivalence migration','final normalized version cannot bypass the identity fence');
insert into public.processes(id,version,json_ordered) values('87900000-0000-4000-8000-000000000003','01.00.000','{"processDataSet":{"administrativeInformation":{"publicationAndOwnership":{"common:dataSetVersion":"01.00.000"}}}}');
set local role service_role;
select throws_ok($q$select api.svc_result_identity_register(jsonb_set(pg_temp.identity_request(),'{result,uuid}','"87900000-0000-4000-8000-000000000003"'))$q$,'55000','Legacy Result identity is occupied; explicit equivalence migration or a new version is required','legacy identity cannot be treated as empty without equivalent content evidence');
select is(api.svc_result_identity_versions('87900000-0000-4000-8000-000000000003')#>>'{data,versions,0,status}','legacy_requires_equivalence','legacy occupancy participates in version planning');
reset role;
select is((select count(*) from private.final_result_identities where result_id::text like '87900000%' and registration_kind='registered'),1::bigint,'rejected requests do not reserve extra identities');
select is((select count(*) from public.processes where id='87900000-0000-4000-8000-000000000001'),0::bigint,'registration stores no state-120 authoring row');
select * from finish();
rollback;
