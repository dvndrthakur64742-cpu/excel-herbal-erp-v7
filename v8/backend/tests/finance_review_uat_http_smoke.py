#!/usr/bin/env python3
"""Loopback-only actual HTTP test using the seeded disposable MariaDB.
This does NOT test or register a production WordPress payment endpoint."""
import json
import os
import urllib.error
import urllib.parse
import urllib.request

ROOT = os.environ.get("V8_FINANCE_HTTP_URL", "")
assert ROOT == "http://127.0.0.1:18746", "Refusing a non-loopback HTTP probe"
ROUTE = ROOT + "/ci-only/v8/finance/employee-cash-evidence"
VALID = {
    "branch_id": "4001", "employee_id": "9001",
    "from": "2026-10-19", "to": "2026-10-19",
    "page": "1", "page_size": "25",
}
counts = 0

def probe(token="synthetic-finance", query=None, method="GET", path=ROUTE):
    args = VALID if query is None else query
    url = path + ("?" + urllib.parse.urlencode(args))
    headers = {"Accept": "application/json"}
    if token is not None:
        headers["Authorization"] = "Bearer " + token
    req = urllib.request.Request(url, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=6) as resp:
            return resp.status, dict(resp.headers), json.loads(resp.read())
    except urllib.error.HTTPError as e:
        return e.code, dict(e.headers), json.loads(e.read())

def check(valid, title):
    global counts
    if not valid:
        raise AssertionError("FAIL: " + title)
    counts += 1
    print("PASS", title)

def denied(token, query=None, method="GET", path=ROUTE):
    status, headers, result = probe(token, query, method, path)
    return 400 <= status < 500 and result.get("ok") is False and (
        "no-store" in headers.get("Cache-Control", "")
    )

status, headers, result = probe()
if status != 200:
    print("FINANCE UAT initial HTTP response", status, "safe code", result.get("code"))
check(status == 200 and result.get("read_only") is True, "Authenticated finance GET returns a read-only source")
check("no-store" in headers.get("Cache-Control", ""), "Cache headers prevent exposure of financial evidence")
check(result.get("scope") == "disposable_v8_test_finance_review_only", "Isolated source cannot masquerade as Office")
check(result.get("company_id") == 987665531 and result.get("branch_id") == 4001
      and result.get("employee_id") == 9001, "Server-scoped finance actor, branch and employee")
check(result.get("period") == {"from": "2026-10-19", "to": "2026-10-19"},
      "Date window is preserved over HTTP")
pages = result["source_pages"]
b2b = pages["canonical_b2b_field_cash"]["rows"]
daily = pages["legacy_daily_orders"]["rows"]
check(len(b2b) == 1 and len(daily) == 1, "Real original B2B and Daily Order rows returned separately")
check(b2b[0].get("cash_handover_verified") is True, "Only canonical B2B handover is verified in UAT")
proof = b2b[0]["cashier_finance_evidence"]
receipt = proof["cashier_receipt"]
finance = proof["finance_check"]
check(receipt["reference"] == "CI-CASHIER-REF-001"
      and receipt["cashier_employee_id"] == 9002,
      "Independent physical cashier and original receipt are source bound")
check(finance["checker_employee_id"] == 9005
      and finance["journal_id"] > 0
      and finance["remittance_id"] > 0
      and receipt["cashier_employee_id"] != finance["checker_employee_id"],
      "Distinct Finance checker and original posted journal are linked")
check(receipt["amount_paise"] == finance["amount_paise"] == 20000,
      "Cash amount matches original sale and handover")
check(daily[0]["cash_handover_verified"] is False
      and daily[0]["upi_bank_verified"] is False,
      "Legacy Daily Order does not inherit B2B Cash/UPI proof")
check(result["combined_sale_total_paise"] is None
      and result["combined_employee_cash_outstanding_paise"] is None
      and result["same_sale_across_sources_not_proven"] is True,
      "No double-counted sales or employee liability calculation")
check(result["external_bank_deposit_verified"] is False
      and proof["physical_cash_confirmed_on_office_staging"] is False,
      "No false production Cash or PSP/bank verification")
check(denied(None), "Unauthenticated finance request rejected")
check(denied("wrong"), "Unknown bearer token rejected")
check(denied("synthetic-field"), "Field seller cannot see finance evidence")
check(denied("synthetic-accounting-only"), "Accounting-only without employee-view denied")
check(denied("synthetic-branch-2"), "Other-branch finance actor denied")
check(denied("synthetic-other-company"), "Other-company finance actor denied")
check(denied("synthetic-finance", method="POST"), "Financial POST never reaches a writer")
check(denied("synthetic-finance", method="DELETE"), "Financial DELETE never reaches a writer")
check(denied("synthetic-finance", path=ROOT + "/wp-json/excel-herbal-erp/v7/organization/employees/9001/360/finance-proof"),
      "Disposable endpoint is not a registered WordPress production path")
for field, value, title in [
    ("company_id", "987665531", "client company override"),
    ("branch_id", "4002", "other branch"),
    ("employee_id", "9002", "wrong target employee"),
    ("page", "2", "unreviewed page two"),
    ("page_size", "101", "oversized page"),
    ("from", "2026-02-30", "impossible business date"),
    ("to", "2026-10-18", "inverted period"),
]:
    args = dict(VALID, **{field:value})
    check(denied("synthetic-finance", query=args), title + " rejected")
check(denied("synthetic-finance", query={**VALID, "debug": "1"}), "Undocumented query parameter denied")
print("FINANCE UAT HTTP SMOKE: %s/%s PASS; 127.0.0.1 and v8_test only; no Office or WordPress writes" % (counts, counts))
