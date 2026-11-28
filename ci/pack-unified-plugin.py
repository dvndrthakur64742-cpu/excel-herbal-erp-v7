#!/usr/bin/env python3
"""Build one review-only WordPress plugin ZIP from the same checked-out Git SHA.

Usage: python3 ci/pack-unified-plugin.py --web-dir flutter-app/build/web --output-dir dist
Never deploy automatically. The compiled Flutter build is Office-only.
"""
import argparse
import hashlib
import json
import pathlib
import re
import shutil
import subprocess
import tempfile
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCE = ROOT / "plugin/excel-herbal-erp-v7"
API = "https://office.excelherbal.in/wp-json/excel-herbal-erp/v7"
BASE = '<base href="/wp-content/uploads/eh7-flutter-web/">'
REPLACEMENT = '<base href="__EH7_PLUGIN_ASSET_BASE__">'

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def version_entrypoints(index, bootstrap, commit):
    """Prevent an older cached bootstrap/main.dart.js surviving a plugin upgrade.

    Both URLs must change together. Keep the asset base and all API targets
    unchanged. Never silently package an unrecognized Flutter entrypoint.
    """
    if re.fullmatch(r"[a-f0-9]{40}", commit) is None:
        raise ValueError("Invalid frontend release identity")
    shell_marker = 'src="flutter_bootstrap.js"'
    build_marker = '"mainJsPath":"main.dart.js"'
    if index.count(shell_marker) != 1 or bootstrap.count(build_marker) != 1:
        raise ValueError("Unexpected Flutter entrypoint; cannot ensure cache invalidation")
    return (
        index.replace(shell_marker, f'src="flutter_bootstrap.js?v={commit}"'),
        bootstrap.replace(build_marker, f'"mainJsPath":"main.dart.js?v={commit}"'),
    )

