begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, auth;

create temporary table derivative_webhook_calls (
  edge_function text not null,
  body jsonb not null,
  timeout_milliseconds integer not null
) on commit drop;

-- Keep the real trigger function and payload construction in the test path,
-- but replace the final pg_net boundary transactionally with a deterministic
-- call ledger. ROLLBACK restores the production implementation.
create or replace function util.invoke_edge_function(
  name text,
  body jsonb,
  timeout_milliseconds integer default ((5 * 60) * 1000)
) returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into pg_temp.derivative_webhook_calls (
    edge_function,
    body,
    timeout_milliseconds
  )
  values (name, body, timeout_milliseconds);
end;
$$;

create or replace function pg_temp.trigger_update_columns(
  p_table regclass,
  p_trigger_name text
) returns text
language sql
stable
as $$
  select string_agg(att.attname, ', ' order by att.attnum)
  from pg_trigger trg
  cross join lateral unnest(trg.tgattr::smallint[]) a(attnum)
  join pg_attribute att
    on att.attrelid = trg.tgrelid
   and att.attnum = a.attnum
  where trg.tgrelid = p_table
    and trg.tgname = p_trigger_name
    and not trg.tgisinternal
  group by trg.oid;
$$;

select plan(25);

select is(
  pg_temp.trigger_update_columns(
    'public.flows'::regclass,
    'flow_extract_md_trigger_update'
  ),
  'json, json_ordered',
  'flow markdown extraction covers direct and ordered JSON updates'
);

select is(
  pg_temp.trigger_update_columns(
    'public.processes'::regclass,
    'process_extract_md_trigger_update'
  ),
  'json, json_ordered',
  'process markdown extraction covers direct and ordered JSON updates'
);

select is(
  pg_temp.trigger_update_columns(
    'public.lifecyclemodels'::regclass,
    'lifecyclemodel_extract_md_trigger_update'
  ),
  'json, json_ordered',
  'lifecycle model markdown extraction covers direct and ordered JSON updates'
);

select is(
  (
    with expected(table_name, trigger_name) as (
      values
        ('flows', 'flow_extract_md_trigger_update'),
        ('processes', 'process_extract_md_trigger_update'),
        ('lifecyclemodels', 'lifecyclemodel_extract_md_trigger_update')
    )
    select count(*)::integer
    from expected e
    join pg_class c on c.relname = e.table_name
    join pg_namespace cn on cn.oid = c.relnamespace and cn.nspname = 'public'
    join pg_trigger t on t.tgrelid = c.oid and t.tgname = e.trigger_name
    join pg_proc p on p.oid = t.tgfoid
    join pg_namespace pn on pn.oid = p.pronamespace
    where not t.tgisinternal
      and pn.nspname = 'util'
      and p.proname = 'queue_dataset_extraction_jobs'
      and lower(replace(pg_get_triggerdef(t.oid, true), '"', ''))
        like '%after update of json, json_ordered%'
      and lower(replace(pg_get_triggerdef(t.oid, true), '"', ''))
        like '%new.json is distinct from old.json%'
  ),
  3,
  'all three update hooks preserve column targeting and change guards'
);

alter table public.flows disable trigger flow_dataset_extraction_trigger_insert;
alter table public.processes disable trigger process_extract_md_trigger_insert;
alter table public.lifecyclemodels disable trigger lifecyclemodel_extract_md_trigger_insert;

insert into public.flows (id, version, json_ordered)
values (
  'e7100000-0000-0000-0000-000000000001',
  '01.00.000',
  '{
    "flowDataSet": {
      "flowInformation": {
        "dataSetInformation": {
          "common:UUID": "e7100000-0000-0000-0000-000000000001"
        }
      },
      "administrativeInformation": {
        "publicationAndOwnership": {
          "common:dataSetVersion": "01.00.000"
        }
      }
    }
  }'::json
);

insert into public.processes (id, version, json_ordered)
values (
  'e7200000-0000-0000-0000-000000000001',
  '01.00.000',
  '{
    "processDataSet": {
      "processInformation": {
        "dataSetInformation": {
          "common:UUID": "e7200000-0000-0000-0000-000000000001"
        }
      },
      "administrativeInformation": {
        "publicationAndOwnership": {
          "common:dataSetVersion": "01.00.000"
        }
      }
    }
  }'::json
);

insert into public.lifecyclemodels (id, version, json_ordered)
values (
  'e7300000-0000-0000-0000-000000000001',
  '01.00.000',
  '{
    "lifeCycleModelDataSet": {
      "lifeCycleModelInformation": {
        "dataSetInformation": {
          "common:UUID": "e7300000-0000-0000-0000-000000000001"
        }
      },
      "administrativeInformation": {
        "publicationAndOwnership": {
          "common:dataSetVersion": "01.00.000"
        }
      }
    }
  }'::json
);

alter table public.flows enable trigger flow_dataset_extraction_trigger_insert;
alter table public.processes enable trigger process_extract_md_trigger_insert;
alter table public.lifecyclemodels enable trigger lifecyclemodel_extract_md_trigger_insert;

