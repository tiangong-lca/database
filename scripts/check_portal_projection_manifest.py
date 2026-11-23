#!/usr/bin/env python3
"""Fail when Portal projection-v1 closures drift outside reviewed forward paths."""

from __future__ import annotations

import hashlib
import re
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
MIGRATIONS_DIR = REPO_ROOT / "supabase" / "migrations"
ANCHOR_NAME = "20260826060422_portal_candidate_first_search.sql"
FLOW_ELIGIBILITY_INDEX_NAME = (
    "20260827010000_portal_flow_embedding_eligibility_index.sql"
)
FLOW_ELIGIBILITY_GUARD_NAME = (
    "20260827010003_portal_flow_embedding_eligibility_guard.sql"
)
FACET_ANCHOR_NAME = "20260827020000_portal_facet_projection_expand.sql"
FACET_RECONCILE_NAME = "20260827020005_portal_facet_projection_reconcile.sql"
FACET_CUTOVER_NAME = "20260827020006_portal_facet_projection_cutover.sql"
CARD_CONTEXT_ANCHOR_NAME = "20260827021441_portal_card_context_decorator.sql"
HYBRID_CORRECTNESS_TIMEOUT_NAME = (
    "20260901183000_portal_hybrid_correctness_timeout.sql"
)
FLOW_GEOGRAPHY_SEARCH_NAME = (
    "20260827134100_optimize_portal_flow_geography_search.sql"
)
FLOW_CAS_RLS_POLICY_NAME = (
    "20260829130000_make_portal_flow_cas_rls_indexable.sql"
)
SINGLE_CHARACTER_SEARCH_NAME = (
    "20260829131000_repair_portal_single_character_literal_search.sql"
)
CHARACTER_PROJECTION_EXPAND_NAME = (
    "20260829131001_portal_character_projection_expand.sql"
)
CHARACTER_PROJECTION_CUTOVER_NAME = (
    "20260829131006_portal_character_projection_cutover.sql"
)
PROCESS_KEYWORD_RANK_HELPERS_NAME = (
    "20260830134000_portal_process_keyword_rank_helpers.sql"
)
PROCESS_KEYWORD_RANK_INDEX_NAME = (
    "20260830134001_portal_process_keyword_rank_index.sql"
)
PROCESS_KEYWORD_RANK_CUTOVER_NAME = (
    "20260830134002_portal_process_keyword_rank_cutover.sql"
)
SITEMAP_LATEST_PROJECTION_NAME = (
    "20260827134101_portal_sitemap_latest_projection.sql"
)
SITEMAP_SHARD_CONTRACT_NAME = (
    "20260827134102_portal_sitemap_shard_contract.sql"
)
SITEMAP_REPAIR_NAME = "20260827134103_portal_sitemap_concurrency_repair.sql"
SITEMAP_PREVIEW_FIXTURE = (
    REPO_ROOT
    / "supabase"
    / "tests"
    / "upgrade"
    / "20260827_portal_sitemap_preview_winner_fixture.sql"
)
SITEMAP_PREVIEW_FIXTURE_SHA256 = (
    "bbdfa95524e1d47c85a8072737c676961f8285ed8054d8e9dec7fdd9499efb98"
)
MANIFEST_SHA256 = (
    "b5e0aff9abbffcc8d2dacaf559a5d1a8c993c20b647d0c70f0e4fa18eb06d2dc"
)
FUNCTION_IDENTITIES = (
    "private.catalog_portal_projection_payload_v1(text,integer,jsonb)",
    "private.portal_catalog_card_v1(text,integer,jsonb)",
    "private.portal_capabilities_v1(text,integer,jsonb)",
    "private.portal_publication_root_v1(text,jsonb)",
    "private.portal_access_restrictions_open_v1(jsonb)",
    "private.portal_scalar_text_v1(jsonb)",
    "private.portal_localized_text_v1(jsonb)",
    "private.portal_json_items_v1(jsonb)",
    "private.portal_classifications_v1(jsonb)",
    "private.portal_safe_year_v1(text)",
    "private.portal_source_v1(text,jsonb)",
)
CONTROL_FUNCTION_IDENTITIES = (
    "private.portal_catalog_projection_manifest_sha256_v1()",
    "private.assert_portal_catalog_projection_contract_v1()",
    "private.portal_projection_semantic_process_exact_v1(extensions.vector)",
    "private.portal_projection_semantic_flow_exact_v1(extensions.vector)",
)
# #1004 rebinds exactly one storage guard and one owner-only fallback.
PROCESS_CONTRACTION_NAME = "20261123034022_portal_process_single_search_projection.sql"
FACET_MANIFEST_SHA256 = (
    "b238e9573ef08a9339062a2fa3092c0776318d13979ec8bf54ffc7a1ba0c7e3a"
)
FACET_FUNCTION_IDENTITIES = (
    "private.portal_catalog_facet_facts_v1(text,jsonb)",
    "private.sync_portal_catalog_facet_row_v1()",
)
FACET_CONTROL_FUNCTION_IDENTITIES = (
    "private.portal_catalog_facet_manifest_sha256_v1()",
    "private.assert_portal_catalog_facet_contract_v1()",
)
CARD_CONTEXT_MANIFEST_SHA256 = (
    "e0516d5f3a641d26221a5c44b92a2e7a87cab125e9145e8141074d9bc2af39fa"
)
CARD_CONTEXT_FUNCTION_IDENTITIES = (
    "private.portal_card_context_v1(text,integer,jsonb)",
    "private.portal_decorate_card_context_v1(jsonb)",
    "private.portal_process_reference_product_v1(jsonb)",
    "private.portal_process_functional_unit_v1(integer,jsonb)",
    "private.portal_exchange_support_v1(integer,jsonb,jsonb)",
    "private.portal_reference_flowproperty_v1(jsonb)",
    "private.portal_localized_text_v1(jsonb)",
    "private.portal_scalar_text_v1(jsonb)",
    "private.portal_json_items_v1(jsonb)",
    "private.portal_source_v1(text,jsonb)",
    "private.portal_capabilities_v1(text,integer,jsonb)",
    "private.portal_canonical_decimal_v1(text)",
    "private.portal_flow_kind_v1(text)",
    "private.portal_support_capabilities_v1(text,integer)",
    "private.portal_classifications_v1(jsonb)",
    "private.portal_publication_root_v1(text,jsonb)",
    "private.portal_access_restrictions_open_v1(jsonb)",
)
CARD_CONTEXT_CONTROL_FUNCTION_IDENTITIES = (
    "private.portal_card_context_manifest_sha256_v1()",
    "private.assert_portal_card_context_contract_v1()",
)
HYBRID_TIMEOUT_FUNCTION_IDENTITIES = (
    "api.portal_hybrid_search_v1(text,text[],text,jsonb,integer)",
    "private.portal_projection_hybrid_search_v1_impl(text,text[],extensions.vector,jsonb,integer,text)",
    "private.catalog_portal_hybrid_pattern_matches_v1(text,text[])",
    "private.catalog_portal_process_pattern_versions_v1(text)",
    "private.catalog_portal_flow_pattern_versions_v1(text)",
    "private.catalog_portal_process_single_character_versions_v1(text)",
    "private.catalog_portal_flow_single_character_versions_v1(text)",
    "private.portal_projection_semantic_candidates_v1(text,extensions.vector)",
    "private.portal_projection_semantic_process_v1(extensions.vector)",
    "private.portal_projection_semantic_flow_v1(extensions.vector)",
    "private.portal_projection_semantic_process_exact_v1(extensions.vector)",
    "private.portal_projection_semantic_flow_exact_v1(extensions.vector)",
    "private.portal_decorate_card_context_v1(jsonb)",
)
HYBRID_TIMEOUT_CONTEXT_MANIFEST_SHA256 = (
    "db78336c8604848af1e068352f8a39d9ee740308c44c59c639b986ed2660c47e"
)
PROCESS_KEYWORD_RANK_MANIFEST_SHA256 = (
    "3dd65dc6b0dbd5ca8108d0a996610030bad1b5478d61ee9674a57580433e6bbf"
)
PROCESS_KEYWORD_RANK_FUNCTION_IDENTITIES = (
    "private.portal_process_rank_name_keys_v1(jsonb)",
    "private.portal_process_rank_classification_keys_v1(jsonb)",
    "private.catalog_portal_process_keyword_keys_v1(text,text,uuid,text,integer)",
    "private.catalog_portal_process_keyword_relevance_v1_impl(text,text,uuid,text,integer,text)",
)
PROCESS_KEYWORD_RANK_CONTROL_FUNCTION_IDENTITIES = (
    "private.portal_process_keyword_rank_manifest_sha256_v1()",
    "private.assert_portal_process_keyword_rank_contract_v1()",
)
PROCESS_KEYWORD_RANK_RETIREMENT_NAME = "20261007143357_retire_qualified_search_indexes.sql"
RETIRED_PROCESS_KEYWORD_RANK_IDENTITIES = (
    PROCESS_KEYWORD_RANK_FUNCTION_IDENTITIES[2:]
    + PROCESS_KEYWORD_RANK_CONTROL_FUNCTION_IDENTITIES
)
SITEMAP_SHARD_FUNCTION_IDENTITIES = (
    "private.sync_portal_sitemap_row_v1()",
    "private.sync_portal_sitemap_latest_row_v1()",
    "private.sync_portal_sitemap_latest_delete_v1()",
    "private.assert_portal_sitemap_projection_v1()",
    "api.portal_sitemap_manifest_v1()",
    "api.portal_sitemap_shard_v1(text)",
)