def renderer_debug_symbol(relative):
    """Keep every renderer JS/WASM asset; omit only offline debug symbol maps."""
    return (
        len(relative.parts) > 1
        and relative.parts[0] == "canvaskit"
        and relative.name.endswith(".js.symbols")
    )

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--web-dir", type=pathlib.Path, required=True)
    parser.add_argument("--output-dir", type=pathlib.Path, required=True)
    args = parser.parse_args()
    web_input = args.web_dir.resolve()
    output = args.output_dir.resolve()
    commit = subprocess.check_output(["git", "-C", str(ROOT), "rev-parse", "HEAD"], text=True).strip()
    if re.fullmatch(r"[a-f0-9]{40}", commit) is None:
        raise ValueError("Source is not pinned to a Git commit")
    js = (web_input / "main.dart.js").read_text()
    if js.count(API) != 1 or "wordpress-uat-production.up.railway.app" in js:
        raise ValueError("Incorrect production Flutter build or mixed UAT targets")
    index = (web_input / "index.html").read_text()
    if index.count(BASE) != 1:
        raise ValueError("Unexpected Flutter base href; refused to package")
    if not (SOURCE / "src/Core/IntegratedFrontend.php").exists():
        raise ValueError("Same-plugin frontend loader is missing")

    with tempfile.TemporaryDirectory(prefix="eh7-unified-review-") as tmp:
        root = pathlib.Path(tmp)
        plugin = root / "excel-herbal-erp-v7"
        plugin.mkdir()
        shutil.copy2(SOURCE / "excel-herbal-erp-v7.php", plugin / "excel-herbal-erp-v7.php")
        shutil.copytree(SOURCE / "src", plugin / "src")
        (plugin / "build-meta.php").write_text(
            "<?php\nif (!defined('ABSPATH')) exit;\n" +
            "if (!defined('EH7_SOURCE_HEAD')) define('EH7_SOURCE_HEAD','" + commit + "');\n"
        )
        web = plugin / "web"
        web.mkdir()
        excluded_symbols = []
        for item in web_input.rglob("*"):
            if not item.is_file():
                continue
            rel = item.relative_to(web_input)
            if rel.as_posix() in ("index.html", "SHA256SUMS.txt", "RELEASE-REVIEW.txt", "flutter_service_worker.js"):
                continue
            if item.is_symlink() or ".." in rel.parts or item.suffix.lower() in (".php", ".pem", ".key"):
                raise ValueError(f"Unsafe web asset: {rel}")
            if renderer_debug_symbol(rel):
                excluded_symbols.append({"path": rel.as_posix(), "bytes": item.stat().st_size})
                continue
            dest = web / rel
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(item, dest)
        bootstrap_path = web / "flutter_bootstrap.js"
        index, bootstrap = version_entrypoints(index, bootstrap_path.read_text(), commit)
        bootstrap_path.write_text(bootstrap)
        (web / "eh7-app-shell.txt").write_text(index.replace(BASE, REPLACEMENT))
        (web / ".htaccess").write_text(
            "Options -Indexes\n<IfModule mod_mime.c>\nAddType application/wasm .wasm\n</IfModule>\n"
            "<IfModule mod_headers.c>\n"
            "<FilesMatch \"^(flutter_bootstrap|main\\\\.dart)\\\\.js$\">\n"
            "Header set Cache-Control \"no-cache, must-revalidate\"\n"
            "</FilesMatch>\n</IfModule>\n"
        )
        (plugin / "RELEASE-REVIEW-ONLY.txt").write_text(
            "Single-plugin frontend QA; no homepage takeover or production deployment.\n"
            "Source Git SHA: " + commit + "\n"
            "PHP WordPress backend + Flutter Office-targeted Web assets in one ZIP.\n"
            "The /erp/ route fails closed on non-Office hosts.\n"
        )
        (plugin / "README-QA-SINGLE-PLUGIN.txt").write_text(
            "ERP V7 — SINGLE PLUGIN QA REVIEW ONLY\nSource: " + commit + "\n"
            "WordPress Tools > ERP Web Preview; /erp/ path; existing homepage unchanged.\n"
            "Compiled API: " + API + "\n"
            "Never replace live plugins without fresh files+DB backup, isolated source-matched\n"
            "multi-role UAT, old UI installer assessment, restore rehearsal and approval.\n"
        )
        files = sorted(p for p in plugin.rglob("*") if p.is_file())
        for f in files:
            if f.is_symlink() or f.name in (".env", "wp-config.php"):
                raise ValueError(f"Unsafe package content: {f}")
            if f.suffix == ".php":
                subprocess.run(["php", "-l", str(f)], capture_output=True, check=True)
        output.mkdir(parents=True, exist_ok=True)
        name = f"excel-herbal-erp-v7-single-plugin-QA-{commit[:8]}.zip"
        target = output / name
        with zipfile.ZipFile(target, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as z:
            for f in files:
                z.write(f, f.relative_to(root).as_posix())
        with zipfile.ZipFile(target) as z:
            assert z.testzip() is None
            entries = z.namelist()
            assert len(entries) == len(set(entries)) == len(files)
            for required in (
                "excel-herbal-erp-v7/excel-herbal-erp-v7.php",
                "excel-herbal-erp-v7/web/eh7-app-shell.txt",
                "excel-herbal-erp-v7/web/main.dart.js",
                "excel-herbal-erp-v7/src/Core/IntegratedFrontend.php",
            ):
                assert required in entries
        manifest = {
            "status": "QA_REVIEW_ONLY_NOT_DEPLOYED",
            "source_sha": commit,
            "plugin_version": "7.3.12-rc1",
            "frontend_api": API,
            "versioned_frontend_entrypoints": True,
            "preview_path": "/erp/",
            "existing_homepage_unchanged": True,
            "zip_name": name,
            "sha256": digest(target),
            "file_count": len(files),
            "zip_bytes": target.stat().st_size,
            "excluded_renderer_debug_symbols": sorted(excluded_symbols, key=lambda item: item["path"]),
            "php_lint_count": sum(f.suffix == ".php" for f in files),
            "no_tests_or_credentials_in_plugin": True,
            "release_blockers": [
                "full hosted files+DB backup and restore",
                "browser UAT on real staff roles and exact source",
                "active older UI installer migration and caching",
                "written rollback and production approval",
            ],
        }
        (output / "SINGLE-PLUGIN-QA-MANIFEST.json").write_text(
            json.dumps(manifest, indent=2) + "\n"
        )
        (output / "SHA256SUMS.txt").write_text(f"{manifest['sha256']}  {name}\n")
        print(json.dumps(manifest, indent=2))

if __name__ == "__main__":
    main()
