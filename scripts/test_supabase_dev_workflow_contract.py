#!/usr/bin/env python3
"""Fail closed if persistent-Dev deployment exceeds the database boundary."""

from __future__ import annotations

import os
import re
import shlex
import shutil
import subprocess
import tempfile
import textwrap
from pathlib import Path

from resolve_migration_head import resolve_migration_head


REPO_ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = REPO_ROOT / ".github" / "workflows" / "supabase-dev.yml"
MIGRATIONS = REPO_ROOT / "supabase" / "migrations"
API_CONTRACT_TEST = (
    REPO_ROOT / "supabase" / "tests" / "20260806_api_contract_closure.sql"
)


def job_sections(text: str) -> dict[str, str]:
    """Return exact top-level job bodies without treating step mappings as jobs."""

    matches = list(re.finditer(r"(?m)^  ([a-zA-Z0-9_-]+):\n", text))
    return {
        match.group(1): text[
            match.start() : matches[index + 1].start()
            if index + 1 < len(matches)
            else len(text)
        ]
        for index, match in enumerate(matches)
    }



EXPECTED_DEPLOYMENT_CONDITION = (
    "github.event_name == 'push' && github.ref == 'refs/heads/dev' && "
    "needs.local-contract.outputs.deploy_required == 'true'"
)


def effective_condition(header: str, indent: int) -> str | None:
    """Read the complete plain/folded scalar; reject duplicate or unsupported keys."""

    prefix = " " * indent
    matches = list(re.finditer(rf"(?m)^{prefix}if: (.*)$", header))
    if len(matches) != 1:
        return None
    first = matches[0].group(1).strip()
    if first in {">-", ">"}:
        lines = []
    elif first.startswith(("|", "'", '\"')):
        return None
    else:
        lines = [first]
    rest = header[matches[0].end():].lstrip("\n")
    for line in rest.splitlines():
        if not line.startswith(prefix + " "):
            break
        lines.append(line.strip())
    return " ".join(lines)


def effective_deployment_condition(header: str) -> str | None:
    return effective_condition(header, 4)


def exact_deployment_condition(header: str) -> bool:
    return effective_deployment_condition(header) == EXPECTED_DEPLOYMENT_CONDITION


def management_api_mutations(text: str) -> list[tuple[str, str]]:
    """Classify curl calls to Management API without parsing unrelated REST probes."""

    calls: list[tuple[str, str]] = []
    for url_match in re.finditer(r'"(https://api[.]supabase[.]com/[^"\n]+)"', text):
        curl_start = text.rfind("curl ", 0, url_match.start())
        if curl_start < 0:
            continue
        curl_block = text[curl_start : url_match.end()]
        methods = re.findall(r"--request\s+([A-Z]+)", curl_block)
        method = methods[-1] if methods else "GET"
        if method in {"PATCH", "POST", "PUT", "DELETE"}:
            calls.append((method, url_match.group(1)))
    return calls



def step_script(text: str, name: str) -> str:
    """Extract the actual Bash body so fixtures exercise the shipped workflow."""

    step = text.split(f"      - name: {name}\n", 1)[1].split("      - name:", 1)[0]
    return textwrap.dedent(step.split("        run: |\n", 1)[1]).rstrip() + "\n"


