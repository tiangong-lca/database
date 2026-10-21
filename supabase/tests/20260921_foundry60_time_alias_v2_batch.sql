-- Foundry #60 / Database #673 — v2 batch executor behaviour suite (real rows, TDD).
--
-- Behaviours pinned here, on the real deployed payload shapes and the shared CLI cohort contract:
--   * a real small success applies: the flow's five-key flow-property reference moves to the locked target
--     (common:shortDescription projected from the target's own common:name object), the bound exchange
--     amounts move by the exact factor, the reviewed functional-unit leaf moves under the text-action block,
--     audit rows are written, and the plan summary binds the source evidence;
--   * a write-pass-induced failure rolls back every already-written row and every audit row;
--   * an exact resubmission returns the stored proof and writes nothing;
--   * closure, scope, text, digest, target/source-evidence and count negatives are refused for their own
--     reason, never incidentally.
-- No has_function/grep/hash proxies anywhere.

begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, auth, private;

select plan(119);

-- ------------------------------------------------------------------------------------------------
-- Fixture: one target unit group (year base plus the exact hour factor), one distinct source unit group
-- referenced by the alias flow property, one target flow property (real common:name language object), the
-- alias flow property, one alias Product flow, one foreign consumer id, one process carrying two bound
-- alias exchanges (reference output quantity 1 and an input 1.03E-4, both with their reviewed source
-- tuples) plus one unrelated exchange, and spare ids used by the negatives.
create temp table v2_fixture (
  actor uuid,
  foreign_actor uuid,
  target_ug uuid,
  source_ug uuid,
  target_fp uuid,
  alias_fp uuid,
  flow_id uuid,
  foreign_flow_id uuid,
  process_id uuid,
  uncertain_flow_id uuid,
  uncertain_process_id uuid,
  mismatch_process_id uuid
) on commit drop;

insert into v2_fixture values (
  '11111111-1111-4111-8111-111111111111',
  '22222222-2222-4222-8222-222222222222',
  '33333333-3333-4333-8333-333333333333',
  '99999999-9999-4999-8999-999999999990',
  '44444444-4444-4444-8444-444444444444',
  '55555555-5555-4555-8555-555555555555',
  '66666666-6666-4666-8666-666666666666',
  '77777777-7777-4777-8777-777777777777',
  '88888888-8888-4888-8888-888888888888',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  'cccccccc-cccc-4ccc-8ccc-cccccccccccc'
);

-- The deployed five-key reference: @refObjectId/@type/@uri(.json)/@version and one language-tagged
-- common:shortDescription object — the shape the live 113 Flow references carry.
create or replace function pg_temp.v2_ref(p_kind text, p_type text, p_id uuid, p_version text, p_name text)
returns jsonb language sql immutable as $$
  select jsonb_build_object(
    '@refObjectId', p_id,
    '@type', p_type,
    '@uri', '../' || p_kind || '/' || p_id || '.json',
    '@version', p_version,
    'common:shortDescription', jsonb_build_object('@xml:lang', 'en', '#text', p_name))
$$;

-- A real Product flow: object-shaped internal-ID-1 property entry, internal quantitative-reference pointer
-- that never moves, and the Product flow eligibility field the plan requires.
create or replace function pg_temp.v2_flow(p_id uuid, p_version text, p_fp uuid, p_fp_version text, p_fp_name text)
returns jsonb language sql immutable as $$
  select jsonb_build_object(
    'flowDataSet', jsonb_build_object(
      'flowInformation', jsonb_build_object(
        'dataSetInformation', jsonb_build_object('common:UUID', p_id),
        'quantitativeReference', jsonb_build_object('referenceToReferenceFlowProperty', '1')),
      'modellingAndValidation', jsonb_build_object(
        'LCIMethod', jsonb_build_object('typeOfDataSet', 'Product flow')),
      'flowProperties', jsonb_build_object(
        'flowProperty', jsonb_build_object(
          '@dataSetInternalID', '1',
          'meanValue', '1.0',
          'referenceToFlowPropertyDataSet', pg_temp.v2_ref('flowproperties', 'flow property data set', p_fp, p_fp_version, p_fp_name))),
      'administrativeInformation', jsonb_build_object(
        'publicationAndOwnership', jsonb_build_object('common:dataSetVersion', p_version))))
$$;

-- A real process shape: TIDAS internal ids "1"/"2"/"3" for the exchanges while the reviewed source tuples
-- carry the original EcoSpold numbers in their generalComment (730045 reference output, 730046 input); the
-- reference-output source quantity is 1, matching a "1.0 a" functional unit. The third exchange references
-- another flow and is the unrelated complement.
create or replace function pg_temp.v2_process(
  p_id uuid, p_version text, p_flow uuid, p_flow_version text, p_flow_name text,
  p_alias_extra jsonb default '{}'::jsonb
)
returns jsonb language sql immutable as $$
  select jsonb_build_object(
    'processDataSet', jsonb_build_object(
      'processInformation', jsonb_build_object(
        'dataSetInformation', jsonb_build_object('common:UUID', p_id),
        'quantitativeReference', jsonb_build_object(
          'referenceToReferenceFlow', '1',
          'functionalUnitOrOther', jsonb_build_object('@xml:lang', 'en', '#text', '1.0 a per unit'))),
      'exchanges', jsonb_build_object('exchange', jsonb_build_array(
        jsonb_build_object(
          '@dataSetInternalID', '1',
          'meanAmount', '1',
          'resultingAmount', '1',
          'exchangeDirection', 'Output',
          'generalComment', 'Reviewed source exchange 730045 (EcoSpold).',
          'referenceToFlowDataSet', pg_temp.v2_ref('flows', 'flow data set', p_flow, p_flow_version, p_flow_name))
        || p_alias_extra,
        jsonb_build_object(
          '@dataSetInternalID', '2',
          'meanAmount', '1.03E-4',
          'resultingAmount', '1.03E-4',
          'exchangeDirection', 'Input',
          'generalComment', 'Reviewed source exchange 730046 (EcoSpold).',
          'referenceToFlowDataSet', pg_temp.v2_ref('flows', 'flow data set', p_flow, p_flow_version, 'Alias flow')),
        jsonb_build_object(
          '@dataSetInternalID', '3',
          'meanAmount', '5',
          'resultingAmount', '5',
          'exchangeDirection', 'Input',
          'referenceToFlowDataSet', pg_temp.v2_ref('flows', 'flow data set', '99999999-9999-4999-8999-999999999999', '01.00.000', 'Other flow')))),
      'administrativeInformation', jsonb_build_object(
        'publicationAndOwnership', jsonb_build_object('common:dataSetVersion', p_version))))
$$;

-- Transaction-local vault prerequisites the row triggers need (fixture values only).
delete from vault.secrets where name in ('project_secret_key', 'project_url');
select vault.create_secret('fixture-service-secret', 'project_secret_key', 'transaction-local v2 batch test key');
select vault.create_secret('http://127.0.0.1:55341', 'project_url', 'transaction-local v2 batch test URL');

-- The deployed Time unit group shape, taken from the live state-0 export: the quantitative reference
-- names the reference unit by internal id (an id string) and the table is units.unit[] with
-- name/meanValue/@dataSetInternalID. The year base keeps the real "1.0" spelling, so the factor
-- comparison is exercised as a value rather than as a string.
insert into public.unitgroups (id, version, user_id, state_code, json_ordered, modified_at)
select target_ug, '01.00.000', actor, 0,
  to_json(jsonb_build_object('unitGroupDataSet', jsonb_build_object(
    'unitGroupInformation', jsonb_build_object('quantitativeReference', jsonb_build_object(
      'referenceToReferenceUnit', '1'
    )),
    'units', jsonb_build_object('unit', jsonb_build_array(
      jsonb_build_object('@dataSetInternalID', '1', 'name', 'a', 'meanValue', '1.0'),
      jsonb_build_object('@dataSetInternalID', '2', 'name', 'hr', 'meanValue', '0.00011415525114155251')
    )),
    'administrativeInformation', jsonb_build_object(
      'publicationAndOwnership', jsonb_build_object('common:dataSetVersion', '01.00.000'))
  ))),
  timestamp '2026-09-21 00:00:00'
from v2_fixture;
-- The source unit group is a distinct row: the alias flow property references it and the source evidence
-- binds its locked snapshot.
insert into public.unitgroups (id, version, user_id, state_code, json_ordered, modified_at)
select source_ug, '01.00.000', actor, 0,
  to_json(jsonb_build_object('unitGroupDataSet', jsonb_build_object(
    'unitGroupInformation', jsonb_build_object('quantitativeReference', jsonb_build_object(
      'referenceToReferenceUnit', jsonb_build_array(
        jsonb_build_object('@dataSetInternalID', '1', '@unitName', 'a', 'meanValue', '1')
      )
    )),
    'administrativeInformation', jsonb_build_object(
      'publicationAndOwnership', jsonb_build_object('common:dataSetVersion', '01.00.000'))
  ))),
  timestamp '2026-09-21 00:00:00'
from v2_fixture;
-- The target flow property: name lives at flowPropertiesInformation.dataSetInformation["common:name"] as a
-- single language object — never at a Process-shaped name/baseName path.
insert into public.flowproperties (id, version, user_id, state_code, json_ordered, modified_at)
select target_fp, '01.00.000', actor, 0,
  to_json(jsonb_build_object('flowPropertyDataSet', jsonb_build_object(
    'flowPropertiesInformation', jsonb_build_object(
      'dataSetInformation', jsonb_build_object(
        'common:UUID', target_fp,
        'common:name', jsonb_build_object('@xml:lang', 'en', '#text', 'Time'),
        'common:other', 'urn:fixture:time'
      ),
      'quantitativeReference', jsonb_build_object(
        'referenceToReferenceUnitGroup', pg_temp.v2_ref('unitgroups', 'unit group data set', target_ug, '01.00.000', 'Units of time')
      )
    ),
    'administrativeInformation', jsonb_build_object(
      'publicationAndOwnership', jsonb_build_object('common:dataSetVersion', '01.00.000'))
  ))),
  timestamp '2026-09-21 00:00:00'
from v2_fixture;
insert into public.flowproperties (id, version, user_id, state_code, json_ordered, modified_at)
select alias_fp, '00.00.001', actor, 0,
  to_json(jsonb_build_object('flowPropertyDataSet', jsonb_build_object(
    'flowPropertiesInformation', jsonb_build_object(
      'dataSetInformation', jsonb_build_object('common:UUID', alias_fp),
      'quantitativeReference', jsonb_build_object(
        'referenceToReferenceUnitGroup', pg_temp.v2_ref('unitgroups', 'unit group data set', source_ug, '01.00.000', 'Units of time')
      )
    ),
    'administrativeInformation', jsonb_build_object(
      'publicationAndOwnership', jsonb_build_object('common:dataSetVersion', '00.00.001'))
  ))),
  timestamp '2026-09-21 00:00:00'
from v2_fixture;
insert into public.flows (id, version, user_id, state_code, json_ordered, modified_at)
select flow_id, '01.00.000', actor, 0, to_json(pg_temp.v2_flow(flow_id, '01.00.000', alias_fp, '00.00.001', 'Alias property')),
  timestamp '2026-09-21 00:00:00'
from v2_fixture;
insert into public.processes (id, version, user_id, state_code, json_ordered, modified_at)
select process_id, '01.00.000', actor, 0,
  to_json(pg_temp.v2_process(process_id, '01.00.000', flow_id, '01.00.000', 'Alias flow')),
  timestamp '2026-09-21 00:00:00'
from v2_fixture;

-- ------------------------------------------------------------------------------------------------
-- Recompute an action's claimed canonical digests after a payload tamper, exactly as a producer would.
create or replace function pg_temp.v2_resign(p_action jsonb)
returns jsonb language sql stable as $$
  select jsonb_set(
    jsonb_set(p_action, '{before_sha256}',
      to_jsonb(private.dataset_alias_v2_payload_sha256(p_action->'expected_json_ordered'))),
    '{desired_sha256}',
    to_jsonb(private.dataset_alias_v2_payload_sha256(p_action->'desired_json_ordered')))
$$;

-- A small, real, valid batch on the shared contract: one flow action and one process action bound to the
-- two alias exchanges, with the text-action block naming the reviewed move. The extras slots append further
-- claimed actions and keep the derived counts consistent.
create or replace function pg_temp.v2_batch(p_extras jsonb default '{}'::jsonb)
returns jsonb language plpgsql stable as $$
declare
  f record;
  v_include_base boolean := coalesce((p_extras->>'include_base')::boolean, true);
  v_extra_flows jsonb := coalesce(p_extras->'flows', '[]'::jsonb);
  v_extra_processes jsonb := coalesce(p_extras->'processes', '[]'::jsonb);
  v_text_actions jsonb := coalesce(p_extras->'text_actions', '[]'::jsonb);
  v_before_flow jsonb;
  v_desired_flow jsonb;
  v_desired_process jsonb;
  v_occurrences integer;
  v_selected integer;
begin
  select * into f from v2_fixture;
  v_before_flow := pg_temp.v2_flow(f.flow_id, '01.00.000', f.alias_fp, '00.00.001', 'Alias property');
  v_desired_flow := pg_temp.v2_flow(f.flow_id, '01.00.000', f.target_fp, '01.00.000', 'Time');
  v_desired_process := jsonb_set(
    jsonb_set(
      jsonb_set(
        jsonb_set(
          jsonb_set(
            pg_temp.v2_process(f.process_id, '01.00.000', f.flow_id, '01.00.000', 'Alias flow'),
            '{processDataSet,exchanges,exchange,0,meanAmount}',
            to_jsonb(private.dataset_alias_v2_multiply_amount('1', private.dataset_alias_v2_factor()::text)), false),
          '{processDataSet,exchanges,exchange,0,resultingAmount}',
          to_jsonb(private.dataset_alias_v2_multiply_amount('1', private.dataset_alias_v2_factor()::text)), false),
        '{processDataSet,exchanges,exchange,1,meanAmount}',
        to_jsonb(private.dataset_alias_v2_multiply_amount('1.03E-4', private.dataset_alias_v2_factor()::text)), false),
      '{processDataSet,exchanges,exchange,1,resultingAmount}',
      to_jsonb(private.dataset_alias_v2_multiply_amount('1.03E-4', private.dataset_alias_v2_factor()::text)), false),
    '{processDataSet,processInformation,quantitativeReference,functionalUnitOrOther,#text}', to_jsonb('1.0 hr per unit'::text), false);
  select (case when v_include_base then 2 else 0 end)
      + coalesce(sum(jsonb_array_length(coalesce(a->'mutation'->'exchanges', '[]'::jsonb))), 0)
    into v_occurrences
  from jsonb_array_elements(v_extra_processes) as a;
  select (case when v_include_base then 3 else 0 end)
      + coalesce(sum(jsonb_array_length(coalesce(a->'expected_json_ordered' #> '{processDataSet,exchanges,exchange}', '[]'::jsonb))), 0)
    into v_selected
  from jsonb_array_elements(v_extra_processes) as a;
  if v_include_base then
    v_text_actions := jsonb_build_array(jsonb_build_object(
      'table', 'processes', 'id', f.process_id, 'version', '01.00.000',
      'before_text', '1.0 a per unit', 'after_text', '1.0 hr per unit', 'source_exchange_number', '730045'))
      || v_text_actions;
  end if;
  return jsonb_build_object(
    'schema_version', 'dataset-alias-batch.v2',
    'batch_id', 'fixture-batch-1',
    'plan_sha256', coalesce(p_extras->>'plan_sha256', repeat('a', 64)),
    'dimension', 'time',
    'factor', '0.00011415525114155251',
    'target_visibility', 'owner_draft',
    'target_snapshots', jsonb_build_object(
      'flowproperty', jsonb_build_object('id', f.target_fp, 'version', '01.00.000',
        'sha256', private.dataset_alias_v2_payload_sha256((select json_ordered::jsonb from public.flowproperties where id = f.target_fp and version = '01.00.000'))),
      'unitgroup', jsonb_build_object('id', f.target_ug, 'version', '01.00.000',
        'sha256', private.dataset_alias_v2_payload_sha256((select json_ordered::jsonb from public.unitgroups where id = f.target_ug and version = '01.00.000')))),
    'source_evidence', jsonb_build_object(
      'sha256', repeat('b', 64),
      'exchange_count', v_occurrences,
      'source_unitgroup', jsonb_build_object('id', f.source_ug, 'version', '01.00.000',
        'sha256', private.dataset_alias_v2_payload_sha256((select json_ordered::jsonb from public.unitgroups where id = f.source_ug and version = '01.00.000'))),
      -- The complete current source flow property payload, bound by its own canonical digest.
      'source_flowproperty', jsonb_build_object('id', f.alias_fp, 'version', '00.00.001',
        'sha256', private.dataset_alias_v2_payload_sha256((select json_ordered::jsonb from public.flowproperties where id = f.alias_fp and version = '00.00.001')))),
    'counts', jsonb_build_object(
      'action_count', (case when v_include_base then 2 else 0 end) + jsonb_array_length(v_extra_flows) + jsonb_array_length(v_extra_processes),
      'flow_count', (case when v_include_base then 1 else 0 end) + jsonb_array_length(v_extra_flows),
      'process_count', (case when v_include_base then 1 else 0 end) + jsonb_array_length(v_extra_processes),
      'exchange_count', v_occurrences,
      'amount_field_count', v_occurrences * 2,
      'unrelated_exchange_count', v_selected - v_occurrences,
      'flowproperty_count', 0),
    'text_actions', v_text_actions,
    'actions', (case when v_include_base then jsonb_build_array(
      pg_temp.v2_resign(jsonb_build_object(
        'action_id', 'flow-1', 'table', 'flows', 'id', f.flow_id, 'version', '01.00.000',
        'expected_state_code', 0,
        'expected_json_ordered', v_before_flow,
        'desired_json_ordered', v_desired_flow,
        'before_sha256', repeat('0', 64), 'desired_sha256', repeat('0', 64),
        'source_flowproperty', jsonb_build_object('id', f.alias_fp, 'version', '00.00.001'),
        'mutation', jsonb_build_object('reference', pg_temp.v2_ref('flowproperties', 'flow property data set', f.target_fp, '01.00.000', 'Time')))))
      else '[]'::jsonb end)
      || v_extra_flows
      || (case when v_include_base then jsonb_build_array(
        pg_temp.v2_resign(jsonb_build_object(
          'action_id', 'process-1', 'table', 'processes', 'id', f.process_id, 'version', '01.00.000',
          'expected_state_code', 0,
          'expected_json_ordered', pg_temp.v2_process(f.process_id, '01.00.000', f.flow_id, '01.00.000', 'Alias flow'),
          'desired_json_ordered', v_desired_process,
          'before_sha256', repeat('0', 64), 'desired_sha256', repeat('0', 64),
          'quantitative_reference', '1',
          'mutation', jsonb_build_object('exchanges', jsonb_build_array(
            jsonb_build_object(
              'index', 0, 'internal_id', '1', 'flow_id', f.flow_id, 'flow_version', '01.00.000',
              'direction', 'Output', 'before_amount', '1',
              'after_amount', private.dataset_alias_v2_multiply_amount('1', private.dataset_alias_v2_factor()::text),
              'before_resulting_amount', '1',
              'after_resulting_amount', private.dataset_alias_v2_multiply_amount('1', private.dataset_alias_v2_factor()::text)),
            jsonb_build_object(
              'index', 1, 'internal_id', '2', 'flow_id', f.flow_id, 'flow_version', '01.00.000',
              'direction', 'Input', 'before_amount', '1.03E-4',
              'after_amount', private.dataset_alias_v2_multiply_amount('1.03E-4', private.dataset_alias_v2_factor()::text),
              'before_resulting_amount', '1.03E-4',
              'after_resulting_amount', private.dataset_alias_v2_multiply_amount('1.03E-4', private.dataset_alias_v2_factor()::text)))))))
      else '[]'::jsonb end)
      || v_extra_processes);
end
$$;

-- The executor is private by design; the suite reaches it through a superuser-owned wrapper that sets the
-- verified-actor claims the protected façade would set, exactly as the v1 suites do.
create or replace function pg_temp.v2_call(p_batch jsonb)
returns jsonb language plpgsql as $$
begin
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config('request.jwt.claim.sub', (select actor::text from v2_fixture), true);
  perform set_config('request.jwt.claim.email', 'fixture@example.invalid', true);
  return private.cmd_dataset_alias_batch_v2_guarded(p_batch);
end
$$;

create temp table v2_before_state as
  select (select count(*) from private.command_audit_log) as audits,
    (select json_ordered::jsonb from public.flows where id = (select flow_id from v2_fixture)) as flow_payload,
    (select json_ordered::jsonb from public.processes where id = (select process_id from v2_fixture)) as process_payload,
    (select modified_at from public.flows where id = (select flow_id from v2_fixture)) as flow_modified,
    (select modified_at from public.processes where id = (select process_id from v2_fixture)) as process_modified;

-- ================================================================================================
-- 1. Negatives on the pristine rows. None of them may write.
-- ================================================================================================

-- 1.1 a stale optional timestamp is a content drift, not a closure problem
select is(
  (pg_temp.v2_call(jsonb_set(pg_temp.v2_batch(), '{actions,1,expected_modified_at}', '"2020-01-01T00:00:00+00:00"'::jsonb)) ->> 'code'),
  'ALIAS_V2_ACTION_DRIFT',
  'a stale optional timestamp refuses the whole batch as a drift'
);

-- 1.2 an omitted consumer breaks the exchange closure, and the refusal names the live occurrence
create temp table v2_neg_omit as select pg_temp.v2_call(
  jsonb_set(
    jsonb_set(
      jsonb_set(pg_temp.v2_batch() #- '{actions,1}' #- '{text_actions,0}',
        '{counts}', jsonb_build_object('action_count', 1, 'flow_count', 1, 'process_count', 0,
          'exchange_count', 0, 'amount_field_count', 0, 'unrelated_exchange_count', 0, 'flowproperty_count', 0)),
      '{source_evidence,exchange_count}', '0'::jsonb),
    '{actions,0,desired_json_ordered}',
    pg_temp.v2_flow((select flow_id from v2_fixture), '01.00.000', (select target_fp from v2_fixture), '01.00.000', 'Time'))
) as result;
select is((select result->>'code' from v2_neg_omit), 'ALIAS_V2_CLOSURE_MISMATCH', 'an omitted consumer is refused as a closure mismatch');
select ok(exists (
  select 1 from jsonb_array_elements((select result->'details' from v2_neg_omit) -> 'live_occurrences') as live
  where live->>'process_id' = (select process_id::text from v2_fixture)
), 'the closure refusal names the unclaimed live occurrence');

-- 1.3 scope eligibility: only Product flows may enter the maintenance path
select is(
  (pg_temp.v2_call(pg_temp.v2_batch(jsonb_build_object('flows', jsonb_build_array(pg_temp.v2_resign(
    pg_temp.v2_batch()->'actions'->0 #- '{expected_json_ordered,flowDataSet,modellingAndValidation}'))))) ->> 'code'),
  'ALIAS_V2_BATCH_INVALID',
  'a flow without the typeOfDataSet eligibility field is refused'
);
select is(
  (pg_temp.v2_call(pg_temp.v2_batch(jsonb_build_object('flows', jsonb_build_array(pg_temp.v2_resign(
    jsonb_set(pg_temp.v2_batch()->'actions'->0, '{expected_json_ordered,flowDataSet,modellingAndValidation,LCIMethod,typeOfDataSet}', '"Elementary flow"'::jsonb)))))) ->> 'code'),
  'ALIAS_V2_BATCH_INVALID',
  'an Elementary flow is refused'
);
select is(
  (pg_temp.v2_call(pg_temp.v2_batch(jsonb_build_object('flows', jsonb_build_array(pg_temp.v2_resign(
    jsonb_set(pg_temp.v2_batch()->'actions'->0, '{expected_json_ordered,flowDataSet,modellingAndValidation,LCIMethod,typeOfDataSet}', '"Waste flow"'::jsonb)))))) ->> 'code'),
  'ALIAS_V2_BATCH_INVALID',
  'a Waste flow is refused'
);

-- 1.4 claimed digests must be the server's own canonical digests of the claimed payloads
select is(
  (pg_temp.v2_call(jsonb_set(pg_temp.v2_batch(), '{actions,0,before_sha256}', to_jsonb(repeat('d', 64)))) ->> 'code'),
  'ALIAS_V2_DERIVE_MISMATCH',
  'a claimed before digest that is not the canonical digest of its payload is refused'
);

-- 1.5 the text-action block is the functional-unit authority and must agree with the claimed leaves
select is(
  (pg_temp.v2_call(jsonb_set(pg_temp.v2_batch(), '{text_actions,0,after_text}', '"1.0 hr something else"'::jsonb)) ->> 'code'),
  'ALIAS_V2_TEXT_BLOCK_MISMATCH',
  'a text action whose after text is not the claimed desired leaf is refused'
);
select is(
  (pg_temp.v2_call(pg_temp.v2_batch(jsonb_build_object('text_actions', jsonb_build_array(
    jsonb_build_object('table', 'processes', 'id', 'dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'version', '01.00.000',
      'before_text', '1.0 a per unit', 'after_text', '1.0 hr per unit', 'source_exchange_number', '730045'))))) ->> 'code'),
  'ALIAS_V2_TEXT_RULE_VIOLATION',
  'a text action naming a process the batch does not claim is refused'
);
select is(
  (pg_temp.v2_call(jsonb_set(pg_temp.v2_batch(), '{text_actions,0,evidence}', '"x"'::jsonb)) ->> 'code'),
  'ALIAS_V2_TEXT_RULE_VIOLATION',
  'a text action with an unknown key is refused'
);
select is(
  (pg_temp.v2_call(pg_temp.v2_batch() #- '{text_actions,0}') ->> 'code'),
  'ALIAS_V2_TEXT_BLOCK_MISMATCH',
  'a moved functional-unit leaf that the block does not name is refused'
);
select is(
  (pg_temp.v2_call(jsonb_set(pg_temp.v2_batch(), '{text_actions,0,source_exchange_number}', '"730046"'::jsonb)) ->> 'code')
    || ' / ' || (pg_temp.v2_call(jsonb_set(pg_temp.v2_batch(), '{text_actions,0,source_exchange_number}', '"730046"'::jsonb)) ->> 'message'),
  'ALIAS_V2_EVIDENCE_MISMATCH / The reviewed source comment of the reference exchange does not carry the declared source exchange number',
  'a source number contradicting the stored reviewed source comment is refused'
);
select ok(
  (pg_temp.v2_batch() #>> '{text_actions,0,source_exchange_number}') = '730045'
    and (pg_temp.v2_batch() #>> '{actions,1,mutation,exchanges,0,internal_id}') = '1'
    and (pg_temp.v2_batch() #>> '{actions,1,quantitative_reference}') = '1',
  'the fixture binds the TIDAS internal id and the original source number as distinct namespaces'
);

-- 1.6 the flow mutation must name the derived canonical target reference
select is(
  (pg_temp.v2_call(jsonb_set(pg_temp.v2_batch(), '{actions,0,mutation,reference,@refObjectId}', '"99999999-9999-4999-8999-999999999999"'::jsonb)) ->> 'code'),
  'ALIAS_V2_EVIDENCE_MISMATCH',
  'a flow mutation naming another reference is refused'
);

-- 1.7 target and source evidence read from the locked rows
select is(
  (pg_temp.v2_call(jsonb_set(pg_temp.v2_batch(), '{target_snapshots,flowproperty,sha256}', to_jsonb(repeat('c', 64)))) ->> 'code'),
  'ALIAS_V2_EVIDENCE_MISMATCH',
  'a target flow-property digest that does not match the locked row is refused'
);
select is(
  (pg_temp.v2_call(jsonb_set(pg_temp.v2_batch(), '{source_evidence,source_unitgroup,sha256}', to_jsonb(repeat('c', 64)))) ->> 'code'),
  'ALIAS_V2_EVIDENCE_MISMATCH',
  'a source unit-group digest that does not match the locked row is refused'
);
select is(
  (pg_temp.v2_call(jsonb_set(pg_temp.v2_batch(), '{source_evidence,source_unitgroup,id}', to_jsonb((select target_ug::text from v2_fixture)))) ->> 'code'),
  'ALIAS_V2_EVIDENCE_MISMATCH',
  'a source unit group the alias flow property does not reference is refused'
);

-- 1.8 envelope, counts and source evidence
select is(
  (pg_temp.v2_call(jsonb_set(pg_temp.v2_batch(), '{factor}', '"0.5"'::jsonb)) ->> 'code'),
  'ALIAS_V2_BATCH_INVALID',
  'a plan-supplied factor is refused'
);
select is(
  (pg_temp.v2_call(jsonb_set(pg_temp.v2_batch(), '{counts,flow_count}', '2'::jsonb)) ->> 'code'),
  'ALIAS_V2_COUNT_MISMATCH',
  'counts that differ from the derived live counts are refused'
);
select is(
  (pg_temp.v2_call(jsonb_set(pg_temp.v2_batch(), '{counts,amount_field_count}', '9'::jsonb)) ->> 'code'),
  'ALIAS_V2_COUNT_MISMATCH',
  'an amount-field count that is not two fields per bound exchange is refused'
);
select is(
  (pg_temp.v2_call(jsonb_set(pg_temp.v2_batch(), '{source_evidence,exchange_count}', '9'::jsonb)) ->> 'code'),
  'ALIAS_V2_EVIDENCE_MISMATCH',
  'a source evidence exchange count that differs from the batch exchange count is refused'
);
select is(
  (pg_temp.v2_call(jsonb_set(pg_temp.v2_batch(), '{actions}', (pg_temp.v2_batch()->'actions') || jsonb_build_array(pg_temp.v2_batch()->'actions'->0))) ->> 'code'),
  'ALIAS_V2_BATCH_INVALID',
  'a duplicate action identity is refused'
);
select is(
  (pg_temp.v2_call(jsonb_set(pg_temp.v2_batch(), '{note}', '"x"'::jsonb)) ->> 'code'),
  'ALIAS_V2_BATCH_INVALID',
  'an unknown batch key is refused'
);

-- 1.9 a foreign live consumer of the alias property breaks the closure, and the refusal names it
insert into public.flows (id, version, user_id, state_code, json_ordered, modified_at)
select foreign_flow_id, '01.00.000', foreign_actor, 0,
  to_json(pg_temp.v2_flow(foreign_flow_id, '01.00.000', alias_fp, '00.00.001', 'Alias property')), timestamp '2026-09-21 00:00:00'
from v2_fixture;
create temp table v2_neg_foreign as select pg_temp.v2_call(pg_temp.v2_batch()) as result;
select is((select result->>'code' from v2_neg_foreign), 'ALIAS_V2_CLOSURE_MISMATCH', 'a foreign consumer of the alias property is refused');
select ok(exists (
  select 1 from jsonb_array_elements((select result->'details' from v2_neg_foreign) -> 'live_flows') as live
  where live->>'id' = (select foreign_flow_id::text from v2_fixture)
    and live->>'user_id' = (select foreign_actor::text from v2_fixture)
), 'the closure refusal names the foreign live consumer');
delete from public.flows where id = (select foreign_flow_id from v2_fixture);

-- 1.10 a same-id published version remains a distinct live consumer. The closure
-- inventories every state; keep one current draft and prove both exact versions
-- remain in that inventory, even though the published row also fails draft scope.
insert into public.flows (id, version, user_id, state_code, json_ordered, modified_at)
select flow_id, '02.00.000', actor, 100,
  to_json(pg_temp.v2_flow(flow_id, '02.00.000', alias_fp, '00.00.001', 'Alias property')), timestamp '2026-09-21 00:00:00'
from v2_fixture;
create temp table v2_neg_version as select pg_temp.v2_call(pg_temp.v2_batch()) as result;
select is((select result->>'code' from v2_neg_version), 'ALIAS_V2_CLOSURE_MISMATCH', 'a same-id second-version consumer is refused');
select ok(jsonb_array_length((select result#>'{details,live_flows}' from v2_neg_version)) = 2 and exists (
  select 1 from jsonb_array_elements((select result->'details' from v2_neg_version) -> 'live_flows') as live
  where live->>'id' = (select flow_id::text from v2_fixture)
    and live->>'version' = '02.00.000'
    and live->>'user_id' = (select actor::text from v2_fixture)
    and live->>'state_code' = '100'
) and exists (
  select 1 from jsonb_array_elements((select result->'details' from v2_neg_version) -> 'live_flows') as live
  where live->>'id' = (select flow_id::text from v2_fixture)
    and live->>'version' = '01.00.000'
    and live->>'user_id' = (select actor::text from v2_fixture)
    and live->>'state_code' = '0'
), 'the closure refusal retains both exact owner versions, including the published consumer');
delete from public.flows where id = (select flow_id from v2_fixture) and version = '02.00.000';

-- 1.11 a stored absolute uncertainty bound has no reviewed scaling and fails the closed key set
insert into public.flows (id, version, user_id, state_code, json_ordered, modified_at)
select uncertain_flow_id, '01.00.000', actor, 0,
  to_json(pg_temp.v2_flow(uncertain_flow_id, '01.00.000', alias_fp, '00.00.001', 'Alias property')), timestamp '2026-09-21 00:00:00'
from v2_fixture;
insert into public.processes (id, version, user_id, state_code, json_ordered, modified_at)
select uncertain_process_id, '01.00.000', actor, 0,
  to_json(pg_temp.v2_process(uncertain_process_id, '01.00.000', uncertain_flow_id, '01.00.000', 'Alias flow',
    jsonb_build_object('absoluteStandardDeviation95In', '0.1'))), timestamp '2026-09-21 00:00:00'
from v2_fixture;
create temp table v2_uncertain_batch as select pg_temp.v2_batch(jsonb_build_object(
  'flows', jsonb_build_array(pg_temp.v2_resign(jsonb_build_object(
    'action_id', 'flow-2', 'table', 'flows', 'id', (select uncertain_flow_id from v2_fixture), 'version', '01.00.000',
    'expected_state_code', 0,
    'expected_json_ordered', pg_temp.v2_flow((select uncertain_flow_id from v2_fixture), '01.00.000', (select alias_fp from v2_fixture), '00.00.001', 'Alias property'),
    'desired_json_ordered', pg_temp.v2_flow((select uncertain_flow_id from v2_fixture), '01.00.000', (select target_fp from v2_fixture), '01.00.000', 'Time'),
    'before_sha256', repeat('0', 64), 'desired_sha256', repeat('0', 64),
    'source_flowproperty', jsonb_build_object('id', (select alias_fp from v2_fixture), 'version', '00.00.001'),
    'mutation', jsonb_build_object('reference', pg_temp.v2_ref('flowproperties', 'flow property data set', (select target_fp from v2_fixture), '01.00.000', 'Time'))))),
  'processes', jsonb_build_array(pg_temp.v2_resign(jsonb_build_object(
    'action_id', 'process-2', 'table', 'processes', 'id', (select uncertain_process_id from v2_fixture), 'version', '01.00.000',
    'expected_state_code', 0,
    'expected_json_ordered', pg_temp.v2_process((select uncertain_process_id from v2_fixture), '01.00.000', (select uncertain_flow_id from v2_fixture), '01.00.000', 'Alias flow',
      jsonb_build_object('absoluteStandardDeviation95In', '0.1')),
    'desired_json_ordered', pg_temp.v2_process((select uncertain_process_id from v2_fixture), '01.00.000', (select uncertain_flow_id from v2_fixture), '01.00.000', 'Alias flow',
      jsonb_build_object('absoluteStandardDeviation95In', '0.1')),
    'before_sha256', repeat('0', 64), 'desired_sha256', repeat('0', 64),
    'quantitative_reference', '1',
    'mutation', jsonb_build_object('exchanges', jsonb_build_array(jsonb_build_object(
      'index', 0, 'internal_id', '1', 'flow_id', (select uncertain_flow_id from v2_fixture), 'flow_version', '01.00.000',
      'direction', 'Output', 'before_amount', '1',
      'after_amount', private.dataset_alias_v2_multiply_amount('1', private.dataset_alias_v2_factor()::text),
      'before_resulting_amount', '1',
      'after_resulting_amount', private.dataset_alias_v2_multiply_amount('1', private.dataset_alias_v2_factor()::text))))))))
) as batch;
select is(
  (pg_temp.v2_call((select batch from v2_uncertain_batch)) ->> 'code'),
  'ALIAS_V2_DERIVE_MISMATCH',
  'a stored absolute uncertainty bound fails the closed exchange key set'
);
delete from public.processes where id = (select uncertain_process_id from v2_fixture);
delete from public.flows where id = (select uncertain_flow_id from v2_fixture);

-- 1.12 a reference exchange whose own source quantity is 5 cannot carry a "1.0 a" functional unit even
-- though the anchored spelling rule alone would accept the text
create temp table v2_mismatch_payload as
  select jsonb_set(jsonb_set(
      pg_temp.v2_process(mismatch_process_id, '01.00.000', flow_id, '01.00.000', 'Alias flow'),
      '{processDataSet,exchanges,exchange,0,meanAmount}', '"5"'::jsonb),
    '{processDataSet,exchanges,exchange,0,resultingAmount}', '"5"'::jsonb) as payload
  from v2_fixture;
insert into public.processes (id, version, user_id, state_code, json_ordered, modified_at)
select mismatch_process_id, '01.00.000', actor, 0, to_json(payload), timestamp '2026-09-21 00:00:00'
from v2_fixture, v2_mismatch_payload;
create temp table v2_mismatch_batch as
  select pg_temp.v2_batch(jsonb_build_object(
    'processes', jsonb_build_array(pg_temp.v2_resign(jsonb_build_object(
      'action_id', 'process-mismatch', 'table', 'processes', 'id', (select mismatch_process_id from v2_fixture), 'version', '01.00.000',
      'expected_state_code', 0,
      'expected_json_ordered', (select payload from v2_mismatch_payload),
      'desired_json_ordered', jsonb_set(
        jsonb_set(
          jsonb_set(
            jsonb_set(
              jsonb_set((select payload from v2_mismatch_payload),
                '{processDataSet,exchanges,exchange,0,meanAmount}', to_jsonb(private.dataset_alias_v2_multiply_amount('5', private.dataset_alias_v2_factor()::text)), false),
              '{processDataSet,exchanges,exchange,0,resultingAmount}', to_jsonb(private.dataset_alias_v2_multiply_amount('5', private.dataset_alias_v2_factor()::text)), false),
            '{processDataSet,exchanges,exchange,1,meanAmount}', to_jsonb(private.dataset_alias_v2_multiply_amount('1.03E-4', private.dataset_alias_v2_factor()::text)), false),
          '{processDataSet,exchanges,exchange,1,resultingAmount}', to_jsonb(private.dataset_alias_v2_multiply_amount('1.03E-4', private.dataset_alias_v2_factor()::text)), false),
        '{processDataSet,processInformation,quantitativeReference,functionalUnitOrOther,#text}', to_jsonb('1.0 hr per unit'::text), false),
      'before_sha256', repeat('0', 64), 'desired_sha256', repeat('0', 64),
      'quantitative_reference', '1',
      'mutation', jsonb_build_object('exchanges', jsonb_build_array(
        jsonb_build_object(
          'index', 0, 'internal_id', '1', 'flow_id', (select flow_id from v2_fixture), 'flow_version', '01.00.000',
          'direction', 'Output', 'before_amount', '5',
          'after_amount', private.dataset_alias_v2_multiply_amount('5', private.dataset_alias_v2_factor()::text),
          'before_resulting_amount', '5',
          'after_resulting_amount', private.dataset_alias_v2_multiply_amount('5', private.dataset_alias_v2_factor()::text)),
        jsonb_build_object(
          'index', 1, 'internal_id', '2', 'flow_id', (select flow_id from v2_fixture), 'flow_version', '01.00.000',
          'direction', 'Input', 'before_amount', '1.03E-4',
          'after_amount', private.dataset_alias_v2_multiply_amount('1.03E-4', private.dataset_alias_v2_factor()::text),
          'before_resulting_amount', '1.03E-4',
          'after_resulting_amount', private.dataset_alias_v2_multiply_amount('1.03E-4', private.dataset_alias_v2_factor()::text))))))),
    'text_actions', jsonb_build_array(jsonb_build_object(
      'table', 'processes', 'id', (select mismatch_process_id from v2_fixture), 'version', '01.00.000',
      'before_text', '1.0 a per unit', 'after_text', '1.0 hr per unit', 'source_exchange_number', '730048')))) as batch;
select is(
  (pg_temp.v2_call((select batch from v2_mismatch_batch)) ->> 'code')
    || ' / ' || (pg_temp.v2_call((select batch from v2_mismatch_batch)) ->> 'message'),
  'ALIAS_V2_TEXT_RULE_VIOLATION / The functional-unit quantity is not the reference exchange''s reviewed source quantity',
  'a functional-unit quantity that is not the reference exchange quantity is refused'
);
delete from public.processes where id = (select mismatch_process_id from v2_fixture);

-- 1.13 an extra live Process occurrence of a claimed Flow breaks the closure, for every owner and state
-- The clause under test is the global occurrence set, so each probe adds one Process that consumes a
-- claimed Flow and then removes it again. Every probe call runs inside a rolled-back subtransaction, so
-- a probe that applies leaves no row, audit or modified_at behind for the later sections.
create or replace function pg_temp.v2_call_rollback(p_batch jsonb)
returns jsonb language plpgsql as $$
declare
  v_result jsonb;
begin
  begin
    v_result := pg_temp.v2_call(p_batch);
    raise exception using errcode = 'P0002', message = 'occurrence probe rollback';
  exception
    when sqlstate 'P0002' then null;
  end;
  return v_result;
end
$$;

insert into public.processes (id, version, user_id, state_code, json_ordered, modified_at)
select 'bbbbbbbb-0000-4000-8000-000000000001', '01.00.000', foreign_actor, 0,
  to_json(pg_temp.v2_process('bbbbbbbb-0000-4000-8000-000000000001', '01.00.000', flow_id, '01.00.000', 'Alias flow')),
  timestamp '2026-09-21 00:00:00'
from v2_fixture;
create temp table v2_neg_occ_foreign as select pg_temp.v2_call_rollback(pg_temp.v2_batch()) as result;
select is((select result->>'code' from v2_neg_occ_foreign), 'ALIAS_V2_CLOSURE_MISMATCH',
  'a foreign owner-draft occurrence of a claimed Flow is refused');
select ok(exists (
  select 1 from jsonb_array_elements((select result->'details' from v2_neg_occ_foreign) -> 'live_occurrences') as live
  where live->>'process_id' = 'bbbbbbbb-0000-4000-8000-000000000001'
    and live->>'user_id' = (select foreign_actor::text from v2_fixture)
), 'the closure refusal names the foreign live occurrence');
delete from public.processes where id = 'bbbbbbbb-0000-4000-8000-000000000001';

insert into public.processes (id, version, user_id, state_code, json_ordered, modified_at)
select 'bbbbbbbb-0000-4000-8000-000000000002', '01.00.000', foreign_actor, 100,
  to_json(pg_temp.v2_process('bbbbbbbb-0000-4000-8000-000000000002', '01.00.000', flow_id, '01.00.000', 'Alias flow')),
  timestamp '2026-09-21 00:00:00'
from v2_fixture;
create temp table v2_neg_occ_published as select pg_temp.v2_call_rollback(pg_temp.v2_batch()) as result;
select is((select result->>'code' from v2_neg_occ_published), 'ALIAS_V2_CLOSURE_MISMATCH',
  'a published occurrence from another owner is refused');
delete from public.processes where id = 'bbbbbbbb-0000-4000-8000-000000000002';

insert into public.processes (id, version, user_id, state_code, json_ordered, modified_at)
select 'bbbbbbbb-0000-4000-8000-000000000003', '01.00.000', actor, 0,
  to_json(pg_temp.v2_process('bbbbbbbb-0000-4000-8000-000000000003', '01.00.000', flow_id, '01.00.000', 'Alias flow')),
  timestamp '2026-09-21 00:00:00'
from v2_fixture;
create temp table v2_neg_occ_own as select pg_temp.v2_call_rollback(pg_temp.v2_batch()) as result;
select is((select result->>'code' from v2_neg_occ_own), 'ALIAS_V2_CLOSURE_MISMATCH',
  'an unclaimed owner-draft occurrence of the same actor is refused');
delete from public.processes where id = 'bbbbbbbb-0000-4000-8000-000000000003';

-- The same Flow id at another version is not an occurrence of the claimed identity, and an unrelated
-- Process whose exchange collection is the singleton-object shape contributes none either: the closure
-- skips a row that cannot carry a claimed occurrence rather than expanding it.
insert into public.processes (id, version, user_id, state_code, json_ordered, modified_at)
select 'bbbbbbbb-0000-4000-8000-000000000004', '01.00.000', foreign_actor, 0,
  to_json(pg_temp.v2_process('bbbbbbbb-0000-4000-8000-000000000004', '01.00.000', flow_id, '99.99.999', 'Alias flow')),
  timestamp '2026-09-21 00:00:00'
from v2_fixture;
insert into public.processes (id, version, user_id, state_code, json_ordered, modified_at)
select 'bbbbbbbb-0000-4000-8000-000000000005', '01.00.000', foreign_actor, 0,
  jsonb_build_object('processDataSet', jsonb_build_object(
    'processInformation', jsonb_build_object(
      'dataSetInformation', jsonb_build_object('common:UUID', 'bbbbbbbb-0000-4000-8000-000000000005'),
      'quantitativeReference', jsonb_build_object('referenceToReferenceFlow', '1')),
    'exchanges', jsonb_build_object('exchange', jsonb_build_object(
      '@dataSetInternalID', '1',
      'meanAmount', '1',
      'resultingAmount', '1',
      'exchangeDirection', 'Input',
      'referenceToFlowDataSet', pg_temp.v2_ref('flows', 'flow data set',
        '99999999-9999-4999-8999-999999999999', '01.00.000', 'Other flow'))))),
  timestamp '2026-09-21 00:00:00'
from v2_fixture;
create temp table v2_neg_occ_outside as select pg_temp.v2_call_rollback(pg_temp.v2_batch()) as result;
select is((select result->>'code' from v2_neg_occ_outside), 'ALIAS_V2_BATCH_APPLIED',
  'a claimed Flow id at another version and a malformed unrelated collection are not occurrences');
delete from public.processes where id in ('bbbbbbbb-0000-4000-8000-000000000004', 'bbbbbbbb-0000-4000-8000-000000000005');

-- ================================================================================================
-- 2. A failure induced inside the write pass must roll back rows and audit alike.
-- ================================================================================================
create or replace function pg_temp.v2_fail_process_write()
returns trigger language plpgsql as $$
begin
  if current_setting('fixture.v2_write_fail', true) = 'on' then
    raise exception 'fixture-induced write-pass failure' using errcode = '23505';
  end if;
  return new;
end
$$;
create trigger v2_fail_process_write before update on public.processes
  for each row execute function pg_temp.v2_fail_process_write();
set local fixture.v2_write_fail = 'on';
create temp table v2_late as select pg_temp.v2_call(pg_temp.v2_batch()) as result;
set local fixture.v2_write_fail = 'off';
drop trigger v2_fail_process_write on public.processes;

select is((select result->>'code' from v2_late), 'ALIAS_V2_INTERNAL_ERROR', 'a write-pass failure is reported as an internal failure');
select is(
  (select json_ordered::jsonb from public.flows where id = (select flow_id from v2_fixture)),
  (select flow_payload from v2_before_state),
  'the already-updated flow row is rolled back by the write-pass failure'
);
select is(
  (select modified_at from public.flows where id = (select flow_id from v2_fixture)),
  (select flow_modified from v2_before_state),
  'the flow modified_at is untouched by the write-pass failure'
);
select is(
  (select json_ordered::jsonb from public.processes where id = (select process_id from v2_fixture)),
  (select process_payload from v2_before_state),
  'the process row is untouched by the write-pass failure'
);
select is(
  (select count(*) from private.command_audit_log),
  (select audits from v2_before_state),
  'no audit row survives the write-pass failure'
);

-- ================================================================================================
-- 3. The real small success.
-- ================================================================================================
create temp table v2_first as select pg_temp.v2_call(pg_temp.v2_batch()) as result;
select is((select result->>'ok' from v2_first), 'true', 'a real small batch applies');
select is((select result->>'code' from v2_first), 'ALIAS_V2_BATCH_APPLIED', 'the applied code is returned');
select is((select result#>>'{counts,flow_count}' from v2_first), '1', 'one flow action is counted');
select is((select result#>>'{counts,exchange_count}' from v2_first), '2', 'both bound exchange occurrences are counted');
select is((select result#>>'{counts,amount_field_count}' from v2_first), '4', 'two amount fields per bound exchange are counted');
select is((select result#>>'{counts,unrelated_exchange_count}' from v2_first), '1', 'the unrelated complement is inside the selected process');
select is((select result#>>'{counts,text_action_count}' from v2_first), '1', 'one text action is counted');
select is(
  (select json_ordered::jsonb #>> '{flowDataSet,flowProperties,flowProperty,referenceToFlowPropertyDataSet,@refObjectId}' from public.flows where id = (select flow_id from v2_fixture)),
  (select target_fp::text from v2_fixture),
  'the flow now references the target property'
);
select is(
  (select json_ordered::jsonb #>> '{flowDataSet,flowProperties,flowProperty,referenceToFlowPropertyDataSet,@version}' from public.flows where id = (select flow_id from v2_fixture)),
  '01.00.000',
  'the derived reference carries the target version'
);
select is(
  (select json_ordered::jsonb #>> '{flowDataSet,flowProperties,flowProperty,referenceToFlowPropertyDataSet,@type}' from public.flows where id = (select flow_id from v2_fixture)),
  'flow property data set',
  'the derived reference keeps the deployed @type'
);
select is(
  (select json_ordered::jsonb #>> '{flowDataSet,flowProperties,flowProperty,referenceToFlowPropertyDataSet,@uri}' from public.flows where id = (select flow_id from v2_fixture)),
  '../flowproperties/' || (select target_fp::text from v2_fixture) || '.json',
  'the derived reference keeps the .json uri convention with the target id'
);
select is(
  (select jsonb_typeof(json_ordered::jsonb #> '{flowDataSet,flowProperties,flowProperty,referenceToFlowPropertyDataSet,common:shortDescription}') from public.flows where id = (select flow_id from v2_fixture)),
  'object',
  'the derived reference description is a single language object'
);
select is(
  (select json_ordered::jsonb #>> '{flowDataSet,flowProperties,flowProperty,referenceToFlowPropertyDataSet,common:shortDescription,#text}' from public.flows where id = (select flow_id from v2_fixture)),
  'Time',
  'the description is the target flow property''s own common:name text'
);
select is(
  (select json_ordered::jsonb #>> '{flowDataSet,flowInformation,quantitativeReference,referenceToReferenceFlowProperty}' from public.flows where id = (select flow_id from v2_fixture)),
  '1',
  'the internal quantitative-reference pointer never moves'
);
select is(
  (select json_ordered::jsonb #>> '{processDataSet,exchanges,exchange,0,meanAmount}' from public.processes where id = (select process_id from v2_fixture)),
  '0.00011415525114155251',
  'the reference output exchange (internal id 1, source 730045, quantity 1) moved by the fixed factor'
);
select is(
  (select json_ordered::jsonb #>> '{processDataSet,exchanges,exchange,0,generalComment}' from public.processes where id = (select process_id from v2_fixture)),
  'Reviewed source exchange 730045 (EcoSpold).',
  'the reviewed source tuple of the reference output survives the amount move'
);
select is(
  (select json_ordered::jsonb #>> '{processDataSet,exchanges,exchange,1,meanAmount}' from public.processes where id = (select process_id from v2_fixture)),
  '0.00000001175799086757990853',
  'the bound input exchange (internal id 2, source 730046) moved by the fixed factor'
);
select is(
  (select json_ordered::jsonb #>> '{processDataSet,exchanges,exchange,1,generalComment}' from public.processes where id = (select process_id from v2_fixture)),
  'Reviewed source exchange 730046 (EcoSpold).',
  'the second source tuple survives independently of the first'
);
select is(
  (select json_ordered::jsonb #>> '{processDataSet,exchanges,exchange,2,meanAmount}' from public.processes where id = (select process_id from v2_fixture)),
  '5',
  'the unrelated exchange amount is untouched'
);
select is(
  (select json_ordered::jsonb #>> '{processDataSet,processInformation,quantitativeReference,functionalUnitOrOther,#text}' from public.processes where id = (select process_id from v2_fixture)),
  '1.0 hr per unit',
  'the reviewed functional-unit leaf moved under the anchored rule'
);
select is(
  (select json_ordered::jsonb #>> '{processDataSet,processInformation,quantitativeReference,referenceToReferenceFlow}' from public.processes where id = (select process_id from v2_fixture)),
  '1',
  'the TIDAS internal reference-flow pointer never moves'
);
select ok(
  (select modified_at from public.flows where id = (select flow_id from v2_fixture)) > (select flow_modified from v2_before_state),
  'the applied row carries a fresh modified_at'
);
select is(
  (select count(*) from private.command_audit_log),
  (select audits + 3 from v2_before_state),
  'two row audit entries and one plan summary are written'
);
select ok(exists (
  select 1 from private.command_audit_log as audit_log
  where audit_log.command = 'cmd_dataset_alias_batch_v2_guarded'
    and audit_log.payload->>'record_type' = 'plan'
    and audit_log.payload->>'plan_sha256' = repeat('a', 64)
    and audit_log.payload#>>'{source_evidence,sha256}' = repeat('b', 64)
), 'the plan summary durably binds the source evidence digest');
create temp table v2_after_state as
  select (select modified_at from public.flows where id = (select flow_id from v2_fixture)) as flow_modified;

-- ================================================================================================
-- 4. Exact resubmission: the stored proof, zero writes.
-- ================================================================================================
create temp table v2_replay as select pg_temp.v2_call(pg_temp.v2_batch()) as result;
select is((select result->>'code' from v2_replay), 'ALIAS_V2_BATCH_REPLAYED', 'an exact resubmission reports the stored replay proof');
select is((select result->>'idempotent_replay' from v2_replay), 'true', 'the replay is flagged idempotent');
select is(
  (select count(*) from private.command_audit_log),
  (select audits + 3 from v2_before_state),
  'an exact replay writes no further audit row'
);
select is(
  (select modified_at from public.flows where id = (select flow_id from v2_fixture)),
  (select flow_modified from v2_after_state),
  'an exact replay leaves the applied rows untouched'
);
select is(
  (pg_temp.v2_call(jsonb_set(pg_temp.v2_batch(), '{source_evidence,sha256}', to_jsonb(repeat('c', 64)))) ->> 'code'),
  'ALIAS_V2_REPLAY_CONFLICT',
  'a resubmission carrying different source evidence is refused as a replay conflict'
);

-- ================================================================================================
-- 4b. Database #694: the row audit carries the canonical digest of what was actually written.
-- The executor no longer recomputes those two digests; it reuses the producer's claimed
-- before_sha256 / desired_sha256, which the untouched structural scan already proved equal to the
-- server's canonical digest of the claimed before payload and of the server-derived payload that is
-- committed. These assertions pin that equality against the live rows, so a future change that
-- stopped enforcing parity could never silently publish an unverified digest.
-- ================================================================================================
create temp table v2_audit_row as
  select audit_log.target_table,
         audit_log.payload->>'before_sha256' as before_sha256,
         audit_log.payload->>'after_sha256' as after_sha256
  from private.command_audit_log as audit_log
  where audit_log.command = 'cmd_dataset_alias_batch_v2_guarded'
    and audit_log.actor_user_id = (select actor from v2_fixture)
    and audit_log.payload->>'record_type' = 'row'
    and audit_log.payload->>'plan_sha256' = pg_temp.v2_batch()->>'plan_sha256';

select is((select count(*) from v2_audit_row), 2::bigint, 'the applied plan wrote exactly one row audit per action');
select is(
  (select before_sha256 from v2_audit_row where target_table = 'flows'),
  private.dataset_alias_v2_payload_sha256(pg_temp.v2_batch()->'actions'->0->'expected_json_ordered'),
  'the flow row audit records the canonical digest of its claimed before payload');
select is(
  (select after_sha256 from v2_audit_row where target_table = 'flows'),
  private.dataset_alias_v2_payload_sha256((select json_ordered::jsonb from public.flows where id = (select flow_id from v2_fixture))),
  'the flow row audit records the canonical digest of the payload actually written');
select is(
  (select before_sha256 from v2_audit_row where target_table = 'processes'),
  private.dataset_alias_v2_payload_sha256(pg_temp.v2_batch()->'actions'->1->'expected_json_ordered'),
  'the process row audit records the canonical digest of its claimed before payload');
select is(
  (select after_sha256 from v2_audit_row where target_table = 'processes'),
  private.dataset_alias_v2_payload_sha256((select json_ordered::jsonb from public.processes where id = (select process_id from v2_fixture))),
  'the process row audit records the canonical digest of the payload actually written');

-- ================================================================================================
-- 4c. The parity guard the #694 reuse depends on is untouched: a well-formed but wrong claimed
-- digest — the other action's own digest, which passes every shape check — is still refused, and
-- the refusal writes nothing at all.
-- ================================================================================================
create temp table v2_before_tamper as
  select
    (select count(*) from private.command_audit_log) as audits,
    (select json_ordered::jsonb from public.flows where id = (select flow_id from v2_fixture)) as flow_payload,
    (select json_ordered::jsonb from public.processes where id = (select process_id from v2_fixture)) as process_payload;

select is(
  (pg_temp.v2_call(jsonb_set(pg_temp.v2_batch(), '{actions,0,before_sha256}',
    to_jsonb(pg_temp.v2_batch() #>> '{actions,1,before_sha256}'))) ->> 'code'),
  'ALIAS_V2_DERIVE_MISMATCH',
  'a well-formed before digest belonging to another action is refused as a parity mismatch');
select is(
  (pg_temp.v2_call(jsonb_set(pg_temp.v2_batch(), '{actions,1,desired_sha256}',
    to_jsonb(pg_temp.v2_batch() #>> '{actions,0,desired_sha256}'))) ->> 'code'),
  'ALIAS_V2_DERIVE_MISMATCH',
  'a well-formed desired digest belonging to another action is refused as a parity mismatch');
select is(
  (select count(*) from private.command_audit_log),
  (select audits from v2_before_tamper),
  'a tampered claimed digest writes no audit row');
select is(
  (select json_ordered::jsonb from public.flows where id = (select flow_id from v2_fixture)),
  (select flow_payload from v2_before_tamper),
  'a tampered claimed digest leaves the flow row unchanged');
select is(
  (select json_ordered::jsonb from public.processes where id = (select process_id from v2_fixture)),
  (select process_payload from v2_before_tamper),
  'a tampered claimed digest leaves the process row unchanged');


-- ================================================================================================
-- 4a. The support reference boundary: a support row is readable only when it is published or owned by
-- the authenticated plan actor, so a foreign owner-draft row with byte-identical JSON is refused
-- before any digest comparison.
-- ================================================================================================
set local session_replication_role = replica;
update public.flowproperties set user_id = (select foreign_actor from v2_fixture)
where id = (select target_fp from v2_fixture);
set local session_replication_role = origin;
select is(
  (pg_temp.v2_call(pg_temp.v2_batch())->>'code'),
  'ALIAS_V2_EVIDENCE_MISMATCH',
  'a foreign owner-draft target flow property is refused even though its payload is unchanged'
);
set local session_replication_role = replica;
update public.flowproperties set user_id = (select actor from v2_fixture)
where id = (select target_fp from v2_fixture);
update public.unitgroups set user_id = (select foreign_actor from v2_fixture)
where id = (select target_ug from v2_fixture);
set local session_replication_role = origin;
select is(
  (pg_temp.v2_call(pg_temp.v2_batch())->>'code'),
  'ALIAS_V2_EVIDENCE_MISMATCH',
  'a foreign owner-draft target unit group is refused'
);
set local session_replication_role = replica;
update public.unitgroups set user_id = (select actor from v2_fixture)
where id = (select target_ug from v2_fixture);
update public.unitgroups set user_id = (select foreign_actor from v2_fixture)
where id = (select source_ug from v2_fixture);
set local session_replication_role = origin;
select is(
  (pg_temp.v2_call(pg_temp.v2_batch())->>'code'),
  'ALIAS_V2_EVIDENCE_MISMATCH',
  'a foreign owner-draft source unit group is refused'
);
set local session_replication_role = replica;
update public.unitgroups set user_id = (select actor from v2_fixture)
where id = (select source_ug from v2_fixture);
update public.flowproperties set user_id = (select foreign_actor from v2_fixture)
where id = (select alias_fp from v2_fixture);
set local session_replication_role = origin;
select is(
  (pg_temp.v2_call(pg_temp.v2_batch())->>'code'),
  'ALIAS_V2_EVIDENCE_MISMATCH',
  'a foreign owner-draft source flow property is refused'
);
-- A published support row is readable by any actor: the whole support set goes public.
set local session_replication_role = replica;
update public.flowproperties set user_id = (select foreign_actor from v2_fixture), state_code = 100
where id in ((select target_fp from v2_fixture), (select alias_fp from v2_fixture));
update public.unitgroups set user_id = (select foreign_actor from v2_fixture), state_code = 100
where id in ((select target_ug from v2_fixture), (select source_ug from v2_fixture));
set local session_replication_role = origin;
select is(
  (pg_temp.v2_call(pg_temp.v2_batch())->>'ok'),
  'true',
  'published support rows stay readable: the batch applies over a fully public support set'
);
set local session_replication_role = replica;
update public.flowproperties set user_id = (select actor from v2_fixture), state_code = 0
where id in ((select target_fp from v2_fixture), (select alias_fp from v2_fixture));
update public.unitgroups set user_id = (select actor from v2_fixture), state_code = 0
where id in ((select target_ug from v2_fixture), (select source_ug from v2_fixture));
set local session_replication_role = origin;
select is(
  (pg_temp.v2_call(pg_temp.v2_batch())->>'ok'),
  'true',
  'the owner-draft support set is readable again after the public case'
);

-- ================================================================================================
-- 4b2. The derivative orchestration is one unit of work: a refused sub-batch leaves no child behind.
-- ================================================================================================
select is(
  (util.admit_dataset_alias_v2_derivative_chunks(
     (select actor from v2_fixture),
     'dddddddd-dddd-4ddd-8ddd-dddddddddddd'::uuid,
     repeat('f', 64),
     repeat('f', 64),
     'PROTECTED_ALIAS_DERIVATIVE_CLOSURE',
     jsonb_build_array(
       jsonb_build_object('table', 'flows', 'id', (select flow_id from v2_fixture), 'version', '01.00.000',
         'expected_json_ordered_sha256', repeat('3', 64), 'baseline_snapshot_sha256', repeat('1', 64)),
       jsonb_build_object('table', 'processes', 'id', (select process_id from v2_fixture), 'version', '01.00.000',
         'expected_json_ordered_sha256', repeat('4', 64), 'baseline_snapshot_sha256', repeat('2', 64))
     ))->>'ok'),
  'false',
  'a derivative sub-batch whose targets do not match the live rows is refused as a whole'
);
select is(
  (select count(*)::integer from util.dataset_derivative_rebuild_requests
    where batch_id = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd'::uuid),
  0,
  'no derivative child survives a refused orchestration'
);

-- ================================================================================================
-- 4b. The shared functional-unit grammar, literally: quantity 1 or 1.0, one ASCII space, the unit token
-- `a`, then a suffix that starts with an ASCII space, carries at least one non-space/non-tab character
-- and holds no CR or LF, matched against the whole string.
-- ================================================================================================
select is(private.dataset_alias_v2_fu_apply_rule('1 a x'), '1 hr x', 'the reviewed form moves the unit token and keeps the suffix');
select is(private.dataset_alias_v2_fu_apply_rule('1.0 a per unit'), '1.0 hr per unit', 'a one-space suffix survives byte for byte');
select is(private.dataset_alias_v2_fu_apply_rule('1.0 a  two spaces'), '1.0 hr  two spaces', 'a suffix may start with several spaces as long as one character is not a space');
select is(private.dataset_alias_v2_fu_apply_rule('1.0 a x  '), '1.0 hr x  ', 'trailing spaces inside the suffix survive');
select is(private.dataset_alias_v2_fu_apply_rule('1.0 a'), null, 'an empty suffix is refused');
select is(private.dataset_alias_v2_fu_apply_rule('1.0 a '), null, 'a whitespace-only suffix is refused');
select is(private.dataset_alias_v2_fu_apply_rule('1.0 a2'), null, 'a glued unit token is refused');
select is(private.dataset_alias_v2_fu_apply_rule(e'1.0 a\tx'), null, 'a tab separator is refused');
select is(private.dataset_alias_v2_fu_apply_rule(e'1.0 a x\ny'), null, 'a suffix spanning lines is refused');
select is(private.dataset_alias_v2_fu_apply_rule(e'1.0 a x\r'), null, 'a trailing carriage return is refused');

-- ================================================================================================
-- 5. The plan executor: the shared plan envelope, its single time dimension and its whole-plan proof.
-- ================================================================================================
create or replace function pg_temp.v2_plan(p_extras jsonb default '{}'::jsonb)
returns jsonb language plpgsql stable as $$
declare
  f record;
  b jsonb;
  v_targets jsonb;
  v_plan jsonb;
  v_plan_sha256 text;
begin
  select * into f from v2_fixture;
  b := pg_temp.v2_batch(coalesce(p_extras->'batch', '{}'::jsonb));
  -- One six-key derivative target per changed action identity, with the frozen before content digest as the
  -- derived baseline snapshot and the exact actor/owner-draft state.
  select coalesce(jsonb_agg(jsonb_build_object(
      'table', a->>'table', 'id', a->>'id', 'version', a->>'version',
      'user_id', f.actor, 'state_code', 0,
      'baseline_snapshot_sha256', a->>'before_sha256')
    order by a->>'id', a->>'version'), '[]'::jsonb)
    into v_targets
  from jsonb_array_elements(b->'actions') as a;
  v_plan := jsonb_build_object(
    'schema_version', 'dataset-alias-plan.v2',
    'actor_id', f.actor,
    'target_visibility', 'owner_draft',
    -- The producer binds the alias IDENTITY: its digest is the canonical hash of the {id, version}
    -- tuple, not of the alias row's payload.
    'source_alias', jsonb_build_object('id', f.alias_fp, 'version', '00.00.001',
      'sha256', private.dataset_alias_v2_payload_sha256(
        jsonb_build_object('id', f.alias_fp, 'version', '00.00.001'))),
    'source_evidence', jsonb_build_object(
      'sha256', b#>>'{source_evidence,sha256}',
      'cohort_sha256', b#>>'{source_evidence,sha256}',
      'expected_cohort_sha256', b#>>'{source_evidence,sha256}',
      -- The external plan carries every count as a JSON number; the helper must emit the same wire
      -- shape or it would only prove the executor accepts a shape the real producer never sends.
      'exchange_count', b#>'{source_evidence,exchange_count}',
      'declared_source_unitgroup', b#>'{source_evidence,source_unitgroup}',
      'source_flowproperty', b#>'{source_evidence,source_flowproperty}',
      'original_source_unit', 'hr'),
    'target_snapshots', b->'target_snapshots',
    'expected', jsonb_build_object(
      'action_count', b#>'{counts,action_count}',
      'batch_count', 1,
      'exchange_count', b#>'{counts,exchange_count}',
      'amount_field_count', b#>'{counts,amount_field_count}',
      'unrelated_exchange_count', b#>'{counts,unrelated_exchange_count}',
      'audit_count', (b#>>'{counts,action_count}')::integer + 2,
      'flowproperty_count', b#>'{counts,flowproperty_count}',
      'flow_count', b#>'{counts,flow_count}',
      'process_count', b#>'{counts,process_count}',
      'derivative_target_count', jsonb_array_length(v_targets),
      'text_action_count', jsonb_array_length(b->'text_actions')),
    'dimensions', jsonb_build_array(jsonb_build_object(
      'dimension', 'time',
      'factor', b->>'factor',
      'declared_source_unitgroup', jsonb_build_object('id', f.source_ug, 'version', '01.00.000'),
      'target_unitgroup', jsonb_build_object('id', f.target_ug, 'version', '01.00.000'))),
    'text_actions', b->'text_actions',
    'actions', b->'actions',
    'plan_sha256', repeat('a', 64));

  -- The producer's own convention: the plan digest is the canonical hash of the document minus its own
  -- binding, which the executor now verifies before it looks up any replay.
  v_plan_sha256 := util.dataset_alias_execution_v2_artifact_sha256(v_plan - 'plan_sha256');
  return jsonb_set(v_plan, '{plan_sha256}', to_jsonb(v_plan_sha256));
end
$$;

-- A mutated plan document must re-declare its own canonical digest before the executor can judge it:
-- the digest check deliberately runs before every other plan check, so a document edited after signing
-- is refused as a different plan.
create or replace function pg_temp.v2_plan_signed(p_plan jsonb)
returns jsonb language sql stable as $$
  select jsonb_set(p_plan, '{plan_sha256}',
    to_jsonb(util.dataset_alias_execution_v2_artifact_sha256(p_plan - 'plan_sha256')), false)
$$;

create or replace function pg_temp.v2_plan_call(p_plan jsonb)
returns jsonb language plpgsql as $$
begin
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config('request.jwt.claim.sub', (select actor::text from v2_fixture), true);
  perform set_config('request.jwt.claim.email', 'fixture@example.invalid', true);
  return private.cmd_dataset_alias_plan_v2_guarded(p_plan);
end
$$;

select is((pg_temp.v2_plan_call('{}'::jsonb) ->> 'code'), 'ALIAS_V2_PLAN_INVALID', 'an empty plan is refused with the frozen stable code');
select is(
  (pg_temp.v2_plan_call(jsonb_set(pg_temp.v2_plan(), '{actor_id}', to_jsonb((select foreign_actor::text from v2_fixture)))) ->> 'code'),
  'ALIAS_V2_PLAN_INVALID',
  'a plan bound to another actor is refused'
);
select is(
  (pg_temp.v2_plan_call(jsonb_set(pg_temp.v2_plan(), '{note}', '"x"'::jsonb)) ->> 'code'),
  'ALIAS_V2_PLAN_INVALID',
  'a plan with an unknown key is refused'
);
select is(
  (pg_temp.v2_plan_call(pg_temp.v2_plan_signed(jsonb_set(pg_temp.v2_plan(), '{expected,flowproperty_count}', '1'::jsonb))) ->> 'code'),
  'ALIAS_V2_COUNT_MISMATCH',
  'a plan claiming flow-property actions is refused'
);

select is(
  (pg_temp.v2_plan_call(pg_temp.v2_plan_signed(jsonb_set(pg_temp.v2_plan(), '{expected,audit_count}',
    to_jsonb(((pg_temp.v2_plan() #>> '{expected,audit_count}')::integer + 1))))) ->> 'code'),
  'ALIAS_V2_COUNT_MISMATCH',
  'an audit count that is not the written row+batch+plan topology is refused'
);
select is(
  (pg_temp.v2_plan_call(pg_temp.v2_plan_signed(jsonb_set(pg_temp.v2_plan(), '{expected,derivative_target_count}', '9'::jsonb))) ->> 'code'),
  'ALIAS_V2_COUNT_MISMATCH',
  'a declared derivative-target count that is not the unique changed identities is refused'
);
select is(
  (pg_temp.v2_plan_call(pg_temp.v2_plan_signed(jsonb_set(pg_temp.v2_plan(), '{expected}', (pg_temp.v2_plan()->'expected') #- '{text_action_count}'))) ->> 'code'),
  'ALIAS_V2_PLAN_INVALID',
  'an expected block without the versioned text-action count is refused'
);
select is(
  (pg_temp.v2_plan_call(pg_temp.v2_plan_signed(jsonb_set(pg_temp.v2_plan(), '{expected,action_count}', '"2"'::jsonb))) ->> 'code'),
  'ALIAS_V2_PLAN_INVALID',
  'a quoted expected count is refused because the external plan emits JSON numbers'
);
select is(
  (pg_temp.v2_plan_call(pg_temp.v2_plan_signed(jsonb_set(pg_temp.v2_plan(), '{source_evidence,exchange_count}', '"2"'::jsonb))) ->> 'code'),
  'ALIAS_V2_PLAN_INVALID',
  'a quoted source-evidence exchange count is refused as a different wire shape'
);
select is(
  (pg_temp.v2_plan_call(pg_temp.v2_plan_signed(jsonb_set(pg_temp.v2_plan(), '{source_evidence,cohort_sha256}', to_jsonb(repeat('d', 64))))) ->> 'code'),
  'ALIAS_V2_PLAN_INVALID',
  'a claimed cohort digest that is not the declared expected cohort digest is refused'
);
select is(
  (pg_temp.v2_plan_call(pg_temp.v2_plan_signed(jsonb_set(pg_temp.v2_plan(), '{source_alias,sha256}', '"not-a-digest"'::jsonb))) ->> 'code'),
  'ALIAS_V2_PLAN_INVALID',
  'a malformed source alias identity is refused'
);
select is(
  (pg_temp.v2_plan_call(pg_temp.v2_plan_signed(jsonb_set(pg_temp.v2_plan(), '{source_alias,sha256}',
    to_jsonb(private.dataset_alias_v2_payload_sha256(
      (select json_ordered::jsonb from public.flowproperties
        where id = (select alias_fp from v2_fixture) and version = '00.00.001')))))) ->> 'code'),
  'ALIAS_V2_EVIDENCE_MISMATCH',
  'an alias payload digest is refused: the producer binds the identity tuple, not the row payload'
);
select is(
  (pg_temp.v2_plan_call(pg_temp.v2_plan_signed(jsonb_set(pg_temp.v2_plan(), '{source_evidence,original_source_unit}', '""'::jsonb))) ->> 'code'),
  'ALIAS_V2_PLAN_INVALID',
  'a plan without the original source unit semantics is refused'
);

-- The plan section gets its own pristine consumer pair so the fresh and replay paths both run on real rows.
insert into public.flows (id, version, user_id, state_code, json_ordered, modified_at)
select uncertain_flow_id, '01.00.000', actor, 0,
  to_json(pg_temp.v2_flow(uncertain_flow_id, '01.00.000', alias_fp, '00.00.001', 'Alias property')), timestamp '2026-09-21 00:00:00'
from v2_fixture;
insert into public.processes (id, version, user_id, state_code, json_ordered, modified_at)
select uncertain_process_id, '01.00.000', actor, 0,
  to_json(pg_temp.v2_process(uncertain_process_id, '01.00.000', uncertain_flow_id, '01.00.000', 'Alias flow')), timestamp '2026-09-21 00:00:00'
from v2_fixture;

create temp table v2_plan_flow_action as select pg_temp.v2_resign(jsonb_build_object(
  'action_id', 'flow-3', 'table', 'flows', 'id', (select uncertain_flow_id from v2_fixture), 'version', '01.00.000',
  'expected_state_code', 0,
  'expected_json_ordered', pg_temp.v2_flow((select uncertain_flow_id from v2_fixture), '01.00.000', (select alias_fp from v2_fixture), '00.00.001', 'Alias property'),
  'desired_json_ordered', pg_temp.v2_flow((select uncertain_flow_id from v2_fixture), '01.00.000', (select target_fp from v2_fixture), '01.00.000', 'Time'),
  'before_sha256', repeat('0', 64), 'desired_sha256', repeat('0', 64),
  'source_flowproperty', jsonb_build_object('id', (select alias_fp from v2_fixture), 'version', '00.00.001'),
  'mutation', jsonb_build_object('reference', pg_temp.v2_ref('flowproperties', 'flow property data set', (select target_fp from v2_fixture), '01.00.000', 'Time')))) as action;
create temp table v2_plan_process_action as select pg_temp.v2_resign(jsonb_build_object(
  'action_id', 'process-3', 'table', 'processes', 'id', (select uncertain_process_id from v2_fixture), 'version', '01.00.000',
  'expected_state_code', 0,
  'expected_json_ordered', pg_temp.v2_process((select uncertain_process_id from v2_fixture), '01.00.000', (select uncertain_flow_id from v2_fixture), '01.00.000', 'Alias flow'),
  'desired_json_ordered', jsonb_set(
    jsonb_set(
      jsonb_set(
        jsonb_set(
          jsonb_set(
            pg_temp.v2_process((select uncertain_process_id from v2_fixture), '01.00.000', (select uncertain_flow_id from v2_fixture), '01.00.000', 'Alias flow'),
            '{processDataSet,exchanges,exchange,0,meanAmount}', to_jsonb(private.dataset_alias_v2_multiply_amount('1', private.dataset_alias_v2_factor()::text)), false),
          '{processDataSet,exchanges,exchange,0,resultingAmount}', to_jsonb(private.dataset_alias_v2_multiply_amount('1', private.dataset_alias_v2_factor()::text)), false),
        '{processDataSet,exchanges,exchange,1,meanAmount}', to_jsonb(private.dataset_alias_v2_multiply_amount('1.03E-4', private.dataset_alias_v2_factor()::text)), false),
      '{processDataSet,exchanges,exchange,1,resultingAmount}', to_jsonb(private.dataset_alias_v2_multiply_amount('1.03E-4', private.dataset_alias_v2_factor()::text)), false),
    '{processDataSet,processInformation,quantitativeReference,functionalUnitOrOther,#text}', to_jsonb('1.0 hr per unit'::text), false),
  'before_sha256', repeat('0', 64), 'desired_sha256', repeat('0', 64),
  'quantitative_reference', '1',
  'mutation', jsonb_build_object('exchanges', jsonb_build_array(
    jsonb_build_object(
      'index', 0, 'internal_id', '1', 'flow_id', (select uncertain_flow_id from v2_fixture), 'flow_version', '01.00.000',
      'direction', 'Output', 'before_amount', '1',
      'after_amount', private.dataset_alias_v2_multiply_amount('1', private.dataset_alias_v2_factor()::text),
      'before_resulting_amount', '1',
      'after_resulting_amount', private.dataset_alias_v2_multiply_amount('1', private.dataset_alias_v2_factor()::text)),
    jsonb_build_object(
      'index', 1, 'internal_id', '2', 'flow_id', (select uncertain_flow_id from v2_fixture), 'flow_version', '01.00.000',
      'direction', 'Input', 'before_amount', '1.03E-4',
      'after_amount', private.dataset_alias_v2_multiply_amount('1.03E-4', private.dataset_alias_v2_factor()::text),
      'before_resulting_amount', '1.03E-4',
      'after_resulting_amount', private.dataset_alias_v2_multiply_amount('1.03E-4', private.dataset_alias_v2_factor()::text)))))) as action;
create temp table v2_plan_fixture as select pg_temp.v2_plan(jsonb_build_object('batch', jsonb_build_object(
  'include_base', false,
  'plan_sha256', repeat('e', 64),
  'flows', jsonb_build_array((select action from v2_plan_flow_action)),
  'processes', jsonb_build_array((select action from v2_plan_process_action)),
  'text_actions', jsonb_build_array(jsonb_build_object(
    'table', 'processes', 'id', (select uncertain_process_id from v2_fixture), 'version', '01.00.000',
    'before_text', '1.0 a per unit', 'after_text', '1.0 hr per unit', 'source_exchange_number', '730045'))
))) as plan;

create temp table v2_plan_first as select pg_temp.v2_plan_call((select plan from v2_plan_fixture)) as result;
select is((select result->>'ok' from v2_plan_first) || ' / ' || (select result->>'code' from v2_plan_first), 'true / ALIAS_V2_PLAN_APPLIED', 'the single-dimension plan with zero flow-property actions applies');
select is((select result#>>'{counts,action_count}' from v2_plan_first) || '/' || (select result#>>'{counts,text_action_count}' from v2_plan_first), '2/1', 'the plan echoes its action and text-action counts');
select ok(
  (select json_ordered::jsonb #>> '{flowDataSet,flowProperties,flowProperty,referenceToFlowPropertyDataSet,@refObjectId}' from public.flows where id = (select uncertain_flow_id from v2_fixture))
    = (select target_fp::text from v2_fixture),
  'the plan moved the flow reference to the locked target'
);
create temp table v2_plan_audits as select (select count(*) from private.command_audit_log) as audits;
create temp table v2_plan_replay as select pg_temp.v2_plan_call((select plan from v2_plan_fixture)) as result;
select is((select result->>'code' from v2_plan_replay) || '/' || (select result->>'idempotent_replay' from v2_plan_replay), 'ALIAS_V2_PLAN_REPLAYED/true', 'an exact plan resubmission returns the stored proof');
select is(
  (select count(*) from private.command_audit_log),
  (select audits from v2_plan_audits),
  'an exact plan resubmission writes nothing'
);
select ok(exists (
  select 1 from private.command_audit_log as audit_log
  where audit_log.command = 'cmd_dataset_alias_plan_v2_guarded'
    and audit_log.payload->>'record_type' = 'plan_summary'
    and audit_log.payload->>'plan_request_sha256' =
      encode(extensions.digest(convert_to((select plan from v2_plan_fixture)::text, 'UTF8'), 'sha256'), 'hex')
), 'the plan summary is bound to the server digest of the submitted plan text');
select is(
  (pg_temp.v2_plan_call(pg_temp.v2_plan_signed(jsonb_set((select plan from v2_plan_fixture), '{actions,1,mutation,exchanges,0,flow_id}', to_jsonb((select flow_id::text from v2_fixture))))) ->> 'code'),
  'ALIAS_V2_BATCH_INVALID',
  'a plan leaf refusal passes through with the batch code unchanged'
);
select is(
  (pg_temp.v2_plan_call(pg_temp.v2_plan()) ->> 'code') || ' / ' || (pg_temp.v2_plan_call(pg_temp.v2_plan()) ->> 'message'),
  'ALIAS_V2_REPLAY_UNPROVEN / A desired-state row has no committed audit proof',
  'a plan resubmitted under an identity whose rows were applied without its audit chain is refused, never re-attested'
);
delete from public.processes where id = (select uncertain_process_id from v2_fixture);
delete from public.flows where id = (select uncertain_flow_id from v2_fixture);

-- ================================================================================================
-- 5. The target flow property's unit-group reference identity: the pointer must name the declared unit
-- group by id, exact version and kind. The batch document is rebuilt from the live rows after each
-- mutation, so every declared digest is self-hashed and only the pointer comparison can refuse a
-- relation that names another version or another kind. The fixture row is restored afterwards.
-- ================================================================================================
create temp table v2_target_pointer on commit drop as
  select json_ordered::jsonb as payload
  from public.flowproperties
  where id = (select target_fp from v2_fixture);

update public.flowproperties
set json_ordered = jsonb_set(
      json_ordered::jsonb,
      '{flowPropertyDataSet,flowPropertiesInformation,quantitativeReference,referenceToReferenceUnitGroup,@version}',
      to_jsonb('99.99.999'::text))::json
where id = (select target_fp from v2_fixture);
create temp table v2_pointer_version_plan on commit drop as select pg_temp.v2_batch() as b;
select is(
  (pg_temp.v2_call((select b from v2_pointer_version_plan)) ->> 'code'),
  'ALIAS_V2_FACTOR_UNSUPPORTED',
  'a target property pointing at another unit-group version refuses before any write'
);
update public.flowproperties
set json_ordered = (select payload from v2_target_pointer)::json
where id = (select target_fp from v2_fixture);

update public.flowproperties
set json_ordered = jsonb_set(
      json_ordered::jsonb,
      '{flowPropertyDataSet,flowPropertiesInformation,quantitativeReference,referenceToReferenceUnitGroup,@type}',
      to_jsonb('flow property data set'::text))::json
where id = (select target_fp from v2_fixture);
create temp table v2_pointer_kind_plan on commit drop as select pg_temp.v2_batch() as b;
select is(
  (pg_temp.v2_call((select b from v2_pointer_kind_plan)) ->> 'code'),
  'ALIAS_V2_FACTOR_UNSUPPORTED',
  'a target property whose reference kind is not a unit group data set refuses before any write'
);
update public.flowproperties
set json_ordered = (select payload from v2_target_pointer)::json
where id = (select target_fp from v2_fixture);

select * from finish();
rollback;
