#!/usr/bin/env python3
"""Real overlapping-session admission/receipt proof on one exact owned local DB.

No database URLs or remote Docker targets are accepted. Writer A parks behind a
controller-owned advisory barrier after its mutation, so B's busy verdict is
accepted only while A is observed waiting and still holds its transaction.
Synthetic fixture identities and sessions are exclusively owned by this runner.
"""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import time
from urllib.parse import urlsplit


ACTOR = "85520000-0000-4000-8000-000000000001"
OTHER = "85520000-0000-4000-8000-000000000002"
IDS = [f"85520000-0000-4000-8000-{n:012x}" for n in range(257, 264)]
CONTAINER = "supabase_db_cli372-local"
NETWORK = "cli372-local"
BARRIER = 855372


def local_docker(parser, args):
    """Bind the public runner to the one explicitly owned, isolated fixture."""
    try:
        target = urlsplit(args.docker_host)
    except ValueError:
        parser.error("--docker-host must be unix:///absolute/path/to/a/local/socket")
    if (not args.docker_host.startswith("unix:///") or target.scheme != "unix"
            or target.netloc or target.query or target.fragment
            or not Path(target.path).is_absolute()):
        parser.error("--docker-host must be unix:///absolute/path/to/a/local/socket")
    try:
        socket = Path(target.path).resolve(strict=True)
        if not stat.S_ISSOCK(socket.stat().st_mode):
            parser.error("--docker-host must identify a local Unix socket")
    except (OSError, ValueError) as exc:
        parser.error(f"cannot use the local Docker socket: {exc}")
    executable = shutil.which(args.docker_bin)
    if executable is None:
        parser.error("--docker-bin must identify an executable Docker CLI")
    # Context, TLS, config and API-version overrides must not redirect this run.
    env = {key: value for key, value in os.environ.items() if not key.startswith("DOCKER_")}
    docker = [executable, "--host", f"unix://{socket}"]

    def inspect(*command):
        result = subprocess.run(docker + list(command), env=env, text=True,
                                capture_output=True, timeout=15)
        if result.returncode:
            parser.error("cannot inspect the exact owned local Docker fixture")
        try:
            objects = json.loads(result.stdout)
            if not isinstance(objects, list) or len(objects) != 1 or not isinstance(objects[0], dict):
                raise ValueError("expected exactly one Docker object")
            return objects[0]
        except (ValueError, TypeError):
            parser.error("invalid Docker inspect response for the owned fixture")

    container = inspect("container", "inspect", CONTAINER)
    network = inspect("network", "inspect", NETWORK)
    container_id = container.get("Id", "")
    network_id = network.get("Id", "")
    networks = container.get("NetworkSettings", {}).get("Networks", {})
    member = network.get("Containers", {}).get(container_id, {})
    if (not re.fullmatch(r"[0-9a-f]{64}", container_id)
            or not re.fullmatch(r"[0-9a-f]{64}", network_id)
            or container.get("Name") != f"/{CONTAINER}"
            or container.get("State", {}).get("Running") is not True
            or (container.get("Config", {}).get("Labels") or {}).get("com.supabase.cli.project") != NETWORK
            or set(networks) != {NETWORK}
            or networks[NETWORK].get("NetworkID") != network_id
            or network.get("Name") != NETWORK
            or network.get("Internal") is not True
            or (network.get("Labels") or {}).get("codex.task") != "cli372"
            or member.get("Name") != CONTAINER):
        parser.error("refusing a fixture without the exact running container, labels and isolated network membership")
    return docker + ["exec", "-i"], env


def literal(value):
    return "'" + value.replace("'", "''") + "'"


def body(version="01.00.000", marker="source"):
    return {"contactDataSet": {"administrativeInformation": {
        "publicationAndOwnership": {"common:dataSetVersion": version}}},
        "fixture": {"marker": marker}}


