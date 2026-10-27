#!/usr/bin/env python3
"""Certify a write-enabled *web-only* Office staging candidate (never deploy it).

This tool has no WordPress, database, network or credential access. The release
workflow owns the Flutter build flags; this tool verifies and signs its output.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import zipfile
from pathlib import Path


BASE_HREF = "/wp-content/uploads/eh7-flutter-web/"
API_BASE = "https://office.excelherbal.in/wp-json/excel-herbal-erp/v7"
MAX_ZIP_BYTES = 9 * 1024 * 1024
REQUIRED = (
    "index.html",
    "main.dart.js",
    "flutter_bootstrap.js",
    "flutter_service_worker.js",
)
RETAINED_ENGINE = frozenset(
    {
        "canvaskit/canvaskit.js",
        "canvaskit/canvaskit.wasm",
        "canvaskit/chromium/canvaskit.js",
        "canvaskit/chromium/canvaskit.wasm",
    }
)


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def certify(web_root: Path, output_dir: Path, source_head: str) -> dict:
    if not re.fullmatch(r"[0-9a-f]{40}", source_head):
        raise ValueError("A full lowercase 40-character Git commit SHA is required")
    if not web_root.is_dir() or web_root.is_symlink():
        raise ValueError("Flutter build/web directory is missing or linked")
    for name in REQUIRED:
        file = web_root / name
        if not file.is_file() or file.is_symlink() or file.stat().st_size == 0:
            raise ValueError(f"Missing or empty Flutter web release asset: {name}")

    index = (web_root / "index.html").read_text(encoding="utf-8")
    if f'<base href="{BASE_HREF}">' not in index:
        raise ValueError("Flutter base href does not target the Office web folder")

    main_js = (web_root / "main.dart.js").read_bytes()
    if API_BASE.encode() not in main_js:
        raise ValueError("Built JavaScript does not target the existing Office V7 API")
    if b"EXCEL HERBAL V8 PREVIEW" in main_js:
        raise ValueError("Read-only preview banner found in functional release JS")

    bootstrap = (web_root / "flutter_bootstrap.js").read_text(encoding="utf-8")
    match = re.search(r"_flutter\.buildConfig\s*=\s*(\{[^\n;]*\})\s*;", bootstrap)
    if not match:
        raise ValueError("Cannot attest compiled Flutter rendering engine")
    configuration = json.loads(match.group(1))
    if configuration.get("builds") != [
        {"compileTarget": "dart2js", "renderer": "canvaskit", "mainJsPath": "main.dart.js"},
        {},
    ]:
        raise ValueError("Unexpected Flutter renderer: do not prune assets")

    worker = (web_root / "flutter_service_worker.js").read_text(encoding="utf-8")
    if "self.registration.unregister()" not in worker or "RESOURCES" in worker:
        raise ValueError("Unexpected active caching service worker")

    removed = []
    for path in sorted(web_root.rglob("*")):
        if path.is_symlink():
            raise ValueError(f"Linked assets are forbidden: {path}")
        if not path.is_file():
            continue
        rel = path.relative_to(web_root).as_posix()
        if rel.startswith("canvaskit/") and rel not in RETAINED_ENGINE:
            if not (
                rel.endswith(".symbols")
                or rel.startswith(
                    ("canvaskit/skwasm", "canvaskit/wimp", "canvaskit/experimental_webparagraph/")
                )
            ):
                raise ValueError(f"Unknown CanvasKit asset: {rel}")
            path.unlink()
            removed.append(rel)
    if len(removed) < 10:
        raise ValueError("Unexpected renderer asset layout; investigate before packaging")
    for rel in RETAINED_ENGINE:
        path = web_root / rel
        if not path.is_file() or path.stat().st_size <= 1000:
            raise ValueError(f"Required CanvasKit runtime missing: {rel}")

    (web_root / ".last_build_id").write_text(source_head + "\n", encoding="ascii")
    checksums = []
    for path in sorted(web_root.rglob("*")):
        if not path.is_file() or path.name == "SHA256SUMS.txt":
            continue
        rel = path.relative_to(web_root).as_posix()
        if rel.startswith("/") or ".." in Path(rel).parts or "\\" in rel:
            raise ValueError(f"Unsafe ZIP member name: {rel}")
        checksums.append(f"{sha256(path.read_bytes())}  {rel}")
    (web_root / "SHA256SUMS.txt").write_text("\n".join(checksums) + "\n", encoding="ascii")

    output_dir.mkdir(parents=True, exist_ok=True)
    zip_path = output_dir / "Excel-Herbal-ERP-V8-Office-Functional-Web.zip"
    with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for path in sorted(web_root.rglob("*")):
            if path.is_file():
                archive.write(path, path.relative_to(web_root).as_posix())

    with zipfile.ZipFile(zip_path) as archive:
        names = archive.namelist()
        expected = {
            filename: digest
            for digest, filename in (
                row.split("  ", 1)
                for row in archive.read("SHA256SUMS.txt").decode("ascii").splitlines()
            )
        }
        if len(names) != len(set(names)) or len(names) != len(expected) + 1:
            raise ValueError("Duplicate or unsigned member in web archive")
        for name, checksum in expected.items():
            if sha256(archive.read(name)) != checksum:
                raise ValueError(f"Web asset failed SHA-256 verification: {name}")
        if archive.read(".last_build_id") != (source_head + "\n").encode("ascii"):
            raise ValueError("Incorrect source commit marker")

    if zip_path.stat().st_size > MAX_ZIP_BYTES:
        raise ValueError("Web ZIP exceeds verified WordPress upload size budget")
    manifest = {
        "release": "v8-office-functional-web-candidate",
        "site": "https://office.excelherbal.in",
        "environment": "staging",
        "api_base_url": API_BASE,
        "base_href": BASE_HREF,
        "preview_read_only": False,
        "source_head": source_head,
        "backend_or_database_included": False,
        "wordpress_deployment_performed": False,
        "main_js_sha256": sha256(main_js),
        "zip_sha256": sha256(zip_path.read_bytes()),
        "zip_bytes": zip_path.stat().st_size,
        "signed_file_count": len(expected),
        "unused_renderer_files_removed": len(removed),
    }
    (output_dir / "V8-FUNCTIONAL-WEB-MANIFEST.json").write_text(
        json.dumps(manifest, sort_keys=True, indent=2) + "\n", encoding="utf-8"
    )
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-head", required=True)
    parser.add_argument("--web-root", type=Path, default=Path("flutter-app/build/web"))
    parser.add_argument("--output-dir", type=Path, default=Path("dist/v8-office-functional-web"))
    args = parser.parse_args()
    manifest = certify(args.web_root, args.output_dir, args.source_head)
    print("PASS functional Office V8 web archive SHA-256:", manifest["zip_sha256"])
    print("PASS signed files:", manifest["signed_file_count"], "bytes:", manifest["zip_bytes"])
    print("NO deploy: WordPress, backend and database remain unchanged")


if __name__ == "__main__":
    main()
