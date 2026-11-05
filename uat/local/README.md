# Excel Herbal ERP — No-Railway Local UAT

Railway usage is exhausted. **Development is not blocked**: the existing GitHub Actions PHP 8.2/8.3, MariaDB, isolated WordPress and Flutter tests continue. For an *interactive persistent* UAT with no extra hosting, this folder provides a localhost-only Docker Compose stack.

**Current Windows workstation:** Docker / PHP / Flutter were not found on PATH when checked 2026-11-02. This setup is prepared in source but **has NOT been started or verified on that workstation**. It needs a supported Docker Engine/Docker Desktop installed and available, subject to license requirements and the user's own machine resources. No software was installed and no purchase/subscription was made.

## Start only on a trusted local machine

1. Pull the reviewed `feature/v7-v15-staging-source-ci-20261031` branch; ensure `git status --porcelain` is clean.
2. Copy `uat/local/.env.example` to `uat/local/.env`. Keep the .env private; **do not upload it**. Replace all placeholders with independently generated strong LOCAL-ONLY passwords. Set `EH7_LOCAL_SOURCE_SHA` to the exact output of `git rev-parse HEAD` (40 hex characters).
3. Confirm Docker Engine/Compose is running. From the **repository root**:

```powershell
docker compose --env-file uat/local/.env -f uat/local/compose.yml config --quiet
docker compose --env-file uat/local/.env -f uat/local/compose.yml up --build -d
docker compose --env-file uat/local/.env -f uat/local/compose.yml logs --tail 100 uat-wordpress
```

4. On the same PC open **http://127.0.0.1:18880** and the WordPress admin URL `http://127.0.0.1:18880/wp-admin/`. Browser/API must remain localhost; *not* `office.excelherbal.in`.
5. Check local `/wp-json/excel-herbal-erp/v7/health` for staging, synthetic-only, source-head match and the correct schema; test employee login/refresh/logout on synthetic users only, then B2C/B2B/distributor payment/stock workflows.

## Stop and backup

```powershell
docker compose --env-file uat/local/.env -f uat/local/compose.yml stop
```

Docker uses private named volumes for UAT WordPress and MariaDB. **Do not run `down -v`** unless intentionally deleting the disposable synthetic UAT data after making any required backups. Local UAT is not connected to Railway or the live WordPress/MySQL database.

## Safety / limitations

- The WordPress entrypoint's **local mode** requires site URL exactly `http://127.0.0.1:18880`, valid 40-character source SHA and `WP_ENVIRONMENT_TYPE=staging`. The Railway mode retains its own public-host allowlist and exact Git commit. Both refuse the office production domain.
- Only the WordPress HTTP service has a published port, bound to `127.0.0.1`. MariaDB has **no host port**. Docker containers can nevertheless make normal outbound network connections; this is not an air-gapped environment. Never import real data or use live credentials.
- Local UAT **cannot be reached from another device** without a deliberate new secure network design. It is not a production hosting replacement.
- On each plugin update, check Git SHA, backup UAT volumes, review migration changes and rerun tests. Image rebuilding alone does not guarantee successful migration.
- This folder does not claim Flutter Android build, public demo access, persistent Railway recovery, production deployment, or full UAT sign-off.
- CI validates Compose syntax and the security allowlist. A true interactive local session depends on Docker actually being installed.