def sql_without_comments(sql: str) -> str:
    """Remove SQL comments while retaining executable strings and function bodies."""

    without_blocks = re.sub(r"/\*.*?\*/", " ", sql, flags=re.DOTALL)
    return re.sub(r"--[^\n]*", " ", without_blocks)


def mutation_pattern(identity: str) -> re.Pattern[str]:
    schema_name = identity.split(".", 1)[0]
    function_name = identity.split(".", 1)[1].split("(", 1)[0]
    return re.compile(
        rf"\b(?:"
        rf"create\s+(?:or\s+replace\s+)?function"
        rf"|drop\s+(?:function|routine)(?:\s+if\s+exists)?"
        rf"|alter\s+(?:function|routine)"
        rf")\s+"
        rf'(?:(?:"?{re.escape(schema_name)}"?)\s*\.\s*)?'
        rf'"?{re.escape(function_name)}"?\s*\(',
        flags=re.IGNORECASE,
    )


def reviewed_process_contraction(name: str, sql: str, identity: str) -> bool:
    if name != PROCESS_CONTRACTION_NAME or identity not in {
        "private.assert_portal_catalog_facet_contract_v1()",
        "private.portal_projection_semantic_process_exact_v1(extensions.vector)",
    }:
        return False
    mutations = list(mutation_pattern(identity).finditer(sql))
    return len(mutations) == 1 and mutations[0].group().lower().startswith("create or replace function ")


def reviewed_process_rank_retirement(name: str, sql: str, identity: str) -> bool:
    """Admit one exact DROP only; historical definitions and live shared keys stay frozen."""
    if name != PROCESS_KEYWORD_RANK_RETIREMENT_NAME or identity not in RETIRED_PROCESS_KEYWORD_RANK_IDENTITIES:
        return False
    # The general historical scanner recognizes the first DROP target. Do not
    # let a second target (or dynamic/unknown DROP) hide behind this exception.
    drops = re.findall(r"\bdrop\s+(?:function|routine)\b[^;]*;", sql, re.IGNORECASE)
    permitted = {
        re.sub(r"\s+", " ", f"drop function {item} restrict").lower()
        for item in RETIRED_PROCESS_KEYWORD_RANK_IDENTITIES
    }
    normalized = [re.sub(r"\s+", " ", drop[:-1].rstrip().rstrip("'").rstrip()).lower()
                  for drop in drops]
    if len(normalized) != len(permitted) or set(normalized) != permitted:
        return False
    mutations = list(mutation_pattern(identity).finditer(sql))
    if len(mutations) != 1:
        return False
    # The reviewed migration uses literal EXECUTE statements. Do not turn its
    # filename into a CREATE/ALTER/overload/CASCADE or future-migration waiver.
    exact_drop = re.compile(
        rf"drop\s+function\s+{re.escape(identity)}\s+restrict\s*'?\s*;",
        flags=re.IGNORECASE,
    )
    return exact_drop.match(sql, mutations[0].start()) is not None


