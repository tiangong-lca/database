#!/usr/bin/env python3
"""Observed PG17 Study races; ONLY the task-owned study894 isolated project.

Commits exact synthetic fixtures so independent sessions share real row locks.
Retains those rows for the owner's isolated reset; never resets or deletes a
project. Receipt reports observed barriers and independently queried stored rows.
"""
import argparse
import json
from pathlib import Path
import select
import subprocess
import time

CONTAINER = "supabase_db_study894"
ROOT = Path(__file__).resolve().parents[3]
OWNER = "89400000-0000-4000-8000-000000000001"
STUDY = "89400000-0000-4000-8000-000000000010"
PREP = "89400000-0000-4000-8000-000000000021"


def quote(value):
    return "'" + value.replace("'", "''") + "'"


def sql_json(value):
    return quote(json.dumps(value, separators=(",", ":"))) + "::jsonb"


def command(application="study894-control"):
    return ["docker", "exec", "-i", "-e", "PGAPPNAME=" + application,
            CONTAINER, "psql", "-X", "-qAt", "-U", "postgres", "-d", "postgres",
            "-v", "ON_ERROR_STOP=1"]


def sql(statement):
    result = subprocess.run(command(), input=statement, text=True, capture_output=True, timeout=25)
    if result.returncode:
        raise RuntimeError("isolated SQL failed: " + result.stderr[-2000:])
    return result.stdout.strip()


def claim(service=False):
    claims = {"role": "service_role" if service else "authenticated"}
    if not service:
        claims["sub"] = OWNER
    return "select set_config('request.jwt.claims'," + quote(json.dumps(claims)) + ",true) is not null;"


def request(operation, fields, key):
    return {"schemaVersion": "lca.study-api.v2", "requestId": key,
            "idempotencyKey": key, "operation": operation, **fields}


def call(req):
    return "select api.cmd_study_v1(" + sql_json(req) + ");"


def json_lines(output):
    return [json.loads(line) for line in output.splitlines() if line.startswith("{")]


def wait_for(condition, description):
    deadline = time.monotonic() + 12
    while time.monotonic() < deadline:
        if condition():
            return
        time.sleep(0.05)
    raise AssertionError("did not observe " + description)


