#!/usr/bin/env bash
# Tier 2 execution harness — runs the scenario matrix a tier2-scenario-planner
# run produced (plan.json + specs/*.md) against a live app + Chronicle, and
# writes a report + evidence structure.
#
# Scope: this script executes the mechanically-runnable cases only (HTTP
# command + witness query). A case whose spec marks a step "not automatable"
# (see register-reactor-logs.md) is skipped with that noted in the report,
# not silently passed or failed.
#
# Usage: run-tier2.sh <run-dir>   (e.g. .build-kit/tier2/runs/2026-09-05-demo)
# Assumes: `docker compose up -d chronicle` and `dotnet run` are already
# running against this repo (this script does not boot them — see
# start-stack.sh, which does, and is meant to wrap this script).

set -euo pipefail

RUN_DIR="${1:?usage: run-tier2.sh <run-dir>}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_URL="${APP_URL:-http://localhost:5266}"
MONGO_URL="${MONGO_URL:-mongodb://localhost:27017}"
EVENT_STORE="${EVENT_STORE:-CratisApp}"
NAMESPACE="${NAMESPACE:-Default}"

EVIDENCE_DIR="$RUN_DIR/evidence"
mkdir -p "$EVIDENCE_DIR"
REPORT_PATH="$RUN_DIR/report.json"

python3 - "$RUN_DIR" "$APP_URL" "$MONGO_URL" "$EVENT_STORE" "$NAMESPACE" "$EVIDENCE_DIR" "$REPORT_PATH" <<'PYEOF'
import sys, json, time, uuid
import urllib.request
import pymongo
from datetime import datetime, timezone

run_dir, app_url, mongo_url, event_store, namespace, evidence_dir, report_path = sys.argv[1:8]

client = pymongo.MongoClient(mongo_url, serverSelectionTimeoutMS=5000)
event_log = client[f"{event_store}+es+{namespace}"]["event-log"]

def post(path, body):
    req = urllib.request.Request(
        f"{app_url}{path}",
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=10) as resp:
        return json.loads(resp.read())

def witness_event(event_type, content_match, timeout_s=5):
    """Match by event type + content field values, NOT by the command's
    response id — verified on a live run 2026-09-05 that Arc's CommandResult
    .response is NOT the resulting event's eventSourceId for this project's
    (Guid, EventType) Handle() return shape. See spike-log.md step 4."""
    deadline = time.time() + timeout_s
    query = {"type": event_type}
    for k, v in content_match.items():
        query[f"content.1.{k}"] = v
    while time.time() < deadline:
        doc = event_log.find_one(query, sort=[("_id", -1)])
        if doc:
            return doc
        time.sleep(0.2)
    return None

results = []

# --- Case: register-happy-path ---
case_id = "register-happy-path"
unique_name = f"Tier2 Witness {uuid.uuid4().hex[:8]}"
try:
    resp = post("/api/some-module/some-feature/registration", {"name": unique_name})
    command_ok = resp.get("isSuccess") is True
    witness = witness_event("Registered", {"name": unique_name})
    passed = command_ok and witness is not None
    evidence = {"commandResponse": resp, "witnessEventLogDoc": witness}
except Exception as e:
    passed = False
    evidence = {"error": str(e)}
with open(f"{evidence_dir}/{case_id}.json", "w") as f:
    json.dump(evidence, f, indent=2, default=str)
results.append({"caseId": case_id, "status": "pass" if passed else "fail", "evidence": f"evidence/{case_id}.json"})

# --- Case: listing-reflects-registration ---
case_id = "listing-reflects-registration"
unique_name = f"Tier2 Listing {uuid.uuid4().hex[:8]}"
try:
    resp = post("/api/some-module/some-feature/registration", {"name": unique_name})
    command_ok = resp.get("isSuccess") is True
    witness = witness_event("Registered", {"name": unique_name})
    read_model_doc = None
    if witness:
        deadline = time.time() + 5
        listings = client[event_store]["listings"]
        while time.time() < deadline:
            read_model_doc = listings.find_one({"name": unique_name})
            if read_model_doc:
                break
            time.sleep(0.2)
    passed = command_ok and witness is not None and read_model_doc is not None
    evidence = {"commandResponse": resp, "witnessEventLogDoc": witness, "readModelDoc": read_model_doc}
except Exception as e:
    passed = False
    evidence = {"error": str(e)}
with open(f"{evidence_dir}/{case_id}.json", "w") as f:
    json.dump(evidence, f, indent=2, default=str)
results.append({"caseId": case_id, "status": "pass" if passed else "fail", "evidence": f"evidence/{case_id}.json"})

# --- Case: register-reactor-logs ---
# Spec marks the reactor-side assertion "not automatable" without log access
# this harness doesn't have yet (see register-reactor-logs.md). Skip, don't fake.
results.append({
    "caseId": "register-reactor-logs",
    "status": "skipped",
    "reason": "reactor side-effect is a log line only (RegistrationReactor calls no command); this harness has no log-assertion mechanism yet — see the case spec's note.",
})

report = {
    "runId": run_dir.rstrip("/").split("/")[-1],
    "executedAt": datetime.now(timezone.utc).isoformat(),
    "cases": results,
    "summary": {
        "pass": sum(1 for r in results if r["status"] == "pass"),
        "fail": sum(1 for r in results if r["status"] == "fail"),
        "skipped": sum(1 for r in results if r["status"] == "skipped"),
    },
}
with open(report_path, "w") as f:
    json.dump(report, f, indent=2)

print(json.dumps(report["summary"]))
sys.exit(1 if report["summary"]["fail"] > 0 else 0)
PYEOF
