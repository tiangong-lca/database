#!/usr/bin/env python3
"""Independent row hashes, multi-block seal and real two-client arbitration.

Refuses every database except the existing task-owned local project. Synthetic
immutable claims remain for its owner reset; no real files or releases are used.
"""
import datetime
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('identity_concurrency', HERE / '20261101_final_result_identity_concurrency.py')
identity = importlib.util.module_from_spec(spec)
spec.loader.exec_module(identity)


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'))


def digest(value):
    return hashlib.sha256(value.encode()).hexdigest()


def sql(value):
    return "'" + (value if isinstance(value, str) else canonical(value)).replace("'", "''") + "'"


def row_hash(row):
    fields = ['ordinal', 'uuid', 'version', 'registrationId', 'contentHash', 'relationKind']
    sources = sorted(row['sources'], key=lambda s: (s['uuid'], s['version']))
    return digest('tiangong.final-result-row.v1\n' + '\n'.join(str(row[k]) for k in fields) + '\n'
                  + ''.join(source['uuid'] + '@' + source['version'] + '\n' for source in sources))


def root_hash(rows):
    hashes = [row_hash(row) for row in sorted(rows, key=lambda r: r['ordinal'])]
    blocks = [digest(''.join(h + '\n' for h in hashes[start:start + 500])) for start in range(0, len(hashes), 500)]
    return digest('tiangong.final-result-row-bindings.v1\n' + ''.join(h + '\n' for h in blocks))


def fixture(number, count=1):
    artifact_id = f'87921000-0000-4000-8000-{number:012d}'
    ids = [f'87922000-0000-4000-8000-{number * 1000 + i:012d}' for i in range(count)]
    assert identity.query(f"select not exists(select 1 from private.final_result_identities where result_id='{ids[0]}');") == 't', 'owner reset required before repeating fixtures'
    expressions = [identity.request(value).removeprefix('select ').removesuffix(';') for value in ids]
    receipts = json.loads(identity.query('set role service_role; select jsonb_build_array(' + ','.join(expressions[:1]) + ');')) if count == 1 else []
    # PostgreSQL function argument count is bounded; qualify large axes in batches.
    if count > 1:
        for start in range(0, count, 50):
            receipts.extend(json.loads(identity.query('set role service_role; select jsonb_build_array(' + ','.join(expressions[start:start + 50]) + ');')))
    rows = [dict(uuid=rid, version='01.00.000', ordinal=i, registrationId=receipts[i]['data']['registrationId'],
                 contentHash=receipts[i]['data']['contentHash'], relationKind='direct',
                 sources=[dict(uuid='87923000-0000-4000-8000-000000000001', version='01.00.000')]) for i, rid in enumerate(ids)]
    # LCI-only with zero inventory is valid: an empty inventory is not a missing capability.
    files = [dict(name=name, sha256=digest(name), byteSize=100,
                  **({'plainByteSize': 500} if name.endswith('.gz') else {}))
             for name in ['inventory-items.json.gz', 'lci.h5', 'results.json.gz']]
    manifest = dict(schemaVersion='tiangong.query-artifact.v2', artifactId=artifact_id,
                    source=dict(schemaVersion='tiangong.final-result-projection.v1', inputHash='f' * 64),
                    resultCount=count, inventoryCount=0, impactCount=0, lciNonzeroCount=0, files=files)
    raw = canonical(manifest)
    ref = dict(schemaVersion=manifest['schemaVersion'], artifactId=artifact_id, manifestSha256=digest(raw), manifestByteSize=len(raw.encode()))
    receipt = dict(schemaVersion='tiangong.final-result-query-readback.v1', verification='full-get-sha256-and-axis',
                   targetHash='d' * 64, rowBindingsSha256=root_hash(rows), readbackId=f'87924000-0000-4000-8000-{number:012d}',
                   verifiedAt=datetime.datetime.now(datetime.timezone.utc).isoformat(), artifact=ref, inputHash='f' * 64,
                   files=sorted([{k: f[k] for k in ['name', 'sha256', 'byteSize']} for f in files]
                                + [dict(name='manifest.json', sha256=ref['manifestSha256'], byteSize=ref['manifestByteSize'])], key=lambda f: f['name']))
    return dict(ref=ref, raw=raw, rows=rows, receipt=receipt)