delete from pgmq.q_dataset_extraction_jobs;

update public.flows
set json = jsonb_set(json, '{derivativeProbe}', '"direct-json"')
where id = 'e7100000-0000-0000-0000-000000000001'
  and version = '01.00.000';

update public.processes
set json = jsonb_set(json, '{derivativeProbe}', '"direct-json"')
where id = 'e7200000-0000-0000-0000-000000000001'
  and version = '01.00.000';

update public.lifecyclemodels
set json = jsonb_set(json, '{derivativeProbe}', '"direct-json"')
where id = 'e7300000-0000-0000-0000-000000000001'
  and version = '01.00.000';

select is(
  (select count(*)::integer from pgmq.q_dataset_extraction_jobs),
  3,
  'direct json changes enqueue one refresh per dataset table'
);

select is(
  (
    select count(distinct message->>'table')::integer
    from pgmq.q_dataset_extraction_jobs
    where message->>'extraction_kind' = 'extracted_md'
  ),
  3,
  'direct json queue messages identify all three updated tables'
);

select is(
  (
    select count(distinct message->>'entity_kind')::integer
    from pgmq.q_dataset_extraction_jobs
  ),
  3,
  'direct json messages distinguish all three entity kinds'
);

delete from pgmq.q_dataset_extraction_jobs;

update public.flows
set json_ordered = jsonb_set(json_ordered::jsonb, '{derivativeProbe}', '"ordered-json"')::json
where id = 'e7100000-0000-0000-0000-000000000001'
  and version = '01.00.000';

update public.processes
set json_ordered = jsonb_set(json_ordered::jsonb, '{derivativeProbe}', '"ordered-json"')::json
where id = 'e7200000-0000-0000-0000-000000000001'
  and version = '01.00.000';

update public.lifecyclemodels
set json_ordered = jsonb_set(json_ordered::jsonb, '{derivativeProbe}', '"ordered-json"')::json
where id = 'e7300000-0000-0000-0000-000000000001'
  and version = '01.00.000';

select is(
  (select count(*)::integer from pgmq.q_dataset_extraction_jobs),
  3,
  'json_ordered changes enqueue one refresh per dataset table'
);

select is(
  (
    select count(distinct message->>'table')::integer
    from pgmq.q_dataset_extraction_jobs
    where message->>'extraction_kind' = 'extracted_md'
  ),
  3,
  'json_ordered queue messages identify all three updated tables'
);

select is(
  (
    select count(*)::integer
    from public.flows
    where id = 'e7100000-0000-0000-0000-000000000001'
      and json = json_ordered::jsonb
      and extracted_md is null
  ),
  1,
  'flow ordered JSON canonicalizes json without synchronously mutating extracted_md'
);

select is(
  (
    select count(*)::integer
    from public.processes
    where id = 'e7200000-0000-0000-0000-000000000001'
      and json = json_ordered::jsonb
      and extracted_md is null
  ),
  1,
  'process ordered JSON canonicalizes json without synchronously mutating extracted_md'
);

select is(
  (
    select count(*)::integer
    from public.lifecyclemodels
    where id = 'e7300000-0000-0000-0000-000000000001'
      and json = json_ordered::jsonb
      and extracted_md is null
  ),
  1,
  'lifecycle model ordered JSON canonicalizes json without synchronously mutating extracted_md'
);

delete from pgmq.q_dataset_extraction_jobs;

update public.flows
set json = jsonb_set(json, '{derivativeProbe}', '"both-columns"'),
    json_ordered = jsonb_set(json_ordered::jsonb, '{derivativeProbe}', '"both-columns"')::json
where id = 'e7100000-0000-0000-0000-000000000001'
  and version = '01.00.000';

update public.processes
set json = jsonb_set(json, '{derivativeProbe}', '"both-columns"'),
    json_ordered = jsonb_set(json_ordered::jsonb, '{derivativeProbe}', '"both-columns"')::json
where id = 'e7200000-0000-0000-0000-000000000001'
  and version = '01.00.000';

update public.lifecyclemodels
set json = jsonb_set(json, '{derivativeProbe}', '"both-columns"'),
    json_ordered = jsonb_set(json_ordered::jsonb, '{derivativeProbe}', '"both-columns"')::json
where id = 'e7300000-0000-0000-0000-000000000001'
  and version = '01.00.000';

select is(
  (select count(*)::integer from pgmq.q_dataset_extraction_jobs),
  3,
  'one UPDATE naming both JSON columns invokes only once per row'
);

select is(
  (
    select count(*)::integer
    from (
      select message->>'table'
      from pgmq.q_dataset_extraction_jobs
      group by message->>'table'
      having count(*) = 1
    ) exactly_once
  ),
  3,
  'both-column updates produce one call for each dataset table'
);

delete from pgmq.q_dataset_extraction_jobs;