def exercise_scope_classifiers(text: str) -> int:
    """Use disposable Git history, no Supabase runtime or hosted authority."""

    push = step_script(text, "Classify exact persistent Dev push scope")
    preview = step_script(text, "Classify exact Supabase Preview scope")
    authority = step_script(text, "Check Preview verification authority")
    current = step_script(text, "Verify current persistent Dev deployment scope")
    checks = 0
    with tempfile.TemporaryDirectory(prefix="database-workflow-contract-") as folder:
        root = Path(folder)
        repo = root / "repo"
        repo.mkdir()
        env = {
            "PATH": os.environ["PATH"],
            "HOME": folder,
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_AUTHOR_NAME": "Workflow fixture",
            "GIT_AUTHOR_EMAIL": "fixture@example.invalid",
            "GIT_COMMITTER_NAME": "Workflow fixture",
            "GIT_COMMITTER_EMAIL": "fixture@example.invalid",
        }

        def git(*args: str) -> str:
            return subprocess.check_output(["git", *args], cwd=repo, env=env, text=True).strip()

        def write(path: str, body: str = "fixture\n") -> None:
            target = repo / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(body)

        def commit(parent: str | None = None) -> str:
            git("add", "-A")
            tree = git("write-tree")
            args = ["commit-tree", tree, "-m", "Disposable workflow fixture"]
            if parent:
                args += ["-p", parent]
            sha = git(*args)
            git("checkout", "-q", "--detach", sha)
            return sha

        def run(script: str, values: dict[str, str], expected: str | None,
                *, fail: bool = False) -> None:
            nonlocal checks
            output = root / "output"
            output.write_text("")
            result = subprocess.run(
                ["bash", "--noprofile", "--norc", "-e", "-o", "pipefail", "-c", script],
                cwd=repo, env={**env, **values, "GITHUB_OUTPUT": str(output)},
                text=True, capture_output=True,
            )
            assert (result.returncode != 0) == fail, (values, result.returncode, result.stderr)
            assert output.read_text() == (f"required={expected}\n" if expected else ""), values
            checks += 1

        git("init", "-q", "--template=")
        deployable = (
            "supabase/config.toml", "supabase/migrations/001.sql", "supabase/seed.sql",
            "supabase/seeds/dev.sql", "supabase/functions/example/index.ts",
        )
        for path in deployable:
            write(path)
        write("README.md")
        base = commit()

        def push_values(head: str) -> dict[str, str]:
            return {"GITHUB_REF": "refs/heads/dev", "GITHUB_SHA": head,
                    "PUSH_BASE_SHA": base, "PUSH_HEAD_SHA": head}

        def preview_values(head: str) -> dict[str, str]:
            return {"PREVIEW_BASE_SHA": base, "PREVIEW_HEAD_SHA": head,
                    "PREVIEW_BASE_BRANCH": "dev", "PREVIEW_GIT_BRANCH": "dependabot/github_actions/fixture",
                    "GITHUB_ACTOR": "dependabot[bot]"}

        for path in (".github/dependabot.yml", ".github/workflows/supabase-dev.yml",
                     "scripts/test.py", "supabase/workspace/schema.sql",
                     "supabase/tests/test.sql", "supabase/templates/recovery.html", "README.md"):
            git("checkout", "-q", "--detach", base)
            write(path, "nondeployable update\n")
            head = commit(base)
            run(push, push_values(head), "false")
            run(preview, preview_values(head), "false")

        for path in deployable:
            git("checkout", "-q", "--detach", base)
            write(path, "deployable update\n")
            head = commit(base)
            run(push, push_values(head), "true")
            run(preview, preview_values(head), "true")
            # Same-repository bot identity cannot replace missing Preview authority.
            run(authority, {"GITHUB_ACTOR": "dependabot[bot]"}, None, fail=True)

        git("checkout", "-q", "--detach", base)
        write(deployable[1], "first pushed commit\n")
        intermediate = commit(base)
        write("README.md", "second pushed commit\n")
        head = commit(intermediate)
        run(push, push_values(head), "true")
        git("checkout", "-q", "--detach", base)
        (repo / deployable[1]).unlink()
        write("README.md", "mixed removal\n")
        head = commit(base)
        run(push, push_values(head), "true")
        # Renaming a migration out of the allowlist must also remain deployable.
        git("checkout", "-q", "--detach", base)
        git("mv", deployable[1], "retired.sql")
        head = commit(base)
        run(push, push_values(head), "true")
        git("checkout", "-q", "--detach", base)
        run(push, push_values(base), "false")
        for bad_base in ("", "0" * 40, "f" * 40, "--help"):
            run(push, {**push_values(base), "PUSH_BASE_SHA": bad_base}, None, fail=True)
        run(push, {**push_values(base), "PUSH_HEAD_SHA": "f" * 40}, None, fail=True)
        run(push, {**push_values(base), "PUSH_HEAD_SHA": "f" * 40,
                   "GITHUB_SHA": "f" * 40}, None, fail=True)
        run(push, {**push_values(base), "GITHUB_REF": "refs/heads/main"}, None, fail=True)
        # An unrelated root commit and a stale checkout cannot authorize deployment.
        write("README.md", "unrelated\n")
        unrelated = commit()
        run(push, push_values(unrelated), None, fail=True)
        run(push, push_values(base), None, fail=True)
        git("checkout", "-q", "--detach", base)
        # A real Git diff error must not be mistaken for a deployable difference.
        git_bin = shutil.which("git", path=env["PATH"])
        shim = root / "bin"
        shim.mkdir()
        wrapper = shim / "git"
        wrapper.write_text('#!/bin/bash\nif [[ "$1" == diff ]]; then exit 128; fi\nexec '
                           + shlex.quote(git_bin) + ' "$@"\n')
        wrapper.chmod(0o755)
        run(push, {**push_values(base), "PATH": str(shim) + os.pathsep + env["PATH"]},
            None, fail=True)
        run(preview, {**preview_values(base), "PREVIEW_BASE_SHA": "f" * 40}, None, fail=True)
        # Real fetched Dev heads model waiting checks, queueing and out-of-order completion.
        git("remote", "add", "origin", str(repo))

        def current_values(candidate: str) -> dict[str, str]:
            return {"GITHUB_REF": "refs/heads/dev", "GITHUB_SHA": candidate}

        # Any newer deployable family supersedes an older otherwise-qualified run.
        for path in deployable:
            git("checkout", "-q", "--detach", base)
            write(path, "newer deployable input\n")
            candidate = commit(base)
            git("update-ref", "refs/heads/dev", candidate)
            git("checkout", "-q", "--detach", base)
            run(current, current_values(base), "false")
        git("checkout", "-q", "--detach", base)
        write(deployable[1], "deployable A\n")
        a = commit(base)
        write("README.md", "nondeployable B\n")
        b = commit(a)
        git("update-ref", "refs/heads/dev", b)
        # B must not cancel A at workflow level or enter/replace its deployment queue.
        run(push, {**push_values(b), "PUSH_BASE_SHA": a}, "false")
        git("checkout", "-q", "--detach", a)
        run(current, current_values(a), "true")
        # Deployable C may complete checks first; its tree includes A and must win.
        git("checkout", "-q", "--detach", b)
        write(deployable[2], "newer deployable C\n")
        c = commit(b)
        git("update-ref", "refs/heads/dev", c)
        run(current, current_values(c), "true")
        git("checkout", "-q", "--detach", a)
        run(current, current_values(a), "false")
        # A late older pending job cannot overwrite C, even after a later docs push.
        git("checkout", "-q", "--detach", c)
        write("README.md", "nondeployable D\n")
        d = commit(c)
        git("update-ref", "refs/heads/dev", d)
        git("checkout", "-q", "--detach", a)
        run(current, current_values(a), "false")
        git("checkout", "-q", "--detach", c)
        run(current, current_values(c), "true")
        # Unknown history/ref, stale checkout, failed fetch and diff errors all stop.
        run(current, current_values(a), None, fail=True)
        run(current, {**current_values(c), "GITHUB_REF": "refs/heads/main"}, None, fail=True)
        git("update-ref", "refs/heads/dev", unrelated)
        run(current, current_values(c), None, fail=True)
        git("update-ref", "refs/heads/dev", d)
        run(current, {**current_values(c), "PATH": str(shim) + os.pathsep + env["PATH"]}, None, fail=True)
        git("remote", "remove", "origin")
        run(current, current_values(c), None, fail=True)
    return checks


