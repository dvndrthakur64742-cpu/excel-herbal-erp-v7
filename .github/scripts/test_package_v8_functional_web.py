"""Offline release-integrity tests; no live WordPress/network actions."""

from __future__ import annotations

import json
import tempfile
import unittest
import zipfile
from pathlib import Path

from package_v8_functional_web import API_BASE, BASE_HREF, certify


HEAD = "a" * 40


class FunctionalWebPackageTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.web = self.root / "build" / "web"
        self.web.mkdir(parents=True)
        self.output = self.root / "dist"
        (self.web / "index.html").write_text(
            f'<html><head><base href="{BASE_HREF}"></head></html>', encoding="utf-8"
        )
        (self.web / "main.dart.js").write_text(f"/* V8 {API_BASE} */", encoding="utf-8")
        (self.web / "flutter_bootstrap.js").write_text(
            '_flutter.buildConfig = {"builds":[{"compileTarget":"dart2js",'
            '"renderer":"canvaskit","mainJsPath":"main.dart.js"},{}]};',
            encoding="utf-8",
        )
        (self.web / "flutter_service_worker.js").write_text(
            "self.registration.unregister();", encoding="utf-8"
        )
        for name in (
            "canvaskit/canvaskit.js", "canvaskit/canvaskit.wasm",
            "canvaskit/chromium/canvaskit.js", "canvaskit/chromium/canvaskit.wasm",
        ):
            path = self.web / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b"1" * 1024)
        for n in range(10):
            path = self.web / "canvaskit" / f"skwasm-{n}.wasm"
            path.write_bytes(b"unused")

    def test_web_only_candidate_signs_exact_source_and_all_files(self):
        manifest = certify(self.web, self.output, HEAD)
        self.assertFalse(manifest["preview_read_only"])
        self.assertFalse(manifest["backend_or_database_included"])
        self.assertFalse(manifest["wordpress_deployment_performed"])
        self.assertEqual(manifest["unused_renderer_files_removed"], 10)
        self.assertEqual(manifest["source_head"], HEAD)
        self.assertEqual(
            json.loads((self.output / "V8-FUNCTIONAL-WEB-MANIFEST.json").read_text()),
            manifest,
        )
        with zipfile.ZipFile(self.output / "Excel-Herbal-ERP-V8-Office-Functional-Web.zip") as z:
            self.assertEqual(z.read(".last_build_id"), (HEAD + "\n").encode())
            self.assertEqual(len(z.namelist()), manifest["signed_file_count"] + 1)
            self.assertIn(b"  main.dart.js\n", z.read("SHA256SUMS.txt"))
            self.assertNotIn("canvaskit/skwasm-0.wasm", z.namelist())
            self.assertIn("canvaskit/chromium/canvaskit.wasm", z.namelist())

    def test_rejects_preview_compiled_code(self):
        with (self.web / "main.dart.js").open("ab") as f:
            f.write(b"EXCEL HERBAL V8 PREVIEW")
        with self.assertRaisesRegex(ValueError, "Read-only preview"):
            certify(self.web, self.output, HEAD)

    def test_rejects_wrong_source_head_and_old_base_url(self):
        with self.assertRaisesRegex(ValueError, "40-character"):
            certify(self.web, self.output, "invalid")
        (self.web / "index.html").write_text('<base href="/other/">', encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "base href"):
            certify(self.web, self.output, HEAD)

    def test_rejects_unexpected_renderer(self):
        (self.web / "flutter_bootstrap.js").write_text(
            '_flutter.buildConfig = {"builds":[{"renderer":"skwasm"}]};', encoding="utf-8"
        )
        with self.assertRaisesRegex(ValueError, "renderer"):
            certify(self.web, self.output, HEAD)

    def test_rejects_unknown_compiler_assets(self):
        (self.web / "canvaskit" / "mystery_engine.bin").write_bytes(b"unsafe")
        with self.assertRaisesRegex(ValueError, "Unknown CanvasKit asset"):
            certify(self.web, self.output, HEAD)


if __name__ == "__main__":
    unittest.main()