update public.flows
set json_ordered = json_ordered
where id = 'e7100000-0000-0000-0000-000000000001'
  and version = '01.00.000';

update public.processes
set json_ordered = json_ordered
where id = 'e7200000-0000-0000-0000-000000000001'
  and version = '01.00.000';

update public.lifecyclemodels
set json_ordered = json_ordered
where id = 'e7300000-0000-0000-0000-000000000001'
  and version = '01.00.000';

select is(
  (select count(*)::integer from pgmq.q_dataset_extraction_jobs),
  0,
  'same-value ordered JSON updates do not invoke markdown extraction'
);

update public.flows
set rule_verification = true
where id = 'e7100000-0000-0000-0000-000000000001'
  and version = '01.00.000';

update public.processes
set rule_verification = true
where id = 'e7200000-0000-0000-0000-000000000001'
  and version = '01.00.000';

update public.lifecyclemodels
set rule_verification = true
where id = 'e7300000-0000-0000-0000-000000000001'
  and version = '01.00.000';

select is(
  (select count(*)::integer from pgmq.q_dataset_extraction_jobs),
  0,
  'unrelated changed columns do not invoke markdown extraction'
);

select is(
  (
    with expected(table_name, trigger_name, input_function) as (
      values
        ('flows', 'flow_embedding_ft_on_extract_md_update', 'flows_embedding_ft_input'),
        ('processes', 'process_embedding_ft_on_extract_md_update', 'processes_embedding_ft_input'),
        ('lifecyclemodels', 'lifecyclemodel_embedding_ft_on_extract_md_update', 'lifecyclemodels_embedding_ft_input')
    )
    select count(*)::integer
    from expected e
    join pg_class c on c.relname = e.table_name
    join pg_namespace cn on cn.oid = c.relnamespace and cn.nspname = 'public'
    join pg_trigger t on t.tgrelid = c.oid and t.tgname = e.trigger_name
    join pg_proc p on p.oid = t.tgfoid
    join pg_namespace pn on pn.oid = p.pronamespace
    where not t.tgisinternal
      and pn.nspname = 'util'
      and p.proname = 'queue_embeddings'
      and lower(replace(pg_get_triggerdef(t.oid, true), '"', ''))
        like '%after update of extracted_md%'
      and lower(replace(pg_get_triggerdef(t.oid, true), '"', ''))
        like '%old.extracted_md is distinct from new.extracted_md%'
      and pg_get_triggerdef(t.oid, true) like '%' || e.input_function || '%'
  ),
  3,
  'downstream extracted_md-to-embedding triggers remain unchanged'
);

select is(
  (
    select count(*)::integer
    from pg_trigger t
    join pg_proc p on p.oid = t.tgfoid
    join pg_namespace pn on pn.oid = p.pronamespace
    where t.tgname in (
      'flow_extract_md_trigger_update',
      'process_extract_md_trigger_update',
      'lifecyclemodel_extract_md_trigger_update'
    )
      and not t.tgisinternal
      and pn.nspname = 'util'
      and p.proname = 'queue_dataset_extraction_jobs'
  ),
  3,
  'all update triggers use the extraction queue'
);

select is((select count(*)::integer from pg_temp.derivative_webhook_calls), 0,
  'body edits never invoke the full-row Edge webhook');
-- An unread wake-up is reusable. A claimed one must have an independent successor.
savepoint before_edit;
update public.flows set json = json || '{"edit":1}'
where id = 'e7100000-0000-0000-0000-000000000001';
select is((select count(*)::int from pgmq.q_dataset_extraction_jobs), 1, 'refresh visible in saving transaction');
rollback to savepoint before_edit;
select is((select count(*)::int from pgmq.q_dataset_extraction_jobs), 0, 'rollback removes the refresh');
select ok(not (select json ? 'edit' from public.flows where id = 'e7100000-0000-0000-0000-000000000001'),
  'rollback restores the source');

update public.flows set json = json || '{"edit":1}' where id = 'e7100000-0000-0000-0000-000000000001';
update public.flows set json = json || '{"edit":2}' where id = 'e7100000-0000-0000-0000-000000000001';
update public.flows set json = json || '{"edit":3}' where id = 'e7100000-0000-0000-0000-000000000001';
select is((select count(*)::int from pgmq.q_dataset_extraction_jobs), 1, 'three unclaimed saves share one message');

create temporary table first_claim as select msg_id from pgmq.read('dataset_extraction_jobs', 300, 1);
update public.flows set json = json || '{"edit":4}' where id = 'e7100000-0000-0000-0000-000000000001';
select is((select count(*)::int from pgmq.q_dataset_extraction_jobs), 2, 'an in-flight refresh has a separate successor');
select pgmq.delete('dataset_extraction_jobs', msg_id) from first_claim;
select is((select count(*)::int from pgmq.q_dataset_extraction_jobs
  where read_ct=0 and msg_id not in (select msg_id from first_claim)), 1, 'old ACK leaves the unread successor intact');

select * from finish();
rollback;
