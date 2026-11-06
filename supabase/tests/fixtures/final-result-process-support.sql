-- Same three Result rows, with the existing support member now a Unit Process.
-- Package attestations remain synthetic. All exact metadata digests are rebuilt.
alter function pg_temp.candidate_fixture() rename to base_candidate_fixture;
create function pg_temp.make_process_support_fixture() returns jsonb language plpgsql as $$
declare f jsonb:=pg_temp.base_candidate_fixture(); c jsonb:=(f->>'candidateText')::jsonb;
 d jsonb; r jsonb:=f->'receipt'; h text; files jsonb;
begin
 d:=(f->>'catalogText')::jsonb;
 d:=jsonb_set(jsonb_set(d,'{datasets,0,datasetType}','"process"'),'{datasets,0,role}','"unit_process"');
 c:=jsonb_set(c,'{publicationCatalog,sha256}',to_jsonb(encode(extensions.digest(convert_to(d::text,'UTF8'),'sha256'),'hex')));
 r:=jsonb_set(r,'{candidateSha256}',to_jsonb(encode(extensions.digest(convert_to(c::text,'UTF8'),'sha256'),'hex')));
 select jsonb_agg(file order by file->>'name') into files from (
  select jsonb_build_object('name','result.'||(value->>'format')||'.7z','sha256',value->'sha256','byteSize',value->'byteSize') file from jsonb_array_elements(c->'packages')
  union all select jsonb_build_object('name','release-candidate.json','sha256',r->'candidateSha256','byteSize',octet_length(c::text))
  union all select jsonb_build_object('name','publication-catalog.json','sha256',c#>'{publicationCatalog,sha256}','byteSize',octet_length(d::text))
 ) x;
 return f||jsonb_build_object('candidateText',c::text,'catalogText',d::text,'receipt',jsonb_set(r,'{files}',files));
end $$;
create temporary table process_support_fixture as select pg_temp.make_process_support_fixture() value;
grant select on process_support_fixture to service_role,authenticated;
create function pg_temp.candidate_fixture() returns jsonb language sql stable as $$select value from process_support_fixture$$;
grant execute on function pg_temp.candidate_fixture() to service_role,authenticated;