def stage(value, rows=None):
    return f"select api.svc_result_query_stage_v2({sql(value['ref'])}::jsonb,{sql(value['raw'])},{sql(value['rows'] if rows is None else rows)}::jsonb);"


def seal(value, receipt=None):
    return f"select api.svc_result_query_seal_v2('{value['ref']['artifactId']}',{sql(receipt or value['receipt'])}::jsonb);"


def race(number, isolation, conflict):
    value = fixture(number)
    first_name, second_name = f'query879_a_{number}', f'query879_b_{number}'
    first, second = identity.client(first_name), identity.client(second_name)
    try:
        first.stdin.write('begin; set local role service_role;\n' + stage(value) + '\n')
        first.stdin.flush()
        identity.wait_for(f"select exists(select 1 from pg_stat_activity where application_name='{first_name}' and state='idle in transaction');")
        next_rows = json.loads(canonical(value['rows']))
        if conflict:
            next_rows[0]['relationKind'] = 'derived'
        second.stdin.write(f'begin isolation level {isolation}; select count(*) from private.final_result_query_artifacts; set local role service_role;\n' + stage(value, next_rows) + '\ncommit;\n\\q\n')
        second.stdin.flush()
        identity.wait_for(f"select exists(select 1 from pg_stat_activity b join pg_stat_activity a on a.pid=any(pg_blocking_pids(b.pid)) where a.application_name='{first_name}' and b.application_name='{second_name}');")
        first.stdin.write('commit;\n\\q\n')
        first.stdin.flush()
        _, first_error = first.communicate(timeout=20)
        _, second_error = second.communicate(timeout=20)
        assert first.returncode == 0, first_error
        if isolation == 'read committed' and not conflict:
            assert second.returncode == 0, second_error
        else:
            # A stale snapshot may hit the unique identity constraint rather
            # than SSI. Either abort is safe; retry requires a new transaction.
            codes = ('23505',) if isolation == 'read committed' else ('23505', '40001')
            assert second.returncode != 0 and any(f'ERROR:  {code}:' in second_error for code in codes), second_error
        result = json.loads(identity.query('set role service_role; ' + seal(value)))
        assert result['data']['rowBindingsSha256'] == root_hash(value['rows'])
        assert result['data']['publicationAuthorized'] is False
        print(f'ok - {isolation}: simultaneous stage {"conflict" if conflict else "retry"}', flush=True)
    finally:
        for proc in (first, second):
            if proc.poll() is None:
                proc.kill()
                proc.communicate(timeout=5)


def main():
    metadata = json.loads(subprocess.run(['docker', 'inspect', identity.CONTAINER], capture_output=True, text=True, check=True).stdout)[0]
    assert metadata['Name'] == '/' + identity.CONTAINER
    assert metadata['Config']['Labels'].get('com.supabase.cli.project') == 'hdf5-final-879'
    golden = json.loads((HERE.parent / 'fixtures/final-result-query-v2.json').read_text())
    assert [row_hash(row) for row in golden['rows']] == golden['rowHashes']
    assert root_hash(golden['rows']) == golden['rowBindingsSha256']
    value = fixture(879500, 501)
    for rows in (value['rows'][500:], value['rows'][:250], value['rows'][250:500]):
        identity.query('set role service_role; ' + stage(value, rows))
    result = json.loads(identity.query('set role service_role; ' + seal(value)))
    assert result['data']['rowBindingsSha256'] == root_hash(value['rows'])
    assert result['data']['sealed'] is True
    assert json.loads(identity.query('set role service_role; ' + seal(value))) == result
    print('ok - 501 real identity receipts, out-of-order batches, two-block golden seal and retry', flush=True)
    number = 879501
    for isolation in ('read committed', 'repeatable read', 'serializable'):
        for conflict in (False, True):
            race(number, isolation, conflict)
            number += 1
    print('7 integration cases passed; synthetic immutable records retained for task owner reset')


if __name__ == '__main__':
    main()
