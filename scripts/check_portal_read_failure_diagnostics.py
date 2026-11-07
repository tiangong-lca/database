#!/usr/bin/env python3
"""Validate real diagnostic-suite LOG DETAIL JSON; never print request bodies."""
import argparse
import json
import re
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--log', type=Path, required=True)
    args = parser.parse_args()
    text = args.log.read_text()
    # Supabase's pg_prove runner summarizes successful TAP instead of emitting
    # the individual plan/assertion lines. Require both its final result and
    # the diagnostic suite's own success, including when reading a larger run.
    assert re.search(r'^Result: PASS\s*$', text, re.MULTILINE), 'SQL run did not pass'
    assert re.search(
        r'^.*20260927_portal_read_failure_diagnostics\.sql\s+\.+\s+ok\s*$',
        text, re.MULTILINE,
    ), 'Diagnostic SQL suite did not pass'
    rows = []
    for line in text.splitlines():
        _, marker, detail = line.partition('DETAIL:')
        if not marker or not detail.strip().startswith('{'):
            continue
        value = json.loads(detail)
        if value.get('schemaVersion') == 'portal.read-failure.v1' and value.get('rpc') in (
                'display_search_processes_v3', 'display_search_flows_v3'):
            rows.append(value)
    enums = {
        'queryClass': {'default','empty','single','multiple','oversize'},
        'filterClass': {'default','empty','filtered','invalid','oversize'},
        'sortClass': {'default','relevance','name_asc','modified_desc','invalid'},
        'limitClass': {'default','1_10','11_50','invalid'},
        'hasCursor': {False,True},
    }
    expected_keys = {'schemaVersion','rpc','category','reason',*enums}
    reasons = {'validation': {'input'}, 'cancellation': {'statement_timeout','cancel_request','unknown'},
               'internal': {'contract_drift','response_budget','other'}}
    assert rows, 'No Search diagnostic records captured'
    for row in rows:
        assert set(row) == expected_keys, 'Unexpected diagnostic field'
        assert row['category'] in reasons and row['reason'] in reasons[row['category']]
        assert type(row['hasCursor']) is bool
        for key, allowed in enums.items():
            assert row[key] in allowed, f'Unbounded {key}'
        assert 'private-' not in json.dumps(row), 'Request canary leaked'
    for rpc in ('display_search_processes_v3','display_search_flows_v3'):
        scoped = [row for row in rows if row['rpc']==rpc]
        for key, allowed in enums.items():
            assert {row[key] for row in scoped} == allowed, f'Incomplete {rpc} {key} coverage'
    print(json.dumps({'passed': True, 'records':len(rows), 'rpcs':2, 'closedShapeFields':len(enums)}))


if __name__ == '__main__':
    main()
