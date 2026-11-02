#!/usr/bin/env python3
"""Offline executable examples for lca.study-durable.v1, not SQL enforcement.

No network, database, environment credentials, clock or third-party dependency.
Fixture actors and trusted service events are test inputs, not public API fields.
"""
import copy
import argparse
import hashlib
import json
from pathlib import Path


# Trusted synthetic policy registry. Events select a profile, never its rules.
# These IDs do not install runtime profiles or claim independent-review support.
REPORT_PROFILES = {
    "test-profile-none": {"reviewRequirement": "none", "available": True},
    "test-profile-internal": {"reviewRequirement": "internal", "available": True},
    "test-profile-independent": {"reviewRequirement": "independent", "available": False},
}


class Rejected(Exception):
    pass


def require(condition, code):
    if not condition:
        raise Rejected(code)


def digest(value):
    # Fixture request comparison only; not the Worker descriptor fingerprint.
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":"),
                                     ensure_ascii=False, allow_nan=False).encode()).hexdigest()


def valid_hash(value):
    return isinstance(value, str) and len(value) == 64 and all(c in "0123456789abcdef" for c in value)


class Model:
    """Small sequential reference model. Future SQL must independently prove it."""
    def __init__(self):
        self.state = {name: {} for name in (
            "studies", "sourceSnapshots", "preparations", "revisions", "scenarios", "runs", "reports", "reviews", "exports", "shares", "receipts")}

    def study(self, study_id):
        require(study_id in self.state["studies"], "REFERENCE_MISMATCH")
        return self.state["studies"][study_id]

    def record(self, table, identifier, study_id):
        record = self.state[table].get(identifier)
        require(record is not None and record["studyId"] == study_id, "REFERENCE_MISMATCH")
        return record

    def authorize(self, actor, study, operation):
        require(actor != "service", "FORBIDDEN")
        role = study["members"].get(actor)
        allowed = {
            "read": {"owner", "editor", "reviewer", "viewer"},
            "write": {"owner", "editor"},
            "review": {"owner", "reviewer"},
            "manage": {"owner"},
        }
        require(role in allowed[operation], "FORBIDDEN")
        require(operation in study["capabilities"].get(actor, []), "FORBIDDEN")

    @staticmethod
    def cas(record, expected):
        require(type(expected) is int and expected == record["revision"], "REVISION_CONFLICT")

    def receipt(self, event):
        key = event.get("idempotencyKey")
        require(isinstance(key, str) and bool(key), "INVALID_REQUEST")
        identity = json.dumps([event["actor"], event["operation"], event["studyId"], key])
        request_hash = digest(event.get("body", {}))
        previous = self.state["receipts"].get(identity)
        if previous:
            require(previous["requestHash"] == request_hash, "IDEMPOTENCY_CONFLICT")
        return identity, request_hash, previous

    def remember(self, identity, request_hash, result):
        self.state["receipts"][identity] = {"requestHash": request_hash, "result": copy.deepcopy(result)}
        return copy.deepcopy(result)

    def qualified_model(self, preparation_id, study_id):
        preparation = self.record("preparations", preparation_id, study_id)
        require(preparation["executionStatus"] == "completed" and preparation["modelRef"] is not None
                and preparation["inputArtifactRef"] is not None, "CAPABILITY_UNAVAILABLE")
        require(preparation["modelProducer"] == "solver-worker"
                and preparation["modelRef"]["digestScope"] == "worker_prepared_model", "REFERENCE_MISMATCH")
        if preparation["source"]["type"] == "scenarioRevision":
            require(valid_hash(preparation["inputHash"]), "CAPABILITY_UNAVAILABLE")
        return preparation

    def review_head(self, actor, target, review_class):
        chain = [item for item in self.state["reviews"].values()
                 if item["actor"] == actor and item["target"] == target
                 and item["reviewClass"] == review_class and item["decision"] != "comment"]
        superseded = {item["supersedesReviewId"] for item in chain if item["supersedesReviewId"] is not None}
        heads = [item for item in chain if item["reviewId"] not in superseded]
        require(len(heads) <= 1, "REFERENCE_MISMATCH")
        return heads[0] if heads else None

    def assert_provenance(self):
        """Edges include frozen parents and captured draft-source dependencies."""
        graph = {}
        for identifier, revision in self.state["revisions"].items():
            graph["revision:" + identifier] = ["preparation:" + revision["modelPreparationId"]]
            if revision.get("parentRevisionId"):
                graph["revision:" + identifier].append("revision:" + revision["parentRevisionId"])
        for identifier, scenario in self.state["scenarios"].items():
            dependencies = ["revision:" + scenario["studyRevisionId"]]
            if scenario.get("parentScenarioRevisionId"):
                dependencies.append("scenario:" + scenario["parentScenarioRevisionId"])
            graph["scenario:" + identifier] = dependencies[:]
            if scenario.get("modelPreparationId"):
                graph["scenario:" + identifier].append("preparation:" + scenario["modelPreparationId"])
        for identifier, preparation in self.state["preparations"].items():
            source = preparation["source"]
            graph["preparation:" + identifier] = []
            if source["type"] == "scenarioRevision":
                # The source is a captured DRAFT generation, not its later frozen node.
                source_node = "draft-source:" + identifier
                graph["preparation:" + identifier] = [source_node]
                captured = preparation["sourceProvenance"]
                graph[source_node] = ["revision:" + captured["studyRevisionId"]]
                if captured.get("parentScenarioRevisionId"):
                    graph[source_node].append("scenario:" + captured["parentScenarioRevisionId"])
        visiting, done = set(), set()
        def visit(node):
            require(node not in visiting, "REFERENCE_MISMATCH")
            if node in done:
                return
            visiting.add(node)
            for dependency in graph.get(node, []):
                visit(dependency)
            visiting.remove(node)
            done.add(node)
        for node in graph:
            visit(node)

    def execute(self, event):
        """Atomic example transition, including rollback of rejected operations."""
        before = copy.deepcopy(self.state)
        try:
            result = self._execute(event)
            self.assert_provenance()
            return result
        except Rejected:
            self.state = before
            raise

    def _execute(self, event):
        operation, actor, body = event["operation"], event["actor"], event.get("body", {})
        study_id = event.get("studyId")
        if operation == "study.create":
            require(actor != "service", "FORBIDDEN")
            key = event.get("idempotencyKey")
            require(isinstance(key, str) and bool(key), "INVALID_REQUEST")
            receipt_key = json.dumps([actor, operation, study_id, key])
            previous = self.state["receipts"].get(receipt_key)
            if previous:
                self.authorize(actor, self.study(study_id), "manage")
                require(previous["requestHash"] == digest(body), "IDEMPOTENCY_CONFLICT")
                return copy.deepcopy(previous["result"])
            require(study_id not in self.state["studies"], "REFERENCE_MISMATCH")
            self.state["studies"][study_id] = {
                "studyId": study_id, "status": "active", "revision": 1, "grantEpoch": 1, "disclosureEpoch": 1,
                "members": {actor: "owner"}, "capabilities": {actor: ["read", "write", "review", "manage"]}}
            result = {"studyId": study_id}
            self.state["receipts"][receipt_key] = {"requestHash": digest(body), "result": result}
            return copy.deepcopy(result)

        study = self.study(study_id)
        if operation == "model.source.record":
            require(actor == "service", "FORBIDDEN")
            self.authorize(body["requestedBy"], study, "write")
            require(body["authorizedExport"] is True, "CAPABILITY_UNAVAILABLE")
            require(body["originRef"]["type"] == "datasetRevision" and body["originRef"]["datasetType"] == "lifecyclemodel"
                    and bool(body["originRef"]["id"]) and bool(body["originRef"]["version"]), "REFERENCE_MISMATCH")
            require(body["sourceArtifactRef"]["type"] == "modelSource" and bool(body["sourceArtifactRef"]["id"]), "REFERENCE_MISMATCH")
            require(body["sourceArtifactRef"]["digestScope"] == "artifact_bytes_sha256", "REFERENCE_MISMATCH")
            require(body["digestScope"] == "artifact_bytes_sha256" and valid_hash(body["contentHash"])
                    and body["contentHash"] == body["sourceArtifactRef"]["contentHash"], "REFERENCE_MISMATCH")
            identity, request_hash, previous = self.receipt(event)
            if previous:
                return copy.deepcopy(previous["result"])
            require(body["snapshotId"] not in self.state["sourceSnapshots"], "REFERENCE_MISMATCH")
            self.state["sourceSnapshots"][body["snapshotId"]] = dict(copy.deepcopy(body), studyId=study_id)
            return self.remember(identity, request_hash, {"snapshotId": body["snapshotId"]})
        if operation == "model.complete":
            require(actor == "service", "FORBIDDEN")
            preparation = self.record("preparations", body["preparationId"], study_id)
            require(body["jobId"] == preparation["jobId"] and body["leaseCurrent"] is True, "FORBIDDEN")
            require(body["producer"] == "solver-worker" and body["modelRef"]["digestScope"] == "worker_prepared_model", "CAPABILITY_UNAVAILABLE")
            require(body["modelRef"]["type"] == "modelRevision" and bool(body["modelRef"]["modelRevisionId"])
                    and valid_hash(body["modelRef"]["contentHash"]), "REFERENCE_MISMATCH")
            require(body["inputArtifactRef"]["type"] == "modelInput" and bool(body["inputArtifactRef"]["id"])
                    and body["inputArtifactRef"]["digestScope"] == "artifact_bytes_sha256"
                    and valid_hash(body["inputArtifactRef"]["contentHash"]), "REFERENCE_MISMATCH")
            require("inputHash" in body, "INVALID_REQUEST")
            require(valid_hash(body["inputHash"]) or (preparation["source"]["type"] == "modelSourceSnapshot"
                    and body["inputHash"] is None), "CAPABILITY_UNAVAILABLE")
            identity, request_hash, previous = self.receipt(event)
            if previous:
                return copy.deepcopy(previous["result"])
            require(preparation["modelRef"] in (None, body["modelRef"])
                    and preparation["inputArtifactRef"] in (None, body["inputArtifactRef"]), "IDEMPOTENCY_CONFLICT")
            if preparation["executionStatus"] == "completed":
                require(preparation["inputHash"] == body["inputHash"], "IDEMPOTENCY_CONFLICT")
            preparation.update(executionStatus="completed", modelProducer=body["producer"],
                               modelRef=copy.deepcopy(body["modelRef"]),
                               inputArtifactRef=copy.deepcopy(body["inputArtifactRef"]), inputHash=body["inputHash"])
            return self.remember(identity, request_hash, {"preparationId": body["preparationId"],
                                 "modelRef": preparation["modelRef"], "inputHash": preparation["inputHash"]})
        if operation == "source.revoke":
            require(actor == "service", "FORBIDDEN")
            # Trusted external disclosure-context change, not source mutation.
            study["disclosureEpoch"] += 1
            return {"disclosureEpoch": study["disclosureEpoch"]}
        if operation == "share.read":
            share = self.record("shares", body["shareId"], study_id)
            require(actor == share["recipientId"] and share["status"] == "active", "FORBIDDEN")
            require(body["now"] < share["expiresAt"] and study["status"] == "active", "FORBIDDEN")
            require(share["grantEpoch"] == study["grantEpoch"], "FORBIDDEN")
            export = self.record("exports", share["exportId"], study_id)
            require(export["availability"] == "ready", "FORBIDDEN")
            require(export["disclosureEpoch"] == study["disclosureEpoch"], "DISCLOSURE_DENIED")
            return {"projectionHash": share["projectionHash"], "reportRevisionId": share["reportRevisionId"]}

        if operation == "run.complete":
            require(actor == "service", "FORBIDDEN")
            run = self.record("runs", body["runId"], study_id)
            require(run["inputHash"] == body["inputHash"], "REFERENCE_MISMATCH")
            require(run["jobId"] == body["jobId"] and body["leaseCurrent"] is True, "FORBIDDEN")
            require(body["resultRef"]["type"] == "runResult"
                    and body["resultRef"]["digestScope"] == "artifact_bytes_sha256"
                    and bool(body["resultRef"]["id"]) and valid_hash(body["resultRef"]["contentHash"]), "INVALID_REQUEST")
            identity, request_hash, previous = self.receipt(event)
            if previous:
                return copy.deepcopy(previous["result"])
            if run["resultRef"] is not None:
                require(run["resultRef"] == body["resultRef"], "IDEMPOTENCY_CONFLICT")
            else:
                run["resultRef"] = copy.deepcopy(body["resultRef"])
            run["executionStatus"] = "completed"
            run["availability"] = "ready"
            return self.remember(identity, request_hash, {"runId": body["runId"], "resultRef": run["resultRef"]})

        action = "read" if operation.endswith(".read") else (
            "manage" if operation in {"member.set", "study.archive", "run.withdraw", "share.revoke"} else (
                "review" if operation == "review.append" else "write"))
        self.authorize(actor, study, action)
        if operation == "study.read":
            return {"studyId": study_id, "revision": study["revision"]}
        if operation == "export.read":
            export = self.record("exports", body["exportId"], study_id)
            require(export["grantEpoch"] == study["grantEpoch"] and export["availability"] == "ready", "FORBIDDEN")
            require(export["disclosureEpoch"] == study["disclosureEpoch"], "DISCLOSURE_DENIED")
            return {"projectionHash": export["projectionHash"]}
        receipt_key, request_hash, previous = self.receipt(event)
        if previous:
            return copy.deepcopy(previous["result"])

        require(study["status"] == "active", "FROZEN_REVISION")
        result = self.transition(operation, actor, study_id, study, body, event.get("trustedValidationEvidence"))
        return self.remember(receipt_key, request_hash, result)

    def transition(self, operation, actor, study_id, study, body, validation_evidence=None):
        if operation == "model.prepare":
            require(body["preparationId"] not in self.state["preparations"], "REFERENCE_MISMATCH")
            ref = body["calculationContractRef"]
            require(set(ref) == {"kind", "schema", "sha256"} and ref["kind"] == "calculation_contract"
                    and ref["schema"] == "lca.calculation-contract.v1" and valid_hash(ref["sha256"]), "REFERENCE_MISMATCH")
            require(bool(body["profileId"]) and bool(body["jobId"]), "INVALID_REQUEST")
            source = body["source"]
            if source["type"] == "modelSourceSnapshot":
                snapshot = self.record("sourceSnapshots", source["snapshotId"], study_id)
                require(source["contentHash"] == snapshot["contentHash"]
                        and source["digestScope"] == snapshot["digestScope"] == "artifact_bytes_sha256", "REFERENCE_MISMATCH")
            elif source["type"] == "scenarioRevision":
                scenario = self.record("scenarios", source["scenarioRevisionId"], study_id)
                self.cas(scenario, source["expectedRevision"])
                require(scenario["status"] == "draft" and scenario["contentHash"] == source["contentHash"], "REFERENCE_MISMATCH")
            else:
                raise Rejected("CAPABILITY_UNAVAILABLE")
            self.state["preparations"][body["preparationId"]] = dict(copy.deepcopy(body), studyId=study_id,
                executionStatus="queued", modelRef=None, inputArtifactRef=None, inputHash=None)
            if source["type"] == "scenarioRevision":
                self.state["preparations"][body["preparationId"]]["sourceProvenance"] = {
                    "studyRevisionId": scenario["studyRevisionId"],
                    "parentScenarioRevisionId": scenario.get("parentScenarioRevisionId")}
            return {"preparationId": body["preparationId"]}
        if operation == "member.set":
            self.cas(study, body["expectedRevision"])
            require(body["memberId"] != actor, "FORBIDDEN")
            require(body["role"] in {"editor", "reviewer", "viewer", None}, "INVALID_REQUEST")
            if body["role"] is None:
                study["members"].pop(body["memberId"], None)
                study["capabilities"].pop(body["memberId"], None)
            else:
                study["members"][body["memberId"]] = body["role"]
                study["capabilities"][body["memberId"]] = body["capabilities"]
            study["revision"] += 1
            study["grantEpoch"] += 1
            return {"revision": study["revision"]}
        if operation == "study.archive":
            self.cas(study, body["expectedRevision"])
            study["status"] = "archived"
            study["revision"] += 1
            return {"revision": study["revision"]}
        if operation in {"revision.create", "scenario.create", "report.create"}:
            table, key = {"revision.create": ("revisions", "revisionId"),
                          "scenario.create": ("scenarios", "scenarioRevisionId"),
                          "report.create": ("reports", "reportRevisionId")}[operation]
            require(body[key] not in self.state[table], "REFERENCE_MISMATCH")
            require(valid_hash(body["contentHash"]), "INVALID_REQUEST")
            if operation == "revision.create" and body.get("parentRevisionId"):
                require(body["parentRevisionId"] != body[key], "REFERENCE_MISMATCH")
                parent = self.record("revisions", body["parentRevisionId"], study_id)
                require(parent["status"] == "frozen", "REFERENCE_MISMATCH")
            if operation == "revision.create":
                require("validation" not in body, "INVALID_REQUEST")
                preparation = self.qualified_model(body["modelPreparationId"], study_id)
                require(body["modelRef"] == preparation["modelRef"], "REFERENCE_MISMATCH")
            if operation == "scenario.create":
                base = self.record("revisions", body["studyRevisionId"], study_id)
                require(base["status"] == "frozen", "FROZEN_REVISION")
                require(body["effectiveModelRef"] is None, "REFERENCE_MISMATCH")
                if body.get("parentScenarioRevisionId"):
                    require(body["parentScenarioRevisionId"] != body[key], "REFERENCE_MISMATCH")
                    parent = self.record("scenarios", body["parentScenarioRevisionId"], study_id)
                    require(parent["status"] == "frozen", "REFERENCE_MISMATCH")
            if operation == "report.create":
                run = self.record("runs", body["runId"], study_id)
                require(run["resultRef"] is not None and run["availability"] == "ready", "REFERENCE_MISMATCH")
                require(body["runResultRef"] == run["resultRef"], "REFERENCE_MISMATCH")
            record = copy.deepcopy(body)
            record.update(studyId=study_id, status="draft", revision=1)
            if table == "revisions":
                record["validation"] = "not_checked"
            if table == "reports":
                record["finalizationStatus"] = "not_finalized"
                record["finalization"] = None
            self.state[table][body[key]] = record
            return {key: body[key], "revision": 1}
        if operation in {"revision.update", "revision.freeze", "scenario.update", "scenario.freeze", "report.freeze"}:
            table, key = {"revision.update": ("revisions", "revisionId"),
                          "revision.freeze": ("revisions", "revisionId"),
                          "scenario.update": ("scenarios", "scenarioRevisionId"),
                          "scenario.freeze": ("scenarios", "scenarioRevisionId"),
                          "report.freeze": ("reports", "reportRevisionId")}[operation]
            record = self.record(table, body[key], study_id)
            self.cas(record, body["expectedRevision"])
            require(record["status"] == "draft", "FROZEN_REVISION")
            if operation in {"revision.update", "scenario.update"}:
                require(valid_hash(body["contentHash"]), "INVALID_REQUEST")
                if operation == "revision.update":
                    require("validation" not in body and "parentRevisionId" not in body, "INVALID_REQUEST")
                    preparation_id = body.get("modelPreparationId", record["modelPreparationId"])
                    model_ref = body.get("modelRef", record["modelRef"])
                    preparation = self.qualified_model(preparation_id, study_id)
                    require(model_ref == preparation["modelRef"], "REFERENCE_MISMATCH")
                    record.update(modelPreparationId=preparation_id, modelRef=copy.deepcopy(model_ref), validation="not_checked")
                    if "definition" in body:
                        record["definition"] = copy.deepcopy(body["definition"])
                else:
                    require(not {"parentScenarioRevisionId", "modelPreparationId", "effectiveModelRef"}.intersection(body), "INVALID_REQUEST")
                    if "overrides" in body:
                        record["overrides"] = copy.deepcopy(body["overrides"])
                record["contentHash"] = body["contentHash"]
            else:
                if operation == "revision.freeze":
                    preparation = self.qualified_model(record["modelPreparationId"], study_id)
                    require(record["modelRef"] == preparation["modelRef"], "REFERENCE_MISMATCH")
                    require("validation" not in body, "INVALID_REQUEST")
                    require(validation_evidence is not None and validation_evidence.get("outcome") != "unavailable", "CAPABILITY_UNAVAILABLE")
                    expected = {"revisionId": body[key], "expectedRevision": record["revision"],
                                "contentHash": record["contentHash"], "modelPreparationId": record["modelPreparationId"],
                                "modelRef": record["modelRef"], "definition": record["definition"]}
                    require({key: validation_evidence.get(key) for key in expected} == expected, "REFERENCE_MISMATCH")
                    require(validation_evidence["outcome"] == "passed", "INVALID_REQUEST")
                    record["validation"] = "passed"
                    record["validationEvidence"] = copy.deepcopy(validation_evidence)
                if operation == "scenario.freeze":
                    preparation = self.qualified_model(body["modelPreparationId"], study_id)
                    require(preparation["source"] == {"type": "scenarioRevision", "scenarioRevisionId": body[key],
                        "expectedRevision": record["revision"], "contentHash": record["contentHash"]}, "REFERENCE_MISMATCH")
                    record["modelPreparationId"] = body["modelPreparationId"]
                    record["effectiveModelRef"] = copy.deepcopy(preparation["modelRef"])
                record["status"] = "frozen"
            record["revision"] += 1
            return {key: body[key], "revision": record["revision"], "contentHash": record["contentHash"]}
        if operation == "run.create":
            require(body["runId"] not in self.state["runs"], "REFERENCE_MISMATCH")
            base = self.record("revisions", body["studyRevisionId"], study_id)
            scenario = self.record("scenarios", body["scenarioRevisionId"], study_id)
            require(base["status"] == scenario["status"] == "frozen", "FROZEN_REVISION")
            require(scenario["studyRevisionId"] == body["studyRevisionId"], "REFERENCE_MISMATCH")
            preparation = self.qualified_model(scenario["modelPreparationId"], study_id)
            require(body["modelPreparationId"] == scenario["modelPreparationId"]
                    and body["effectiveModelRef"] == scenario["effectiveModelRef"] == preparation["modelRef"], "REFERENCE_MISMATCH")
            require(body["calculationContractRef"] == preparation["calculationContractRef"]
                    and body["profileId"] == preparation["profileId"] and body["engineId"] == "solver-worker", "REFERENCE_MISMATCH")
            require(valid_hash(body["inputHash"]), "INVALID_REQUEST")
            require(body["inputHash"] == preparation["inputHash"], "REFERENCE_MISMATCH")
            ref = body["calculationContractRef"]
            require(set(ref) == {"kind", "schema", "sha256"} and ref["kind"] == "calculation_contract"
                    and ref["schema"] == "lca.calculation-contract.v1" and valid_hash(ref["sha256"]), "REFERENCE_MISMATCH")
            record = copy.deepcopy(body)
            record.update(studyId=study_id, revision=1, executionStatus="queued", validity="current",
                          availability="pending", resultRef=None)
            self.state["runs"][body["runId"]] = record
            return {"runId": body["runId"], "inputHash": body["inputHash"]}
        if operation == "run.withdraw":
            run = self.record("runs", body["runId"], study_id)
            self.cas(run, body["expectedRevision"])
            run["validity"] = "withdrawn"
            run["revision"] += 1
            return {"runId": body["runId"], "validity": "withdrawn"}
        if operation == "review.append":
            target = body["target"]
            require(target["type"] == "reportRevision", "REFERENCE_MISMATCH")
            report = self.record("reports", target["revisionId"], study_id)
            require(report["status"] == "frozen" and report["contentHash"] == target["contentHash"], "REFERENCE_MISMATCH")
            require(body["decision"] in {"approved", "changes_requested", "withdrawn", "comment"}, "INVALID_REQUEST")
            require(body["reviewClass"] == "internal", "CAPABILITY_UNAVAILABLE")
            require(body["reviewId"] not in self.state["reviews"], "REFERENCE_MISMATCH")
            previous = self.review_head(actor, target, body["reviewClass"])
            if body["decision"] == "comment":
                require(body["supersedesReviewId"] is None, "REFERENCE_MISMATCH")
            elif previous is None:
                require(body["supersedesReviewId"] is None and body["decision"] != "withdrawn", "REFERENCE_MISMATCH")
            else:
                require(body["supersedesReviewId"] == previous["reviewId"], "REFERENCE_MISMATCH")
            self.state["reviews"][body["reviewId"]] = dict(copy.deepcopy(body), studyId=study_id, actor=actor)
            return {"reviewId": body["reviewId"]}
        if operation == "report.finalize":
            report = self.record("reports", body["reportRevisionId"], study_id)
            self.cas(report, body["expectedRevision"])
            require(report["status"] == "frozen", "FROZEN_REVISION")
            require(report["finalizationStatus"] == "not_finalized", "REVISION_CONFLICT")
            profile = REPORT_PROFILES.get(body["profileId"])
            require(profile is not None, "CAPABILITY_UNAVAILABLE")
            requirement = profile["reviewRequirement"]
            # Optional trusted projection is a consistency assertion, not authority.
            require(body.get("reviewRequirement", requirement) == requirement, "REFERENCE_MISMATCH")
            require(profile["available"], "CAPABILITY_UNAVAILABLE")
            accepted_review_ids = []
            if requirement == "internal":
                target = {"type": "reportRevision", "revisionId": body["reportRevisionId"], "contentHash": report["contentHash"]}
                for reviewer in sorted({item["actor"] for item in self.state["reviews"].values()}):
                    head = self.review_head(reviewer, target, "internal")
                    if head and head["decision"] == "approved" and study["members"].get(reviewer) in {"owner", "reviewer"} and "review" in study["capabilities"].get(reviewer, []):
                        accepted_review_ids.append(head["reviewId"])
                require(bool(accepted_review_ids), "REVIEW_REQUIRED")
            report["finalizationStatus"] = "finalized"
            report["finalization"] = {"profileId": body["profileId"], "reviewIds": accepted_review_ids,
                                      "finalizedAt": body["now"]}
            report["revision"] += 1
            return {"reportRevisionId": body["reportRevisionId"], "revision": report["revision"]}
        if operation == "export.create":
            report = self.record("reports", body["reportRevisionId"], study_id)
            require(report["status"] == "frozen", "FROZEN_REVISION")
            require(body["exportId"] not in self.state["exports"], "REFERENCE_MISMATCH")
            # A trusted Edge decision covers the complete serialized projection.
            require(body["trustedDisclosureDecision"] == "allowed", "DISCLOSURE_DENIED")
            require(body["grantEpoch"] == study["grantEpoch"], "FORBIDDEN")
            require(body["disclosureEpoch"] == study["disclosureEpoch"], "DISCLOSURE_DENIED")
            require(bool(body["policyId"]) and valid_hash(body["disclosureContextHash"]), "INVALID_REQUEST")
            require(valid_hash(body["projectionHash"]), "INVALID_REQUEST")
            self.state["exports"][body["exportId"]] = dict(copy.deepcopy(body), studyId=study_id, actor=actor, availability="ready")
            return {"exportId": body["exportId"], "projectionHash": body["projectionHash"]}
        if operation == "share.create":
            export = self.record("exports", body["exportId"], study_id)
            require(export["grantEpoch"] == study["grantEpoch"], "FORBIDDEN")
            require(export["disclosureEpoch"] == study["disclosureEpoch"], "DISCLOSURE_DENIED")
            require((body["reportRevisionId"], body["projectionHash"]) ==
                    (export["reportRevisionId"], export["projectionHash"]), "REFERENCE_MISMATCH")
            require(body["shareId"] not in self.state["shares"], "REFERENCE_MISMATCH")
            require(body["expiresAt"] > body["now"], "INVALID_REQUEST")
            self.state["shares"][body["shareId"]] = dict(copy.deepcopy(body), studyId=study_id,
                                                       grantEpoch=study["grantEpoch"], status="active", revision=1)
            return {"shareId": body["shareId"]}
        if operation == "share.revoke":
            share = self.record("shares", body["shareId"], study_id)
            self.cas(share, body["expectedRevision"])
            require(share["status"] == "active", "REVISION_CONFLICT")
            share["status"] = "revoked"
            share["revision"] += 1
            return {"shareId": body["shareId"]}
        raise Rejected("INVALID_REQUEST")


