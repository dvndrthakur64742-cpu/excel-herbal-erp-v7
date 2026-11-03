# Excel Herbal ERP V7 — Additive Migration Rehearsal (2026-11-03)

## Tested source and CI evidence

- Commit: `143b81a38a66b394eada6553b59f43bb82cb4191` on `feature/v7-v15-staging-source-ci-20261031`.
- CI: [Disposable WordPress + MariaDB run #41578689481](https://github.com/dvndrthakur64742-cpu/excel-herbal-erp-v7/actions/runs/41578689481) — **passed**.
- PHP/MariaDB staging, Windows QA, and Flutter CI at that same commit — **passed**.
- No production or existing office database was used; Docker creates a new `eh7_ci_synthetic` database and removes the CI containers after the run.

## What was exercised

An added `uat/railway/ci-additive-upgrade-rehearsal.php` test runs only with `EH7_CI_ISOLATED=1`, the WordPress `staging` environment, and positive source-matching, sanitized, seeded, **synthetic-only** assertions. It refuses nonempty Return/Refund Evidence tables.

In the disposable synthetic CI database:

1. Snapshot full rows and SHA-256 hashes for WordPress users and usermeta, plus ERP companies, branches, employees, stock balances and ledger, journal entries, prepaid orders and payments, and mobile sessions.
2. Remove the **empty** `eh7_prepaid_return_requests` and `eh7_prepaid_refund_evidence` tables, and mark the test schema as the previous `7.3.10-prepaid-sales-1` version.
3. Exercise `Schema::maybeUpgrade()` to target `7.3.12-prepaid-refund-evidence-1`. Assert both tables are recreated.
4. Verify unique indexes: `uq_prepaid_return`, `uq_refund_original_payment`, `uq_refund_evidence_ref`, and `uq_refund_verify_ref`.
5. Compare all preserved data snapshots byte-for-byte via JSON SHA-256. Run `Schema::install()` a second time and verify the same snapshots and schema version still hold.

GitHub CI explicitly printed:

- `PASS synthetic v7.3.10-to-7.3.12 return/refund additive migration`
- `PASS unique refund/order evidence indexes and existing identity/stock/journal preservation`
- `PASS repeated schema install is idempotent on disposable WordPress/MariaDB`

## Precise scope and limitations

This is a **disposable synthetic schema-upgrade rehearsal**, not a restore rehearsal of Hostinger and not a replica of the user-populated Office database. It tests two new empty Return/Refund tables and protects existing synthetic rows; it does **not** guarantee that all production data, WordPress plugins, active sessions or custom host changes survive an Office in-place upgrade.

No automatic Cash/UPI refund transfer or statutory credit-note posting was enabled by this work. Existing manual evidence verification is still not proof of disbursement.

## Next mandatory gates before Office deployment

- Fresh hosting-provider **full WordPress files + MariaDB backup**, with retention location and a successfully rehearsed restore.
- Compare hosted plugin files, WordPress source marker, site URL and database schema to the reviewed source SHA. Office health previously reported `sanitized=false` and a source marker that was not GitHub-attested.
- Rehearse a copy of the **hosted** data (with privacy protections) on an isolated site; keep the user-populated Office environment and active sessions unchanged until explicit release acceptance.
- Versioned Flutter Web release and rollback of the entire web directory; authenticated employee/Branch Manager mobile login → bootstrap → dashboard → scoped sales → logout, plus device/browser acceptance.
- Review remaining actual Refund Posting, Credit Note, GST/tax, returns and stock-control scope; do not represent incomplete modules as complete.

**No Office URL, customer records, employee logins, production WordPress plugin or hosted database was changed in this test.**
