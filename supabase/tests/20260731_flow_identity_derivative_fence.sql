begin;

create extension if not exists pgtap with schema extensions;
create extension if not exists dblink with schema extensions;

select extensions.plan(13);

select extensions.ok(
  (
    select trigger.tgtype = 19
      and trigger.tgqual is null and trigger.tgattr = ''::int2vector
      and trigger.tgfoid = 'private.dataset_flow_identity_active_fence()'::regprocedure
    from pg_trigger as trigger
    where trigger.tgrelid = 'public.flows'::regclass
      and trigger.tgname = 'flows_z_identity_active_fence'
      and not trigger.tgisinternal
  ),
  'Flow UPDATE checks actual row values inside the identity fence'
);

select extensions.ok(
  (
    select trigger.tgtype = 15
      and trigger.tgqual is null
    from pg_trigger as trigger
    where trigger.tgrelid = 'public.flows'::regclass
      and trigger.tgname =
        'dataset_flow_identity_flow_insert_delete_active_fence'
      and not trigger.tgisinternal
  ),
  'Flow INSERT and DELETE remain unconditionally actor-fenced'
);

alter table public.flows
  disable trigger dataset_flow_identity_flow_insert_delete_active_fence;

insert into public.flows (
  id,
  version,
  user_id,
  state_code,
  json,
  json_ordered
) values (
  'fa324000-0000-4000-8000-000000000001'::uuid,
  '01.00.000',
  'fa324000-0000-4000-8000-000000000002'::uuid,
  0,
  '{}'::jsonb,
  '{}'::json
);

alter table public.flows
  enable trigger dataset_flow_identity_flow_insert_delete_active_fence;

select extensions.dblink_connect(
  'flow_derivative_actor_lock',
  'host=db port=5432 dbname=' || current_database()
    || ' user=postgres password=postgres'
);
select extensions.dblink_exec('flow_derivative_actor_lock', 'begin');
select extensions.dblink_exec(
  'flow_derivative_actor_lock',
  $dblink$
    do $lock$
    begin
      perform pg_advisory_xact_lock(hashtextextended(
        'dataset-flow-identity-actor:fa324000-0000-4000-8000-000000000002',
        0
      ));
    end
    $lock$
  $dblink$
);

select extensions.lives_ok(
  $test$
    update public.flows
    set extracted_md = '# derivative markdown'
    where id = 'fa324000-0000-4000-8000-000000000001'::uuid
  $test$,
  'extracted_md-only Flow update bypasses a busy owner actor fence'
);

select extensions.lives_ok(
  $test$
    update public.flows
    set embedding_ft =
          array_fill(0::real, array[1024])::extensions.vector(1024),
        embedding_ft_at = clock_timestamp()
    where id = 'fa324000-0000-4000-8000-000000000001'::uuid
  $test$,
  'embedding value/timestamp Flow update bypasses a busy owner actor fence'
);

select extensions.lives_ok(
  $test$
    update public.flows
    set search_text = array['multilingual lexical projection']::text[]
    where id = 'fa324000-0000-4000-8000-000000000001'::uuid
  $test$,
  'search_text-only Flow update bypasses a busy owner actor fence'
);

select extensions.throws_ok(
  $test$
    update public.flows
    set json_ordered = '{"changed":true}'::json
    where id = 'fa324000-0000-4000-8000-000000000001'::uuid
  $test$,
  '55P03',
  'FLOW_IDENTITY_ACTIVE_SCOPE_ACTOR_FENCE_BUSY',
  'Flow payload mutation remains fail-closed behind the actor fence'
);

select extensions.throws_ok(
  $test$
    update public.flows
    set state_code = 1
    where id = 'fa324000-0000-4000-8000-000000000001'::uuid
  $test$,
  '55P03',
  'FLOW_IDENTITY_ACTIVE_SCOPE_ACTOR_FENCE_BUSY',
  'Flow state mutation remains fail-closed behind the actor fence'
);

select extensions.throws_ok(
  $test$
    update public.flows
    set user_id = 'fa324000-0000-4000-8000-000000000003'::uuid
    where id = 'fa324000-0000-4000-8000-000000000001'::uuid
  $test$,
  '55P03',
  'FLOW_IDENTITY_ACTIVE_SCOPE_ACTOR_FENCE_BUSY',
  'Flow ownership mutation remains fail-closed behind the actor fence'
);

select extensions.throws_ok(
  $test$
    update public.flows
    set modified_at = modified_at + interval '1 second'
    where id = 'fa324000-0000-4000-8000-000000000001'::uuid
  $test$,
  '55P03',
  'FLOW_IDENTITY_ACTIVE_SCOPE_ACTOR_FENCE_BUSY',
  'Flow guard timestamp mutation remains fail-closed behind the actor fence'
);

select extensions.lives_ok(
  $$update public.flows set search_text = array['latest'], extracted_md = '# latest'
    where id = 'fa324000-0000-4000-8000-000000000001'$$,
  'combined extraction writeback bypasses the uncommitted activation lock'
);

-- The fixture and its authored timestamp were created in this transaction,
-- so the timestamp hook sets the same value. Only JSON spelling differs.
select extensions.lives_ok(
  $$update public.flows set json_ordered = ' { } '::json, search_text = array['same body']
    where id = 'fa324000-0000-4000-8000-000000000001'$$,
  'different JSON spelling with the same final primary values is still neutral'
);

-- The SET list alone cannot establish neutrality. Observe NEW as rewritten
-- by an earlier BEFORE trigger, even when the caller targets only search_text.
create function pg_temp.change_flow_team() returns trigger language plpgsql as $$
begin
  new.team_id := 'fa324000-0000-4000-8000-000000000003';
  return new;
end
$$;
create trigger aa_change_flow_team before update of search_text on public.flows
for each row execute function pg_temp.change_flow_team();
select extensions.throws_ok(
  $$update public.flows set search_text = array['trigger change']
    where id = 'fa324000-0000-4000-8000-000000000001'$$,
  '55P03', 'FLOW_IDENTITY_ACTIVE_SCOPE_ACTOR_FENCE_BUSY',
  'a worker SET list cannot hide an earlier trigger changing a business column'
);
drop trigger aa_change_flow_team on public.flows;

-- A future column inherits the original default protection automatically.
alter table public.flows add column test_future_column text;
select extensions.throws_ok(
  $$update public.flows set search_text = array['mixed'], test_future_column = 'changed'
    where id = 'fa324000-0000-4000-8000-000000000001'$$,
  '55P03', 'FLOW_IDENTITY_ACTIVE_SCOPE_ACTOR_FENCE_BUSY',
  'mixed write to a newly added column still participates in the actor fence'
);

select extensions.dblink_exec('flow_derivative_actor_lock', 'rollback');
select extensions.dblink_disconnect('flow_derivative_actor_lock');

select * from extensions.finish();

rollback;