def race(name, first_sql, second_sql, first_service=False):
    lock_key = 8942157
    barrier = subprocess.Popen(command("study894-barrier"), stdin=subprocess.PIPE,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, bufsize=1)
    writers = []
    try:
        barrier.stdin.write("begin;set local idle_in_transaction_session_timeout='25s';"
                            "select 'barrier-held' from pg_advisory_xact_lock(%d);\n" % lock_key)
        barrier.stdin.flush()
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            if select.select([barrier.stdout], [], [], 0.2)[0] and barrier.stdout.readline().strip() == "barrier-held":
                break
        else:
            raise AssertionError("barrier was not acquired")
        a = subprocess.Popen(command("study894-writer-a"), stdin=subprocess.PIPE,
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        writers.append(a)
        a.stdin.write("begin;set local statement_timeout='20s';" + claim(first_service) + first_sql +
                      "select pg_advisory_xact_lock(%d);commit;\n" % lock_key)
        a.stdin.close()
        a.stdin = None
        wait_for(lambda: sql("select exists(select 1 from pg_stat_activity where application_name='study894-writer-a' and wait_event_type='Lock' and wait_event='advisory');") == "t", "first writer holding domain locks at advisory barrier")
        b = subprocess.Popen(command("study894-writer-b"), stdin=subprocess.PIPE,
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        writers.append(b)
        b.stdin.write("begin;set local statement_timeout='20s';" + claim() + second_sql + "commit;\n")
        b.stdin.close()
        b.stdin = None
        wait_for(lambda: sql("select exists(select 1 from pg_stat_activity where application_name='study894-writer-b' and wait_event_type='Lock' and wait_event in ('transactionid','tuple'));") == "t", "second writer waiting on actual row/transaction lock")
        barrier.stdin.write("commit;\n\\q\n")
        barrier.stdin.flush()
        barrier.communicate(timeout=10)
        first, first_err = a.communicate(timeout=12)
        second, second_err = b.communicate(timeout=12)
        assert a.returncode == b.returncode == 0, (first_err, second_err)
        return {"name": name, "first": json_lines(first)[0], "second": json_lines(second)[0],
                "observedFirstAdvisoryWait": True, "observedSecondRowWait": True}
    finally:
        for process in [barrier, *writers]:
            if process.poll() is None:
                process.kill()
                process.communicate(timeout=5)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    assert not args.report.exists(), "report must be new"
    inventory = json.loads(subprocess.check_output(["docker", "inspect", CONTAINER], text=True))[0]
    assert inventory["Name"] == "/" + CONTAINER
    assert inventory["Config"]["Labels"].get("com.supabase.cli.project") == "study894"
    bindings = inventory["HostConfig"]["PortBindings"]["5432/tcp"]
    assert {item["HostPort"] for item in bindings} == {"56422"}
    assert sql("select current_setting('server_version_num')::integer/10000;") == "17"
    assert sql("select count(*) from auth.users where id::text like '89400000-%';") == "0", "fixture namespace already exists; owner must reset its exact isolated project"
    fixture = (ROOT / "supabase/tests/fixtures/study894_runtime_fixture.sql").read_text()
    setup = ("begin;" + fixture + "\nselect pg_temp.study894_claim(null,null,true);"
             "select api.svc_study_model_preparation_complete_v1('" + PREP + "','89400000-0000-4000-8000-000000000031','89400000-0000-4000-8000-000000000041',pg_temp.study894_complete(),'race-base-complete');"
             "select pg_temp.study894_claim(1);select api.cmd_study_v1(jsonb_build_object('schemaVersion','lca.study-api.v2','requestId','race-create','idempotencyKey','race-create','operation','revision.create','studyId','" + STUDY + "','parentRevisionId',null,'definition',pg_temp.study894_definition(),'modelPreparationId','" + PREP + "','modelRef',pg_temp.study894_model()));commit;")
    results = json_lines(sql(setup))
    assert all(item["ok"] for item in results), results
    revision = results[-1]["data"]["value"]
    definition = revision["definition"]
    model = revision["modelRef"]

    def save(rev, generation, goal, key):
        return request("revision.save", {"target": {"type": "studyRevision", "id": rev, "expectedRevision": generation},
                       "definition": {**definition, "goal": goal}, "modelPreparationId": PREP, "modelRef": model}, key)

    receipts = []
    first = race("save-save", call(save(revision["revisionId"], 1, "writer-a", "race-save-a")),
                 call(save(revision["revisionId"], 1, "writer-b", "race-save-b")))
    assert first["first"]["ok"] and first["second"]["code"] == "REVISION_CONFLICT", first
    row = json.loads(sql("select jsonb_build_object('revision',revision,'goal',definition->>'goal','hash',content_hash) from private.study_revisions where id=" + quote(revision["revisionId"]) + ";"))
    assert row["revision"] == 2 and row["goal"] == "writer-a"
    receipts.append(first)
    freeze = request("revision.freeze", {"target": {"type": "studyRevision", "id": revision["revisionId"], "expectedRevision": 2}, "expectedContentHash": row["hash"]}, "race-freeze-intent")
    intent = json_lines(sql("begin;" + claim() + call(freeze) + "commit;"))[0]
    assert intent["ok"], intent
    consume = "select api.svc_study_revision_freeze_consume_v1(" + quote(intent["data"]["intentId"]) + ",'passed');"
    second = race("freeze-save", consume, call(save(revision["revisionId"], 2, "late-save", "race-late-save")), True)
    assert second["first"]["ok"] and second["second"]["code"] == "REVISION_CONFLICT", second
    assert sql("select status||':'||validation||':'||revision from private.study_revisions where id=" + quote(revision["revisionId"]) + ";") == "frozen:passed:3"
    receipts.append(second)

    for conflicting in [False, True]:
        name = "changed-key-content" if conflicting else "exact-key-retry"
        create = request("revision.create", {"studyId": STUDY, "parentRevisionId": revision["revisionId"],
                         "definition": definition, "modelPreparationId": PREP, "modelRef": model}, name + "-create")
        child = json_lines(sql("begin;" + claim() + call(create) + "commit;"))[0]
        assert child["ok"], child
        rid = child["data"]["value"]["revisionId"]
        third = race(name, call(save(rid, 1, "same", name)), call(save(rid, 1, "different" if conflicting else "same", name)))
        assert third["first"]["ok"], third
        if conflicting:
            assert third["second"]["code"] == "IDEMPOTENCY_CONFLICT", third
        else:
            assert third["first"] == third["second"], third
        assert sql("select revision::text||':'||(definition->>'goal') from private.study_revisions where id=" + quote(rid) + ";") == "2:same"
        receipts.append(third)
    assert sql("select count(*) from pg_stat_activity where application_name in ('study894-writer-a','study894-writer-b','study894-barrier');") == "0"
    args.report.write_text(json.dumps({"schemaVersion": "lca.study-concurrency-receipt.v1", "project": "study894",
        "postgresMajor": 17, "races": receipts, "ownedSessionsReleased": True,
        "disposition": "synthetic fixtures retained for exact owned reset; not hosted or end-to-end producer qualification"}, indent=2) + "\n")
    print("Study PG17 concurrency: 4 races passed with observed overlapping locks; fixtures retained for owned reset.")


if __name__ == "__main__":
    main()
