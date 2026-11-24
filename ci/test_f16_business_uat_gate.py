#!/usr/bin/env python3
"""Offline regression tests: F16 never mistakes missing scenario for green."""
import importlib.util
import tempfile
import unittest
from pathlib import Path

MODULE = Path(__file__).with_name("f16-business-uat-gate.py")
spec = importlib.util.spec_from_file_location("f16_gate", MODULE)
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)
SHA = "3" * 40


class F16Gate(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.log_dir = Path(self.tmp.name)
        for case, rule in gate.REQUIRED.items():
            content = "\n".join(
                ["PASS " + name for name in rule["cases"]]
                + [rule["finish"]]
            ) + "\n"
            (self.log_dir / (case + ".log")).write_text(content, encoding="utf-8")

    def tearDown(self):
        self.tmp.cleanup()

    def test_all_four_real_suite_markers_produce_source_pinned_report(self):
        result = gate.validate_logs(self.log_dir, SHA)
        self.assertEqual(result["gate"], "PASS")
        self.assertEqual(result["required_suites"], 4)
        self.assertEqual(result["mandatory_named_business_cases"], 17)
        self.assertEqual(result["source_sha"], SHA)
        self.assertFalse(result["production_mutation_performed"])
        self.assertFalse(result["real_staff_acceptance_verified"])
        self.assertFalse(result["production_backup_restore_verified"])

    def test_missing_business_scenario_never_passes(self):
        file = self.log_dir / "business.log"
        value = file.read_text()
        value = value.replace("PASS e2_branch_closing_blocks_posting_and_reopens\n", "")
        file.write_text(value)
        with self.assertRaisesRegex(ValueError, "e2_branch_closing"):
            gate.validate_logs(self.log_dir, SHA)

    def test_failed_case_blocks_even_when_finish_present(self):
        file = self.log_dir / "uat.log"
        file.write_text(file.read_text() + "FAIL uat_daily_order_full_cycle\n")
        with self.assertRaisesRegex(ValueError, "reported failure"):
            gate.validate_logs(self.log_dir, SHA)

    def test_missing_suite_marker_fails(self):
        file = self.log_dir / "prepaid.log"
        file.write_text("PASS partly done\n")
        with self.assertRaisesRegex(ValueError, "finish line missing"):
            gate.validate_logs(self.log_dir, SHA)

    def test_missing_log_file_fails(self):
        (self.log_dir / "daily.log").unlink()
        with self.assertRaisesRegex(ValueError, "suite missing"):
            gate.validate_logs(self.log_dir, SHA)

    def test_sha_must_be_exact_git_hash(self):
        for bad in ("", "bad", "123" * 15, "office-secret"):
            with self.subTest(bad=bad):
                with self.assertRaisesRegex(ValueError, "Git source"):
                    gate.validate_logs(self.log_dir, bad)

    def test_out_of_order_cases_cannot_fool_gate(self):
        file = self.log_dir / "uat.log"
        file.write_text(file.read_text().replace(
            "PASS uat_daily_order_full_cycle",
            "INFO uat_daily_order_full_cycle"))
        with self.assertRaisesRegex(ValueError, "Missing mandatory"):
            gate.validate_logs(self.log_dir, SHA)


if __name__ == "__main__":
    unittest.main()
