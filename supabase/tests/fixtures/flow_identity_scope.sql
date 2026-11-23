create or replace function pg_temp.flow_identity_id(p_kind text)
returns uuid
language sql
immutable
as $$
  select (case p_kind
    when 'owner' then 'f1000000-0000-4000-8000-000000000001'
    when 'other' then 'f1000000-0000-4000-8000-000000000002'
    when 'unitgroup' then 'f2000000-0000-4000-8000-000000000001'
    when 'flowproperty' then 'f3000000-0000-4000-8000-000000000001'
    when 'source_flow' then 'f4000000-0000-4000-8000-000000000001'
    when 'target_flow' then 'f4000000-0000-4000-8000-000000000002'
    when 'pending_flow' then 'f4000000-0000-4000-8000-000000000003'
    when 'process' then 'f5000000-0000-4000-8000-000000000001'
    when 'process_2' then 'f5000000-0000-4000-8000-000000000002'
  end)::uuid
$$;

create or replace function pg_temp.flow_identity_orphan_id(p_ordinal integer)
returns uuid
language sql
immutable
strict
as $$
  select ('e0000000-0000-4000-8000-' ||
    lpad(p_ordinal::text, 12, '0'))::uuid
$$;

create or replace function pg_temp.flow_identity_reference(
  p_id uuid,
  p_version text,
  p_name text
) returns jsonb
language sql
immutable
as $$
  select jsonb_build_object(
    '@refObjectId', p_id,
    '@type', 'flow data set',
    '@uri', '../flows/' || p_id::text || '_' || p_version || '.xml',
    '@version', p_version,
    'common:shortDescription', jsonb_build_object(
      '@xml:lang', 'en', '#text', p_name
    )
  )
$$;

create or replace function pg_temp.flow_identity_unitgroup_payload()
returns jsonb
language sql
immutable
as $$
  select jsonb_build_object(
    'unitGroupDataSet', jsonb_build_object(
      'unitGroupInformation', jsonb_build_object(
        'dataSetInformation', jsonb_build_object(
          'common:UUID', pg_temp.flow_identity_id('unitgroup'),
          'common:name', jsonb_build_object('#text', 'kg')
        ),
        'quantitativeReference', jsonb_build_object(
          'referenceToReferenceUnit', '1'
        )
      ),
      'units', jsonb_build_object('unit', jsonb_build_array(
        jsonb_build_object(
          '@dataSetInternalID', '1', 'meanValue', '1', 'name', 'kg'
        )
      )),
      'administrativeInformation', jsonb_build_object(
        'publicationAndOwnership', jsonb_build_object(
          'common:dataSetVersion', '01.00.000'
        )
      )
    )
  )
$$;

create or replace function pg_temp.flow_identity_flowproperty_payload()
returns jsonb
language sql
immutable
as $$
  select jsonb_build_object(
    'flowPropertyDataSet', jsonb_build_object(
      'flowPropertiesInformation', jsonb_build_object(
        'dataSetInformation', jsonb_build_object(
          'common:UUID', pg_temp.flow_identity_id('flowproperty'),
          'common:name', jsonb_build_object('#text', 'Mass')
        ),
        'quantitativeReference', jsonb_build_object(
          'referenceToReferenceUnitGroup', jsonb_build_object(
            '@refObjectId', pg_temp.flow_identity_id('unitgroup'),
            '@type', 'unit group data set',
            '@uri', '../unitgroups/' ||
              pg_temp.flow_identity_id('unitgroup')::text || '_01.00.000.xml',
            '@version', '01.00.000',
            'common:shortDescription', jsonb_build_object('#text', 'kg')
          )
        )
      ),
      'administrativeInformation', jsonb_build_object(
        'publicationAndOwnership', jsonb_build_object(
          'common:dataSetVersion', '01.00.000'
        )
      )
    )
  )
$$;