def main() -> int:
    text = WORKFLOW.read_text(encoding="utf-8")
    lowered = text.lower()

    forbidden = {
        "Edge Functions command": "supabase functions",
        "project configuration deploy": "supabase config push",
    }
    failures = [label for label, token in forbidden.items() if token in lowered]
    for event, expected in (("push", {"dev"}), ("pull_request", {"dev", "main"})):
        event_block = re.search(
            rf"(?ms)^  {event}:\n(.*?)(?=^  \w|^\w|\Z)", text
        )
        branches = set(re.findall(r"(?m)^      - (\S+)\s*$", event_block.group(1))) if event_block else set()
        if branches != expected:
            failures.append(
                f"{event} branches must be {sorted(expected)}: validate Main hotfix PRs without deploying persistent Dev"
            )

    supabase_cli_versions = re.findall(
        r"uses: supabase/setup-cli@v3\s+with:\s+version:\s*([^\s#]+)", text
    )
    if supabase_cli_versions != ["2.117.0"] * 4:
        failures.append(
            "all four local, ARM profile, persistent-Dev, and Preview Supabase CLI pins "
            f"must be 2.117.0, found {supabase_cli_versions or 'none'}"
        )

    expected_head = resolve_migration_head(MIGRATIONS)
    if re.search(r'EXPECTED_MIGRATION_HEAD:\s*["\']?\d{14}', text):
        failures.append("migration head must not be pinned manually")

    api_contract_text = API_CONTRACT_TEST.read_text(encoding="utf-8")
    api_contract_heads = re.findall(
        r"api[.]svc_schema_contract_status[(][)]\s*->>\s*'migrationHead'\s*,"
        r"\s*'(\d{14})'::text",
        api_contract_text,
    )
    if api_contract_heads != [expected_head]:
        failures.append(
            "API closure must assert the exact checkout migration head "
            f"{expected_head}, found {api_contract_heads or 'none'}"
        )

    jobs = job_sections(text)
    local_workflow = jobs.get("local-contract", "")
    profile_workflow = jobs.get("scheduler-profile", "")
    hosted_workflow = jobs.get("deploy-and-verify", "")
    preview_workflow = jobs.get("preview-runtime-contract", "")
    if not local_workflow:
        failures.append("x64 local contract job is missing")
    if not profile_workflow:
        failures.append("ARM64 scheduler profile job is missing")
    if not hosted_workflow:
        failures.append("persistent-Dev job is missing")
    if not preview_workflow:
        failures.append("Preview runtime job is missing")

    scope_closure_checks = (
        "supabase test db supabase/tests/20260801_scope_closure_cutoff_main_hotfix.sql",
        "supabase test db supabase/tests/20260724_initial_candidate_scope_closure_e2e.sql",
        "supabase test db supabase/tests/20260722_scope_closure_release_binding_e2e.sql",
        "supabase test db supabase/tests/20260722_data_product_scope_closure_and_task_feed.sql",
        "scripts/test_scope_closure_scanner_upgrade.sh",
    )
    failures.extend(
        f"local Scope Closure validation missing {command}"
        for command in scope_closure_checks
        if command not in local_workflow
    )
    if "continue-on-error:" in local_workflow:
        failures.append("local contract checks must not allow failures")
    if "SCOPE_CLOSURE_UPGRADE_ALLOW_RESET: isolated" not in local_workflow:
        failures.append("scanner upgrade must use the explicitly isolated local runner")
    upgrade_script = (REPO_ROOT / "scripts/test_scope_closure_scanner_upgrade.sh").read_text()
    for isolation_token in (
        '${GITHUB_ACTIONS:-}', '${RUNNER_ENVIRONMENT:-}', 'github-hosted',
        '${GITHUB_WORKSPACE:-}', '${DOCKER_HOST:-}', '${DOCKER_CONTEXT:-}',
        'docker context inspect', 'unix://*',
    ):
        if isolation_token not in upgrade_script:
            failures.append(f"scanner upgrade isolation check missing {isolation_token}")
    upgrade_order = (
        upgrade_script.find("supabase db reset --local --version 20261011151720 --no-seed"),
        upgrade_script.find('supabase test db "$fixture"'),
        upgrade_script.find("supabase migration up --local"),
    )
    if -1 in upgrade_order or upgrade_order != tuple(sorted(upgrade_order)):
        failures.append("scanner upgrade must verify the populated canonical base before restoring HEAD")
    for forbidden_upgrade_token in ("--linked", "--db-url", "SUPABASE_ACCESS_TOKEN", "|| true"):
        if forbidden_upgrade_token in upgrade_script:
            failures.append(f"scanner upgrade must not use {forbidden_upgrade_token}")

    profile_required = (
        "runs-on: ubuntu-24.04-arm",
        "timeout-minutes: 25",
        "uses: actions/checkout@v7",
        "uses: supabase/setup-cli@v3",
        "run: supabase start && supabase db reset --no-seed",
        "supabase test db supabase/tests/20260923_derivative_scheduler_benchmark.sql",
        "supabase test db supabase/tests/20260923_derivative_scheduler_history_profile.sql",
        "if: always()",
        "run: supabase stop --no-backup",
    )
    failures.extend(
        f"ARM64 scheduler profile missing {token}"
        for token in profile_required
        if token not in profile_workflow
    )
    benchmark = "supabase test db supabase/tests/20260923_derivative_scheduler_benchmark.sql"
    history = "supabase test db supabase/tests/20260923_derivative_scheduler_history_profile.sql"
    if profile_workflow.count("supabase db reset --no-seed") != 2 or not (
        0 <= profile_workflow.find(benchmark)
        < profile_workflow.find("          supabase db reset --no-seed\n", profile_workflow.find(benchmark))
        < profile_workflow.find(history)
    ):
        failures.append("ARM64 profiles must run in order with an isolated database reset")
    if benchmark in local_workflow or history in local_workflow:
        failures.append("production-shape profiles must run only in the separate ARM64 job")
    if any(token in profile_workflow for token in (
        "SUPABASE_ACCESS_TOKEN", "SUPABASE_DB_PASSWORD", "supabase link", "supabase db push",
        "--request PATCH", "--linked",
    )):
        failures.append("ARM64 profile job must not receive hosted authority or mutate hosted projects")

    hosted_required = (
        "uses: actions/checkout@v7",
        "needs: [local-contract, scheduler-profile]",
        "SUPABASE_DB_PASSWORD: ${{ secrets.SUPABASE_DEV_DB_PASSWORD }}",
        'supabase link --project-ref "$SUPABASE_PROJECT_ID"',
        "supabase db push --include-all",
        "id: migration_head",
        "python scripts/resolve_migration_head.py",
        "EXPECTED_MIGRATION_HEAD: ${{ steps.migration_head.outputs.head }}",
    )
    failures.extend(
        f"hosted verification missing {token}"
        for token in hosted_required
        if token not in hosted_workflow
    )

    push_scope = step_script(text, "Classify exact persistent Dev push scope")
    for token in (
        "deploy_required: ${{ steps.dev_scope.outputs.required }}",
        "if: github.event_name == 'push'",
        "PUSH_BASE_SHA: ${{ github.event.before }}",
        "PUSH_HEAD_SHA: ${{ github.event.after }}",
    ):
        if token not in local_workflow:
            failures.append(f"secretless local job must classify push scope: {token}")
    hosted_header = hosted_workflow.split("    steps:", 1)[0]
    if not exact_deployment_condition(hosted_header):
        failures.append("persistent Dev must require the complete exact deployable-diff condition before credentials")
    for bypass in (
        " || true", " || always()", "\n      || true", "\n      || success()",
    ):
        mutated = hosted_header.replace(
            "needs.local-contract.outputs.deploy_required == 'true'",
            "needs.local-contract.outputs.deploy_required == 'true'" + bypass,
        )
        if exact_deployment_condition(mutated):
            failures.append(f"deployment condition parser accepted bypass {bypass!r}")
    for bypass in (" || true", "\n          || true"):
        scalar = "        if: steps.current_dev_scope.outputs.required == 'true'" + bypass + "\n        shell: bash\n"
        if effective_condition(scalar, 8) == "steps.current_dev_scope.outputs.required == 'true'":
            failures.append(f"step condition parser accepted bypass {bypass!r}")
    workflow_header = text.split("jobs:\n", 1)[0]
    if (
        "group: supabase-dev-deployment-${{ github.event_name == 'push' && github.run_id || github.ref }}" not in workflow_header
        or "cancel-in-progress: ${{ github.event_name != 'push' }}" not in workflow_header
    ):
        failures.append("Dev pushes must use distinct run groups without cancelling earlier push proof")
    if "    concurrency:\n      group: supabase-persistent-dev\n      cancel-in-progress: false\n      queue: max\n" not in hosted_header:
        failures.append("persistent Dev jobs must serialize and preserve queued deployment candidates")
    hosted_steps = hosted_workflow.split("    steps:\n", 1)[1]
    for step in hosted_steps.split("      - name:")[1:]:
        name = step.splitlines()[0].strip()
        if name in {"Checkout repository", "Verify current persistent Dev deployment scope"}:
            continue
        if effective_condition(step.split("        run:", 1)[0], 8) != "steps.current_dev_scope.outputs.required == 'true'":
            failures.append(f"hosted step must require the complete current Dev scope condition: {name}")
    if "secrets." in local_workflow or "SUPABASE_ACCESS_TOKEN" in push_scope:
        failures.append("push classification/local checks must remain free of hosted authority")
    for path in ("supabase/config.toml", "supabase/migrations/", "supabase/seed.sql",
                 "supabase/seeds/", "supabase/functions/"):
        if push_scope.count(path) != 1:
            failures.append(f"persistent Dev classifier must contain deployable path exactly once: {path}")
    if "permissions:\n  contents: read\n" not in text:
        failures.append("workflow token must default to read-only contents")

    if lowered.count("supabase db push --include-all") != 1:
        failures.append("workflow must contain exactly one database-only db push")

    exact_postgrest_patch = (
        '{"db_schema":"public,api,graphql_public",'
        '"db_extra_search_path":"public,api,extensions","max_rows":1000}'
    )
    if hosted_workflow.count("--request PATCH") != 1:
        failures.append("persistent-Dev job must contain exactly one PostgREST PATCH")
    if hosted_workflow.count(exact_postgrest_patch) != 1:
        failures.append("persistent-Dev PATCH must contain only the exact runtime contract")
    if preview_workflow.count("--request PATCH") != 1:
        failures.append("Preview job must contain exactly one PostgREST PATCH")
    if preview_workflow.count(exact_postgrest_patch) != 1:
        failures.append("Preview PATCH must contain only the exact runtime contract")
    if text.count("--request PATCH") != 2:
        failures.append("workflow must contain exactly two targeted PostgREST PATCH calls")
    expected_management_mutations = {
        (
            "PATCH",
            "https://api.supabase.com/v1/projects/$SUPABASE_PROJECT_ID/postgrest",
        ),
        (
            "PATCH",
            "https://api.supabase.com/v1/projects/$PREVIEW_PROJECT_REF/postgrest",
        ),
    }
    actual_management_mutations = management_api_mutations(text)
    if len(actual_management_mutations) != 2 or set(actual_management_mutations) != expected_management_mutations:
        failures.append(
            "Management API mutation surface must be exactly one persistent-Dev and one Preview PostgREST PATCH"
        )

    deployment_order = (
        hosted_workflow.find('supabase link --project-ref "$SUPABASE_PROJECT_ID"'),
        hosted_workflow.find("supabase db push --include-all"),
        hosted_workflow.find("- name: Apply exact PostgREST runtime contract"),
        hosted_workflow.find("id: migration_head"),
        hosted_workflow.find("- name: Verify exact deployed migration head"),
        hosted_workflow.find("- name: Verify hosted PostgREST boundary"),
    )
    if -1 not in deployment_order and deployment_order != tuple(sorted(deployment_order)):
        failures.append(
            "link, migration push, PostgREST runtime PATCH, and hosted probes are out of order"
        )

    preview_required = (
        "github.event_name == 'pull_request'",
        "github.event.pull_request.head.repo.full_name == github.repository",
        "SUPABASE_ACCESS_TOKEN: ${{ secrets.SUPABASE_ACCESS_TOKEN }}",
        "SUPABASE_MAIN_PROJECT_ID: ${{ vars.SUPABASE_MAIN_PROJECT_ID }}",
        "PREVIEW_BASE_BRANCH: ${{ github.event.pull_request.base.ref }}",
        "PREVIEW_GIT_BRANCH: ${{ github.event.pull_request.head.ref }}",
        "PREVIEW_BASE_SHA: ${{ github.event.pull_request.base.sha }}",
        "PREVIEW_HEAD_SHA: ${{ github.event.pull_request.head.sha }}",
        "PREVIEW_PR_NUMBER: ${{ github.event.pull_request.number }}",
        "Classify exact Supabase Preview scope",
        "id: preview_scope",
        'git cat-file -e "$PREVIEW_BASE_SHA^{commit}"',
        'git cat-file -e "$PREVIEW_HEAD_SHA^{commit}"',
        '[[ "$PREVIEW_BASE_BRANCH" == "main" && "$PREVIEW_GIT_BRANCH" == "dev" ]]',
        "Exact dev-to-main promotion reuses prior disposable Preview and persistent Dev proof.",
        'git diff --quiet "$PREVIEW_BASE_SHA" "$PREVIEW_HEAD_SHA" --',
        "supabase/config.toml",
        "supabase/migrations/",
        "supabase/seed.sql",
        "supabase/seeds/",
        "supabase/functions/",
        'echo "required=false" >> "$GITHUB_OUTPUT"',
        'echo "required=true" >> "$GITHUB_OUTPUT"',
        "steps.preview_scope.outputs.required == 'true'",
        "steps.preview_authority.outputs.available == 'true'",
        "Supabase Preview runtime verification requires SUPABASE_ACCESS_TOKEN, SUPABASE_MAIN_PROJECT_ID, and SUPABASE_DEV_PROJECT_ID",
        "exit 1",
        "uses: supabase/setup-cli@v3",
        "version: 2.117.0",
        "Wait for exact Supabase Preview check",
        "check_name=Supabase%20Preview&filter=latest",
        '.name == "Supabase Preview"',
        '.head_sha == $head',
        ".app.id == 330661",
        '.app.slug == "supabase"',
        '.app.owner.login == "supabase"',
        '.conclusion == "success"',
        'capture("^https://supabase[.]com/dashboard/project/(?<ref>[a-z]{20})$").ref',
        'EXPECTED_PREVIEW_PROJECT_REF: ${{ steps.supabase_preview_check.outputs.ref }}',
        "supabase branches list",
        '--project-ref "$SUPABASE_MAIN_PROJECT_ID"',
        "--output json",
        '--arg branch "$PREVIEW_GIT_BRANCH"',
        '--arg parent "$SUPABASE_MAIN_PROJECT_ID"',
        '--argjson pr_number "$PREVIEW_PR_NUMBER"',
        ".git_branch == $branch",
        ".pr_number == $pr_number",
        ".parent_project_ref == $parent",
        ".is_default == false",
        ".persistent == false",
        '(.project_ref | test("^[a-z]{20}$"))',
        "if length == 1 then .[0].project_ref",
        '[[ "$preview_project_ref" == "$EXPECTED_PREVIEW_PROJECT_REF" ]]',
        '[[ "$preview_project_ref" != "$SUPABASE_MAIN_PROJECT_ID" ]]',
        '[[ "$preview_project_ref" != "$SUPABASE_DEV_PROJECT_ID" ]]',
        "Read back exact Preview PostgREST runtime contract",
        '"https://api.supabase.com/v1/projects/$PREVIEW_PROJECT_REF/api-keys"',
        "(.disabled // false) == false",
        '.type == "publishable"',
        '.name == "anon"',
        '.type == "legacy"',
        '(.api_key | type == "string")',
        'test("^sb_publishable_[A-Za-z0-9_-]+$")',
        'test("^eyJ[A-Za-z0-9_-]+[.][A-Za-z0-9_-]+[.][A-Za-z0-9_-]+$")',
        "unset api_keys SUPABASE_ACCESS_TOKEN",
        "PREVIEW_PUBLIC_API_KEY=%s",
        "id: preview_api_key",
        'Content-Profile: api',
        'portal_hybrid_search_v1',
        'portal.public-hybrid-candidate-page.v1.schema.json',
        "sanitized_error_code=",
        'test("^(PGRST[0-9]{3}|[0-9A-Z]{5})$")',
        "with sanitized code $sanitized_error_code",
        'assert_opaque_error 404 PGRST202',
        'assert_opaque_error 406 PGRST106',
        'p_actor_id p_team_id p_state_codes p_data_source',
        'Verify anonymous Preview sitemap shard boundary',
        'portal_sitemap_manifest_v1',
        'portal_sitemap_shard_v1',
        'portal.public-sitemap-manifest.v1.schema.json',
        'portal.public-sitemap-shard.v1.schema.json',
        'probe_deadline=$((SECONDS + 300))',
        '--connect-timeout 5',
        '--max-time "$request_timeout"',
        "steps.preview_api_key.outcome == 'success'",
        'always()',
        '(.shards | length) == 64',
        'all(.shards[]; .maxItems == 4096)',
        '.code == "22023"',
    )
    failures.extend(
        f"Preview verification missing {token}"
        for token in preview_required
        if token not in preview_workflow
    )
    if preview_workflow.count("probe_deadline=$((SECONDS + 300))") != 2:
        failures.append(
            "Hybrid and sitemap Preview readiness probes must each use one exact 300-second deadline"
        )
    if preview_workflow.count('--max-time "$request_timeout"') != 2:
        failures.append(
            "Hybrid and sitemap readiness curl calls must be bounded by their remaining deadline"
        )
    preview_scope_step = preview_workflow.split(
        "- name: Classify exact Supabase Preview scope", 1
    )[-1].split("- name: Check Preview verification authority", 1)[0]
    if preview_scope_step.count(
        'git diff --quiet "$PREVIEW_BASE_SHA" "$PREVIEW_HEAD_SHA" --'
    ) != 1:
        failures.append("Preview scope must use one exact base-to-head diff")
    promotion_guard = (
        '[[ "$PREVIEW_BASE_BRANCH" == "main" && "$PREVIEW_GIT_BRANCH" == "dev" ]]'
    )
    if preview_scope_step.count(promotion_guard) != 1:
        failures.append(
            "Preview scope must contain exactly one narrow dev-to-main promotion guard"
        )
    promotion_guard_position = preview_scope_step.find(promotion_guard)
    deployable_diff_position = preview_scope_step.find(
        'git diff --quiet "$PREVIEW_BASE_SHA" "$PREVIEW_HEAD_SHA" --'
    )
    if not (0 <= promotion_guard_position < deployable_diff_position):
        failures.append(
            "exact dev-to-main promotion classification must precede deployable Preview diff classification"
        )
    promotion_block = preview_scope_step.split(promotion_guard, 1)[-1].split("fi", 1)[0]
    if (
        promotion_block.count('echo "required=false" >> "$GITHUB_OUTPUT"') != 1
        or "exit 0" not in promotion_block
    ):
        failures.append(
            "exact dev-to-main promotion must stop before Preview authority with required=false"
        )
    for deployable_path in (
        "supabase/config.toml",
        "supabase/migrations/",
        "supabase/seed.sql",
        "supabase/seeds/",
        "supabase/functions/",
    ):
        if preview_scope_step.count(deployable_path) != 1:
            failures.append(
                f"Preview scope must contain deployable path exactly once: {deployable_path}"
            )
    for nondeployable_path in (
        "supabase/workspace/",
        "supabase/tests/",
        "supabase/templates/",
    ):
        if nondeployable_path in preview_scope_step:
            failures.append(
                f"Preview scope must not treat repository-only path as deployable: {nondeployable_path}"
            )
    if preview_workflow.count('echo "required=false" >> "$GITHUB_OUTPUT"') != 2:
        failures.append(
            "Preview scope must emit exactly one promotion and one no-change outcome"
        )
    if preview_workflow.count('echo "required=true" >> "$GITHUB_OUTPUT"') != 1:
        failures.append("Preview scope must emit exactly one runtime-required outcome")
    for app_identity_token in (
        ".app.id == 330661",
        '.app.slug == "supabase"',
        '.app.owner.login == "supabase"',
    ):
        if preview_workflow.count(app_identity_token) < 3:
            failures.append(
                "Preview exact-count, success, and failure checks must all bind "
                f"the official Supabase App with {app_identity_token}"
            )

    preview_forbidden = (
        "supabase link",
        "supabase db push",
        "supabase config push",
        "supabase functions",
        "SUPABASE_DB_PASSWORD",
        "supabase branches get",
        "supabase projects api-keys",
        "?reveal=true",
    )
    failures.extend(
        f"Preview verification must not contain {token}"
        for token in preview_forbidden
        if token.lower() in preview_workflow.lower()
    )

    preview_order = (
        preview_workflow.find("- name: Checkout exact PR head"),
        preview_workflow.find("- name: Classify exact Supabase Preview scope"),
        preview_workflow.find("- name: Check Preview verification authority"),
        preview_workflow.find("- name: Wait for exact Supabase Preview check"),
        preview_workflow.find("- name: Resolve exact Preview project"),
        preview_workflow.find("- name: Apply exact Preview PostgREST runtime contract"),
        preview_workflow.find("- name: Read back exact Preview PostgREST runtime contract"),
        preview_workflow.find("- name: Verify anonymous Preview Hybrid boundary"),
        preview_workflow.find("- name: Verify anonymous Preview sitemap shard boundary"),
    )
    if -1 not in preview_order and preview_order != tuple(sorted(preview_order)):
        failures.append(
            "Preview check, branch resolution, PATCH, readback, and anonymous probes are out of order"
        )

    preview_probe_marker = "- name: Verify anonymous Preview Hybrid boundary"
    preview_key_marker = "- name: Read enabled Preview public API key"
    preview_key_step = preview_workflow.split(preview_key_marker, 1)[-1].split(
        preview_probe_marker, 1
    )[0]
    preview_probe = preview_workflow.split(preview_probe_marker, 1)[-1]
    preview_job_header = preview_workflow.split("    steps:", 1)[0]
    if "secrets.SUPABASE_ACCESS_TOKEN" in preview_job_header:
        failures.append("Supabase access token must be scoped only to steps that require it")
    if "available=false" in preview_workflow or "verification skipped" in preview_workflow:
        failures.append(
            "same-repository Preview verification must fail closed when authority is missing"
        )
    for forbidden_probe_credential in (
        "Authorization:",
        "Cookie:",
        "SERVICE_ROLE",
        "service_role",
        "SUPABASE_ACCESS_TOKEN",
        "api-keys",
    ):
        if forbidden_probe_credential in preview_probe:
            failures.append(
                "anonymous Preview probes must not contain "
                f"{forbidden_probe_credential}"
            )
    for forbidden_probe_output in (
        'cat "$response_file"',
        'echo "$(<"$response_file")"',
        'echo "$(cat "$response_file")"',
    ):
        if forbidden_probe_output in preview_probe:
            failures.append(
                "anonymous Preview diagnostics must not print the raw "
                f"response body via {forbidden_probe_output}"
            )
    if preview_key_step.count(
        '"https://api.supabase.com/v1/projects/$PREVIEW_PROJECT_REF/api-keys"'
    ) != 1:
        failures.append("Preview probe must read API keys exactly once without reveal")
    if preview_key_step.count("(.disabled // false) == false") != 2:
        failures.append("Preview key selector must reject disabled publishable and anon keys")
    if preview_key_step.count('(.api_key | type == "string")') != 2:
        failures.append("Preview key selector must require concrete string public keys")
    if preview_key_step.find('.type == "publishable"') > preview_key_step.find('.name == "anon"'):
        failures.append("Preview key selector must prefer publishable over legacy anon")
    key_step_order = (
        preview_key_step.find('echo "::add-mask::$public_api_key"'),
        preview_key_step.find("PREVIEW_PUBLIC_API_KEY=%s"),
        preview_key_step.find("unset api_keys SUPABASE_ACCESS_TOKEN"),
    )
    if -1 in key_step_order or key_step_order != tuple(sorted(key_step_order)):
        failures.append("Preview public key must be masked, exported, then raw authority cleared")
    for forbidden_key_output in ('echo "$api_keys"', "?reveal=true"):
        if forbidden_key_output in preview_key_step:
            failures.append(
                f"Preview API-key read must not retain or print {forbidden_key_output}"
            )

    required = (
        "pull_request:",
        "supabase-dev-deployment-${{ github.event_name == 'push' && github.run_id || github.ref }}",
        "cancel-in-progress: ${{ github.event_name != 'push' }}",
        "github.event_name == 'push' && github.ref == 'refs/heads/dev'",
        "python scripts/test_resolve_migration_head.py",
        "python3 scripts/test_configure_derivative_scheduler.py",
        "python scripts/test_supabase_dev_workflow_contract.py",
        "python scripts/build_schema_workspace.py --environment local",
        "git diff --exit-code -- supabase/workspace",
        "git status --porcelain --untracked-files=all -- supabase/workspace",
        "::add-mask::",
        "svc_schema_contract_status",
        "SUPABASE_ACCESS_TOKEN",
        "SUPABASE_DEV_PROJECT_ID",
        "SUPABASE_MAIN_PROJECT_ID",
        "supabase db reset --no-seed",
        "supabase test db supabase/tests/20260830_oauth_client_capability_foundation.sql",
        "supabase test db supabase/tests/20260831_oauth_actor_command_capabilities.sql",
        "supabase test db supabase/tests/20260925_foundry60_cli_alias_oauth_capability.sql",
        "supabase test db supabase/tests/20260827_portal_sitemap_shards_v1.sql",
        "supabase test db supabase/tests/20260909_review_queue_full_text_search.sql",
        "supabase test db supabase/tests/20260929_rejected_review_report_download.sql",
        "supabase test db supabase/tests/20260909_tidas_partial_import.sql",
        "supabase test db supabase/tests/20260910_example_dataset_scope.sql",
        "supabase test db supabase/tests/20260714_guarded_dataset_derivative_rebuild.sql",
        "supabase test db supabase/tests/20260715_guarded_dataset_derivative_rebuild_batch.sql",
        "supabase test db supabase/tests/20260525_embedding_backpressure_and_deferred_queue.sql",
        "supabase test db supabase/tests/20260728_embedding_queue_selector_plan_governance.sql",
        "supabase test db supabase/tests/20260923_derivative_scheduler_budget.sql",
        "supabase test db supabase/tests/20260923_retired_sample_library_contract.sql",
        "supabase test db supabase/tests/20260923_derivative_scheduler_benchmark.sql",
        "supabase test db supabase/tests/20260923_derivative_scheduler_history_profile.sql",
        "supabase test db supabase/tests/20260921_foundry60_time_alias_v2_math.sql",
        "supabase test db supabase/tests/20260921_foundry60_time_alias_v2_vectors.sql",
        "supabase test db supabase/tests/20260921_foundry60_time_alias_v2.sql",
        "supabase test db supabase/tests/20260921_foundry60_time_alias_v2_batch.sql",
        "supabase test db supabase/tests/20260922_foundry60_time_alias_v2_protected.sql",
        "supabase test db supabase/tests/20260923_foundry60_time_alias_v2_rollback.sql",
        "supabase test db supabase/tests/20260924_foundry60_time_alias_v2_terminal.sql",
        "supabase test db supabase/tests/20260925_foundry186_length_time_v1.sql",
        "supabase test db supabase/tests/20260926_foundry60_time_alias_v2_current_closure.sql",
        "supabase test db supabase/tests/20260927_hotfix694_canonical_key_hash.sql",
        "supabase test db supabase/tests/20260919_portal_navigation_v1.sql",
        "supabase test db supabase/tests/20260919_portal_catalog_summary_bounded.sql",
        "supabase test db supabase/tests/20261010_portal_display_brand_foundation.sql",
        "supabase test db supabase/tests/20261010_portal_display_readers.sql",
        '"public", "api", "graphql_public"',
        '"public", "api", "extensions"',
        '"max_rows":1000',
        "and .max_rows == 1000",
        "Accept-Profile: private",
        "Content-Profile: public",
        "python3 scripts/test_protected_alias_postgrest_routing.py",
    )
    failures.extend(f"missing {token}" for token in required if token not in text)

    if failures:
        for failure in failures:
            print(f"FAIL: {failure}")
        return 1

    checks = exercise_scope_classifiers(text)
    print(f"PASS: {checks} offline push/Preview scope and missing-authority controls")
    print(
        "PASS: Supabase Dev workflow separately gates persistent Dev and exact "
        "PR Preview runtime contracts, limits Management API mutation to two "
        "three-field PostgREST PATCH calls, and verifies exact head "
        f"{expected_head}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