def main() -> int:
    anchor = MIGRATIONS_DIR / ANCHOR_NAME
    if not anchor.is_file():
        print(f"missing Portal projection manifest anchor: {anchor}", file=sys.stderr)
        return 1
    if len(FUNCTION_IDENTITIES) != 11 or len(set(FUNCTION_IDENTITIES)) != 11:
        print("Portal projection manifest must contain exactly 11 identities", file=sys.stderr)
        return 1

    anchor_sql = anchor.read_text(encoding="utf-8")
    if MANIFEST_SHA256 not in anchor_sql:
        print("Portal projection manifest digest literal is absent", file=sys.stderr)
        return 1
    missing_identities = [
        identity for identity in FUNCTION_IDENTITIES if identity not in anchor_sql
    ]
    if missing_identities:
        print(
            "Portal projection manifest anchor omits: "
            + ", ".join(missing_identities),
            file=sys.stderr,
        )
        return 1

    violations: list[str] = []

    hybrid_timeout_migration = MIGRATIONS_DIR / HYBRID_CORRECTNESS_TIMEOUT_NAME
    if not hybrid_timeout_migration.is_file():
        violations.append(
            "missing Portal Hybrid correctness timeout migration: "
            + HYBRID_CORRECTNESS_TIMEOUT_NAME
        )
    else:
        timeout_sql = sql_without_comments(
            hybrid_timeout_migration.read_text(encoding="utf-8")
        )
        timeout_sql_lower = timeout_sql.lower()
        required_timeout_tokens = (
            "begin;",
            "set local lock_timeout = '5s'",
            "set local statement_timeout = '30s'",
            "grant portal_public_executor, api_internal_executor to postgres",
            "grant create on schema private to portal_public_executor",
            "revoke create on schema private from portal_public_executor",
            "revoke portal_public_executor, api_internal_executor from postgres",
            CARD_CONTEXT_MANIFEST_SHA256,
            HYBRID_TIMEOUT_CONTEXT_MANIFEST_SHA256,
            "create or replace function private.assert_portal_card_context_contract_v1()",
            "commit;",
        ) + HYBRID_TIMEOUT_FUNCTION_IDENTITIES
        missing = [
            token for token in required_timeout_tokens if token not in timeout_sql_lower
        ]
        if missing:
            violations.append(
                f"{HYBRID_CORRECTNESS_TIMEOUT_NAME}: missing bounded timeout tokens "
                + ", ".join(missing)
            )
        if timeout_sql_lower.count("set statement_timeout = '20s'") != 13:
            violations.append(
                f"{HYBRID_CORRECTNESS_TIMEOUT_NAME}: expected thirteen exact "
                "20-second function settings"
            )
        if len(
            re.findall(
                r"create\s+or\s+replace\s+function",
                timeout_sql,
                flags=re.IGNORECASE,
            )
        ) != 1:
            violations.append(
                f"{HYBRID_CORRECTNESS_TIMEOUT_NAME}: only the card-context "
                "assertion may be replaced"
            )
        if re.search(
            r"\b(?:create\s+(?:unlogged\s+)?table|create\s+(?:unique\s+)?index|"
            r"create\s+trigger|alter\s+table|insert\s+into|update\s+|"
            r"delete\s+from|truncate\s+)\b",
            timeout_sql,
            flags=re.IGNORECASE,
        ):
            violations.append(
                f"{HYBRID_CORRECTNESS_TIMEOUT_NAME}: config-only migration "
                "must not mutate schema data, projections, indexes, or writers"
            )
        for identity in HYBRID_TIMEOUT_FUNCTION_IDENTITIES:
            if len(mutation_pattern(identity).findall(timeout_sql)) != 1:
                violations.append(
                    f"{HYBRID_CORRECTNESS_TIMEOUT_NAME}: expected one config "
                    f"mutation for {identity}"
                )
    protected_identities = FUNCTION_IDENTITIES + CONTROL_FUNCTION_IDENTITIES
    patterns = {identity: mutation_pattern(identity) for identity in protected_identities}
    pattern_probes = (
        "create function private.portal_scalar_text_v1(jsonb)",
        "create or replace function private.portal_scalar_text_v1(jsonb)",
        "drop function if exists private.portal_scalar_text_v1(jsonb)",
        "alter routine private.portal_scalar_text_v1(jsonb) owner to postgres",
        "execute 'drop function private.portal_scalar_text_v1(jsonb)'",
    )
    leaf_pattern = patterns["private.portal_scalar_text_v1(jsonb)"]
    if any(not leaf_pattern.search(probe) for probe in pattern_probes):
        print("Portal projection manifest mutation scanner self-test failed", file=sys.stderr)
        return 1
    control_probe = (
        "alter function private.assert_portal_catalog_projection_contract_v1() "
        "security invoker"
    )
    if not patterns[
        "private.assert_portal_catalog_projection_contract_v1()"
    ].search(control_probe):
        print("Portal projection control-function scanner self-test failed", file=sys.stderr)
        return 1
    for migration in sorted(MIGRATIONS_DIR.glob("*.sql")):
        if migration.name <= ANCHOR_NAME:
            continue
        if migration.name == HYBRID_CORRECTNESS_TIMEOUT_NAME:
            continue
        executable_sql = sql_without_comments(migration.read_text(encoding="utf-8"))
        for identity, pattern in patterns.items():
            if pattern.search(executable_sql):
                if reviewed_process_contraction(migration.name, executable_sql, identity):
                    continue
                if (
                    migration.name == FLOW_CAS_RLS_POLICY_NAME
                    and identity
                    == "private.assert_portal_catalog_projection_contract_v1()"
                ):
                    continue
                violations.append(f"{migration.name}: {identity}")

    facet_anchor = MIGRATIONS_DIR / FACET_ANCHOR_NAME
    if not facet_anchor.is_file():
        violations.append(f"missing Portal facet manifest anchor: {FACET_ANCHOR_NAME}")
    else:
        facet_anchor_sql = facet_anchor.read_text(encoding="utf-8")
        if FACET_MANIFEST_SHA256 not in facet_anchor_sql:
            violations.append("Portal facet manifest digest literal is absent")
        for identity in FACET_FUNCTION_IDENTITIES + FACET_CONTROL_FUNCTION_IDENTITIES:
            if identity not in facet_anchor_sql:
                violations.append(f"Portal facet manifest anchor omits: {identity}")

    facet_protected = FACET_FUNCTION_IDENTITIES + FACET_CONTROL_FUNCTION_IDENTITIES
    facet_patterns = {
        identity: mutation_pattern(identity) for identity in facet_protected
    }
    facet_probe = (
        "create or replace function "
        "private.portal_catalog_facet_facts_v1(text,jsonb)"
    )
    if not facet_patterns[FACET_FUNCTION_IDENTITIES[0]].search(facet_probe):
        violations.append("Portal facet manifest mutation scanner self-test failed")
    for migration in sorted(MIGRATIONS_DIR.glob("*.sql")):
        if migration.name <= FACET_ANCHOR_NAME:
            continue
        executable_sql = sql_without_comments(migration.read_text(encoding="utf-8"))
        for identity, pattern in facet_patterns.items():
            if pattern.search(executable_sql) and not reviewed_process_contraction(migration.name, executable_sql, identity):
                violations.append(f"{migration.name}: {identity}")

    context_anchor = MIGRATIONS_DIR / CARD_CONTEXT_ANCHOR_NAME
    if not context_anchor.is_file():
        violations.append(
            f"missing Portal card-context migration: {CARD_CONTEXT_ANCHOR_NAME}"
        )
    else:
        context_sql = sql_without_comments(
            context_anchor.read_text(encoding="utf-8")
        )
        context_sql_lower = context_sql.lower()
        if CARD_CONTEXT_MANIFEST_SHA256 not in context_sql:
            violations.append("Portal card-context manifest digest literal is absent")
        for identity in (
            CARD_CONTEXT_FUNCTION_IDENTITIES
            + CARD_CONTEXT_CONTROL_FUNCTION_IDENTITIES
        ):
            if identity not in context_sql:
                violations.append(
                    f"Portal card-context manifest anchor omits: {identity}"
                )
        required_context_tokens = (
            "begin;",
            "set local lock_timeout = '5s'",
            "set local statement_timeout = '120s'",
            "portal_process_functional_unit_v1(100, p_json)",
            "portal_decorate_card_context_v1",
            "jsonb_array_elements(p_page -> 'items')",
            "join public.processes as source",
            "join public.flows as source",
            "v_expected > (",
            "then 50",
            "else 20",
            "portal_card_context_writer_before",
            "private.assert_portal_card_context_contract_v1()",
            "commit;",
        )
        missing = [
            token for token in required_context_tokens if token not in context_sql_lower
        ]
        if missing:
            violations.append(
                f"{CARD_CONTEXT_ANCHOR_NAME}: missing selected-row tokens "
                + ", ".join(missing)
            )
        for wrapper in (
            "api.portal_search_processes_v1",
            "api.portal_search_flows_v1",
            "api.portal_hybrid_search_v1",
        ):
            wrapper_pattern = re.compile(
                rf"create\s+or\s+replace\s+function\s+{re.escape(wrapper)}\s*\(",
                flags=re.IGNORECASE,
            )
            if len(wrapper_pattern.findall(context_sql)) != 1:
                violations.append(
                    f"{CARD_CONTEXT_ANCHOR_NAME}: expected one {wrapper} replacement"
                )
        if re.search(
            r"\b(?:create\s+(?:unlogged\s+)?table|create\s+(?:unique\s+)?index|"
            r"create\s+trigger|alter\s+table)\b",
            context_sql,
            flags=re.IGNORECASE,
        ):
            violations.append(
                f"{CARD_CONTEXT_ANCHOR_NAME}: selected-row decorator must not add "
                "a table, index, trigger, or source-table rewrite"
            )

    context_protected = (
        CARD_CONTEXT_FUNCTION_IDENTITIES
        + CARD_CONTEXT_CONTROL_FUNCTION_IDENTITIES
    )
    context_patterns = {
        identity: mutation_pattern(identity) for identity in context_protected
    }
    for migration in sorted(MIGRATIONS_DIR.glob("*.sql")):
        if migration.name <= CARD_CONTEXT_ANCHOR_NAME:
            continue
        if migration.name == HYBRID_CORRECTNESS_TIMEOUT_NAME:
            continue
        executable_sql = sql_without_comments(migration.read_text(encoding="utf-8"))
        for identity, pattern in context_patterns.items():
            if pattern.search(executable_sql):
                violations.append(f"{migration.name}: {identity}")

    flow_geography_search = MIGRATIONS_DIR / FLOW_GEOGRAPHY_SEARCH_NAME
    if not flow_geography_search.is_file():
        violations.append(
            f"missing Portal Flow geography Search migration: "
            f"{FLOW_GEOGRAPHY_SEARCH_NAME}"
        )
    else:
        geography_sql = sql_without_comments(
            flow_geography_search.read_text(encoding="utf-8")
        )
        geography_sql_lower = geography_sql.lower()
        required_geography_tokens = (
            "3fdf121819227c2885a23233ab406291c8310902cf413e3eca96f1f0809bb7f4",
            "cf1e7a540a9f0fe4370de7588160b7720eb97b94f641d6b3d019ab9780586936",
            "portal_latest_facts as materialized",
            "private.portal_catalog_facet_rows_v1",
            "facet.facet_geography",
            "portal_ordered_keys as materialized",
            "limit p_limit + 1",
            "join private.portal_catalog_search_rows_v1",
            "private.assert_portal_catalog_projection_contract_v1()",
            "private.assert_portal_catalog_facet_contract_v1()",
        )
        missing = [
            token
            for token in required_geography_tokens
            if token not in geography_sql_lower
        ]
        if missing:
            violations.append(
                f"{FLOW_GEOGRAPHY_SEARCH_NAME}: missing narrow Search tokens "
                + ", ".join(missing)
            )
        if len(
            re.findall(
                r"create\s+or\s+replace\s+function\s+"
                r'"?private"?\s*[.]\s*"?catalog_portal_search_v1_impl"?\s*[(]',
                geography_sql,
                flags=re.IGNORECASE,
            )
        ) != 1:
            violations.append(
                f"{FLOW_GEOGRAPHY_SEARCH_NAME}: expected one Search kernel replacement"
            )
        if re.search(
            r"\b(?:create\s+(?:unlogged\s+)?table|create\s+(?:unique\s+)?index|"
            r"create\s+trigger|alter\s+table)\b",
            geography_sql,
            flags=re.IGNORECASE,
        ):
            violations.append(
                f"{FLOW_GEOGRAPHY_SEARCH_NAME}: query-only repair must not add "
                "a table, index, trigger, or writer-table rewrite"
            )

    flow_cas_rls_policy = MIGRATIONS_DIR / FLOW_CAS_RLS_POLICY_NAME
    if not flow_cas_rls_policy.is_file():
        violations.append(
            f"missing Portal Flow CAS RLS migration: {FLOW_CAS_RLS_POLICY_NAME}"
        )
    else:
        rls_sql = sql_without_comments(
            flow_cas_rls_policy.read_text(encoding="utf-8")
        )
        rls_sql_lower = rls_sql.lower()
        required_rls_tokens = (
            "35cf6024873514fa198dad8684cd41815f7cd4147f715a9becbb764a6bb37149",
            "b001ad1fe7c4ae14fd577a740205af0b2e0f91a62b9912bcb133628e05e8b8cc",
            "c23867609136dd833aa713cf3868ad27f9b858efbca8f4f130e1840c9a359094",
            "alter policy portal_catalog_search_rows_portal_select_v1",
            "on private.portal_catalog_search_rows_v1",
            "using (true)",
            "portal_catalog_search_rows_v1_state_code_check",
            "(state_code=any(array[100,200]))",
            "policy.qual = 'true'",
            "relation.relrowsecurity",
            "relation.relforcerowsecurity",
            "private.assert_portal_catalog_projection_contract_v1()",
            "portal flow cas rls-indexability prerequisites drifted",
        )
        missing = [
            token for token in required_rls_tokens if token not in rls_sql_lower
        ]
        if missing:
            violations.append(
                f"{FLOW_CAS_RLS_POLICY_NAME}: missing RLS-indexability tokens "
                + ", ".join(missing)
            )
        assertion_pattern = mutation_pattern(
            "private.assert_portal_catalog_projection_contract_v1()"
        )
        if len(assertion_pattern.findall(rls_sql)) != 1:
            violations.append(
                f"{FLOW_CAS_RLS_POLICY_NAME}: expected one projection assertion replacement"
            )
        if re.search(
            r"\b(?:create\s+(?:unlogged\s+)?table|create\s+(?:unique\s+)?index|"
            r"create\s+trigger|alter\s+table|drop\s+(?:table|index|trigger))\b",
            rls_sql,
            flags=re.IGNORECASE,
        ):
            violations.append(
                f"{FLOW_CAS_RLS_POLICY_NAME}: policy-only repair must not add, "
                "rewrite, or remove a relation, index, trigger, or writer path"
            )
        if len(
            re.findall(
                r"\balter\s+policy\s+portal_catalog_search_rows_portal_select_v1\b",
                rls_sql,
                flags=re.IGNORECASE,
            )
        ) != 1:
            violations.append(
                f"{FLOW_CAS_RLS_POLICY_NAME}: expected one exact Portal SELECT policy change"
            )

    single_character_search = MIGRATIONS_DIR / SINGLE_CHARACTER_SEARCH_NAME
    if not single_character_search.is_file():
        violations.append(
            "missing Portal single-character Search migration: "
            f"{SINGLE_CHARACTER_SEARCH_NAME}"
        )
    else:
        character_sql = sql_without_comments(
            single_character_search.read_text(encoding="utf-8")
        )
        character_sql_lower = character_sql.lower()
        required_character_tokens = (
            "114236b32b7a8a813f222ea301be9dd92529aba1eaf565301b3ed533d94e2115",
            "e36c34a1fec82f769fef1c67ce4505f760025d0b2c0d4b72ed8b55e87abfd6a4",
            "private.catalog_portal_process_pattern_versions_v1",
            "private.catalog_portal_flow_pattern_versions_v1",
            "private.catalog_portal_process_single_character_versions_v1",
            "private.catalog_portal_flow_single_character_versions_v1",
            "char_length(p_like_pattern) = 3",
            "pg_catalog.strpos",
            "return query execute pg_catalog.format",
            "portal_catalog_search_rows_portal_select_v1",
            "policy.qual = 'true'",
            "portal single-character search prerequisites drifted",
        )
        missing = [
            token
            for token in required_character_tokens
            if token not in character_sql_lower
        ]
        if missing:
            violations.append(
                f"{SINGLE_CHARACTER_SEARCH_NAME}: missing correctness tokens "
                + ", ".join(missing)
            )
        for helper in (
            "private.catalog_portal_process_pattern_versions_v1",
            "private.catalog_portal_flow_pattern_versions_v1",
        ):
            helper_pattern = re.compile(
                rf"create\s+or\s+replace\s+function\s+{re.escape(helper)}\s*\(",
                flags=re.IGNORECASE,
            )
            if len(helper_pattern.findall(character_sql)) != 1:
                violations.append(
                    f"{SINGLE_CHARACTER_SEARCH_NAME}: expected one {helper} replacement"
                )
        for helper in (
            "private.catalog_portal_process_single_character_versions_v1",
            "private.catalog_portal_flow_single_character_versions_v1",
        ):
            helper_pattern = re.compile(
                rf"create\s+function\s+{re.escape(helper)}\s*\(",
                flags=re.IGNORECASE,
            )
            if len(helper_pattern.findall(character_sql)) != 1:
                violations.append(
                    f"{SINGLE_CHARACTER_SEARCH_NAME}: expected one new {helper}"
                )
        if re.search(
            r"\b(?:create\s+(?:unlogged\s+)?table|create\s+(?:unique\s+)?index|"
            r"create\s+trigger|alter\s+(?:table|policy)|"
            r"drop\s+(?:table|index|trigger))\b",
            character_sql,
            flags=re.IGNORECASE,
        ):
            violations.append(
                f"{SINGLE_CHARACTER_SEARCH_NAME}: helper-only repair must not "
                "change a relation, index, trigger, policy, or writer path"
            )
        if re.search(
            r"create\s+or\s+replace\s+function\s+api[.]portal_",
            character_sql,
            flags=re.IGNORECASE,
        ):
            violations.append(
                f"{SINGLE_CHARACTER_SEARCH_NAME}: public Portal wrappers must remain byte-stable"
            )

    character_expand = MIGRATIONS_DIR / CHARACTER_PROJECTION_EXPAND_NAME
    if not character_expand.is_file():
        violations.append(
            f"missing Portal character projection expand: {CHARACTER_PROJECTION_EXPAND_NAME}"
        )
    else:
        expand_sql = sql_without_comments(
            character_expand.read_text(encoding="utf-8")
        ).lower()
        required_expand_tokens = (
            "create table private.portal_catalog_character_rows_v1",
            "portal_catalog_character_parent_v1_fk",
            "on update restrict",
            "on delete cascade",
            "portal_catalog_character_rows_latest_v1_idx",
            "portal_catalog_character_set_v1",
            "portal_catalog_character_field_set_v1",
            "sync_portal_catalog_character_row_v1",
            "create trigger portal_catalog_character_sync_v1",
            "after insert or update",
            "enable row level security",
            "force row level security",
            "portal_catalog_character_rows_portal_select_v1",
            "portal_catalog_character_rows_internal_all_v1",
            "select count(*)",
            "<> 0",
        )
        missing = [
            token for token in required_expand_tokens if token not in expand_sql
        ]
        if missing:
            violations.append(
                f"{CHARACTER_PROJECTION_EXPAND_NAME}: missing expand tokens "
                + ", ".join(missing)
            )

    character_backfills = sorted(
        MIGRATIONS_DIR.glob(
            "2026082913100[2-5]_portal_character_projection_backfill_*.sql"
        )
    )
    if len(character_backfills) != 4:
        violations.append(
            "expected exactly four Portal character projection backfills, "
            f"found {len(character_backfills)}"
        )
    expected_character_ranges = (
        ("00000000-0000-0000-0000-000000000000", "40000000-0000-0000-0000-000000000000"),
        ("40000000-0000-0000-0000-000000000000", "80000000-0000-0000-0000-000000000000"),
        ("80000000-0000-0000-0000-000000000000", "c0000000-0000-0000-0000-000000000000"),
        ("c0000000-0000-0000-0000-000000000000", None),
    )
    for migration, (lower, upper) in zip(
        character_backfills, expected_character_ranges
    ):
        executable_sql = sql_without_comments(
            migration.read_text(encoding="utf-8")
        ).lower()
        required_tokens = (
            "set local lock_timeout = '5s'",
            "set local statement_timeout = '120s'",
            "insert into private.portal_catalog_character_rows_v1",
            "from private.portal_catalog_search_rows_v1",
            "portal_catalog_character_set_v1",
            "portal_catalog_character_field_set_v1",
            "on conflict (dataset_kind, id, version) do nothing",
            "portal character backfill is incomplete",
            lower,
        )
        missing = [token for token in required_tokens if token not in executable_sql]
        if upper is not None and upper not in executable_sql:
            missing.append(upper)
        if missing:
            violations.append(
                f"{migration.name}: missing character backfill tokens "
                + ", ".join(missing)
            )

    character_cutover = MIGRATIONS_DIR / CHARACTER_PROJECTION_CUTOVER_NAME
    if not character_cutover.is_file():
        violations.append(
            f"missing Portal character projection cutover: "
            f"{CHARACTER_PROJECTION_CUTOVER_NAME}"
        )
    else:
        cutover_sql = sql_without_comments(
            character_cutover.read_text(encoding="utf-8")
        )
        cutover_sql_lower = cutover_sql.lower()
        required_cutover_tokens = (
            "lock table private.portal_catalog_search_rows_v1",
            "in share row exclusive mode",
            "insert into private.portal_catalog_character_rows_v1",
            "delete from private.portal_catalog_character_rows_v1",
            "portal character projection reconciliation failed",
            "assert_portal_catalog_character_contract_v1",
            "catalog_portal_single_character_search_v1_impl",
            "char_length(v_query) = 1",
            "v_filters = '{}'::jsonb",
            "v_sort = 'relevance'",
            "join private.portal_catalog_search_rows_v1",
            "limit p_limit + 1",
            "catalog_portal_search_v1_impl",
            "portal character search cutover drifted",
        )
        missing = [
            token for token in required_cutover_tokens
            if token not in cutover_sql_lower
        ]
        if missing:
            violations.append(
                f"{CHARACTER_PROJECTION_CUTOVER_NAME}: missing cutover tokens "
                + ", ".join(missing)
            )
        if len(
            re.findall(
                r"create\s+or\s+replace\s+function\s+"
                r"private[.]portal_search_v1\s*[(]",
                cutover_sql,
                flags=re.IGNORECASE,
            )
        ) != 1:
            violations.append(
                f"{CHARACTER_PROJECTION_CUTOVER_NAME}: expected one Search coordinator replacement"
            )
        if re.search(
            r"\b(?:create\s+(?:unlogged\s+)?table|"
            r"create\s+(?:unique\s+)?index|create\s+trigger|"
            r"alter\s+(?:table|policy)|drop\s+(?:table|index|trigger))\b",
            cutover_sql,
            flags=re.IGNORECASE,
        ):
            violations.append(
                f"{CHARACTER_PROJECTION_CUTOVER_NAME}: cutover must not change "
                "a relation, index, trigger, policy, or writer definition"
            )
        if re.search(
            r"create\s+or\s+replace\s+function\s+api[.]portal_",
            cutover_sql,
            flags=re.IGNORECASE,
        ):
            violations.append(
                f"{CHARACTER_PROJECTION_CUTOVER_NAME}: public wrappers must remain byte-stable"
            )

    process_rank_helpers = MIGRATIONS_DIR / PROCESS_KEYWORD_RANK_HELPERS_NAME
    if not process_rank_helpers.is_file():
        violations.append(
            "missing Portal Process keyword rank helpers: "
            f"{PROCESS_KEYWORD_RANK_HELPERS_NAME}"
        )
    else:
        process_rank_helpers_sql = sql_without_comments(
            process_rank_helpers.read_text(encoding="utf-8")
        )
        process_rank_helpers_lower = process_rank_helpers_sql.lower()
        process_rank_helpers_compact = re.sub(
            r"\s+", " ", process_rank_helpers_lower
        )
        required_process_rank_tokens = (
            PROCESS_KEYWORD_RANK_MANIFEST_SHA256,
            "portal_catalog_search_process_exact_rank_v1_gin",
            "catalog_portal_process_pattern_versions_v1",
            "portal_process_rank_name_keys_v1",
            "portal_process_rank_classification_keys_v1",
            "catalog_portal_process_keyword_keys_v1",
            "catalog_portal_process_keyword_relevance_v1_impl",
            "assert_portal_process_keyword_rank_contract_v1",
            "grant execute on function private.portal_process_rank_name_keys_v1(jsonb) to api_internal_executor",
            "grant execute on function private.portal_process_rank_name_keys_v1(jsonb) to postgres",
            "limit p_limit + 1",
            "set statement_timeout = '8s'",
            "set plan_cache_mode = 'force_custom_plan'",
            "set row_security = 'on'",
        )
        missing = [
            token
            for token in required_process_rank_tokens
            if token not in process_rank_helpers_compact
        ]
        for identity in (
            PROCESS_KEYWORD_RANK_FUNCTION_IDENTITIES
            + PROCESS_KEYWORD_RANK_CONTROL_FUNCTION_IDENTITIES
        ):
            if identity not in process_rank_helpers_sql:
                missing.append(identity)
        if missing:
            violations.append(
                f"{PROCESS_KEYWORD_RANK_HELPERS_NAME}: missing helper tokens "
                + ", ".join(missing)
            )
        if re.search(
            r"^[ \t]*(?:create\s+(?:unlogged\s+)?table|"
            r"create\s+(?:unique\s+)?index|create\s+trigger|"
            r"alter\s+(?:table|policy)|drop\s+(?:table|index|trigger))\b",
            process_rank_helpers_sql,
            flags=re.IGNORECASE | re.MULTILINE,
        ):
            violations.append(
                f"{PROCESS_KEYWORD_RANK_HELPERS_NAME}: dormant helper phase must not change a relation, index, trigger, policy, or writer definition"
            )

    process_rank_index = MIGRATIONS_DIR / PROCESS_KEYWORD_RANK_INDEX_NAME
    if not process_rank_index.is_file():
        violations.append(
            f"missing Portal Process keyword rank index: {PROCESS_KEYWORD_RANK_INDEX_NAME}"
        )
    else:
        process_rank_index_sql = sql_without_comments(
            process_rank_index.read_text(encoding="utf-8")
        )
        process_rank_index_pattern = re.compile(
            r"\s*create\s+index\s+concurrently\s+"
            r"portal_catalog_search_process_exact_rank_v1_gin\s+"
            r"on\s+private[.]portal_catalog_search_rows_v1\s+using\s+gin\s*[(]"
            r"\s*private[.]portal_process_rank_name_keys_v1[(]card[)]\s*,"
            r"\s*private[.]portal_process_rank_classification_keys_v1[(]card[)]\s*"
            r"[)]\s*where\s+dataset_kind\s*=\s*'process'\s*;\s*",
            flags=re.IGNORECASE,
        )
        if not process_rank_index_pattern.fullmatch(process_rank_index_sql):
            violations.append(
                f"{PROCESS_KEYWORD_RANK_INDEX_NAME}: must be one exact concurrent partial expression GIN statement without IF NOT EXISTS"
            )

    process_rank_cutover = MIGRATIONS_DIR / PROCESS_KEYWORD_RANK_CUTOVER_NAME
    if not process_rank_cutover.is_file():
        violations.append(
            f"missing Portal Process keyword rank cutover: {PROCESS_KEYWORD_RANK_CUTOVER_NAME}"
        )
    else:
        process_rank_cutover_sql = sql_without_comments(
            process_rank_cutover.read_text(encoding="utf-8")
        )
        process_rank_cutover_lower = process_rank_cutover_sql.lower()
        required_process_rank_cutover_tokens = (
            "assert_portal_process_keyword_rank_contract_v1",
            "catalog_portal_process_keyword_relevance_v1_impl",
            "char_length(v_query) > 1",
            "v_query !~",
            "p_kind = 'process'",
            "v_filters = '{}'::jsonb",
            "v_sort = 'relevance'",
            "catalog_portal_single_character_search_v1_impl",
            "catalog_portal_search_v1_impl",
            "portal process keyword rank cutover drifted",
            "has_function_privilege(",
            "'api_internal_executor'",
            "'postgres'",
        )
        missing = [
            token
            for token in required_process_rank_cutover_tokens
            if token not in process_rank_cutover_lower
        ]
        if missing:
            violations.append(
                f"{PROCESS_KEYWORD_RANK_CUTOVER_NAME}: missing cutover tokens "
                + ", ".join(missing)
            )
        if len(
            re.findall(
                r"create\s+or\s+replace\s+function\s+private[.]portal_search_v1\s*[(]",
                process_rank_cutover_sql,
                flags=re.IGNORECASE,
            )
        ) != 1:
            violations.append(
                f"{PROCESS_KEYWORD_RANK_CUTOVER_NAME}: expected one Search coordinator replacement"
            )
        if re.search(
            r"\b(?:create\s+(?:unlogged\s+)?table|create\s+(?:unique\s+)?index|"
            r"create\s+trigger|alter\s+(?:table|policy)|drop\s+(?:table|index|trigger))\b",
            process_rank_cutover_sql,
            flags=re.IGNORECASE,
        ):
            violations.append(
                f"{PROCESS_KEYWORD_RANK_CUTOVER_NAME}: cutover must not change a relation, index, trigger, policy, or writer definition"
            )
        if re.search(
            r"create\s+or\s+replace\s+function\s+api[.]portal_",
            process_rank_cutover_sql,
            flags=re.IGNORECASE,
        ):
            violations.append(
                f"{PROCESS_KEYWORD_RANK_CUTOVER_NAME}: public wrappers must remain byte-stable"
            )

    process_rank_patterns = {
        identity: mutation_pattern(identity)
        for identity in (
            PROCESS_KEYWORD_RANK_FUNCTION_IDENTITIES
            + PROCESS_KEYWORD_RANK_CONTROL_FUNCTION_IDENTITIES
        )
    }
    for migration in sorted(MIGRATIONS_DIR.glob("*.sql")):
        if migration.name <= PROCESS_KEYWORD_RANK_CUTOVER_NAME:
            continue
        executable_sql = sql_without_comments(migration.read_text(encoding="utf-8"))
        for identity, pattern in process_rank_patterns.items():
            if pattern.search(executable_sql) and not reviewed_process_rank_retirement(
                migration.name, executable_sql, identity
            ):
                violations.append(f"{migration.name}: {identity}")

    required_guard_counts = {
        "20260826080345_portal_projection_reconcile.sql": 1,
        "20260826080400_portal_projection_candidate_cutover.sql": 2,
        "20260826080403_portal_projection_facets.sql": 2,
    }
    guard_name = "assert_portal_catalog_projection_contract_v1"
    for migration_name, expected_count in required_guard_counts.items():
        migration = MIGRATIONS_DIR / migration_name
        if not migration.is_file():
            violations.append(f"missing guarded migration: {migration_name}")
            continue
        actual_count = sql_without_comments(
            migration.read_text(encoding="utf-8")
        ).count(guard_name)
        if actual_count != expected_count:
            violations.append(
                f"{migration_name}: expected {expected_count} {guard_name} calls, "
                f"found {actual_count}"
            )

    backfill_migrations = sorted(
        MIGRATIONS_DIR.glob("2026082608*_portal_projection_backfill_*.sql")
    )
    if len(backfill_migrations) != 16:
        violations.append(
            "expected exactly 16 Portal projection backfill migrations, "
            f"found {len(backfill_migrations)}"
        )
    backfill_timeout_pattern = re.compile(
        r"\bbegin\s*;\s*"
        r"set\s+local\s+lock_timeout\s*=\s*'5s'\s*;\s*"
        r"set\s+local\s+statement_timeout\s*=\s*'120s'\s*;",
        flags=re.IGNORECASE,
    )
    for migration in backfill_migrations:
        executable_sql = sql_without_comments(migration.read_text(encoding="utf-8"))
        if not backfill_timeout_pattern.search(executable_sql):
            violations.append(
                f"{migration.name}: missing outer 5s lock / 120s statement timeout"
            )

    facet_backfills = sorted(
        MIGRATIONS_DIR.glob("2026082702000[1-4]_portal_facet_projection_backfill_*.sql")
    )
    if len(facet_backfills) != 4:
        violations.append(
            "expected exactly four Portal facet projection backfills, "
            f"found {len(facet_backfills)}"
        )
    expected_facet_ranges = (
        ("00000000-0000-0000-0000-000000000000", "40000000-0000-0000-0000-000000000000"),
        ("40000000-0000-0000-0000-000000000000", "80000000-0000-0000-0000-000000000000"),
        ("80000000-0000-0000-0000-000000000000", "c0000000-0000-0000-0000-000000000000"),
        ("c0000000-0000-0000-0000-000000000000", None),
    )
    for migration, (lower, upper) in zip(facet_backfills, expected_facet_ranges):
        executable_sql = sql_without_comments(
            migration.read_text(encoding="utf-8")
        ).lower()
        required_tokens = (
            "set local lock_timeout = '5s'",
            "set local statement_timeout = '120s'",
            "grant api_internal_executor to postgres",
            "set role api_internal_executor",
            "reset role",
            "revoke api_internal_executor from postgres",
            "assert_portal_catalog_projection_contract_v1",
            "assert_portal_catalog_facet_contract_v1",
            "portal_catalog_facet_facts_v1",
            "on conflict (dataset_kind, id, version) do nothing",
            "where projection.dataset_kind = 'process'",
            "where projection.dataset_kind = 'flow'",
            "where facet.dataset_kind = 'process'",
            "where facet.dataset_kind = 'flow'",
            "select count(*)",
            lower,
        )
        missing = [token for token in required_tokens if token not in executable_sql]
        if upper is not None and upper not in executable_sql:
            missing.append(upper)
        if missing:
            violations.append(
                f"{migration.name}: missing facet backfill tokens "
                + ", ".join(missing)
            )
        if re.search(
            r"(?:insert\s+into|update|delete\s+from)\s+"
            r"private[.]portal_catalog_search_rows_v1",
            executable_sql,
        ):
            violations.append(
                f"{migration.name}: must not mutate the immutable parent projection"
            )

    for migration_name, required_tokens in {
        FACET_RECONCILE_NAME: (
            "lock table private.portal_catalog_search_rows_v1",
            "lock table private.portal_catalog_facet_rows_v1",
            "on conflict (dataset_kind, id, version) do nothing",
            "portal facet projection reconciliation failed",
        ),
        FACET_CUTOVER_NAME: (
            "v_query = '' and v_filters = '{}'::jsonb",
            "catalog_portal_facets_empty_v1_impl",
            "catalog_portal_facets_v1_impl",
            "portal_catalog_facet_rows_v1",
            "set work_mem = '32mb'",
            "portal facet cutover contract drifted",
        ),
    }.items():
        migration = MIGRATIONS_DIR / migration_name
        if not migration.is_file():
            violations.append(f"missing Portal facet migration: {migration_name}")
            continue
        executable_sql = sql_without_comments(
            migration.read_text(encoding="utf-8")
        ).lower()
        missing = [token for token in required_tokens if token not in executable_sql]
        if missing:
            violations.append(
                f"{migration_name}: missing facet rollout tokens "
                + ", ".join(missing)
            )

    eligibility_index = MIGRATIONS_DIR / FLOW_ELIGIBILITY_INDEX_NAME
    if not eligibility_index.is_file():
        violations.append(
            f"missing Flow embedding eligibility migration: {FLOW_ELIGIBILITY_INDEX_NAME}"
        )
    else:
        eligibility_sql = sql_without_comments(
            eligibility_index.read_text(encoding="utf-8")
        )
        eligibility_pattern = re.compile(
            r"\s*create\s+index\s+concurrently\s+"
            r"flows_portal_embedding_eligible_v1_idx\s+"
            r"on\s+public[.]flows\s+using\s+btree\s*"
            r"[(]\s*state_code\s*[)]\s*"
            r"where\s+state_code\s+in\s*[(]\s*100\s*,\s*200\s*[)]\s*"
            r"and\s+embedding_ft\s+is\s+not\s+null\s*;\s*",
            flags=re.IGNORECASE,
        )
        if not eligibility_pattern.fullmatch(eligibility_sql):
            violations.append(
                f"{FLOW_ELIGIBILITY_INDEX_NAME}: must be one exact concurrent "
                "partial btree statement without IF NOT EXISTS"
            )

    eligibility_guard = MIGRATIONS_DIR / FLOW_ELIGIBILITY_GUARD_NAME
    if not eligibility_guard.is_file():
        violations.append(
            f"missing Flow embedding eligibility guard: {FLOW_ELIGIBILITY_GUARD_NAME}"
        )
    else:
        guard_sql = sql_without_comments(
            eligibility_guard.read_text(encoding="utf-8")
        ).lower()
        required_guard_tokens = (
            "set local lock_timeout = '5s'",
            "set local statement_timeout = '8s'",
            "flows_portal_embedding_eligible_v1_idx",
            "index_catalog.indisvalid",
            "index_catalog.indisready",
            "index_catalog.indislive",
            "index_catalog.indnkeyatts = 1",
            "index_catalog.indnatts = 1",
            "first_key.attname = 'state_code'",
            "first_opclass_namespace.nspname = 'pg_catalog'",
            "first_opclass.opcname = 'int4_ops'",
            "first_opclass.opcintype = 'pg_catalog.int4'::pg_catalog.regtype",
            "((state_code=any(array[100,200]))and(embedding_ftisnotnull))",
            "portal flow embedding eligibility index drifted",
        )
        missing_guard_tokens = [
            token for token in required_guard_tokens if token not in guard_sql
        ]
        if missing_guard_tokens:
            violations.append(
                f"{FLOW_ELIGIBILITY_GUARD_NAME}: missing guard tokens "
                + ", ".join(missing_guard_tokens)
            )

    sitemap_latest = MIGRATIONS_DIR / SITEMAP_LATEST_PROJECTION_NAME
    if not sitemap_latest.is_file():
        violations.append(
            "missing Portal sitemap latest projection: "
            f"{SITEMAP_LATEST_PROJECTION_NAME}"
        )
    else:
        sitemap_latest_sql = sql_without_comments(
            sitemap_latest.read_text(encoding="utf-8")
        ).lower()
        required_latest_tokens = (
            "create table private.portal_sitemap_rows_v1",
            "primary key (dataset_kind, id, version)",
            "constraint portal_sitemap_rows_source_v1_fk",
            "on delete cascade",
            "shard_no smallint not null",
            "check (shard_no between 0 and 63)",
            "create index portal_sitemap_rows_shard_v1_idx",
            "version desc",
            "modified_at desc",
            "create function private.sync_portal_sitemap_row_v1()",
            "security definer",
            "portal_sitemap_rows_sync_v1",
            "on conflict (dataset_kind, id, version) do update",
            "pg_catalog.md5(",
            ") / 4",
            "portal sitemap version projection reconciliation failed",
        )
        missing_latest_tokens = [
            token
            for token in required_latest_tokens
            if token not in sitemap_latest_sql
        ]
        if missing_latest_tokens:
            violations.append(
                f"{SITEMAP_LATEST_PROJECTION_NAME}: missing latest projection tokens "
                + ", ".join(missing_latest_tokens)
            )
        if "advisory" in sitemap_latest_sql or "hashtextextended" in sitemap_latest_sql:
            violations.append(
                f"{SITEMAP_LATEST_PROJECTION_NAME}: row triggers must not wait on a second application lock after source/facet row locking"
            )
        if "sync_portal_sitemap_latest_delete_v1" in sitemap_latest_sql \
           or "portal_sitemap_latest_delete_v1" in sitemap_latest_sql:
            violations.append(
                f"{SITEMAP_LATEST_PROJECTION_NAME}: exact-version DELETE must use only the FK cascade"
            )
        if "create index concurrently" in sitemap_latest_sql:
            violations.append(
                f"{SITEMAP_LATEST_PROJECTION_NAME}: the new index must be created "
                "on the empty latest table before its set-based backfill"
            )
        if "portal_sitemap_entries_v1" in sitemap_latest_sql:
            violations.append(
                f"{SITEMAP_LATEST_PROJECTION_NAME}: expand must not change a public RPC"
            )

    sitemap_contract = MIGRATIONS_DIR / SITEMAP_SHARD_CONTRACT_NAME
    if not sitemap_contract.is_file():
        violations.append(
            f"missing Portal sitemap shard contract: {SITEMAP_SHARD_CONTRACT_NAME}"
        )
    else:
        sitemap_contract_sql = sql_without_comments(
            sitemap_contract.read_text(encoding="utf-8")
        )
        sitemap_contract_lower = sitemap_contract_sql.lower()
        required_contract_tokens = (
            "api.portal_sitemap_manifest_v1()",
            "api.portal_sitemap_shard_v1(text)",
            "private.assert_portal_sitemap_projection_v1()",
            "generate_series(0, 63)",
            "'maxitems', 4096",
            "limit 4097",
            "jsonb_array_length(v_items) > 4096",
            "portal.public-sitemap-manifest.v1",
            "portal.public-sitemap-shard.v1",
            "03dd37bd0871c220fcd94cb2dec203ed",
            "9bc7007c0e8fef48c75d997ea8ef96d8",
            "portal_sitemap_rows_v1",
            "projection.shard_no = v_bucket",
            "select distinct on (projection.dataset_kind, projection.id)",
            "v_expected_cursor := pg_catalog.jsonb_build_object",
            "private.portal_cursor_encode_v1(v_expected_cursor)",
        )
        missing_contract_tokens = [
            token
            for token in required_contract_tokens
            if token not in sitemap_contract_lower
        ]
        if missing_contract_tokens:
            violations.append(
                f"{SITEMAP_SHARD_CONTRACT_NAME}: missing bounded shard tokens "
                + ", ".join(missing_contract_tokens)
            )
        if re.search(
            r"\b(?:create\s+(?:unlogged\s+)?table|create\s+trigger|alter\s+table)\b",
            sitemap_contract_sql,
            flags=re.IGNORECASE,
        ):
            violations.append(
                f"{SITEMAP_SHARD_CONTRACT_NAME}: sitemap shards must not add "
                "a writer table, trigger, or table rewrite"
            )
        if re.search(
            r"create\s+(?:or\s+replace\s+)?function\s+"
            r"api[.]portal_sitemap_entries_v1\s*[(]",
            sitemap_contract_sql,
            flags=re.IGNORECASE,
        ):
            violations.append(
                f"{SITEMAP_SHARD_CONTRACT_NAME}: retained sitemap v1 must stay unchanged"
            )

    if not SITEMAP_PREVIEW_FIXTURE.is_file():
        violations.append(
            f"missing Portal sitemap Preview fixture: {SITEMAP_PREVIEW_FIXTURE.name}"
        )
    else:
        fixture_sha256 = hashlib.sha256(
            SITEMAP_PREVIEW_FIXTURE.read_bytes()
        ).hexdigest()
        if fixture_sha256 != SITEMAP_PREVIEW_FIXTURE_SHA256:
            violations.append(
                f"{SITEMAP_PREVIEW_FIXTURE.name}: old Preview fixture digest drifted"
            )

    sitemap_repair = MIGRATIONS_DIR / SITEMAP_REPAIR_NAME
    if not sitemap_repair.is_file():
        violations.append(
            f"missing Portal sitemap forward repair: {SITEMAP_REPAIR_NAME}"
        )
    else:
        sitemap_repair_sql = sql_without_comments(
            sitemap_repair.read_text(encoding="utf-8")
        ).lower()
        required_repair_tokens = (
            "lock table private.portal_catalog_facet_rows_v1",
            "create table if not exists private.portal_sitemap_rows_v1",
            "constraint portal_sitemap_rows_source_v1_fk",
            "on delete cascade",
            "create or replace function private.sync_portal_sitemap_row_v1()",
            "create trigger portal_sitemap_rows_sync_v1",
            "create or replace function private.assert_portal_sitemap_projection_v1()",
            "create or replace function api.portal_sitemap_shard_v1",
            "9bc7007c0e8fef48c75d997ea8ef96d8",
            "v_expected_cursor := pg_catalog.jsonb_build_object",
            "private.portal_cursor_encode_v1(v_expected_cursor)",
            "on conflict (dataset_kind, id, version) do update",
            "drop function if exists private.sync_portal_sitemap_latest_delete_v1()",
            "drop table if exists private.portal_sitemap_latest_rows_v1",
            "portal sitemap version repair did not converge",
        )
        missing_repair_tokens = [
            token
            for token in required_repair_tokens
            if token not in sitemap_repair_sql
        ]
        if missing_repair_tokens:
            violations.append(
                f"{SITEMAP_REPAIR_NAME}: missing forward repair tokens "
                + ", ".join(missing_repair_tokens)
            )
        if "advisory" in sitemap_repair_sql or "hashtextextended" in sitemap_repair_sql:
            violations.append(
                f"{SITEMAP_REPAIR_NAME}: repair must not add application locks to exact-version writers"
            )
        if "create trigger portal_sitemap_latest_delete_v1" in sitemap_repair_sql \
           or "create or replace function private.sync_portal_sitemap_latest_delete_v1" in sitemap_repair_sql:
            violations.append(
                f"{SITEMAP_REPAIR_NAME}: repair must retire rather than recreate the shared-winner DELETE path"
            )
        for identity in (
            "private.sync_portal_sitemap_row_v1()",
            "private.assert_portal_sitemap_projection_v1()",
            "api.portal_sitemap_shard_v1(text)",
        ):
            function_name = identity.split(".", 1)[1].split("(", 1)[0]
            if sitemap_repair_sql.count(function_name) == 0:
                violations.append(
                    f"{SITEMAP_REPAIR_NAME}: repair omits {identity}"
                )

    sitemap_patterns = {
        identity: mutation_pattern(identity)
        for identity in SITEMAP_SHARD_FUNCTION_IDENTITIES
    }
    for migration in sorted(MIGRATIONS_DIR.glob("*.sql")):
        if migration.name <= SITEMAP_REPAIR_NAME:
            continue
        executable_sql = sql_without_comments(migration.read_text(encoding="utf-8"))
        for identity, pattern in sitemap_patterns.items():
            if not pattern.search(executable_sql):
                continue
            # #807 replaces only the public dispatchers. Their legacy bodies and
            # metadata are proved unchanged by the populated-upgrade rehearsal;
            # private shard derivation and every later mutation stay frozen.
            display_dispatch = migration.name == "20261010110000_portal_display_projection.sql" and identity in {
                "api.portal_sitemap_manifest_v1()", "api.portal_sitemap_shard_v1(text)"
            }
            if display_dispatch and all(token in executable_sql for token in (
                "private.portal_display_mode_v1() is distinct from 'legacy'",
                "perform private.portal_display_assert_contract_v1()",
                "private.display_api_sitemap_manifest_v1()",
                "private.display_api_sitemap_shard_v1(p_shard_cursor)",
                '"private"."display_legacy_sitemap_manifest_v1"',
                '"private"."display_legacy_sitemap_shard_v1"',
            )):
                continue
            violations.append(f"{migration.name}: {identity}")

    # Composite-name generation has its own frozen closure. Shared V1 helpers
    # remain covered by the existing guards above; never exempt those identities.
    composite_anchor = "20260908090000_portal_composite_names_expand.sql"
    composite_identities = (
        "private.portal_process_names_v1(jsonb)",
        "private.portal_catalog_card_cn1(text,integer,jsonb)",
        "private.catalog_portal_projection_payload_cn1(text,integer,jsonb)",
        "private.portal_catalog_projection_manifest_sha256_cn1()",
        "private.assert_portal_catalog_projection_contract_cn1()",
        "private.catalog_portal_process_keyword_keys_cn1(text,text,uuid,text,integer)",
        "private.catalog_portal_process_keyword_relevance_cn1_impl(text,text,uuid,text,integer,text)",
        "private.portal_process_keyword_rank_manifest_sha256_cn1()",
        "private.assert_portal_process_keyword_rank_contract_cn1()",
    )
    composite_sql = (MIGRATIONS_DIR / composite_anchor).read_text(encoding="utf-8")
    for digest in (
        "5260ed0b5662bf6b4bdae5250d0971fca369d8f36766f32207df47acd68e3500",
        "9686f14020c08ebfdd7a7cd0b049d8e0ea8b6acf9710d16fbe0bf3ca45510821",
    ):
        if digest not in composite_sql:
            violations.append(f"{composite_anchor}: missing literal {digest}")
    for identity in composite_identities:
        pattern = mutation_pattern(identity)
        if not pattern.search(composite_sql):
            violations.append(f"{composite_anchor}: missing {identity}")
        for migration in sorted(MIGRATIONS_DIR.glob("*.sql")):
            if migration.name > composite_anchor and pattern.search(
                sql_without_comments(migration.read_text(encoding="utf-8"))
            ):
                violations.append(f"{migration.name}: frozen composite helper {identity}")

    if violations:
        print(
            "Portal projection-v1 manifest governance failed:\n- "
            + "\n- ".join(violations),
            file=sys.stderr,
        )
        return 1

    print(
        "Portal projection-v1 manifest is immutable: "
        f"{len(FUNCTION_IDENTITIES)} derivation functions and "
        f"{len(CONTROL_FUNCTION_IDENTITIES)} control functions, "
        f"sha256={MANIFEST_SHA256}; facet closure "
        f"{len(FACET_FUNCTION_IDENTITIES)} derivation functions and "
        f"{len(FACET_CONTROL_FUNCTION_IDENTITIES)} controls, "
        f"sha256={FACET_MANIFEST_SHA256}; selected-row context closure "
        f"{len(CARD_CONTEXT_FUNCTION_IDENTITIES)} derivation functions and "
        f"{len(CARD_CONTEXT_CONTROL_FUNCTION_IDENTITIES)} controls, "
        f"anchor sha256={CARD_CONTEXT_MANIFEST_SHA256}, bounded Hybrid timeout "
        f"config sha256={HYBRID_TIMEOUT_CONTEXT_MANIFEST_SHA256}; "
        "Flow geography Search "
        "repair remains query-only; forced-RLS Flow CAS equality remains an "
        "exact index condition over the validated public-state projection; "
        "one-code-point literal Search uses one narrow exact-version child, "
        "latest-key index, and parent INSERT/UPDATE trigger; "
        "multi-code-point unfiltered Process relevance preselects exact/general "
        "keys through one immutable expression GIN before bounded card hydration; "
        "sitemap shards remain fixed at 64 with "
        "an exact-version FK child/index, one AFTER INSERT/UPDATE direct-upsert "
        "trigger, FK-cascade DELETE, the 134103 forward repair, and a "
        "4096-item fail-closed output cap"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