create or replace function pg_temp.flow_identity_flow_payload(
  p_id uuid,
  p_name text
) returns jsonb
language sql
immutable
as $$
  select jsonb_build_object(
    'flowDataSet', jsonb_build_object(
      'flowInformation', jsonb_build_object(
        'dataSetInformation', jsonb_build_object(
          'common:UUID', p_id,
          'name', jsonb_build_object('baseName', jsonb_build_object(
            '@xml:lang', 'en', '#text', p_name
          )),
          'classificationInformation', jsonb_build_object(
            'common:classification', jsonb_build_object(
              'common:class', jsonb_build_object(
                '@level', '0', '@classId', 'emissions', '#text', 'Emissions'
              )
            )
          )
        ),
        'quantitativeReference', jsonb_build_object(
          'referenceToReferenceFlowProperty', '1'
        )
      ),
      'modellingAndValidation', jsonb_build_object(
        'LCIMethod', jsonb_build_object('typeOfDataSet', 'Elementary flow')
      ),
      'flowProperties', jsonb_build_object(
        'flowProperty', jsonb_build_object(
          '@dataSetInternalID', '1',
          'meanValue', '1',
          'referenceToFlowPropertyDataSet', jsonb_build_object(
            '@refObjectId', pg_temp.flow_identity_id('flowproperty'),
            '@type', 'flow property data set',
            '@uri', '../flowproperties/' ||
              pg_temp.flow_identity_id('flowproperty')::text ||
              '_01.00.000.xml',
            '@version', '01.00.000',
            'common:shortDescription', jsonb_build_object('#text', 'Mass')
          )
        )
      ),
      'administrativeInformation', jsonb_build_object(
        'publicationAndOwnership', jsonb_build_object(
          'common:dataSetVersion', '01.00.000'
        )
      )
    )
  )
$$;

create or replace function pg_temp.flow_identity_process_payload(
  p_after boolean default false,
  p_process_id uuid default null
) returns jsonb
language sql
immutable
as $$
  select jsonb_build_object(
    'processDataSet', jsonb_build_object(
      'processInformation', jsonb_build_object(
        'dataSetInformation', jsonb_build_object(
          'common:UUID', coalesce(
            p_process_id, pg_temp.flow_identity_id('process')
          ),
          'name', jsonb_build_object('baseName', jsonb_build_object(
            '@xml:lang', 'en', '#text', 'Step 3 test process'
          ))
        )
      ),
      'exchanges', jsonb_build_object('exchange', jsonb_build_array(
        jsonb_build_object(
          '@dataSetInternalID', '1',
          'exchangeDirection', 'Input',
          'meanAmount', '5',
          'resultingAmount', '5',
          'generalComment', jsonb_build_object('#text', 'preserve me'),
          'referenceToFlowDataSet', case when p_after
            then pg_temp.flow_identity_reference(
              pg_temp.flow_identity_id('target_flow'),
              '01.00.000', 'Public target'
            )
            else pg_temp.flow_identity_reference(
              pg_temp.flow_identity_id('source_flow'),
              '01.00.000', 'Owner source'
            )
          end
        ),
        jsonb_build_object(
          '@dataSetInternalID', '2',
          'exchangeDirection', 'Output',
          'meanAmount', '7',
          'resultingAmount', '7',
          'referenceToFlowDataSet', pg_temp.flow_identity_reference(
            pg_temp.flow_identity_id('target_flow'),
            '01.00.000', 'Public target'
          )
        ),
        jsonb_build_object(
          '@dataSetInternalID', '3',
          'exchangeDirection', 'Input',
          'meanAmount', '11',
          'resultingAmount', '11',
          'referenceToFlowDataSet', pg_temp.flow_identity_reference(
            pg_temp.flow_identity_id('pending_flow'),
            '01.00.000', 'Protected pending'
          )
        )
      )),
      'administrativeInformation', jsonb_build_object(
        'publicationAndOwnership', jsonb_build_object(
          'common:dataSetVersion', '01.00.000'
        )
      )
    )
  )
$$;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at, is_sso_user, is_anonymous
) values
  (
    '00000000-0000-0000-0000-000000000000',
    pg_temp.flow_identity_id('owner'), 'authenticated', 'authenticated',
    'flow-owner@example.com', 'test-password-hash', now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object('sub', pg_temp.flow_identity_id('owner')), now(), now(),
    false, false
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    pg_temp.flow_identity_id('other'), 'authenticated', 'authenticated',
    'flow-other@example.com', 'test-password-hash', now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object('sub', pg_temp.flow_identity_id('other')), now(), now(),
    false, false
  );

