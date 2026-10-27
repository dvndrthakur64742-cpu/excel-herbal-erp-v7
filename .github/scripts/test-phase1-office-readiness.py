#!/usr/bin/env python3
"""Offline tests for Phase-1 fail-closed read-only admission."""
import importlib.util
from pathlib import Path
import unittest

p = Path(__file__).with_name("phase1-office-readiness.py")
spec = importlib.util.spec_from_file_location("phase1_readiness", p)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
A = "a" * 40
B = "b" * 40

def fixture():
    return {"ok": True, "data": {
        "environment": "staging", "source_head": A,
        "web_runtime": {"present": True, "source_head": B},
        "schema_installed": True,
        "host_hardening": {"status": "passed", "wp_environment_type": "staging",
                           "disallow_file_edit": True},
        "staging_safety": {"required": True, "sanitized": True,
                           "source_head_match": True, "active_mobile_sessions_zero": True,
                           "active_push_devices_zero": True, "search_indexing_disabled": True},
        "uat_bootstrap": {"required": True, "seeded": True, "synthetic_only": True,
                          "source_head_match": True, "admin_employee_present": True,
                          "limited_employee_present": True}}}

class Phase1ReadinessTests(unittest.TestCase):
    def test_all_green_remains_not_human_signed(self):
        result = module.evaluate(fixture(), A, B)
        self.assertEqual("PASS", result["technical_preflight"])
        self.assertEqual(0, result["human_uat"]["accepted"])
        self.assertEqual(0, result["human_uat"]["percent"])
        self.assertIsNone(result["audited_full_erp_percent"])
        self.assertEqual("NOT_AUTHORIZED", result["production_go_live"])
        self.assertFalse(result["office_mutations"])

    def test_unsanitized_and_sessions_block(self):
        data = fixture()
        data["data"]["staging_safety"]["sanitized"] = False
        data["data"]["staging_safety"]["active_mobile_sessions_zero"] = False
        data["data"]["uat_bootstrap"]["seeded"] = False
        result = module.evaluate(data, A, B)
        self.assertEqual("BLOCKED", result["technical_preflight"])
        for key in ("sanitized", "mobile_sessions_zero", "synthetic_uat_roles"):
            self.assertEqual("BLOCKED", result["checks"][key])

    def test_bad_both_build_hashes_block(self):
        result = module.evaluate(fixture(), "c" * 40, "d" * 40)
        self.assertEqual("BLOCKED", result["checks"]["backend_head"])
        self.assertEqual("BLOCKED", result["checks"]["web_head"])

    def test_missing_build_pin_never_certified(self):
        result = module.evaluate(fixture())
        self.assertEqual("BLOCKED", result["checks"]["backend_head"])
        self.assertEqual("BLOCKED", result["checks"]["web_head"])

    def test_no_data_fail_closed(self):
        result = module.evaluate({})
        self.assertEqual("BLOCKED", result["technical_preflight"])
        self.assertGreaterEqual(len(result["blockers"]), 10)

    def test_production_denied_even_if_all_else_green(self):
        data = fixture()
        data["data"]["environment"] = "production"
        self.assertEqual("BLOCKED", module.evaluate(data, A, B)["checks"]["staging"])

    def test_string_boolean_never_counts_as_true(self):
        data = fixture()
        data["data"]["staging_safety"]["sanitized"] = "true"
        data["data"]["uat_bootstrap"]["seeded"] = 1
        result = module.evaluate(data, A, B)
        self.assertEqual("BLOCKED", result["checks"]["sanitized"])
        self.assertEqual("BLOCKED", result["checks"]["synthetic_uat_roles"])

    def test_url_hard_allowlist_never_requests_bad_target(self):
        with self.assertRaises(ValueError):
            module.live_health("http://office.excelherbal.in")
        with self.assertRaises(ValueError):
            module.live_health(module.OFFICE_URL + "?x=1")

if __name__ == "__main__":
    unittest.main()
