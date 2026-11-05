# Railway isolated UAT — recovery checklist (2026-11-02)

This is the next **small engineering task** within the approved ERP V7 two-stage plan, not a new plan. The existing Railway UAT is **not restored** merely because GitHub CI passes.

## Observed, read-only

- Isolated Railway project: `Excel Herbal ERP - Isolated UAT`. Its environment happens to be named `production`, but it is separate from the real office WordPress website.
- WordPress-UAT, MariaDB, Primary, wordpress-uat-init and WordPress-UAT-Deploy all report **offline**.
- WordPress-UAT last recorded failure: image **BUILD_IMAGE**; Railway's diagnosis endpoint has no further automatic explanation.
- An older `Primary` WordPress deployment failed at container startup because an executable named `exec` could not be found; do not use Primary as a shortcut.
- WordPress-UAT has staged branch `codex/reports-date-export-workflow` rather than our reviewed `feature/v7-v15-staging-source-ci-20261031`.
- Unaccepted environment patch includes **deleting WordPress-UAT-Deploy**. Do not accept it blindly.
- A dedicated MariaDB volume `/var/lib/mysql` and older Primary volume `/var/www/html` exist. Protect their contents even when services are offline.
- The latest GitHub Docker-based **ephemeral** WordPress/MariaDB test, PHP tests and Flutter UAT build pass on reviewed code. They do not start the persistent Railway project.

## Implemented safety gate

`uat/railway/recovery-preflight.mjs` evaluates three read-only provider snapshots, without credentials or any API mutation:

```sh
node uat/railway/recovery-preflight.mjs \
  --inventory railway-inventory.json \
  --staged railway-staged.json \
  --health railway-health.json
```

Use the **unmodified JSON** from the authorized read-only Railway environment inventory, staged-change and environment-status actions for the **same environment**. Save those JSON exports only locally in a private work area; never commit them or any environment variables. Exit 0 means the service configuration and online states are eligible for the *next* authenticated synthetic login UAT — **not** that the application has passed UAT. Exit 1 blocks readiness; exit 2 means input missing/invalid.

The gate rejects wrong project/repo/branch, a staged or deleted WordPress service, any unreviewed staged patch, missing MariaDB persistent volume, failed WordPress deployment, offline WordPress/MariaDB, or conflicting environment IDs. It cannot independently attest actual customer-data sanitization, PHP schema, Git SHA, database backup, employee authentication, or successful restore.

Synthetic acceptance tests run inside the GitHub UAT Image CI; this **does not poll Railway** automatically.

## Safe recovery sequence (execution still pending)

1. Inventory exact Railway services, variables **by name only**, mounted volumes and domains. Confirm isolated project ownership and budget authorization; do not copy live credentials or real employee records.
2. Obtain/verify backup and rollback for the existing UAT MariaDB volume and any WordPress persistent files before any potentially destructive operation.
3. Remove or reconcile the **old staged deletion and unrelated branch change** using a reviewed, explicit configuration process. Do not use `accept-deploy` while the destructive patch is present. Confirm the reviewed source and Dockerfile path `uat/railway/Dockerfile` are selected.
4. Confirm WordPress-UAT uses required isolated variables, correct database service hostname, staging environment and UAT domain. Keep the MariaDB volume intact. When safely authorized, start the existing database and reviewed UAT service and verify health.
5. Refresh the three read-only Railway snapshots and run the gate again. It must report `readyForLoginUat: true`.
6. On the running, synthetic-only UAT site verify source-head, schema, `sanitized`, `synthetic_only`, host hardening and **authenticated** Flutter web/Android login, refresh/logout and session revocation. Verify backup/restore separately.
7. Only after the above and explicit production approval can the main WordPress release be considered.

## Not performed

No Railway changes accepted, services deleted, volumes modified, new paid resources created, production plugins touched, or real employee passwords changed.
