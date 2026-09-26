#!/usr/bin/env python3
"""Profile concurrent Portal RPCs on an explicitly disposable, empty local DB.

Unlike the rollback benchmark, this commits synthetic fixture rows so independent
connections can see the SAME fixture. It restores candidate readers in finally,
but retains rows for inspection. Reset/release the owned isolated project after
retaining the report; never use the shared local stack or a hosted database.
"""
from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import math
from pathlib import Path
import re
import subprocess
import time

from benchmark_portal_catalog_bounded import CANDIDATE, cases, definitions, fixture, run


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--container', required=True)
    p.add_argument('--reference-report', type=Path, required=True)
    p.add_argument('--concurrency', type=int, default=4)
    p.add_argument('--requests', type=int, default=24)
    p.add_argument('--report', type=Path, required=True)
    a = p.parse_args()
    if not re.fullmatch(r'supabase_db_database-engine-723-[a-z0-9-]+', a.container):
        p.error('An explicitly isolated Database #723 container is required')
    if not 1 <= a.concurrency <= 8 or not 4 <= a.requests <= 100 or a.report.exists():
        p.error('Invalid bounds or report already exists')
    context = json.loads(subprocess.check_output(['docker', 'context', 'inspect'], text=True))[0]
    if not context['Endpoints']['docker']['Host'].startswith('unix://'):
        p.error('A local Docker socket is required')
    empty = run(a.container, 'select inet_server_addr() is null; select count(*) from public.processes; select count(*) from public.flows; select count(*) from private.portal_catalog_search_rows_v1; select count(*) from private.portal_catalog_search_rows_v2;')
    if empty.returncode or empty.stdout.strip().splitlines() != ['t', '0', '0', '0', '0']:
        p.error('Refusing a nonempty or non-local database')
    reference = json.loads(a.reference_report.read_text())
    candidate = CANDIDATE.read_text()
    candidate_sha = hashlib.sha256(candidate.encode()).hexdigest()
    if reference.get('candidateSha256') != candidate_sha:
        p.error('Reference must bind the exact candidate migration')
    settings = reference['fixture']
    processes, flows = settings['processVersions'] // 2, settings['flowVersions'] // 2
    padding = settings['summaryPaddingBytes']
    if not 1 <= processes <= 50000 or not 1 <= flows <= 100000 or not 0 <= padding <= 8192:
        p.error('Reference fixture bounds are invalid')
    expected = {x['label']: x['sha256'] for x in reference['samples'] if x['variant'] == 'candidate' and x['ordinal'] == 0 and not x['error']}
    all_cases = cases()
    selected = ['process_geo', 'flow_geo', 'facets_flow_geo', 'navigation_world']
    if any(label not in expected for label in selected):
        p.error('Reference is missing successful expected payloads')
    # All trigger changes and grants in the fixture are undone before committing.
    seed = fixture(processes, flows, padding).split('create temp table measurements', 1)[0]
    seed += '\nrevoke create on schema private from portal_public_executor;\nrevoke portal_public_executor,api_internal_executor from postgres;\ncommit;\n'
    seeded = run(a.container, seed)
    if seeded.returncode:
        raise RuntimeError(seeded.stderr[-5000:])
    observations = []
    restore = None
    try:
        for variant in ['previous', 'candidate']:
            change = candidate if variant == 'candidate' else (
                "begin; grant portal_public_executor to postgres; grant create on schema private to portal_public_executor; set local role portal_public_executor;\n"
                + definitions(False, candidate)
                + '\nreset role; revoke create on schema private from portal_public_executor; revoke portal_public_executor from postgres; commit;\n'
            )
            applied = run(a.container, change)
            if applied.returncode:
                raise RuntimeError(applied.stderr[-5000:])

            def one(index: int) -> dict:
                label = selected[index % len(selected)]
                sql = "set role anon; set statement_timeout='8s'; set work_mem='12MB';\n"
                # PostgreSQL's own canonical JSONB text uses the same digest as
                # the serial report, independent of Python serializer choices.
                sql += "select encode(extensions.digest(convert_to(payload::text,'UTF8'),'sha256'),'hex') from (" + all_cases[label] + ") q(payload);\n"
                began = time.perf_counter()
                response = run(a.container, sql, timeout=20)
                digest = response.stdout.strip() if response.returncode == 0 else None
                return {'variant': variant, 'ordinal': index, 'label': label, 'wallMs': round((time.perf_counter() - began) * 1000, 3), 'ok': response.returncode == 0, 'matchesReference': digest == expected[label], 'error': None if response.returncode == 0 else 'rpc_failed'}

            with ThreadPoolExecutor(max_workers=a.concurrency) as executor:
                observations.extend(executor.map(one, range(a.requests)))
    finally:
        restored = run(a.container, candidate)
        restore = {'candidateRestored': restored.returncode == 0, 'syntheticRowsRetained': True}
        report = {'schemaVersion': 'portal.catalog-concurrency.v1', 'candidateSha256': candidate_sha, 'fixture': settings, 'concurrency': a.concurrency, 'requestsPerVariant': a.requests, 'samples': observations, 'disposition': restore, 'scope': 'local disposable synthetic fixture; wall time includes Docker/psql overhead; not production latency'}
        a.report.write_text(json.dumps(report, indent=2) + '\n')
    failures = [x for x in observations if x['variant'] == 'candidate' and (not x['ok'] or not x['matchesReference'])]
    wall_times = sorted(x['wallMs'] for x in observations if x['variant'] == 'candidate')
    p95 = wall_times[math.ceil(len(wall_times) * 0.95) - 1] if wall_times else None
    print(json.dumps({'report': str(a.report), 'candidateFailures': failures, 'candidateP95WallMs': p95, 'previousFailures': sum(not x['ok'] for x in observations if x['variant'] == 'previous'), 'disposition': restore}, indent=2))
    return int(bool(failures or not restore['candidateRestored'] or p95 is None or p95 > 2000))


if __name__ == '__main__':
    raise SystemExit(main())
