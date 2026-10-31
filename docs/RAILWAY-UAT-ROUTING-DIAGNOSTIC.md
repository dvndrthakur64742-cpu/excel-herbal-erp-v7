# Isolated Railway UAT routing audit — 2026-10-31

This is **read-only diagnosis**. No Railway patch accepted, deployment restarted, or production WordPress records modified.

## Observed
- Project: Excel Herbal ERP - Isolated UAT (Railway environment is named `production` but is a **separate UAT project**).
- WordPress-UAT container: online, old staging plugin 7.3.5-rc1, old source SHA `4510d5f3183607d5bf2677fbe4038ec2dc729446`.
- `GET /?rest_route=%2Fexcel-herbal-erp%2Fv7%2Fhealth` -> 200, JSON `ok:true`, synthetic seed and sanitization reported true.
- `GET /wp-json/excel-herbal-erp/v7/health` -> 301 to trailing slash; followed by transient 503 or HTML. Canonical pretty REST routing is **not reliable**.
- Host-hardening status blocked: `WP_ENVIRONMENT_TYPE` and `DISALLOW_FILE_EDIT` constants reported missing. A mere process variable is not enough for current host-hardening check.
- Existing Railway staged patch is destructive: includes deletion of WordPress-UAT-Deploy. Do not accept it unreviewed.
- The old source's UAT entrypoint does not explicitly ensure WordPress Apache rewrite rules or persistent `.htaccess` setup.

## Remediation plan (NOT EXECUTED)
1. Review the staged destructive patch, isolate and preserve existing services/volumes.
2. Verify Apache `rewrite_module`, `AllowOverride`, and `/var/www/html/.htaccess` in the disposable UAT container.
3. After UAT backup, set non-destructive WordPress rewrite rules/flush for UAT host; do **not** change production permalinks.
4. Define `WP_ENVIRONMENT_TYPE=staging` and `DISALLOW_FILE_EDIT=true` in an appropriate UAT WordPress configuration loaded early enough for host-hardening checks.
5. Build a new UAT image from the reviewed Git commit and plugin source. Ensure `EH7_SOURCE_HEAD` matches the packaged source and rerun sanitization/attestation **on isolated UAT only**.
6. Validate clean JSON responses on normal `/wp-json/excel-herbal-erp/v7/health` and authenticated `/bootstrap`, no redirect or HTML.
7. Use synthetic UAT employees for login, refresh, role scope and dashboard startup tests; never reuse real employee passwords.

## Acceptance criteria
- Normal REST routes return 200 JSON consistently without redirect.
- UAT host-hardening status passes; sanitized, source-head matched, synthetic data attestation passes.
- PHP 8.2/8.3 and Flutter CI pass on same commit.
- UAT Flutter web artifact connects to UAT host only; zero traffic to live office WordPress.
- Only after successful end-to-end tests may a separate production deployment review be opened.
