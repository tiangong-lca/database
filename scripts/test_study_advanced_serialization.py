#!/usr/bin/env python3
"""Compare exact Worker-owned numerical/config goldens against owned PG17 SQL."""
import argparse
import hashlib
import json
from pathlib import Path
import time
from study_advanced_test_support import ROOT, sql, sql_json, verify_owned


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--workdir',type=Path,required=True)
    p.add_argument('--report',type=Path,required=True)
    args=p.parse_args()
    verify_owned(args.workdir)
    assert not args.report.exists()
    fixture=ROOT/'supabase/tests/fixtures/study909_worker_goldens.json'
    data=json.loads(fixture.read_text())
    canonical=[row['canonical'] for row in data['numericBoundaryVectors']]
    aliases=[row['input'] for row in data['numericBoundaryVectors'] if 'input' in row and row['input']!=row['canonical']]
    started=time.monotonic()
    statement='''select jsonb_build_object(
 'allCanonicalNumbersMatch',not exists(select 1 from jsonb_array_elements_text(%s)v where private.study_advanced_number(to_jsonb(v)) is distinct from v),
 'allAliasesRejected',not exists(select 1 from jsonb_array_elements_text(%s)v where private.study_advanced_number(to_jsonb(v)) is not null),
 'allConfigsValid',not exists(select 1 from jsonb_array_elements(%s)c where not private.study_advanced_config_valid(c->'config')),
 'allConfigHashesMatch',not exists(select 1 from jsonb_array_elements(%s)c where private.study_advanced_config_hash(c->'config') is distinct from c->>'configHash'));
'''%(sql_json(canonical),sql_json(aliases),sql_json(data['configs']),sql_json(data['configs']))
    proof=json.loads(sql(statement))
    assert all(value is True for value in proof.values()),proof
    args.report.write_text(json.dumps({'schemaVersion':'lca.study-advanced-serialization-receipt.v1','project':'study909','workerCommit':data['workerCommit'],
        'fixtureSha256':hashlib.sha256(fixture.read_bytes()).hexdigest(),'numericBoundaryCount':len(canonical),'aliasCount':len(aliases),'configCount':len(data['configs']),
        'proof':proof,'elapsedMillis':round((time.monotonic()-started)*1000),'classification':'exact owner serialization/config identity; no numerical algorithm or capacity qualification'},indent=2)+'\n')
    print('Exact Worker numerical spelling and configuration goldens match PG17; aliases rejected.')


if __name__=='__main__':
    main()
