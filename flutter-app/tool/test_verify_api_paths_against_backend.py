"""Source-level Flutter/WordPress route drift parser tests."""
import tempfile
import unittest
from pathlib import Path

from verify_api_paths_against_backend import (
    API_PATHS,
    ROUTE_REGISTRY,
    KNOWN_MISSING,
    missing_paths,
    normalize_flutter,
    normalize_backend,
    read_baseline,
)


class RouteAuditTests(unittest.TestCase):
    def test_php_route_parameter_normalizes_single_and_double_slash(self):
        self.assertEqual(
            normalize_backend(r"/daily/cycles/(?P<id>\d+)/submit"),
            "/daily/cycles/{#}/submit",
        )
        self.assertEqual(
            normalize_backend(r"/daily/cycles/(?P<id>\\d+)/submit"),
            "/daily/cycles/{#}/submit",
        )

    def test_flutter_parameter_normalizes(self):
        self.assertEqual(
            normalize_flutter("/daily/cycles/$cycleId/submit"),
            "/daily/cycles/{#}/submit",
        )

    def test_baseline_rejects_duplicate_and_non_path(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "baseline.txt"
            path.write_text("/a\n/a\n", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "Duplicate"):
                read_baseline(path)
            path.write_text("abc\n", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "Invalid"):
                read_baseline(path)

    def test_uses_canonical_current_php_registry(self):
        self.assertTrue(API_PATHS.is_file())
        self.assertTrue(ROUTE_REGISTRY.is_file())
        self.assertIn(
            "plugin/excel-herbal-erp-v7/src/Http/RouteRegistry.php",
            ROUTE_REGISTRY.as_posix(),
        )
        missing = missing_paths(
            API_PATHS.read_text(encoding="utf-8"),
            ROUTE_REGISTRY.read_text(encoding="utf-8"),
        )
        self.assertEqual(missing, read_baseline(KNOWN_MISSING))


if __name__ == "__main__":
    unittest.main()
