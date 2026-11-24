#!/usr/bin/env python3
"""F16 synthetic MariaDB business UAT acceptance. No production access.

Reads logs emitted by the *existing isolated integration suites*. Does not
open a database, execute PHP, access secrets, or modify any business data.

Release gate: exit nonzero if a mandatory business case was not visibly
executed, reported FAIL, or omitted its suite-completion marker.
"""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

SOURCE_SHA_PATTERN = re.compile(r"^[a-f0-9]{40}$")
REQUIRED = {
    "uat": {
        "finish": "PASSED staging UAT end-to-end smoke suite",
        "cases": (
            "uat_staff_bm_finance_ho_role_scopes_no_writes",
            "uat_employee_directory_names_and_company_scope",
            "uat_branch_scope_fail_closed",
            "uat_automatic_attendance_and_gps_evidence",
            "uat_daily_order_full_cycle",
            "uat_inventory_transfer_create_dispatch_receive",
            "uat_inventory_transfer_list_branches_units_and_scope",
            "uat_finance_expense_maker_checker",
            "uat_payroll_generate_approve_pay",
            "uat_hr_document_download_and_revoke",
            "uat_no_negative_stock_and_balanced_journals",
        ),
    },
    "business": {
        "finish": "PASSED business E2E coverage II suite",
        "cases": (
            "e2_purchase_bill_and_supplier_payment",
            "e2_full_prepayment_and_no_customer_credit",
            "e2_inventory_adjustment_maker_checker",
            "e2_finance_expense_reversal_workflow",
            "e2_reports_and_subledger_reconciliation",
            "e2_branch_closing_blocks_posting_and_reopens",
        ),
    },
    "prepaid": {
        "finish": "PASSED full prepaid B2C/B2B/distributor MariaDB transaction and concurrent posting integration (synthetic only)",
        "cases": (),
    },
    "daily": {
        "finish": "PASSED real MariaDB initial rejection, correction, withdrawal, allocation protection and audit",
        "cases": (),
    },
}


def validate_logs(log_dir: Path, sha: str) -> dict:
    if not SOURCE_SHA_PATTERN.fullmatch(sha):
        raise ValueError("Invalid 40-character Git source commit")
    if not log_dir.is_dir():
        raise ValueError("Missing synthetic UAT log directory")

    results = {}
    for scenario, required in REQUIRED.items():
        logfile = log_dir / (scenario + ".log")
        if not logfile.is_file():
            raise ValueError("Required synthetic business suite missing: " + scenario)
        content = logfile.read_text(encoding="utf-8")
        # Never capture logs themselves in the release report, including
        # potential exception details or transaction payloads.
        lines = set(content.splitlines())
        if any(line.startswith(("FAIL ", "FAILED ")) for line in lines):
            raise ValueError("Synthetic business suite reported failure: " + scenario)
        if required["finish"] not in lines:
            raise ValueError("Expected suite finish line missing: " + scenario)
        missing = [
            case for case in required["cases"] if "PASS " + case not in lines
        ]
        if missing:
            raise ValueError("Missing mandatory pass cases in " + scenario + ": " + ", ".join(missing))
        results[scenario] = {
            "status": "PASS",
            "mandatory_case_count": len(required["cases"]),
            "completion_marker_found": True,
        }

    return {
        "gate": "PASS",
        "source_sha": sha,
        "environment": "github_actions_disposable_synthetic_mariadb",
        "latest_source_e2e_only": True,
        "real_staff_acceptance_verified": False,
        "production_backup_restore_verified": False,
        "production_mutation_performed": False,
        "required_suites": len(REQUIRED),
        "mandatory_named_business_cases": sum(len(x["cases"]) for x in REQUIRED.values()),
        "suites": results,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-sha", required=True)
    parser.add_argument("--log-dir", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    opts = parser.parse_args()
    try:
        report = validate_logs(opts.log_dir, opts.source_sha)
    except (OSError, ValueError) as exc:
        raise SystemExit("F16_GATE_BLOCKED: " + str(exc))
    opts.output.parent.mkdir(parents=True, exist_ok=True)
    opts.output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