insert into public.unitgroups (
  id, version, user_id, state_code, json, json_ordered, modified_at
) values (
  pg_temp.flow_identity_id('unitgroup'), '01.00.000',
  pg_temp.flow_identity_id('other'), 100,
  pg_temp.flow_identity_unitgroup_payload(),
  pg_temp.flow_identity_unitgroup_payload()::json,
  '2026-07-16T01:00:00Z'
);

insert into public.flowproperties (
  id, version, user_id, state_code, json, json_ordered, modified_at
) values (
  pg_temp.flow_identity_id('flowproperty'), '01.00.000',
  pg_temp.flow_identity_id('other'), 100,
  pg_temp.flow_identity_flowproperty_payload(),
  pg_temp.flow_identity_flowproperty_payload()::json,
  '2026-07-16T01:00:00Z'
);

-- Fixture loading must not take a table-wide DDL lock against the peer writer.
set local session_replication_role = replica;

insert into public.flows (
  id, version, user_id, state_code, json, json_ordered, modified_at,
  extracted_md
) values
  (
    pg_temp.flow_identity_id('source_flow'), '01.00.000',
    pg_temp.flow_identity_id('owner'), 0,
    pg_temp.flow_identity_flow_payload(
      pg_temp.flow_identity_id('source_flow'), 'Owner source'
    ),
    pg_temp.flow_identity_flow_payload(
      pg_temp.flow_identity_id('source_flow'), 'Owner source'
    )::json,
    '2026-07-16T01:00:00Z', 'source markdown'
  ),
  (
    pg_temp.flow_identity_id('target_flow'), '01.00.000',
    pg_temp.flow_identity_id('other'), 100,
    pg_temp.flow_identity_flow_payload(
      pg_temp.flow_identity_id('target_flow'), 'Public target'
    ),
    pg_temp.flow_identity_flow_payload(
      pg_temp.flow_identity_id('target_flow'), 'Public target'
    )::json,
    '2026-07-16T01:00:00Z', 'target markdown'
  ),
  (
    pg_temp.flow_identity_id('pending_flow'), '01.00.000',
    pg_temp.flow_identity_id('owner'), 0,
    pg_temp.flow_identity_flow_payload(
      pg_temp.flow_identity_id('pending_flow'), 'Protected pending'
    ),
    pg_temp.flow_identity_flow_payload(
      pg_temp.flow_identity_id('pending_flow'), 'Protected pending'
    )::json,
    '2026-07-16T01:00:00Z', 'pending markdown'
  );

insert into public.flows (
  id, version, user_id, state_code, json, json_ordered, modified_at,
  extracted_md
)
select
  pg_temp.flow_identity_orphan_id(n), '01.00.000',
  pg_temp.flow_identity_id('owner'), 0,
  pg_temp.flow_identity_flow_payload(
    pg_temp.flow_identity_orphan_id(n), 'Protected orphan ' || n
  ),
  pg_temp.flow_identity_flow_payload(
    pg_temp.flow_identity_orphan_id(n), 'Protected orphan ' || n
  )::json,
  '2026-07-16T01:00:00Z', 'orphan markdown ' || n
from generate_series(1, 303) as n;

insert into public.processes (
  id, version, user_id, state_code, json, json_ordered, modified_at,
  extracted_md, model_id, rule_verification
) values
  (
    pg_temp.flow_identity_id('process'), '01.00.000',
    pg_temp.flow_identity_id('owner'), 0,
    pg_temp.flow_identity_process_payload(false),
    pg_temp.flow_identity_process_payload(false)::json,
    '2026-07-16T01:00:00Z', 'process markdown', null, null
  ),
  (
    pg_temp.flow_identity_id('process_2'), '01.00.000',
    pg_temp.flow_identity_id('owner'), 0,
    pg_temp.flow_identity_process_payload(
      false, pg_temp.flow_identity_id('process_2')
    ),
    pg_temp.flow_identity_process_payload(
      false, pg_temp.flow_identity_id('process_2')
    )::json,
    '2026-07-16T01:00:00Z', 'process 2 markdown', null, null
  );

