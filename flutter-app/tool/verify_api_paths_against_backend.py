#!/usr/bin/env python3
"""Audit Flutter route shapes against the *current* WordPress V7 PHP registry.

--baseline is a development regression gate. It rejects any new unsupported
Flutter path AND stale baseline entries. It does NOT certify release parity.
Without --baseline the check is strict and fails until all gaps are closed.
"""
from __future__ import annotations

import argparse
from pathlib import Path
import re
import sys

FLUTTER_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = FLUTTER_ROOT.parent
API_PATHS = FLUTTER_ROOT / "lib/core/api_paths.dart"
ROUTE_REGISTRY = (
    REPO_ROOT / "plugin/excel-herbal-erp-v7/src/Http/RouteRegistry.php"
)
KNOWN_MISSING = FLUTTER_ROOT / "tool/known_unsupported_backend_paths.txt"


def quoted_routes(text: str) -> set[str]:
    """Only actual quoted leading-slash path shapes, never arbitrary prose."""
    return set(re.findall(r"""['"](/[^'"]+)['"]""", text))


def normalize_flutter(path: str) -> str:
    return re.sub(r"\$[A-Za-z_]\w*", "{#}", path)


def normalize_backend(path: str) -> str:
    return re.sub(r"\(\?P<[^>]+>\\{1,2}d\+\)", "{#}", path)


def missing_paths(flutter: str, backend: str) -> set[str]:
    frontend = quoted_routes(flutter)
    routes = quoted_routes(backend)
    if len(frontend) < 180 or len(routes) < 180:
        raise ValueError(
            f"Unexpectedly small route registry: Flutter={len(frontend)} "
            f"PHP={len(routes)}. Check source paths and extraction."
        )
    normalized_backend = {normalize_backend(route) for route in routes}
    return {
        route
        for route in frontend
        if normalize_flutter(route) not in normalized_backend
    }


def read_baseline(path: Path) -> set[str]:
    if not path.exists():
        raise ValueError(f"Missing explicitly reviewed route baseline: {path}")
    raw = path.read_text(encoding="utf-8")
    items = [line.strip() for line in raw.splitlines()
             if line.strip() and not line.startswith("#")]
    if len(items) != len(set(items)):
        raise ValueError("Duplicate unsupported route in reviewed baseline.")
    if any(not item.startswith("/") for item in items):
        raise ValueError("Invalid unsupported path baseline entry.")
    return set(items)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--baseline", action="store_true",
        help="allow only exactly declared unresolved path shapes (CI review mode)"
    )
    args = parser.parse_args()
    if not API_PATHS.is_file() or not ROUTE_REGISTRY.is_file():
        print("BLOCKED: Flutter or canonical PHP route registry is missing.",
              file=sys.stderr)
        return 2
    try:
        missing = missing_paths(
            API_PATHS.read_text(encoding="utf-8"),
            ROUTE_REGISTRY.read_text(encoding="utf-8"),
        )
        if args.baseline:
            declared = read_baseline(KNOWN_MISSING)
            new = missing - declared
            stale = declared - missing
            if new or stale:
                print("FAIL: route audit baseline drift; update code first, "
                      "then review declared exceptions.", file=sys.stderr)
                for route in sorted(new):
                    print(f"  NEW UNSUPPORTED: {route}", file=sys.stderr)
                for route in sorted(stale):
                    print(f"  STALE BASELINE: {route}", file=sys.stderr)
                return 1
            print(f"PASS regression baseline: {len(missing)} known unresolved "
                  "Flutter paths; no new unsupported paths.")
            if missing:
                print("RELEASE BLOCKED: backend parity incomplete (listed below).")
                for route in sorted(missing):
                    print(f"  - {route}")
            return 0
        if missing:
            print(f"FAIL strict route parity: {len(missing)} unsupported paths",
                  file=sys.stderr)
            for route in sorted(missing):
                print(f"  - {route}", file=sys.stderr)
            return 1
        print("PASS strict Flutter/PHP route parity: no unsupported path shapes.")
        return 0
    except ValueError as error:
        print(f"BLOCKED: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
