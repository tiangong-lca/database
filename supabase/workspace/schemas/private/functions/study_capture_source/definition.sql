CREATE OR REPLACE FUNCTION "private"."study_capture_source"("p_origin" "jsonb", "p_actor" "uuid", "p_client" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare queue jsonb:=jsonb_build_array(jsonb_build_object('kind','lifecyclemodel','id',p_origin->>'id','version',p_origin->>'version'));
  seen text[]:='{}'; item jsonb; doc jsonb; data jsonb; x jsonb; selected jsonb; docs jsonb:='[]'; scope jsonb; key text; pivot text; count_items integer; root_key text; size_bytes bigint:=0;
begin
  perform private.study_require(private.study_keys(p_origin,array['type','datasetType','id','version']) and p_origin->>'type'='datasetRevision'
    and p_origin->>'datasetType'='lifecyclemodel','REFERENCE_MISMATCH');
  while jsonb_array_length(queue)>0 loop
    item:=queue->0; queue:=queue-0; key:=(item->>'kind')||':'||(item->>'id')||':'||(item->>'version');
    if key=any(seen) then continue; end if;
    perform private.study_require(cardinality(seen)<512,'CAPABILITY_UNAVAILABLE'); seen:=seen||key;
    doc:=private.study_source_document(item->>'kind',item->>'id',item->>'version',p_actor,p_client);
    size_bytes:=size_bytes+octet_length(doc->>'json'); perform private.study_require(size_bytes<=4194304,'CAPABILITY_UNAVAILABLE');
    docs:=docs||jsonb_build_array(doc); data:=(doc->>'json')::jsonb;
    case item->>'kind'
    when 'lifecyclemodel' then
      select count(*) into count_items from private.study_source_items(data#>'{lifeCycleModelDataSet,lifeCycleModelInformation,technology,processes,processInstance}');
      perform private.study_require(count_items between 1 and 64,'CAPABILITY_UNAVAILABLE');
      for x in select * from private.study_source_items(data#>'{lifeCycleModelDataSet,lifeCycleModelInformation,technology,processes,processInstance}') loop
        queue:=queue||jsonb_build_array(private.study_source_ref('process',x->'referenceToProcess'));
      end loop;
    when 'process' then
      for x in select * from private.study_source_items(data#>'{processDataSet,exchanges,exchange}') loop
        queue:=queue||jsonb_build_array(private.study_source_ref('flow',x->'referenceToFlowDataSet'));
      end loop;
    when 'flow' then
      pivot:=data#>>'{flowDataSet,flowInformation,quantitativeReference,referenceToReferenceFlowProperty}';
      select count(*),jsonb_agg(v) into count_items,selected from private.study_source_items(data#>'{flowDataSet,flowProperties,flowProperty}')v where v->>'@dataSetInternalID'=pivot;
      perform private.study_require(count_items=1,'REFERENCE_MISMATCH');
      queue:=queue||jsonb_build_array(private.study_source_ref('flowproperty',selected->0->'referenceToFlowPropertyDataSet'));
    when 'flowproperty' then
      queue:=queue||jsonb_build_array(private.study_source_ref('unitgroup',data#>'{flowPropertyDataSet,flowPropertiesInformation,quantitativeReference,referenceToReferenceUnitGroup}'));
    when 'unitgroup' then null;
    end case;
    perform private.study_require(jsonb_array_length(queue)<=8192,'CAPABILITY_UNAVAILABLE');
  end loop;
  select jsonb_agg(v order by v->>'kind',v->'identity'->>'id',v->'identity'->>'version') into docs from jsonb_array_elements(docs)v;
  select jsonb_agg((v-'json')||jsonb_build_object('id',v->'identity'->>'id','version',v->'identity'->>'version',
    'sourceEncoding','postgresql.json-text.utf8.v1','licenseEvidence',coalesce((v->>'json')::jsonb#>array[case v->>'kind' when 'lifecyclemodel' then 'lifeCycleModelDataSet' when 'process' then 'processDataSet' when 'flow' then 'flowDataSet' when 'flowproperty' then 'flowPropertyDataSet' when 'unitgroup' then 'unitGroupDataSet' end,'administrativeInformation','publicationAndOwnership'],'{}'::jsonb)))
    into scope from jsonb_array_elements(docs)v;
  return jsonb_build_object('schemaVersion','lca.study-source-snapshot.v1','originRef',p_origin,'licenseRef','study-source-access.actor-data-rights.v1',
    'issuerId','database.study-source.v1','observedAt',clock_timestamp(),'sourceAuthorization',jsonb_build_object('schemaVersion','lca.study-source-authorization.v1',
      'requestedBy',p_actor,'originRef',p_origin,'sourceEncoding','postgresql.json-text.utf8.v1','sourceScope',scope),
    'source',jsonb_build_object('schemaVersion','lca.study-source.v1','origin',jsonb_build_object('id',p_origin->>'id','version',p_origin->>'version'),
      'actorId',p_actor,'documents',docs,'methodRefs','[]'::jsonb,'cutoffs','[]'::jsonb,'overrides','[]'::jsonb,'studyBinding',null,'qualityFindings','[]'::jsonb));
end $$;

ALTER FUNCTION "private"."study_capture_source"("p_origin" "jsonb", "p_actor" "uuid", "p_client" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_capture_source"("p_origin" "jsonb", "p_actor" "uuid", "p_client" "text") FROM PUBLIC;