set local session_replication_role = origin;

create temp table flow_identity_state (
  key text primary key,
  value jsonb not null
);  -- Session-local so multi-transaction fence tests can retain the receipt.

grant select, insert, update, delete on flow_identity_state to authenticated;

delete from vault.secrets
where name in ('project_secret_key', 'project_url');
select vault.create_secret(
  'flow-identity-test-service-secret',
  'project_secret_key',
  'transaction-local Step 3 test key'
);
select vault.create_secret(
  'http://127.0.0.1:55321',
  'project_url',
  'transaction-local Step 3 local URL'
);

create or replace function pg_temp.flow_guard(p_target boolean)
returns jsonb
language plpgsql
stable
as $$
declare
  v_flow public.flows%rowtype;
  v_payload_sha text;
  v_guard jsonb;
begin
  select flow.* into v_flow
  from public.flows as flow
  where flow.id = pg_temp.flow_identity_id(
    case when p_target then 'target_flow' else 'source_flow' end
  ) and flow.version = '01.00.000';
  v_payload_sha := util.dataset_flow_identity_sha256(v_flow.json_ordered::jsonb);
  v_guard := jsonb_build_object(
    'id', v_flow.id,
    'version', btrim(v_flow.version::text),
    'user_id', v_flow.user_id,
    'state_code', v_flow.state_code,
    'modified_at', v_flow.modified_at,
    'payload_sha256', v_payload_sha,
    'row_sha256', private.dataset_flow_identity_row_sha256(
      v_flow.id, btrim(v_flow.version::text), v_flow.user_id,
      v_flow.state_code, v_flow.modified_at, v_payload_sha
    ),
    'flow_type', 'Elementary flow',
    'flow_property_id', pg_temp.flow_identity_id('flowproperty'),
    'flow_property_version', '01.00.000',
    'unit_group_id', pg_temp.flow_identity_id('unitgroup'),
    'unit_group_version', '01.00.000',
    'category_path_sha256', util.dataset_flow_identity_sha256(
      v_flow.json #>
        '{flowDataSet,flowInformation,dataSetInformation,classificationInformation}'
    )
  );
  if p_target then
    return v_guard || jsonb_build_object(
      'reference', pg_temp.flow_identity_reference(
        v_flow.id, btrim(v_flow.version::text), 'Public target'
      )
    );
  end if;
  return v_guard || jsonb_build_object(
    'source_trace_sha256', repeat('a', 64)
  );
end;
$$;

create or replace function pg_temp.flow_identity_mapping()
returns jsonb
language plpgsql
stable
as $$
declare
  v_mapping jsonb;
begin
  v_mapping := jsonb_build_object(
    'source', pg_temp.flow_guard(false),
    'target', pg_temp.flow_guard(true),
    'compatibility', jsonb_build_object(
      'policy_sha256', repeat('1', 64),
      'mode', 'identity',
      'confidence', 'approved',
      'flow_property_compatible', true,
      'unit_group_compatible', true,
      'direction_compatible', true,
      'compartment_compatible', true,
      'conversion_factor', '1',
      'evidence_sha256', repeat('2', 64),
      'flow_schema', jsonb_build_object(
        'status', 'legacy_warning',
        'warning_set_sha256', repeat('3', 64)
      ),
      'process_schema_required', 'pass'
    )
  );
  return jsonb_build_object(
    'ordinal', 1,
    'mapping_id', util.dataset_flow_identity_sha256(v_mapping)
  ) || v_mapping;
end;
$$;

create or replace function pg_temp.flow_identity_protected_closure()
returns jsonb
language plpgsql
stable
as $$
declare
  v_exchange jsonb := private.dataset_flow_identity_exchanges(
    pg_temp.flow_identity_process_payload(false)
  )->2;
  v_exchange_2 jsonb := private.dataset_flow_identity_exchanges(
    pg_temp.flow_identity_process_payload(
      false, pg_temp.flow_identity_id('process_2')
    )
  )->2;
  v_occurrences jsonb;
  v_pending jsonb;
  v_orphans jsonb;
