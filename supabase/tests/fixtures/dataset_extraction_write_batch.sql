-- Run with psql on a disposable migration-rebuilt database. Repeat on each
-- candidate. All writes, including pg_net requests, roll back together.
\set ON_ERROR_STOP on
begin;

select vault.create_secret('http://127.0.0.1:9', 'project_url')
where not exists (select 1 from vault.secrets where name = 'project_url');
select vault.create_secret('synthetic-extraction-fixture', 'project_secret_key')
where not exists (select 1 from vault.secrets where name = 'project_secret_key');

create temp table extraction_batch on commit drop as
with padding as (
  select string_agg(encode(sha256(convert_to(n::text, 'UTF8')), 'hex'), '' order by n) as value
  from generate_series(0, 191) n
), identities as (
  select i, ('f2210000-0000-0000-0000-' || lpad((1+i/2)::text,12,'0'))::uuid as id,
    case when i%2=0 then '01.00.000' else '01.01.000' end as version
  from generate_series(0,7) i
)
select tab, i, id, version, rev, json_build_object(root, json_build_object(
  info, json_build_object('dataSetInformation', json_build_object(
    'common:UUID', id, 'name', json_build_object('baseName', json_build_array(
      json_build_object('@xml:lang', 'en', '#text', format('Fixture %s %s rev%s', tab,i,rev)))))),
  'administrativeInformation', json_build_object('publicationAndOwnership',
    json_build_object('common:dataSetVersion', version)), 'padding', padding.value)) as body
from identities cross join padding cross join generate_series(0,3) rev cross join (values
  ('flows','flowDataSet','flowInformation'), ('processes','processDataSet','processInformation'),
  ('lifecyclemodels','lifeCycleModelDataSet','lifeCycleModelInformation')) kinds(tab,root,info);

create temp table first_request on commit drop as
select coalesce(max(id),0) as id from net.http_request_queue;

do $$
declare
  tab text;
  rev int;
  started timestamptz := clock_timestamp();
begin
  for rev in 0..3 loop
    foreach tab in array array['flows','processes','lifecyclemodels'] loop
      if rev=0 then
        execute format('insert into public.%I(id,version,json_ordered)
          select id,version,body from pg_temp.extraction_batch where tab=$1 and rev=0 order by i', tab) using tab;
      else
        execute format('update public.%I d set json_ordered=b.body from pg_temp.extraction_batch b
          where b.tab=$1 and b.rev=$2 and d.id=b.id and d.version=b.version::char(9)', tab) using tab,rev;
      end if;
    end loop;
  end loop;
  raise notice '24 inserts and 72 edits: % ms', extract(epoch from clock_timestamp()-started)*1000;
end;
$$;

select count(*) as webhook_count, coalesce(sum(octet_length(body)),0) as webhook_body_bytes
from net.http_request_queue where id > (select id from first_request) and url like '%/webhook_%';
select count(*) as extraction_messages, coalesce(sum(octet_length(message::text)),0) as message_text_bytes
from pgmq.q_dataset_extraction_jobs where message->>'id' like 'f2210000-%';
rollback;
