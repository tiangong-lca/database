-- psql -X -v ON_ERROR_STOP=1 -f <this file> on an isolated PG17 reset,
-- before and after the migration. All fixtures, queue effects and DDL roll back.
begin;
create temp table fence_samples (
  profile text, dataset text, write_columns text, trial int,
  elapsed_ms numeric, identity_trigger_ms numeric
);

do $bench$
declare
  dataset text;
  profile text;
  write_columns text;
  assignments text;
  trial int;
  plan jsonb;
  affected int;
  identity_trigger name;
begin
  foreach dataset in array array['flows', 'processes'] loop
    select tgname into strict identity_trigger from pg_trigger
    where tgrelid = format('public.%I', dataset)::regclass
      and tgfoid = 'private.dataset_flow_identity_active_fence()'::regprocedure
      and (tgtype & 16) <> 0;
    -- Initialize identical, out-of-line bodies without paying for ingestion.
    set local session_replication_role = replica;
    execute format($fixture$
      insert into public.%1$I (id, version, user_id, state_code, json, json_ordered)
      select md5('fence1007' || i)::uuid, '01.00.000', md5('fence owner')::uuid,
             0, body, body::json
      from generate_series(1, 100) i
      cross join lateral (
        select jsonb_build_object(%2$L, jsonb_build_object('fixture',
          jsonb_agg(md5(i::text || ':' || j) order by j))) body
        from generate_series(1, 1050) j
      ) payload
    $fixture$, dataset, case dataset when 'flows' then 'flowDataSet' else 'processDataSet' end);
    set local session_replication_role = origin;
    foreach profile in array array['all triggers', 'identity fence only'] loop
      if profile = 'identity fence only' then
        execute format('alter table public.%I disable trigger user', dataset);
        execute format('alter table public.%I enable trigger %I', dataset,
          identity_trigger);
      end if;
      foreach write_columns in array array['search_text','extracted_md + search_text'] loop
        for trial in 0..5 loop
          assignments := format('search_text = array[%L]', profile || write_columns || trial);
          if write_columns <> 'search_text' then
            assignments := assignments || format(', extracted_md = %L', profile || ' md ' || trial);
          end if;
          execute format($update$
            explain (analyze, format json)
            with source as materialized (
              select id, version, xmin from public.%1$I where user_id = md5('fence owner')::uuid
            )
            update public.%1$I target set %2$s from source
            where target.id = source.id and target.version = source.version and target.xmin = source.xmin
            returning target.id
          $update$, dataset, assignments) into plan;
          affected := (plan #>> '{0,Plan,Actual Rows}')::int;
          if affected is distinct from 100 then
            raise exception 'expected 100 updates, observed %', affected;
          end if;
          insert into fence_samples values (profile, dataset, write_columns, trial,
            (plan #>> '{0,Execution Time}')::numeric,
            coalesce((select sum((entry->>'Time')::numeric)
              from jsonb_array_elements(plan #> '{0,Triggers}') entry
              where entry->>'Trigger Name' = identity_trigger::text), 0));
        end loop;
      end loop;
    end loop;
  end loop;
end
$bench$;

select 'flows' as dataset, count(*), avg(octet_length(json_ordered::text))::int as body_bytes
from public.flows where user_id = md5('fence owner')::uuid
union all
select 'processes', count(*), avg(octet_length(json_ordered::text))::int
from public.processes where user_id = md5('fence owner')::uuid;

select profile, dataset, write_columns,
       percentile_disc(0.5) within group (order by elapsed_ms) as median_total_ms,
       percentile_disc(0.5) within group (order by identity_trigger_ms) as median_fence_ms
from fence_samples where trial > 0
group by profile, dataset, write_columns order by profile, dataset, write_columns;
rollback;