begin
  v_occurrences := jsonb_build_array(
    jsonb_build_object(
      'process_id', pg_temp.flow_identity_id('process'),
      'process_version', '01.00.000',
      'exchange_index', 2,
      'internal_id', '3',
      'direction', 'Input',
      'reference_sha256', util.dataset_flow_identity_sha256(
        private.dataset_flow_identity_reference(v_exchange)
      )
    ),
    jsonb_build_object(
      'process_id', pg_temp.flow_identity_id('process_2'),
      'process_version', '01.00.000',
      'exchange_index', 2,
      'internal_id', '3',
      'direction', 'Input',
      'reference_sha256', util.dataset_flow_identity_sha256(
        private.dataset_flow_identity_reference(v_exchange_2)
      )
    )
  );
  v_pending := jsonb_build_array(jsonb_build_object(
    'source_id', pg_temp.flow_identity_id('pending_flow'),
    'source_version', '01.00.000',
    'expected_reference_count', 2,
    'occurrences', v_occurrences,
    'occurrence_set_sha256', util.dataset_flow_identity_sha256(v_occurrences),
    'evidence_sha256', repeat('4', 64)
  ));
  select jsonb_agg(jsonb_build_object(
    'source_id', pg_temp.flow_identity_orphan_id(n),
    'source_version', '01.00.000',
    'evidence_sha256', encode(digest('orphan-' || n, 'sha256'), 'hex')
  ) order by pg_temp.flow_identity_orphan_id(n)::text)
  into v_orphans
  from generate_series(1, 303) as n;
  return jsonb_build_object(
    'schema_version', 'dataset-flow-identity-protected-closure.v1',
    'pending', v_pending,
    'blockers', '[]'::jsonb,
    'orphans', v_orphans,
    'pending_set_sha256', util.dataset_flow_identity_sha256(v_pending),
    'blocker_set_sha256', util.dataset_flow_identity_sha256('[]'::jsonb),
    'orphan_set_sha256', util.dataset_flow_identity_sha256(v_orphans),
    'total_expected_reference_count', 2
  );
end;
$$;

create or replace function pg_temp.flow_identity_support_snapshots()
returns jsonb
language plpgsql
stable
as $$
declare
  v_result jsonb;
begin
  select jsonb_agg(entry order by ordinal)
  into v_result
  from (
    select 1 as ordinal, jsonb_build_object(
      'ordinal', 1, 'table', 'flowproperties', 'id', fp.id,
      'version', btrim(fp.version::text), 'user_id', fp.user_id,
      'state_code', fp.state_code, 'modified_at', fp.modified_at,
      'payload_sha256', util.dataset_flow_identity_sha256(fp.json_ordered::jsonb),
      'row_sha256', private.dataset_flow_identity_row_sha256(
        fp.id, btrim(fp.version::text), fp.user_id, fp.state_code,
        fp.modified_at, util.dataset_flow_identity_sha256(fp.json_ordered::jsonb)
      )
    ) as entry
    from public.flowproperties fp
    where fp.id = pg_temp.flow_identity_id('flowproperty')
      and fp.version = '01.00.000'
    union all
    select 2, jsonb_build_object(
      'ordinal', 2, 'table', 'unitgroups', 'id', ug.id,
      'version', btrim(ug.version::text), 'user_id', ug.user_id,
      'state_code', ug.state_code, 'modified_at', ug.modified_at,
      'payload_sha256', util.dataset_flow_identity_sha256(ug.json_ordered::jsonb),
      'row_sha256', private.dataset_flow_identity_row_sha256(
        ug.id, btrim(ug.version::text), ug.user_id, ug.state_code,
        ug.modified_at, util.dataset_flow_identity_sha256(ug.json_ordered::jsonb)
      )
    )
    from public.unitgroups ug
    where ug.id = pg_temp.flow_identity_id('unitgroup')
      and ug.version = '01.00.000'
  ) support;
  return v_result;
