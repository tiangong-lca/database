-- Five task-authored TIDAS documents. Actual source authority is determined
-- from these real rows; no caller state/owner claims are used by the resolver.
insert into auth.users(id,instance_id,aud,role,email,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
select ('89500000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','study895-'||i||'@invalid.test','{}','{}',now(),now() from generate_series(1,2)i;
insert into private.users(id,raw_user_meta_data,contact)
select ('89500000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,'{}',null from generate_series(1,2)i on conflict(id) do nothing;
create temp table study895_sources(kind text,id uuid,body jsonb);
insert into study895_sources values
('lifecyclemodel','89500000-0000-4000-8000-000000000101','{"lifeCycleModelDataSet":{"lifeCycleModelInformation":{"dataSetInformation":{"common:UUID":"89500000-0000-4000-8000-000000000101"},"quantitativeReference":{"referenceToReferenceProcess":"i"},"technology":{"processes":{"processInstance":{"@dataSetInternalID":"i","referenceToProcess":{"@refObjectId":"89500000-0000-4000-8000-000000000102","@version":"01.00.000"}}}}},"administrativeInformation":{"publicationAndOwnership":{"common:dataSetVersion":"01.00.000"}}}}'),
('process','89500000-0000-4000-8000-000000000102','{"processDataSet":{"processInformation":{"dataSetInformation":{"common:UUID":"89500000-0000-4000-8000-000000000102"},"quantitativeReference":{"referenceToReferenceFlow":"p"}},"administrativeInformation":{"publicationAndOwnership":{"common:dataSetVersion":"01.00.000"}},"exchanges":{"exchange":{"@dataSetInternalID":"p","exchangeDirection":"Output","meanAmount":"1","referenceToFlowDataSet":{"@refObjectId":"89500000-0000-4000-8000-000000000103","@version":"01.00.000"}}}}}'),
('flow','89500000-0000-4000-8000-000000000103','{"flowDataSet":{"flowInformation":{"dataSetInformation":{"common:UUID":"89500000-0000-4000-8000-000000000103"},"quantitativeReference":{"referenceToReferenceFlowProperty":"0"}},"administrativeInformation":{"publicationAndOwnership":{"common:dataSetVersion":"01.00.000"}},"flowProperties":{"flowProperty":{"@dataSetInternalID":"0","meanValue":"1","referenceToFlowPropertyDataSet":{"@refObjectId":"89500000-0000-4000-8000-000000000104","@version":"01.00.000"}}},"modellingAndValidation":{"LCIMethod":{"typeOfDataSet":"Product flow"}}}}'),
('flowproperty','89500000-0000-4000-8000-000000000104','{"flowPropertyDataSet":{"flowPropertiesInformation":{"dataSetInformation":{"common:UUID":"89500000-0000-4000-8000-000000000104"},"quantitativeReference":{"referenceToReferenceUnitGroup":{"@refObjectId":"89500000-0000-4000-8000-000000000105","@version":"01.00.000"}}},"administrativeInformation":{"publicationAndOwnership":{"common:dataSetVersion":"01.00.000"}}}}'),
('unitgroup','89500000-0000-4000-8000-000000000105','{"unitGroupDataSet":{"unitGroupInformation":{"dataSetInformation":{"common:UUID":"89500000-0000-4000-8000-000000000105"},"quantitativeReference":{"referenceToReferenceUnit":"0"}},"administrativeInformation":{"publicationAndOwnership":{"common:dataSetVersion":"01.00.000"}},"units":{"unit":{"@dataSetInternalID":"0","name":"kg","meanValue":"1"}}}}');
do $$ declare d record; t text; begin
  for d in select * from study895_sources loop
    t:=case d.kind when 'lifecyclemodel' then 'lifecyclemodels' when 'process' then 'processes' when 'flow' then 'flows' when 'flowproperty' then 'flowproperties' else 'unitgroups' end;
    execute format('insert into public.%I(id,version,state_code,user_id,json_ordered,json) values($1,''01.00.000'',$2,''89500000-0000-4000-8000-000000000001'',$3::json,$3)',t)
      using d.id,case when d.kind='lifecyclemodel' then 0 else 100 end,d.body;
  end loop;
end $$;
create function pg_temp.study895_claim(p_actor integer default 1,p_service boolean default false,p_client text default null) returns void language plpgsql as $$ begin
 perform set_config('request.jwt.claim.sub','',true);perform set_config('request.jwt.claim.role','',true);
 perform set_config('request.jwt.claims',jsonb_strip_nulls(jsonb_build_object('role',case when p_service then 'service_role' else 'authenticated' end,'sub',case when p_actor is null then null else '89500000-0000-4000-8000-'||lpad(p_actor::text,12,'0') end,'client_id',p_client))::text,true);
end $$;
create function pg_temp.study895_request(p_operation text,p_fields jsonb,p_key text default null) returns jsonb language sql as $$
select jsonb_build_object('schemaVersion','lca.study-api.v2','requestId',gen_random_uuid(),'operation',p_operation)||case when p_key is null then '{}'::jsonb else jsonb_build_object('idempotencyKey',p_key) end||p_fields
$$;
