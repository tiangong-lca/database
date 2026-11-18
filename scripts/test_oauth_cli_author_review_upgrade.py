#!/usr/bin/env python3
"""Rehearse the actual author Review grant migration on both prior route vectors."""

import argparse
from pathlib import Path
import re
import subprocess


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/migrations/20261118023133_authorize_oauth_cli_author_review.sql"
PRODUCTION = ["CLI-ALIAS-02", "CLI-RPC-01", "DB-CORE-READ-01", "DB-CORE-WRITE-01", "EDGE-BUNDLE-01", "NX-CORE-02"]
DEV = ["CLI-RPC-01", "DB-CORE-READ-01", "DB-CORE-WRITE-01"]
AUTHOR = "CLI-REVIEW-AUTHOR-01"


def sql_array(values):
    return "array[" + ",".join("'" + value + "'" for value in sorted(values)) + "]"


def fixture_sql():
    source = MIGRATION.read_text(encoding="utf-8")
    blocks = re.findall(r"(?is)\bdo\s+\$authorize_review\$.*?\$authorize_review\$;", source)
    if len(blocks) != 1 or not source.startswith("begin;") or not source.rstrip().endswith("commit;"):
        raise ValueError("expected the actual authorization migration block and transaction boundary")
    block = blocks[0].replace("'", "''")
    return f"""
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public;
set local statement_timeout = '20s';
select plan(11);

create function pg_temp.predecessor(read_capability text, cli_grants text[], other_grants text[])
returns void language plpgsql as $fixture$
begin
  update private.api_capability_grants
  set capability_id = 'NX-CMD-01'
  where to_regprocedure(routine_identity) = 'api.cmd_review_submit(text,uuid,text,jsonb)'::regprocedure;
  update private.api_capability_grants
  set capability_id = read_capability
  where to_regprocedure(routine_identity) = 'api.qry_review_get_items(uuid[],uuid,text,integer[])'::regprocedure;
  perform api.svc_oauth_client_configure('review986-cli', 'cli', true, cli_grants);
  perform api.svc_oauth_client_configure('review986-other', 'cli', true, other_grants);
end
$fixture$;

create function pg_temp.allowed(client text) returns text[]
language sql as $fixture$
  select array_agg(capability_id order by capability_id)
  from private.oauth_client_capability_grants where client_id = client and allowed
$fixture$;

select pg_temp.predecessor('NX-REV-01', {sql_array(PRODUCTION)}, {sql_array(DEV)});
select lives_ok('{block}', 'canonical predecessor with the production client upgrades');
select is(pg_temp.allowed('review986-cli'), {sql_array([*PRODUCTION, AUTHOR])}, 'production receives one additive grant');
select is(pg_temp.allowed('review986-other'), {sql_array(DEV)}, 'canonical route does not admit the Dev grant class');

select pg_temp.predecessor('CLI-RPC-01', {sql_array(DEV)}, {sql_array(PRODUCTION)});
select lives_ok('{block}', 'observed Dev fallback with the Dev client upgrades');
select is(pg_temp.allowed('review986-cli'), {sql_array([*DEV, AUTHOR])}, 'Dev receives one additive grant');
select is(pg_temp.allowed('review986-other'), {sql_array(PRODUCTION)}, 'Dev fallback does not admit the production grant class');
select is((select count(*) from private.api_capability_grants where capability_id = '{AUTHOR}'), 2::bigint,
  'only the exact author routes receive the capability');
select is((select count(*) from private.oauth_client_registry_audit
    where client_id = 'review986-cli' and action = 'replace'
      and (before_state -> 'capabilities') = to_jsonb({sql_array(DEV)})
      and (after_state -> 'capabilities') = to_jsonb({sql_array([*DEV, AUTHOR])})), 1::bigint,
  'Dev grant is audited with the exact before and after state');

select pg_temp.predecessor('UNRECOGNIZED', {sql_array(DEV)}, {sql_array(PRODUCTION)});
select throws_ok('{block}', 'P0001', 'Issue #984 author review read capability has an unrecognized predecessor',
  'unknown read capability is refused');
select pg_temp.predecessor('CLI-RPC-01', {sql_array(DEV)}, {sql_array(DEV)});
select throws_ok('{block}', 'P0001', 'Issue #984 expected at most one enabled official CLI capability class',
  'ambiguous Dev clients are refused');
select is((select count(*) from private.api_capability_grants where capability_id = '{AUTHOR}'), 0::bigint,
  'a rejected grant rolls back the attempted route remap');
select * from finish();
rollback;
"""


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--local-container", required=True, help="exact disposable local Database container")
    args = parser.parse_args()
    if not re.fullmatch(r"supabase_db_database-engine(?:-[a-z0-9-]+)?", args.local_container):
        parser.error("requires an explicit local Database container; hosted DSNs are unsupported")
    result = subprocess.run(
        ["docker", "exec", "-i", args.local_container, "psql", "-X", "-qAt", "-v", "ON_ERROR_STOP=1", "-U", "postgres", "-d", "postgres"],
        input=fixture_sql(), text=True, capture_output=True, timeout=60,
    )
    print(result.stdout, end="")
    if result.stderr:
        print(result.stderr, end="")
    passed = re.findall(r"(?m)^ok ([0-9]+)\b", result.stdout)
    return int(result.returncode != 0 or passed != [str(i) for i in range(1, 12)]
               or re.search(r"(?m)^not ok\b", result.stdout) is not None)


if __name__ == "__main__":
    raise SystemExit(main())