end;
$$;

create or replace function pg_temp.flow_identity_source_universe()
returns jsonb
language sql
stable
as $$
  select jsonb_agg(jsonb_build_object(
    'id', f.id, 'version', btrim(f.version::text),
    'user_id', f.user_id, 'state_code', f.state_code,
    'flow_type', 'Elementary flow'
  ) order by f.id::text, btrim(f.version::text))
  from public.flows f
  where f.user_id = pg_temp.flow_identity_id('owner')
    and f.state_code = 0
    and f.json #>> '{flowDataSet,modellingAndValidation,LCIMethod,typeOfDataSet}'
      = 'Elementary flow'
$$;

create or replace function pg_temp.flow_identity_rewrites()
returns jsonb
language plpgsql
stable
as $$
declare
  v_source jsonb := pg_temp.flow_identity_reference(
    pg_temp.flow_identity_id('source_flow'), '01.00.000', 'Owner source'
  );
  v_target jsonb := pg_temp.flow_identity_reference(
    pg_temp.flow_identity_id('target_flow'), '01.00.000', 'Public target'
  );
begin
  return jsonb_build_array(jsonb_build_object(
    'ordinal', 1,
    'exchange_index', 0,
    'internal_id', '1',
    'direction', 'Input',
    'mapping_id', pg_temp.flow_identity_mapping()->>'mapping_id',
    'source_reference', v_source,
    'target_reference', v_target,
    'before_reference_sha256', util.dataset_flow_identity_sha256(v_source),
    'after_reference_sha256', util.dataset_flow_identity_sha256(v_target)
  ));
end;
$$;

create or replace function pg_temp.flow_identity_collision()
returns jsonb
language sql
stable
as $$
  select private.dataset_flow_identity_collision_ledger(
    private.dataset_flow_identity_exchanges(
      pg_temp.flow_identity_process_payload(true)
    ),
    pg_temp.flow_identity_rewrites()
  )
$$;

create or replace function pg_temp.flow_identity_manifest()
returns jsonb
language plpgsql
stable
as $$
declare
  v_process public.processes%rowtype;
  v_before jsonb;
  v_desired jsonb := pg_temp.flow_identity_process_payload(true);
  v_before_sha text;
  v_snapshot jsonb;
  v_closure jsonb := pg_temp.flow_identity_protected_closure();
  v_manifest jsonb;
begin
  select process.* into v_process
  from public.processes as process
  where process.id = pg_temp.flow_identity_id('process')
    and process.version = '01.00.000';
  v_before := v_process.json_ordered::jsonb;
  v_before_sha := util.dataset_flow_identity_sha256(v_before);
  v_snapshot := util.dataset_derivative_rebuild_snapshot(v_process);
  v_manifest := jsonb_build_object(
    'ordinal', 1,
    'id', v_process.id,
    'version', btrim(v_process.version::text),
    'user_id', v_process.user_id,
    'state_code', v_process.state_code,
    'modified_at', v_process.modified_at,
    'model_id', v_process.model_id,
    'rule_verification', v_process.rule_verification,
    'before_row_sha256', util.dataset_flow_identity_sha256(jsonb_build_object(
      'id', v_process.id,
      'version', btrim(v_process.version::text),
      'user_id', v_process.user_id,
      'state_code', v_process.state_code,
      'modified_at', v_process.modified_at,
      'model_id', v_process.model_id,
      'rule_verification', v_process.rule_verification,
      'payload_sha256', v_before_sha
    )),
    'before_payload_sha256', v_before_sha,
    'before_exchange_set_sha256', util.dataset_flow_identity_sha256(
      private.dataset_flow_identity_exchanges(v_before)
    ),
    'before_exchange_count', 3,
    'desired_payload_sha256', util.dataset_flow_identity_sha256(v_desired),
    'desired_exchange_set_sha256', util.dataset_flow_identity_sha256(
      private.dataset_flow_identity_exchanges(v_desired)
    ),
    'rewrite_count', 1,
    'rewrite_set_sha256', util.dataset_flow_identity_sha256(
      pg_temp.flow_identity_rewrites()
    ),
    'collision_ledger_sha256', util.dataset_flow_identity_sha256(
      pg_temp.flow_identity_collision()
    ),
    'rewrites', pg_temp.flow_identity_rewrites(),
    'collision_ledger', pg_temp.flow_identity_collision(),
    'derivative_baseline_snapshot_sha256', v_snapshot->>'snapshot_sha256',
    'process_schema', jsonb_build_object(
      'status', 'pass', 'evidence_sha256', repeat('5', 64)
    ),
    'pending_blocker_closure_sha256',
      util.dataset_flow_identity_sha256(v_closure)
  );
  return v_manifest || jsonb_build_object(
    'process_template_sha256',
    util.dataset_flow_identity_sha256(v_manifest)
  );