def lookup(value, path):
    for part in path.split("."):
        value = value[part]
    return value


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fixture", type=Path, default=Path(__file__).with_name("fixtures").joinpath("lca-study-durable.v1.json"))
    fixture = json.loads(parser.parse_args().fixture.read_text())
    assert fixture["schemaVersion"] == "lca.study-durable-fixtures.v1"
    assert fixture["contractVersion"] == "lca.study-durable.v1"
    ids = set()
    assertions = 0
    for case in fixture["cases"]:
        assert case["id"] not in ids, "duplicate case ID"
        ids.add(case["id"])
        model = Model()
        for event in fixture["setup"] + case["steps"]:
            before = copy.deepcopy(model.state)
            try:
                result = model.execute(event)
            except Rejected as error:
                assert str(error) == event.get("expectError"), (case["id"], event["operation"], str(error))
                assert model.state == before, "rejected transition changed durable state"
            else:
                assert "expectError" not in event, (case["id"], event["operation"], "expected rejection")
                if "expect" in event:
                    assert result == event["expect"], (case["id"], result, event["expect"])
            assertions += 1
        for path, expected in case.get("state", {}).items():
            assert lookup(model.state, path) == expected, (case["id"], path)
            assertions += 1
        for receipt in case.get("receipts", []):
            identity = json.dumps([receipt["actor"], receipt["operation"], receipt["studyId"], receipt["idempotencyKey"]])
            assert model.state["receipts"][identity]["result"] == receipt["result"], (case["id"], identity)
            assertions += 1
    assert ids and assertions > len(ids)
    print(f"lca.study-durable.v1: {len(ids)} traces, {assertions} transition/state assertions passed (offline model only).")


if __name__ == "__main__":
    main()
