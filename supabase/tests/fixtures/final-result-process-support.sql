-- Same three Result rows, with the existing support member now a Unit Process.
-- Package attestations remain synthetic. All exact metadata digests are rebuilt.
alter function pg_temp.candidate_fixture() rename to base_candidate_fixture;
create function pg_temp.make_process_support_fixture() returns jsonb language plpgsql as $$
declare f jsonb:=pg_temp.base_candidate_fixture(); c jsonb:=(f->>'candidateText')::jsonb;
 d jsonb; r jsonb:=f->'receipt'; h text; files jsonb;
begin
 d:=replace(f->>'catalogText','flow:87920000-0000-4000-8000-000000000050','process:87920000-0000-4000-8000-000000000050')::jsonb;
 d:=jsonb_set(jsonb_set(jsonb_set(d,'{datasets,0,datasetType}','"process"'),'{datasets,0,role}','"unit_process"'),'{datasets,0,path}','"processes/support.json"');
 select encode(extensions.digest(convert_to(private.lcia_scope_closure_worker_canonical_json_text(jsonb_agg(to_jsonb(encode(extensions.digest(convert_to(private.lcia_scope_closure_worker_canonical_json_text(jsonb_build_object('key',m->'key','sha256',m->'sha256','references',m->'references')),'UTF8'),'sha256'),'hex')) order by ordinal)),'UTF8'),'sha256'),'hex') into h
 from jsonb_array_elements(d->'datasets') with ordinality a(m,ordinal);
 d:=jsonb_set(d,'{catalogSetHash}',to_jsonb(h));
 c:=jsonb_set(c,'{publicationCatalog,sha256}',to_jsonb(encode(extensions.digest(convert_to(d::text,'UTF8'),'sha256'),'hex')));
 r:=jsonb_set(r,'{candidateSha256}',to_jsonb(encode(extensions.digest(convert_to(c::text,'UTF8'),'sha256'),'hex')));
 select jsonb_agg(file order by file->>'name') into files from (
  select jsonb_build_object('name','result.'||(value->>'format')||'.zip','sha256',value->'sha256','byteSize',value->'byteSize') file from jsonb_array_elements(c->'packages')
  union all select jsonb_build_object('name','release-candidate.json','sha256',r->'candidateSha256','byteSize',octet_length(c::text))
  union all select jsonb_build_object('name','publication-catalog.json','sha256',c#>'{publicationCatalog,sha256}','byteSize',octet_length(d::text))
 ) x;
 return f||jsonb_build_object('candidateText',c::text,'catalogText',d::text,'receipt',jsonb_set(r,'{files}',files));
end $$;
create temporary table process_support_fixture as select pg_temp.make_process_support_fixture() value;
grant select on process_support_fixture to service_role,authenticated;
create function pg_temp.candidate_fixture() returns jsonb language sql stable as $$select value from process_support_fixture$$;
grant execute on function pg_temp.candidate_fixture() to service_role,authenticated;
