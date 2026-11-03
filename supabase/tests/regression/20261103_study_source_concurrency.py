#!/usr/bin/env python3
"""Two observed same-lease source reads on the receipt-owned study894 project.

Commits only a distinct synthetic fixture namespace and retains it for the
owner's explicit reset. No Worker, Storage or hosted endpoint is invoked.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location(
    "study_race", Path(__file__).with_name("20261103_study_runtime_concurrency.py"))
race = importlib.util.module_from_spec(spec)
spec.loader.exec_module(race)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--namespace", choices=("89510000", "89520000"), default="89510000")
    args = parser.parse_args()
    assert not args.report.exists(), "report must be new"
    info = json.loads(subprocess.check_output(
        ["docker", "inspect", race.CONTAINER], text=True))[0]
    assert info["Config"]["Labels"].get("com.supabase.cli.project") == "study894"
    assert {x["HostPort"] for x in info["HostConfig"]["PortBindings"]["5432/tcp"]} == {"56422"}
    assert race.sql("select current_setting('server_version_num')::integer/10000;") == "17"
    assert race.sql("select count(*) from private.worker_jobs where worker_queue='solver' and status in('queued','running','waiting');") == "0"
    source_enabled_before = race.sql("select source_enabled from private.study_runtime_config where singleton;")
    assert source_enabled_before in ("t", "f")
    prefix = args.namespace
    owner = prefix + "-0000-4000-8000-000000000001"
    assert race.sql("select count(*) from auth.users where id::text like " + race.quote(prefix+"-%") + ";") == "0"
    fixture = (ROOT / "supabase/tests/fixtures/study895_source_rows.sql").read_text().replace("89500000", prefix).replace("study895-", "study"+prefix+"-")
    setup = """
begin;
create temp table study_source_original_hook as select pg_get_functiondef(
 'util.invoke_edge_function(text,jsonb,integer)'::regprocedure) definition;
create or replace function util.invoke_edge_function(name text,body jsonb,timeout_milliseconds integer default 300000) returns void
language plpgsql security definer set search_path='' as $$begin return;end$$;
""" + fixture + """
do $$begin execute (select definition from study_source_original_hook);end$$;
select pg_temp.study895_claim();
create temp table study_source_scope as select api.cmd_study_v1(
 pg_temp.study895_request('study.create','{"scope":{"kind":"personal"},"title":"Owned source-read concurrency"}','source-race-study')) response;
update private.study_runtime_config set source_enabled=true where singleton;
create temp table study_source_acquisition as select api.cmd_study_v1(
 pg_temp.study895_request('model.source.resolve',jsonb_build_object(
 'studyId',response->'data'->'value'->'studyId',
 'originRef',jsonb_build_object('type','datasetRevision','datasetType','lifecyclemodel',
 'id','ORIGIN_ID','version','01.00.000')),'source-race-acquire')) response from study_source_scope;
select pg_temp.study895_claim(null,true);
create temp table study_source_claim as select private.worker_claim_jobs('solver','study895-source-race',1,900) response;
select jsonb_build_object('acquisition',a.response,'claim',c.response)
 from study_source_acquisition a,study_source_claim c;
commit;
""".replace("ORIGIN_ID", prefix+"-0000-4000-8000-000000000101")
    values = race.json_lines(race.sql(setup))[-1]
    acquisition = values["acquisition"]["data"]["value"]
    claim = values["claim"]["data"][0]
    assert acquisition["execution"]["jobId"] == claim["id"]
    call = "select api.svc_study_source_acquisition_read_input_v1(" + ",".join(
        race.quote(x)+"::uuid" for x in (
            acquisition["acquisitionId"], claim["id"], claim["leaseToken"])) + ");"
    result = race.race("same-lease-first-source-read", call, race.claim(True)+call, first_service=True)
    first, second = result.pop("first"), result.pop("second")
    a = first.get("data", {}).get("sourcePacket")
    b = second.get("data", {}).get("sourcePacket")
    passed = first.get("ok") is True and second.get("ok") is True and a == b and a is not None
    # End the fixture job through the actor domain API; retain all immutable rows.
    cancel = {"schemaVersion":"lca.study-api.v2","requestId":"source-race-cancel",
        "idempotencyKey":"source-race-cancel","operation":"task.cancel",
        "studyId":acquisition["studyId"],
        "resource":{"type":"modelSourceAcquisition","id":acquisition["acquisitionId"]},
        "reason":"Owned concurrency fixture finished"}
    cancelled = race.json_lines(race.sql("begin;select set_config('request.jwt.claims',"+
        race.quote(json.dumps({"role":"authenticated","sub":owner}))+",true) is not null;"+
        race.call(cancel)+"update private.study_runtime_config set source_enabled="+
        ("true" if source_enabled_before == "t" else "false")+" where singleton;commit;"))[-1]
    assert cancelled.get("ok") is True and cancelled["data"]["value"]["execution"]["status"] == "cancelled"
    receipt = {"schemaVersion":"lca.study-source-concurrency-proof.v1","passed":passed,
        "projectId":"study894","namespace":prefix,"firstOk":first.get("ok"),
        "secondOk":second.get("ok"),"secondCode":second.get("code"),
        "samePacket":a == b and a is not None,"observedLocks":result,
        "fixtureJobCancelled":True,
        "sourceSha256":hashlib.sha256((ROOT/"supabase/migrations/20261102215839_study_task_admission_v1.sql").read_bytes()).hexdigest(),
        "disposition":"Synthetic source/actor/domain rows retained for exact owned reset; no Storage or hosted authority."}
    args.report.write_text(json.dumps(receipt,indent=2)+"\n")
    args.report.chmod(0o600)
    print(json.dumps({"passed":passed,"firstOk":receipt["firstOk"],"secondOk":receipt["secondOk"],
                      "secondCode":receipt["secondCode"],"samePacket":receipt["samePacket"]}))
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