end;
$$;

create or replace function pg_temp.flow_identity_protected_intent()
returns jsonb
language plpgsql
stable
as $$
declare
  v_closure jsonb := pg_temp.flow_identity_protected_closure();
  v_pending jsonb;
  v_blockers jsonb;
  v_orphans jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object(
    'source_id', entry.value->>'source_id',
    'source_version', entry.value->>'source_version',
    'expected_reference_count', entry.value->'expected_reference_count',
    'occurrences', coalesce((select jsonb_agg(jsonb_build_object(
      'process_id', occurrence.value->>'process_id',
      'process_version', occurrence.value->>'process_version',
      'exchange_index', occurrence.value->'exchange_index',
      'internal_id', occurrence.value->>'internal_id',
      'direction', occurrence.value->>'direction'
    ) order by occurrence.ordinality)
    from jsonb_array_elements(entry.value->'occurrences')
      with ordinality as occurrence(value, ordinality)), '[]'::jsonb),
    'evidence_sha256', entry.value->>'evidence_sha256'
  ) order by entry.ordinality), '[]'::jsonb)
  into v_pending
  from jsonb_array_elements(v_closure->'pending')
    with ordinality as entry(value, ordinality);
  select coalesce(jsonb_agg(jsonb_build_object(
    'source_id', entry.value->>'source_id',
    'source_version', entry.value->>'source_version',
    'expected_reference_count', entry.value->'expected_reference_count',
    'occurrences', coalesce((select jsonb_agg(jsonb_build_object(
      'process_id', occurrence.value->>'process_id',
      'process_version', occurrence.value->>'process_version',
      'exchange_index', occurrence.value->'exchange_index',
      'internal_id', occurrence.value->>'internal_id',
      'direction', occurrence.value->>'direction'
    ) order by occurrence.ordinality)
    from jsonb_array_elements(entry.value->'occurrences')
      with ordinality as occurrence(value, ordinality)), '[]'::jsonb),
    'evidence_sha256', entry.value->>'evidence_sha256'
  ) order by entry.ordinality), '[]'::jsonb)
  into v_blockers
  from jsonb_array_elements(v_closure->'blockers')
    with ordinality as entry(value, ordinality);
  select coalesce(jsonb_agg(jsonb_build_object(
    'source_id', entry.value->>'source_id',
    'source_version', entry.value->>'source_version',
    'evidence_sha256', entry.value->>'evidence_sha256'
  ) order by entry.ordinality), '[]'::jsonb)
  into v_orphans
  from jsonb_array_elements(v_closure->'orphans')
    with ordinality as entry(value, ordinality);
  return jsonb_build_object(
    'schema_version', 'dataset-flow-identity-protected-intent.v2',
    'pending', v_pending, 'blockers', v_blockers, 'orphans', v_orphans
  );
end;
$$;

create or replace function pg_temp.flow_identity_mapping_intent()
returns jsonb
language sql
stable
as $$
  select jsonb_build_object(
    'ordinal', 1,
    'source', jsonb_build_object(
      'id', pg_temp.flow_identity_id('source_flow'),
      'version', '01.00.000',
      'source_trace_sha256', repeat('a', 64)
    ),
    'target', jsonb_build_object(
      'id', pg_temp.flow_identity_id('target_flow'),
      'version', '01.00.000',
      'reference', pg_temp.flow_identity_reference(
        pg_temp.flow_identity_id('target_flow'), '01.00.000', 'Public target'
      )
    ),
    'compatibility', pg_temp.flow_identity_mapping()->'compatibility'
  )
