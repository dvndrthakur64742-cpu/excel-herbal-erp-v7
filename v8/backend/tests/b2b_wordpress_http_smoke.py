#!/usr/bin/env python3
"""Real loopback HTTP request/response against real V7 Api callbacks.

The server uses synthetic WP/identity stubs, NOT a deployed WordPress site.
No external domain, actual credentials, payment provider or financial writes.
"""
import json
import os
import pathlib
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request

ROUTER = pathlib.Path(__file__).with_name("b2b_wordpress_http_router.php")
ENDPOINT = "/wp-json/excel-herbal-erp/v7/development/b2b-staging-readiness"
CHECKS = 0


def check(test, name):
    global CHECKS
    if not test:
        raise AssertionError(name)
    CHECKS += 1
    print("PASS", name, flush=True)


def request(url, method="GET", token=None):
    headers = {"Accept": "application/json"}
    if token:
        headers["Authorization"] = "Bearer synthetic-" + token
    req = urllib.request.Request(url, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            code, headers, data = response.status, response.headers, response.read(20000)
    except urllib.error.HTTPError as exc:
        code, headers, data = exc.code, exc.headers, exc.read(20000)
    return code, json.loads(data.decode("utf-8")), headers


def listen_port():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def run_profile(environment, database, missing="", myisam="", checks=None):
    port = listen_port()
    os_env = dict(os.environ)
    os_env.update(
        B2B_HTTP_ENV=environment,
        B2B_HTTP_DB=database,
        B2B_HTTP_MISSING=missing,
        B2B_HTTP_MYISAM=myisam,
    )
    # Only a loopback-only listener; no Internet or remote staging service.
    proc = subprocess.Popen(
        ["php", "-S", "127.0.0.1:" + str(port), str(ROUTER)],
        env=os_env, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
    )
    try:
        root = "http://127.0.0.1:" + str(port)
        for _ in range(80):
            if proc.poll() is not None:
                raise RuntimeError("local PHP server terminated on startup")
            try:
                request(root + ENDPOINT + "?branch_id=31")
                break
            except (OSError, TimeoutError):
                time.sleep(0.1)
        else:
            raise RuntimeError("loopback PHP server readiness timed out")
        checks(root + ENDPOINT)
    finally:
        proc.terminate()
        try:
            _, err = proc.communicate(timeout=4)
        except subprocess.TimeoutExpired:
            proc.kill()
            _, err = proc.communicate(timeout=4)
        # Do not print synthetic bearer headers or server trace in normal output.
        if proc.returncode not in (0, -15, -9, 1, 143):
            print("Loopback PHP server terminated:", proc.returncode, file=sys.stderr)
            print(err.decode("utf-8", "replace")[-1200:], file=sys.stderr)


def development(endpoint):
    code, body, headers = request(endpoint + "?branch_id=31")
    check(code == 401 and body.get("error", {}).get("code") == "not_authenticated",
          "HTTP GET without bearer denied at V7 ActorResolver boundary")
    code, body, _ = request(endpoint + "?branch_id=31", token="unknown")
    check(code == 401 and body.get("error", {}).get("code") == "not_authenticated",
          "synthetic invalid bearer denied before staging metadata")
    code, body, headers = request(endpoint + "?branch_id=31", token="finance")
    data = body.get("data", {})
    check(code == 200 and body.get("ok") is True and data.get("read_only") is True,
          "real V7 API callback returns successful JSON envelope")
    check(data.get("company_id") == 11 and data.get("branch_id") == 31
          and data.get("existing_source_table_count") == 14
          and data.get("structural_preflight_possible") is True,
          "finance actor can inspect fourteen exact InnoDB metadata sources")
    check(data.get("financial_records_disclosed") is False
          and data.get("financial_posting_enabled") is False
          and data.get("production_release_authorized") is False
          and data.get("snapshot_executed") is False,
          "HTTP response explicitly disclaims financial posting and settlement proof")
    check(bool(headers.get("X-Request-Id")) and bool(headers.get("X-EH7-Version")),
          "HTTP emits canonical V7 request/version headers")
    check("no-store" in headers.get("Cache-Control", ""),
          "HTTP response disables storage of staging finance diagnostics")
    for token, expected_code, label in [
        ("bm", "permission_denied", "BM"),
        ("fse", "permission_denied", "FSE"),
        ("other-branch", "branch_forbidden", "other branch"),
    ]:
        code, body, _ = request(endpoint + "?branch_id=31", token=token)
        check(code == 403 and body.get("error", {}).get("code") == expected_code,
              label + " real HTTP request cannot inspect finance metadata")
    code, body, _ = request(endpoint + "?branch_id=notanumber", token="finance")
    check(code == 422 and body.get("error", {}).get("code") == "parameter_invalid",
          "malformed branch rejected by canonical V7 API contract")
    code, body, _ = request(endpoint, token="finance")
    check(code == 422 and body.get("error", {}).get("code") == "parameter_required",
          "missing mandatory branch rejected before data access")
    code, body, _ = request(endpoint + "?branch_id=31", method="POST", token="finance")
    check(code == 404 and body.get("code") == "rest_no_route",
          "no financial POST route is registered")


def disabled(endpoint):
    code, body, _ = request(endpoint + "?branch_id=31", token="finance")
    check(code == 404 and body.get("code") == "rest_no_route",
          "production/staging/wrong database never exposes diagnostic route")


def missing_table(endpoint):
    code, body, _ = request(endpoint + "?branch_id=31", token="finance")
    data = body.get("data", {})
    check(code == 200 and data.get("missing_source_table_count") == 1
          and data.get("structural_preflight_possible") is False,
          "missing immutable tender table cannot be marked staging-ready")


def myisam_table(endpoint):
    code, body, _ = request(endpoint + "?branch_id=31", token="finance")
    data = body.get("data", {})
    check(code == 200 and data.get("all_sources_innodb") is False
          and data.get("structural_preflight_possible") is False,
          "nontransactional canonical GL source blocks readiness")


if __name__ == "__main__":
    run_profile("development", "v8_test", checks=development)
    run_profile("production", "v8_test", checks=disabled)
    run_profile("staging", "v8_test", checks=disabled)
    run_profile("development", "office_live", checks=disabled)
    run_profile("development", "v8_test",
                missing="v8_b2b_payment_intents_uat", checks=missing_table)
    run_profile("development", "v8_test",
                myisam="wp_eh7_journal_lines", checks=myisam_table)
    print("B2B V7 REST OVER LOOPBACK HTTP:", CHECKS, "/", CHECKS, "PASS", flush=True)
