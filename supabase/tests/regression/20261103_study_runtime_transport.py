#!/usr/bin/env python3
"""Real actor/OAuth PostgREST proof on the already-owned study894 fixture.

Reads generated local keys in memory; never prints credentials or raw errors.
Requires the concurrency runner's committed synthetic Auth/Study fixture. Its
new synthetic Study is retained for the owner's exact isolated reset.
"""
import argparse
import base64
import hashlib
import hmac
import json
from pathlib import Path
import shutil
import subprocess
import time
import urllib.error
import urllib.request
import uuid

CONTAINER = "supabase_db_study894"
CLIENT = "study894-http-read-only"
STUDY = "89400000-0000-4000-8000-000000000010"


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def sql(statement):
    result = subprocess.run(["docker", "exec", "-i", CONTAINER, "psql", "-X", "-qAt", "-U", "postgres", "-d", "postgres", "-v", "ON_ERROR_STOP=1"], input=statement, text=True, capture_output=True, timeout=15)
    if result.returncode:
        raise RuntimeError("isolated transport setup/readback failed")
    return result.stdout.strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--workdir", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    assert not args.report.exists()
    info = json.loads(subprocess.check_output(["docker", "inspect", CONTAINER], text=True))[0]
    assert info["Config"]["Labels"].get("com.supabase.cli.project") == "study894"
    assert {x["HostPort"] for x in info["HostConfig"]["PortBindings"]["5432/tcp"]} == {"56422"}
    cli = ["supabase"] if shutil.which("supabase") else ["npx", "--yes", "supabase@2.117.0"]
    result = subprocess.run(cli + ["status", "--workdir", str(args.workdir), "--output", "json"], text=True, capture_output=True, check=True, timeout=30)
    env = json.loads(result.stdout)
    assert env["API_URL"] == "http://127.0.0.1:56421"
    assert "127.0.0.1:56422/" in env["DB_URL"]
    # The pinned CLI's legacy status JWT_SECRET may differ from the running
    # verifier's local JWK. Use ONLY this owned loopback verifier's test key;
    # this exercises signed fixture claims, not an OAuth consent/login flow.
    rest = json.loads(subprocess.check_output(["docker", "inspect", "supabase_rest_study894"], text=True))[0]
    assert rest["Config"]["Labels"].get("com.supabase.cli.project") == "study894"
    rest_env = dict(item.split("=", 1) for item in rest["Config"]["Env"] if "=" in item)
    key_set = json.loads(rest_env["PGRST_JWT_SECRET"])
    keys = [key for key in key_set["keys"] if key.get("kty") == "oct"]
    assert len(keys) == 1, "local test verifier key unavailable"
    jwk = keys[0]
    signing_key = base64.urlsafe_b64decode(jwk["k"] + "=" * (-len(jwk["k"]) % 4))
    assert sql("select count(*) from auth.users where id='89400000-0000-4000-8000-000000000001';") == "1"
    assert sql("select count(*) from private.oauth_client_registry where client_id='" + CLIENT + "';") == "0"
    # A disposable VM can have a different wall clock from its host. Sign test
    # claims on the issuer/verifier clock, without changing any system clock.
    issuer_now = int(sql("select extract(epoch from clock_timestamp())::bigint;"))
    clock_skew = int(time.time()) - issuer_now
    assertions = []

    def token(actor=1, client=None, role="authenticated"):
        encode = lambda value: base64.urlsafe_b64encode(value).decode().rstrip("=")
        payload = {"role": role, "aud": "authenticated", "iat": issuer_now, "exp": issuer_now + 300}
        if actor is not None:
            payload["sub"] = "89400000-0000-4000-8000-" + str(actor).zfill(12)
        if client:
            payload["client_id"] = client
        header_fields = {"alg": "HS256", "typ": "JWT"}
        if jwk.get("kid"):
            header_fields["kid"] = jwk["kid"]
        header = encode(json.dumps(header_fields, separators=(",", ":")).encode())
        body = encode(json.dumps(payload, separators=(",", ":")).encode())
        signature = encode(hmac.new(signing_key, (header + "." + body).encode(), hashlib.sha256).digest())
        return header + "." + body + "." + signature

    def http(path, body=None, actor=1, client=None, role="authenticated", profile="api"):
        headers = {"apikey": env["ANON_KEY"], "Authorization": "Bearer " + token(actor, client, role),
                   "Content-Type": "application/json", "Content-Profile": profile, "Accept-Profile": profile}
        request = urllib.request.Request(env["API_URL"] + "/rest/v1/" + path, headers=headers,
            data=None if body is None else json.dumps(body).encode(), method="GET" if body is None else "POST")
        try:
            with urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect).open(request, timeout=15) as response:
                status, raw = response.status, response.read()
        except urllib.error.HTTPError as error:
            status, raw = error.code, error.read()
        try:
            return status, json.loads(raw)
        except (ValueError, UnicodeDecodeError):
            return status, {}

    def rpc(operation, fields=None, write=False, **kwargs):
        request = {"schemaVersion": "lca.study-api.v2", "requestId": str(uuid.uuid4()), "operation": operation, **(fields or {})}
        if write:
            request["idempotencyKey"] = str(uuid.uuid4())
        return http("rpc/" + ("cmd_study_v1" if write else "qry_study_v1"), {"p_request": request}, **kwargs)

    def check(name, condition, response):
        status, body = response
        evidence = {"name": name, "httpStatus": status, "code": body.get("code"), "passed": bool(condition)}
        assertions.append(evidence)
        if not condition:
            raise AssertionError("transport assertion failed: " + json.dumps(evidence))

    owned_client = False
    try:
        response = rpc("study.read", {"studyId": STUDY})
        check("owner-JWT-read", response[0] == 200 and response[1].get("ok") is True, response)
        response = rpc("study.read", {"studyId": STUDY}, actor=2)
        check("other-existing-actor-denied", response[0] == 200 and response[1].get("code") == "FORBIDDEN", response)
        response = rpc("study.read", {"studyId": STUDY}, actor=None, role="anon")
        check("anonymous-ACL-denied", response[0] in (401, 403, 404), response)
        response = http("studies?select=id", actor=1, profile="private")
        check("private-schema-unexposed", response[0] == 406, response)
        response = http("rpc/svc_study_revision_freeze_consume_v1", {"p_intent_id": str(uuid.uuid4()), "p_outcome": "passed"})
        check("actor-cannot-call-trusted-consume", response[0] in (401, 403, 404), response)
        response = rpc("study.create", {"scope": {"kind": "personal"}, "title": "HTTP-owned synthetic Study"}, write=True)
        check("actor-HTTP-create", response[0] == 200 and response[1].get("ok") is True, response)
        created = response[1]["data"]["value"]["studyId"]
        response = rpc("study.read", {"studyId": created})
        check("separate-request-recovers-study", response[0] == 200 and response[1].get("ok") is True, response)
        response = rpc("study.create", {"scope": {"kind": "personal"}, "title": "forged", "actorId": "89400000-0000-4000-8000-000000000002"}, write=True)
        check("public-actor-field-rejected", response[0] == 200 and response[1].get("code") == "INVALID_REQUEST", response)
        sql("insert into private.oauth_client_registry(client_id,client_kind) values('" + CLIENT + "','manual');insert into private.oauth_client_capability_grants(client_id,capability_id) values('" + CLIENT + "','STUDY-READ-01');")
        owned_client = True
        response = rpc("study.read", {"studyId": STUDY}, client=CLIENT)
        check("live-OAuth-read-capability", response[0] == 200 and response[1].get("ok") is True, response)
        response = rpc("capability.read", client=CLIENT)
        check("capability-projection-narrow", response[0] == 200 and "study.create" not in response[1].get("data", {}).get("operations", ["study.create"]), response)
        response = rpc("study.create", {"scope": {"kind": "personal"}, "title": "write denied"}, write=True, client=CLIENT)
        check("OAuth-pre-request-denies-write", response[0] == 403 and response[1].get("code") == "42501", response)
        sql("update private.oauth_client_registry set enabled=false,disabled_at=clock_timestamp() where client_id='" + CLIENT + "';")
        response = rpc("study.read", {"studyId": STUDY}, client=CLIENT)
        check("same-OAuth-session-revoked", response[0] == 403 and response[1].get("code") == "42501", response)
        args.report.write_text(json.dumps({"schemaVersion": "lca.study-transport-receipt.v1", "project": "study894",
            "assertions": assertions, "credentialsLogged": False, "hostMinusVerifierClockSeconds": clock_skew,
            "disposition": "synthetic Study retained for exact owned reset; no hosted or source/solver qualification"}, indent=2) + "\n")
        print("Study real PostgREST: 12 actor/OAuth/ACL assertions passed; no credentials logged.")
    finally:
        if owned_client:
            sql("delete from private.oauth_client_registry where client_id='" + CLIENT + "';")


if __name__ == "__main__":
    main()
