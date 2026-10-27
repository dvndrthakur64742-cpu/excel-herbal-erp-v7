#!/usr/bin/env python3
"""V8 Phase-1 UAT admission: read-only, no deployment or human signoff."""
import argparse
import datetime
import json
from pathlib import Path
import sys
from urllib.request import Request, build_opener, HTTPRedirectHandler

OFFICE_URL = "https://office.excelherbal.in/wp-json/excel-herbal-erp/v7/health"
TOTAL_HUMAN_GATES = 10

def field(data, *path):
    for key in path:
        if not isinstance(data, dict):
            return None
        data = data.get(key)
    return data

def evaluate(raw, backend=None, web=None):
    data = raw.get("data", {}) if isinstance(raw, dict) else {}
    checks = {}
    blockers = []
    def gate(name, passed, action):
        checks[name] = "PASS" if passed else "BLOCKED"
        if not passed:
            blockers.append({"gate": name, "action": action})
    def yes(*key):
        return field(data, *key) is True
    current_backend = field(data, "source_head")
    current_web = field(data, "web_runtime", "source_head")
    gate("health_ok", isinstance(raw, dict) and raw.get("ok") is True, "Restore ERP health endpoint.")
    gate("staging", field(data, "environment") == "staging", "Use isolated staging, never production.")
    gate("host_hardening", field(data, "host_hardening", "status") == "passed" and
         field(data, "host_hardening", "wp_environment_type") == "staging" and
         yes("host_hardening", "disallow_file_edit"), "Verify WordPress staging hardening.")
    gate("schema_installed", yes("schema_installed"), "Verify schema on a separately isolated UAT copy.")
    gate("backend_head", bool(backend and current_backend == backend), "Pin and attest approved installed backend SHA.")
    gate("web_head", bool(web and current_web == web and yes("web_runtime", "present")), "Pin and attest approved installed web SHA.")
    gate("sanitized", yes("staging_safety", "required") and yes("staging_safety", "sanitized") and
         yes("staging_safety", "source_head_match"), "Prepare a safely isolated/sanitized staging copy, not an in-place wipe.")
    gate("mobile_sessions_zero", yes("staging_safety", "active_mobile_sessions_zero"), "Do not run business UAT with live mobile sessions.")
    gate("push_devices_zero", yes("staging_safety", "active_push_devices_zero"), "Detach real push devices from the isolated UAT copy.")
    gate("search_indexing_off", yes("staging_safety", "search_indexing_disabled"), "Disable staging indexing.")
    gate("synthetic_uat_roles", all(yes("uat_bootstrap", key) for key in (
         "required", "seeded", "synthetic_only", "source_head_match",
         "admin_employee_present", "limited_employee_present")), "Seed isolated synthetic Employee/ASM/Finance identities.")
    return {
        "schema_version": 1,
        "scope": "phase1_read_only_technical_uat_admission",
        "checked_at_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "observed": {"backend_head": current_backend, "web_head": current_web},
        "checks": checks,
        "blockers": blockers,
        "technical_preflight": "BLOCKED" if blockers else "PASS",
        "human_uat": {"accepted": 0, "total": TOTAL_HUMAN_GATES,
                      "percent": 0, "state": "NOT_ASSESSED_BY_HEALTH"},
        "audited_full_erp_percent": None,
        "production_go_live": "NOT_AUTHORIZED",
        "office_mutations": False,
    }

class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, url):
        raise ValueError("Office health redirect refused")

def live_health(url=OFFICE_URL):
    if url != OFFICE_URL:
        raise ValueError("Only the exact Office HTTPS read-only health URL is allowed.")
    with build_opener(NoRedirect()).open(Request(url, method="GET"), timeout=15) as resp:
        if resp.status != 200:
            raise ValueError("Unexpected Office health HTTP status")
        return json.loads(resp.read(1024 * 1024))

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--office-health", action="store_true")
    group.add_argument("--health-file", type=Path)
    parser.add_argument("--expected-backend", default="")
    parser.add_argument("--expected-web", default="")
    parser.add_argument("--output", type=Path, default=Path("dist/phase1-readiness/EVIDENCE.json"))
    args = parser.parse_args()
    def valid_sha(value):
        return len(value) == 40 and all(x in "0123456789abcdefABCDEF" for x in value)
    for value in (args.expected_backend, args.expected_web):
        if value and not valid_sha(value):
            parser.error("Expected source heads must be 40-digit hexadecimal hashes.")
    try:
        raw = live_health() if args.office_health else json.loads(args.health_file.read_text("utf-8"))
        result = evaluate(raw, args.expected_backend, args.expected_web)
    except (ValueError, OSError, KeyError) as exc:
        result = evaluate({}, args.expected_backend, args.expected_web)
        result["blockers"].insert(0, {"gate": "read_health", "action": str(exc)[:160]})
        result["technical_preflight"] = "BLOCKED"
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + "\n", "utf-8")
    print("PHASE-1:", result["technical_preflight"])
    print("OPEN:", ",".join(x["gate"] for x in result["blockers"]) or "none")
    print("HUMAN UAT: 0/10 is never inferred from health/CI")
    return 0 if result["technical_preflight"] == "PASS" else 2

if __name__ == "__main__":
    sys.exit(main())
