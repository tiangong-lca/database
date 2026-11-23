begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, auth;

select plan(16);

select is(
  (
    select count(*)::integer
    from pg_trigger t
    join pg_proc p on p.oid = t.tgfoid
    join pg_namespace n on n.oid = p.pronamespace
    where not t.tgisinternal
      and n.nspname = 'supabase_functions'
      and p.proname = 'http_request'
  ),
  0,
  'no active database webhook trigger uses Dashboard-managed supabase_functions.http_request'
);

select is(
  (
    select count(*)::integer
    from pg_trigger
    where not tgisinternal
      and pg_get_triggerdef(oid, true) like '%sb_secret_%'
  ),
  0,
  'database webhook triggers do not embed Supabase secret keys'
);

select is(
  (
    with expected(table_name, trigger_name) as (
      values
        ('flows', 'flow_extract_md_trigger_update'),
        ('lifecyclemodels', 'lifecyclemodel_extract_md_trigger_insert'),
        ('lifecyclemodels', 'lifecyclemodel_extract_md_trigger_update'),
        ('processes', 'process_extract_md_trigger_insert'),
        ('processes', 'process_extract_md_trigger_update')
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
  ),
  5,
  'all five additional extraction triggers register compact jobs'
);

select is(
  (
    select count(*)::integer
    from pg_trigger
    where not tgisinternal
      and tgname = 'flow_extract_md_trigger_insert'
  ),
  0,
  'flow inserts do not use the old full-row markdown webhook trigger'
);

select ok(
  exists (
    select 1
    from pg_trigger t
    join pg_proc p on p.oid = t.tgfoid
    join pg_namespace pn on pn.oid = p.pronamespace
    where t.tgrelid = 'public.flows'::regclass
      and t.tgname = 'flow_dataset_extraction_trigger_insert'
      and not t.tgisinternal
      and pn.nspname = 'util'
      and p.proname = 'queue_dataset_extraction_jobs'
  ),
  'flow inserts keep the compact dataset extraction queue trigger'
);

select is(
  (
    select count(*)::integer
    from pg_trigger
    where not tgisinternal
      and tgname in (
        'flow_extract_text_trigger_insert',
        'flow_extract_text_trigger_update',
        'process_extract_text_trigger_insert',
        'process_extract_text_trigger_update',
        'lifecyclemodels_extract_text_trigger_insert',
        'lifecyclemodels_extract_text_trigger_update'
      )
  ),
  0,
  'legacy text extraction Edge webhook triggers remain removed'
);

select is(
  (
    select count(*)::integer
    from pg_trigger
    where not tgisinternal
      and tgname in (
        'flow_extract_md_trigger_update_flag',
        'lifecyclemodel_extract_md_trigger_update_flag',
        'process_extract_md_trigger_update_flag'
      )
  ),
  0,
  'embedding_flag no longer enqueues legacy webhook_jobs work'
);

select is(
  (
    select count(*)::integer
    from pg_trigger t
    join pg_proc p on p.oid = t.tgfoid
    join pg_namespace n on n.oid = p.pronamespace
    where not t.tgisinternal
      and n.nspname = 'util'
      and p.proname = 'queue_embedding_webhook'
  ),
  0,
  'no trigger references util.queue_embedding_webhook'
);

select ok(
  to_regprocedure('util.queue_embedding_webhook()') is null,
  'legacy util.queue_embedding_webhook function is removed'
);

select ok(
  to_regprocedure('util.process_webhook_jobs(integer, integer, integer)') is null,
  'legacy util.process_webhook_jobs function is removed'
);

select ok(
  to_regclass('pgmq.q_webhook_jobs') is null
    and to_regclass('pgmq.a_webhook_jobs') is null,
  'legacy webhook_jobs queue tables are removed'
);

select ok(
  exists (select 1 from pg_extension where extname = 'pg_cron'),
  'pg_cron extension is available for dataset extraction cron governance assertions'
);

select is(
  (
    select count(*)::integer
    from cron.job
    where jobname = 'process-dataset-extraction-jobs'
  ),
  1,
  'process-dataset-extraction-jobs is scheduled exactly once'
);

select is(
  (
    select schedule
    from cron.job
    where jobname = 'process-dataset-extraction-jobs'
  ),
  '10 seconds',
  'process-dataset-extraction-jobs uses the intended catch-up cadence'
);

select is(
  (
    select active
    from cron.job
    where jobname = 'process-dataset-extraction-jobs'
  ),
  true,
  'process-dataset-extraction-jobs is active'
);

select ok(
  (
    select command like '%batch_size => 5%'
      and command like '%visibility_timeout_seconds => 300%'
      and command like '%max_read_count => 5%'
      and command like '%timeout_milliseconds => 300000%'
    from cron.job
    where jobname = 'process-dataset-extraction-jobs'
  ),
  'process-dataset-extraction-jobs uses explicit conservative worker arguments'
);

select * from finish();

rollback;
