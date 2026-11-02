#!/usr/bin/env python3
"""Real Candidate registration races on the owner-reset hdf5-final-879 DB.

Uses actual identity and query registration RPCs. File receipts are synthetic:
this proves database arbitration, not S3 package qualification or publication.
"""
import copy
import datetime
import importlib.util
import json
from pathlib import Path
import subprocess

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('query_v2', HERE / '20261101_final_result_query_v2.py')
query = importlib.util.module_from_spec(spec)
spec.loader.exec_module(query)
identity = query.identity


def fixture(number):
    artifact = query.fixture(number)
    identity.query('set role service_role; ' + query.stage(artifact) + query.seal(artifact))
    base = json.loads((HERE.parent / 'fixtures/final-result-candidate-v2.json').read_text())
    candidate, catalog = json.loads(base['candidateText']), json.loads(base['catalogText'])
    support, result = catalog['datasets'][0], catalog['datasets'][1]
    result.update(uuid=artifact['rows'][0]['uuid'], canonicalContentHash='a' * 64)
    result['key'] = 'process:' + result['uuid'] + '@' + result['version']
    result['path'] = 'processes/' + result['uuid'] + '.json'
    catalog['datasets'] = [support, result]
    catalog['datasetCount'] = 2
    catalog['components']['result'].update(roots=[result['key']], datasets=[support['key'], result['key']])
    catalog['catalogSetHash'] = query.digest(query.canonical([
        query.digest(query.canonical({k: member[k] for k in ('key', 'sha256', 'references')}))
        for member in catalog['datasets']]))
    raw_catalog = query.canonical(catalog) + '\n'
    candidate['publicationCatalog']['sha256'] = query.digest(raw_catalog)
    candidate['queryArtifacts'] = [dict(artifact['ref'], path='pair/query/synthetic', resultCount=1)]
    candidate['releaseVersion'] = f'2026.11.{number}'
    candidate['packages'] = [dict(p, memberCount=2) for p in candidate['packages']]
    raw = query.canonical(candidate) + '\n'
    receipt = dict(base['receipt'], candidateSha256=query.digest(raw),
                   readbackId=f'87926000-0000-4000-8000-{number:012d}',
                   verifiedAt=datetime.datetime.now(datetime.timezone.utc).isoformat())
    receipt['files'] = sorted([
        dict(name='result.' + p['format'] + '.zip', sha256=p['sha256'], byteSize=p['byteSize']) for p in candidate['packages']
    ] + [dict(name='release-candidate.json', sha256=query.digest(raw), byteSize=len(raw.encode())),
         dict(name='publication-catalog.json', sha256=query.digest(raw_catalog), byteSize=len(raw_catalog.encode()))], key=lambda f: f['name'])
    return dict(raw=raw, catalog=raw_catalog, receipt=receipt)


def register(value):
    return 'select api.svc_result_candidate_register_v2(' + ','.join(query.sql(value[k]) for k in ('raw', 'catalog', 'receipt')) + '::jsonb);'


def race(number, isolation, conflict):
    value = fixture(number)
    first_name, second_name = f'candidate879_a_{number}', f'candidate879_b_{number}'
    first, second = identity.client(first_name), identity.client(second_name)
    try:
        first.stdin.write('begin; set local role service_role;\n' + register(value) + '\n')
        first.stdin.flush()
        identity.wait_for(f"select exists(select 1 from pg_stat_activity where application_name='{first_name}' and state='idle in transaction');")
        other = copy.deepcopy(value)
        if conflict:
            other['receipt']['readbackId'] = f'87927000-0000-4000-8000-{number:012d}'
        second.stdin.write(f'begin isolation level {isolation}; select count(*) from private.final_result_candidates; set local role service_role;\n' + register(other) + '\ncommit;\n\\q\n')
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
            codes = ('23505',) if isolation == 'read committed' else ('23505', '40001')
            assert second.returncode != 0 and any(f'ERROR:  {code}:' in second_error for code in codes), second_error
        recovered = json.loads(identity.query('set role service_role; ' + register(value)))
        assert recovered['data']['readbackId'] == value['receipt']['readbackId']
        assert recovered['data']['publicationAuthorized'] is False
        candidate_hash = value['receipt']['candidateSha256']
        assert identity.query(f"select count(*) from private.final_result_candidate_members where candidate_hash='{candidate_hash}';") == '2'
        assert identity.query(f"select count(*) from private.final_result_candidate_storage where candidate_hash='{candidate_hash}';") == '1'
        print(f'ok - {isolation}: Candidate {"conflict" if conflict else "retry"}, exact receipt recovered', flush=True)
    finally:
        for process in (first, second):
            if process.poll() is None:
                process.kill()
                process.communicate(timeout=5)


def main():
    metadata = json.loads(subprocess.run(['docker', 'inspect', identity.CONTAINER], capture_output=True, text=True, check=True).stdout)[0]
    assert metadata['Name'] == '/' + identity.CONTAINER
    assert metadata['Config']['Labels'].get('com.supabase.cli.project') == 'hdf5-final-879'
    number = 879600
    for isolation in ('read committed', 'repeatable read', 'serializable'):
        for conflict in (False, True):
            race(number, isolation, conflict)
            number += 1
    print('6 real two-client Candidate races passed; synthetic immutable fixtures retained for owner reset')


if __name__ == '__main__':
    main()