def request(dataset_id):
    return {"table": "contacts", "id": dataset_id, "expectedActorId": ACTOR,
            "expectedDrafts": [], "source": {"version": "01.00.000", "userId": ACTOR,
                                                "stateCode": 100, "jsonOrdered": body()}}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--docker-host", required=True,
                        help="explicit unix:///absolute/path/to/local/docker.sock")
    parser.add_argument("--docker-bin", default="docker", help="Docker CLI executable (default: docker)")
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    docker, docker_env = local_docker(parser, args)
    suffix = [CONTAINER, "psql", "-X", "-q", "-t", "-A", "-U", "postgres", "-d", "postgres", "-v", "ON_ERROR_STOP=1"]
    checks = []
    processes = []
    session_apps = []
    run_token = f"{time.time_ns():x}"
    armed = False

    def sql(statement, *, fail=True):
        result = subprocess.run(docker + suffix, env=docker_env, input=statement,
                                text=True, capture_output=True, timeout=30)
        if fail and result.returncode:
            raise AssertionError(result.stderr.strip())
        return result

    def scalar(statement):
        return sql(statement).stdout.strip().splitlines()[-1]

    def check(name, actual, expected_value):
        if actual != expected_value:
            raise AssertionError(f"{name}: expected {expected_value!r}, got {actual!r}")
        checks.append(name)

    def command_result(expression):
        # set_config output is suppressed by psql's \gset, so the only result is JSON.
        raw = sql(f"select set_config('request.jwt.claim.sub',{literal(ACTOR)},false) as actor \\gset\nselect {expression};").stdout
        return json.loads(raw.strip().splitlines()[-1])

    def prepare(req_id, payload):
        return command_result(f"api.cmd_dataset_prepare_stable_draft({literal(req_id)}, {literal(json.dumps(payload))}::jsonb)")

    def recover(req_id, payload):
        return command_result(f"api.get_dataset_stable_draft_request({literal(req_id)}, {literal(json.dumps(payload))}::jsonb)")

    def spawn(app, statement):
        proc = subprocess.Popen(docker + ["-e", f"PGAPPNAME={app}"] + suffix,
                                env=docker_env, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, text=True)
        processes.append(proc)
        session_apps.append(app)
        proc.stdin.write(statement)
        proc.stdin.flush()
        return proc

    def wait_for(statement, expected_value, description):
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            if scalar(statement) == expected_value:
                return
            time.sleep(0.05)
        raise AssertionError(f"did not observe {description}")

    def overlap(label, a_statement, b_call, family_id=None, rollback_a=False):
        app_control = f"stable855_{run_token}_{label}_control"
        app_a = f"stable855_{run_token}_{label}_a"
        controller = spawn(app_control, f"select pg_advisory_lock({BARRIER});\n")
        wait_for(f"select exists(select 1 from pg_locks l join pg_stat_activity a on a.pid=l.pid where a.application_name={literal(app_control)} and l.locktype='advisory' and l.granted);", "t", "controller barrier ownership")
        writer_a = spawn(app_a, "begin;\n" +
                         f"select set_config('request.jwt.claim.sub',{literal(ACTOR)},true) as actor \\gset\n" +
                         a_statement + f";\nselect pg_advisory_xact_lock({BARRIER});\n" +
                         ("rollback" if rollback_a else "commit") + ";\n\\q\n")
        wait_for(f"select exists(select 1 from pg_stat_activity where application_name={literal(app_a)} and wait_event_type='Lock' and lower(wait_event)='advisory');", "t", "writer A parked with its admission lock")
        if family_id is not None:
            check(f"{label}: review transition holds the exact family advisory lock", scalar(
                "select exists(select 1 from pg_locks l join pg_stat_activity a on a.pid=l.pid "
                f"where a.application_name={literal(app_a)} and l.locktype='advisory' and l.granted "
                "and l.objsubid=2 and l.classid::bigint=(hashtext('cmd_dataset_create_version:contacts')::bigint & 4294967295) "
                f"and l.objid::bigint=(hashtext({literal(family_id)})::bigint & 4294967295));"), "t")
        result_b = b_call()
        check(f"{label}: A is still uncommitted while B returns", writer_a.poll(), None)
        controller.stdin.write(f"select pg_advisory_unlock({BARRIER});\n\\q\n")
        controller.stdin.flush()
        controller.stdin.close()
        controller.wait(timeout=15)
        writer_a.stdin.close()
        writer_a.wait(timeout=15)
        stderr = writer_a.stderr.read()
        if writer_a.returncode:
            raise AssertionError(f"writer A failed: {stderr}")
        checks.append(f"{label}: real overlap observed before A " + ("rollback" if rollback_a else "commit"))
        return result_b

    try:
        existing = scalar(f"select (select count(*) from auth.users where id in ({literal(ACTOR)},{literal(OTHER)})) + (select count(*) from public.contacts where id in ({','.join(map(literal,IDS))}));")
        check("fixture identities are initially absent", existing, "0")
        check("candidate RPC is present", scalar("select to_regprocedure('api.cmd_dataset_prepare_stable_draft(uuid,jsonb)') is not null;"), "t")
        values = ",".join(f"({literal(uid)},'authenticated','authenticated',{literal('race-'+str(i)+'-855@example.com')},'{{}}'::jsonb,'{{}}'::jsonb)" for i, uid in enumerate([ACTOR, OTHER]))
        sql(f"insert into auth.users(id,aud,role,email,raw_app_meta_data,raw_user_meta_data) values {values};")
        armed = True
        sql("insert into public.contacts(id,json_ordered,user_id,state_code,rule_verification) values " +
            ",".join(f"({literal(dataset_id)},{literal(json.dumps(body()))}::json,{literal(ACTOR)},100,true)" for dataset_id in IDS) + ";")
        sql(f"insert into public.contacts(id,json_ordered,user_id,state_code) values ({literal(IDS[3])},{literal(json.dumps(body('01.00.001','foreign')))}::json,{literal(OTHER)},0);")
        sql(f"insert into public.contacts(id,json_ordered,user_id,state_code) values ({literal(IDS[4])},{literal(json.dumps(body('01.00.001','draft-to-review')))}::json,{literal(ACTOR)},0);")

        req_a = "85520000-0000-4000-8000-000000001001"
        req_b = "85520000-0000-4000-8000-000000001002"
        payload = request(IDS[0])
        expr_a = f"select api.cmd_dataset_prepare_stable_draft({literal(req_a)},{literal(json.dumps(payload))}::jsonb)"
        result_b = overlap("stable_stable", expr_a, lambda: prepare(req_b, payload))
        check("concurrent second prepare safely reports busy", result_b.get("code"), "DATASET_STABLE_DRAFT_BUSY")
        check("losing request has no receipt", recover(req_b, payload).get("code"), "REQUEST_NOT_RECORDED")
        # Deliberately discard A's response: only readonly original-request lookup
        # determines its committed outcome, without any second writer dispatch.
        recovered = recover(req_a, payload)
        check("lost response recovers the fixed allocated version", recovered["data"]["result"]["version"], "01.00.001")
        check("lost response target is unchanged", recovered["data"]["targetStatus"], "unchanged")
        check("stale empty census after the winner commits is rejected", prepare(req_b, payload).get("code"), "DATASET_DRAFT_CENSUS_CHANGED")
        check("same original request is idempotent", prepare(req_a, payload)["data"]["replayed"], True)

        req_c = "85520000-0000-4000-8000-000000001003"
        p2 = request(IDS[1])
        legacy_create = f"api.cmd_dataset_create('contacts',{literal(IDS[1])},{literal(json.dumps(body('01.00.099','legacy')))}::jsonb)"
        result_b = overlap("stable_legacy", f"select api.cmd_dataset_prepare_stable_draft({literal(req_c)},{literal(json.dumps(p2))}::jsonb)",
                           lambda: command_result(legacy_create))
        check("legacy insert competes in the same family lock", result_b.get("code"), "DATASET_CREATE_LOCK_TIMEOUT")
        check("legacy insert cannot append after the stable draft commits", command_result(legacy_create).get("message"), "DATASET_DRAFT_CONFLICT")

        req_d = "85520000-0000-4000-8000-000000001004"
        p3 = request(IDS[2])
        result_b = overlap("legacy_stable", f"select api.cmd_dataset_create_version('contacts',{literal(IDS[2])},'01.00.000',{literal(json.dumps(body()))}::jsonb)",
                           lambda: prepare(req_d, p3))
        check("prepare cannot race a legacy version allocation", result_b.get("code"), "DATASET_STABLE_DRAFT_BUSY")
        check("legacy winner invalidates stale empty census", prepare(req_d, p3).get("code"), "DATASET_DRAFT_CENSUS_CHANGED")

        req_e = "85520000-0000-4000-8000-000000001005"
        p4 = request(IDS[3])
        result_b = overlap("owner_transfer", f"update public.contacts set user_id={literal(ACTOR)} where id={literal(IDS[3])} and version='01.00.001'",
                           lambda: prepare(req_e, p4))
        check("owner transfer into draft participates in the family lock", result_b.get("code"), "DATASET_STABLE_DRAFT_BUSY")
        check("committed owner transfer invalidates old owner census", prepare(req_e, p4).get("code"), "DATASET_DRAFT_CENSUS_CHANGED")

        req_review = "85520000-0000-4000-8000-000000001007"
        p_review = request(IDS[4])
        result_b = overlap("review_entry", f"update public.contacts set state_code=20 where id={literal(IDS[4])} and version='01.00.001'",
                           lambda: prepare(req_review, p_review), family_id=IDS[4])
        check("prepare cannot slip through an uncommitted 0-to-20 transition", result_b.get("code"), "DATASET_STABLE_DRAFT_BUSY")
        review_result = prepare(req_review, p_review)
        check("committed review blocks a zero-draft census", review_result.get("code"), "DATASET_REVIEW_IN_PROGRESS")
        check("review return point retains the existing exact version", review_result["details"]["reviews"][0]["version"], "01.00.001")
        legacy_review = command_result(f"api.cmd_dataset_create('contacts',{literal(IDS[4])},{literal(json.dumps(body('01.00.002')))}::jsonb)")
        check("legacy create cannot fork around the committed review", legacy_review.get("code"), "DATASET_REVIEW_IN_PROGRESS")
        check("reviewed family has zero new drafts", scalar(f"select count(*) from public.contacts where id={literal(IDS[4])} and user_id={literal(ACTOR)} and state_code=0;"), "0")

        # A successful exact-key DO NOTHING must pin the existing key until
        # transaction end. Otherwise DELETE/key-change could remove the key
        # after an EXISTS shortcut and turn a presumed no-op into admission.
        exact_id, moved_id = IDS[5:7]
        duplicate = ("insert into public.contacts(id,json_ordered,user_id,state_code) values ("
                     f"{literal(exact_id)},{literal(json.dumps(body('01.00.001','exact')))}::json,{literal(ACTOR)},0)")
        sql(duplicate + ";")
        noop = duplicate + " on conflict(id,version) do nothing"

        def locked_sql(statement):
            return sql("\\set VERBOSITY verbose\nbegin;set local lock_timeout='500ms';" + statement + ";commit;", fail=False)

        def check_lock_failure(label, result, message=None):
            check(label + ": SQL safely refuses the overlapping operation", result.returncode != 0, True)
            check(label + ": SQLSTATE identifies lock contention", "55P03" in result.stderr, True)
            if message:
                check(label + ": stable admission reports its existing busy code", message in result.stderr, True)

        result_b = overlap("exact_pin_delete", noop, lambda: locked_sql(
            f"delete from public.contacts where id={literal(exact_id)} and version='01.00.001'"))
        check_lock_failure("exact pin/delete", result_b)
        check("failed concurrent delete preserves the no-op target", scalar(
            f"select count(*) from public.contacts where id={literal(exact_id)} and version='01.00.001';"), "1")

        result_b = overlap("exact_pin_keychange", noop, lambda: locked_sql(
            f"update public.contacts set id={literal(moved_id)} where id={literal(exact_id)} and version='01.00.001'"))
        check_lock_failure("exact pin/key change", result_b)
        check("failed concurrent key change preserves the no-op target", scalar(
            f"select count(*) from public.contacts where id={literal(exact_id)} and version='01.00.001';"), "1")

        result_b = overlap("delete_exact_pin",
                           f"delete from public.contacts where id={literal(exact_id)} and version='01.00.001'",
                           lambda: locked_sql(noop))
        check_lock_failure("delete/exact pin", result_b, "DATASET_STABLE_DRAFT_BUSY")
        check("delete winner leaves no speculative insertion", scalar(
            f"select count(*) from public.contacts where id={literal(exact_id)} and version='01.00.001';"), "0")
        sql(duplicate + ";")
        check("a fresh retry after committed deletion performs normal admission", scalar(
            f"select count(*) from public.contacts where id={literal(exact_id)} and version='01.00.001';"), "1")

        result_b = overlap("delete_rollback_exact_pin",
                           f"delete from public.contacts where id={literal(exact_id)} and version='01.00.001'",
                           lambda: locked_sql(noop), rollback_a=True)
        check_lock_failure("delete rollback/exact pin", result_b, "DATASET_STABLE_DRAFT_BUSY")
        sql(noop + ";")
        check("an exact no-op retry after rollback preserves the original row", scalar(
            f"select count(*) from public.contacts where id={literal(exact_id)} and version='01.00.001';"), "1")

        result_b = overlap("keychange_exact_pin",
                           f"update public.contacts set id={literal(moved_id)} where id={literal(exact_id)} and version='01.00.001'",
                           lambda: locked_sql(noop))
        check_lock_failure("key change/exact pin", result_b, "DATASET_STABLE_DRAFT_BUSY")
        check("key-change winner leaves no speculative old-key insertion", scalar(
            f"select count(*) from public.contacts where id={literal(exact_id)} and version='01.00.001';"), "0")
        check("key-change winner preserves exactly one moved draft", scalar(
            f"select count(*) from public.contacts where id={literal(moved_id)} and version='01.00.001';"), "1")
        sql(duplicate + ";")
        check("a fresh retry after committed key change performs normal admission", scalar(
            f"select count(*) from public.contacts where id={literal(exact_id)} and version='01.00.001';"), "1")

        rr = sql("begin isolation level repeatable read;" +
                 f"select set_config('request.jwt.claim.sub',{literal(ACTOR)},true) as actor \\gset\n" +
                 f"select api.cmd_dataset_prepare_stable_draft('85520000-0000-4000-8000-000000001006',{literal(json.dumps(payload))}::jsonb);rollback;").stdout
        check("stale-snapshot transaction cannot claim uniqueness", json.loads(rr.strip().splitlines()[-1])["code"], "DATASET_DRAFT_ISOLATION_REQUIRED")
        check("one current-owner draft per active raced family", scalar(f"select bool_and(n=1) from (select id,count(*) n from public.contacts where id in ({','.join(map(literal,IDS[:4]))}) and user_id={literal(ACTOR)} and state_code=0 group by id)x;"), "t")
        check("real native writer executes once per created family", scalar(f"select count(*) from private.command_audit_log where command='cmd_dataset_create_version' and target_id in ({','.join(map(literal,IDS[:3]))});"), "3")
        check("receipt count records only the two successful stable winners", scalar(f"select count(*) from private.command_audit_log where command='cmd_dataset_prepare_stable_draft' and actor_user_id={literal(ACTOR)};"), "2")
        report = {"schema": "stable-owner-draft-concurrency.v1", "container": CONTAINER,
                  "passed": True, "assertionCount": len(checks), "checks": checks}
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2) + "\n")
        print(json.dumps({"passed": True, "assertionCount": len(checks), "report": str(args.report)}))
    finally:
        for proc in processes:
            if proc.poll() is None:
                proc.terminate()
                try:
                    proc.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    proc.kill()
        # A killed docker client may leave its backend; settle only our named
        # sessions before deleting only this run's exact synthetic identities.
        if session_apps:
            sql("select pg_terminate_backend(pid) from pg_stat_activity where application_name in (" +
                ",".join(map(literal, session_apps)) + ") and pid<>pg_backend_pid();", fail=False)
        if armed:
            cleanup = sql(f"delete from pgmq.q_dataset_extraction_jobs where message->>'id' in ({','.join(map(literal,IDS))});"
                          f"delete from private.command_audit_log where target_id in ({','.join(map(literal,IDS))});"
                          f"delete from private.lcia_scope_closure_candidate_document_hashes where dataset_id in ({','.join(map(literal,IDS))});"
                          f"delete from public.contacts where id in ({','.join(map(literal,IDS))});"
                          f"delete from private.users where id in ({literal(ACTOR)},{literal(OTHER)});"
                          f"delete from auth.users where id in ({literal(ACTOR)},{literal(OTHER)});", fail=False)
            if cleanup.returncode:
                raise AssertionError("owned fixture cleanup did not complete: " + cleanup.stderr.strip())


if __name__ == "__main__":
    main()