$$;

create or replace function pg_temp.flow_identity_process_intent(
  p_process_id uuid default null,
  p_ordinal integer default 1
)
returns jsonb
language sql
stable
as $$
  select jsonb_build_object(
    'ordinal', p_ordinal,
    'id', coalesce(p_process_id, pg_temp.flow_identity_id('process')),
    'version', '01.00.000',
    'rewrites', jsonb_build_array(jsonb_build_object(
      'ordinal', 1, 'exchange_index', 0, 'internal_id', '1',
      'direction', 'Input', 'mapping_ordinal', 1
    )),
    'process_schema', jsonb_build_object(
      'status', 'pass', 'evidence_sha256', repeat('5', 64)
    )
  )
$$;

create or replace function pg_temp.flow_identity_capture()
returns jsonb
language sql
stable
as $$
  select jsonb_build_object(
    'schema_version', 'dataset-flow-identity-capture-attest.v2',
    'request_id', 'fb000000-0000-4000-8000-000000000001',
    'environment', 'local',
    'project_ref', 'local',
    'actor', jsonb_build_object(
      'user_id', pg_temp.flow_identity_id('owner'),
      'email', 'flow-owner@example.com'
    ),
    'target_visibility', 'owner_draft',
    'operation_id', 'flow-identity-test-operation',
    'compatibility_policy', jsonb_build_object(
      'schema_version', 'dataset-flow-identity-compatibility-policy.v1',
      'policy_sha256', repeat('1', 64),
      'evidence_resolution_sha256', repeat('b', 64),
      'approved_at_utc', '2026-07-16T02:00:00Z',
      'approval_text_sha256', repeat('9', 64)
    ),
    'artifact_evidence', jsonb_build_object(
      'review_ledger_sha256', repeat('e', 64),
      'live_capture_artifact_sha256', repeat('f', 64),
      'toolchain_evidence_sha256', repeat('a', 64)
    ),
    'mappings', jsonb_build_array(pg_temp.flow_identity_mapping_intent()),
    'process_intents', jsonb_build_array(
      pg_temp.flow_identity_process_intent(),
      pg_temp.flow_identity_process_intent(
        pg_temp.flow_identity_id('process_2'), 2
      )
    ),
    'protected_closure', pg_temp.flow_identity_protected_intent()
  );
$$;

create or replace function pg_temp.flow_identity_preflight()
returns jsonb
language plpgsql
stable
as $$
declare
  v_capture jsonb;
begin
  select value into v_capture from flow_identity_state where key = 'capture';
  return jsonb_build_object(
    'schema_version', 'dataset-flow-identity-scope-preflight.v2',
    'request_id', 'fa000000-0000-4000-8000-000000000001',
    'receipt_id', v_capture->>'receipt_id',
    'receipt_proof_sha256', v_capture->>'receipt_proof_sha256',
    'environment', 'local', 'project_ref', 'local',
    'actor', jsonb_build_object(
      'user_id', pg_temp.flow_identity_id('owner'),
      'email', 'flow-owner@example.com'
    ),
    'target_visibility', 'owner_draft',
    'user_state_claim',
      'authenticated_actor_state_100_plus_own_state_0',
    'operation_id', 'flow-identity-test-operation',
    'plan_sha256', repeat('6', 64),
    'freeze_sha256', repeat('7', 64),
    'policy_approval_text_sha256', repeat('9', 64),
    'execution_approval_request_sha256', repeat('8', 64),
    'execution_approval_text_sha256', repeat('c', 64),
    'execution_approval_identity_sha256', repeat('d', 64),
    'toolchain_evidence_sha256', repeat('a', 64),
    'maximum_wrapper_invocations', 1,
    'maximum_process_posts', 2,
    'maximum_finalize_posts', 1,
    'maximum_cli_apply_spawns', 1,
    'approval_reusable', false,
    'automatic_retry', false
  );
end;
$$;
