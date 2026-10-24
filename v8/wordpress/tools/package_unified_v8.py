#!/usr/bin/env python3
"""Build a complete self-contained ERP V8 WordPress plugin from the existing core."""
import argparse
import hashlib
import json
import re
import shutil
import subprocess
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SLUG = "excel-herbal-erp-v8"

def build(repo: Path, head: str, staging: Path, output: Path) -> None:
    if not re.fullmatch(r"[a-f0-9]{40}", head):
        raise ValueError("Exact Git commit SHA required")
    if staging.exists():
        shutil.rmtree(staging)
    package = staging / SLUG
    package.mkdir(parents=True)
    template = repo / "v8/wordpress/plugin"
    core = repo / "backend/excel-herbal-erp-v7/src"
    web = repo / "flutter-app/build/web"
    if not core.is_dir() or not web.is_dir():
        raise RuntimeError("Existing business core / Flutter release build missing")
    shutil.copytree(template, package, dirs_exist_ok=True)
    shutil.copytree(core, package / "src")
    (web / ".last_build_id").write_text(head + "\n", encoding="ascii")
    paths = sorted(p for p in web.rglob("*") if p.is_file() and p.name != "SHA256SUMS.txt")
    lines = []
    for source in paths:
        if source.is_symlink():
            raise RuntimeError("Web symlinks not allowed")
        name = source.relative_to(web).as_posix()
        if ".." in Path(name).parts or "\\" in name:
            raise RuntimeError("Unsafe web path")
        lines.append(hashlib.sha256(source.read_bytes()).hexdigest() + "  " + name)
    (web / "SHA256SUMS.txt").write_text("\n".join(lines) + "\n", encoding="ascii")
    shutil.copytree(web, package / "bundled-web")
    (package / "build-meta.php").write_text(
        "<?php\nif (!defined('ABSPATH')) exit;\n"
        + "define('EH7_SOURCE_HEAD', '" + head + "');\n"
        + "define('EH7_DEPLOY_ENVIRONMENT', 'staging');\n"
        + "define('EH7_BUILD_UAT_ALLOW_OFFICE', true);\n"
        + "define('EH7_BUILD_UAT_HOST', 'office.excelherbal.in');\n",
        encoding="ascii",
    )
    required = [
        "excel-herbal-erp-v8.php", "build-meta.php",
        "app/SetupCenter.php", "app/BundledPreviewInstaller.php",
        "app/FrontendShell.php",
        "src/Core/Autoloader.php", "src/Core/Plugin.php",
        "src/Http/Api.php", "src/Administration/UatWebDeployAdmin.php",
        "bundled-web/SHA256SUMS.txt", "bundled-web/main.dart.js",
        "bundled-web/.last_build_id",
    ]
    for path in required:
        if not (package / path).is_file():
            raise RuntimeError("Incomplete plugin file: " + path)
    php_files = sorted(package.rglob("*.php"))
    for path in php_files:
        result = subprocess.run(["php", "-l", str(path)], capture_output=True, text=True)
        if result.returncode:
            raise RuntimeError("PHP lint failed: " + str(path) + "\n" + result.stdout + result.stderr)
    subprocess.run(
        ["php", str(repo / "v8/wordpress/tests/plugin_bootstrap_smoke.php"), str(package)],
        check=True,
    )
    subprocess.run(
        ["php", str(repo / "backend/excel-herbal-erp-v7/tests/attendance_separate_policy.php")],
        check=True,
    )
    subprocess.run(
        ["php", str(repo / "backend/excel-herbal-erp-v7/tests/gps_independent_policy.php")],
        check=True,
    )
    output.parent.mkdir(parents=True, exist_ok=True)
    if output.exists():
        output.unlink()
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for path in sorted(package.rglob("*")):
            if path.is_file():
                if path.is_symlink():
                    raise RuntimeError("Symlinks forbidden")
                archive.write(path, path.relative_to(staging).as_posix())
    with zipfile.ZipFile(output) as archive:
        names = archive.namelist()
        if len(names) != len(set(names)):
            raise RuntimeError("ZIP duplicate entries")
        if not names or not all(n.startswith(SLUG + "/") for n in names):
            raise RuntimeError("Bad installable WordPress plugin root")
        if archive.testzip() is not None:
            raise RuntimeError("ZIP CRC failure")
        if SLUG + "/excel-herbal-erp-v8.php" not in names:
            raise RuntimeError("WordPress V8 plugin entry missing")
        if archive.read(SLUG + "/bundled-web/.last_build_id").decode("ascii") != head + "\n":
            raise RuntimeError("Web build source is not exact HEAD")
        if archive.read(SLUG + "/build-meta.php").count(head.encode()) != 1:
            raise RuntimeError("Package build metadata mismatch")
    report = {
        "purpose": "Independent staging ERP V8 main plugin; no automatic deployment",
        "commit": head,
        "slug": SLUG,
        "production_approved": False,
        "same_existing_erp_business_database": True,
        "bundled_flutter_preview_read_only": True,
        "php_linted_files": len(php_files),
        "verified_web_files": len(lines),
        "zip_file": output.name,
        "zip_bytes": output.stat().st_size,
        "zip_sha256": hashlib.sha256(output.read_bytes()).hexdigest(),
    }
    (output.parent / "V8-UNIFIED-PLUGIN-MANIFEST.json").write_text(
        json.dumps(report, indent=2) + "\n", encoding="utf-8"
    )
    print("PASS unified ERP V8 WordPress ZIP", report["zip_sha256"])
    print("PASS PHP lint", len(php_files), "files; web manifest", len(lines), "files")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-head", required=True)
    args = parser.parse_args()
    build(
        ROOT, args.source_head, ROOT / "dist/v8-plugin-stage",
        ROOT / "dist/v8-wordpress-plugin/excel-herbal-erp-v8.zip",
    )
