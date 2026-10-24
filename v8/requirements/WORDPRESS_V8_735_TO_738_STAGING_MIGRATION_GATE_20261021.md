# Excel Herbal ERP V8 — Office Staging Migration Gate (21 October 2026)

## Authorization
Owner approved proceeding with the **staging** migration and V8 activation on 21 October 2026. This does NOT authorize data loss, unverified backup usage, deleting older plugins, or a production rollout.

## LIVE, READ-ONLY findings
- Host: `https://office.excelherbal.in`, `environment=staging`, WordPress hardening `passed`.
- Active backend: V7 7.3.5-rc1, Git source `a9d03f384096b54464ffbe9ba79da88252f9dd28`. Its REST health is OK.
- New V8 Unified Main plugin 8.0.0-dev, source `95a9e2806edef95257cd6b6aee6f1d56ca632d6b`, is **installed but inactive**. No activation or DB migration performed.
- Existing DB marker: `7.3.5-performance-indexes-1`. V8 packaged core marker: `7.3.8-reminder-review-center-1`.
- Live selected counts: 27 employees (all 27 active), 95 stock balance records, 22 journal entries, 27 current employee-branch history rows, 27 salary revision rows, 1 inter-branch clearing account.
- V8 expected reporting tables are **absent**: `report_submissions`, `report_reminder_drafts`, `report_submission_events`.
- Both GitHub Schema.php versions were compared using their `$c` table definitions: V7 defines 73 tables, V8 defines 76; 73/73 existing table definitions are byte-identical; 3 additional reporting tables are needed.
- **Risk:** `Schema::install()` uses dbDelta on all 76 definitions and calls `ensureColumn`, `ensureIndex`, `ensureInterBranchClearingAccounts`, `backfillEmployeeBranchHistory`, salary snapshot INSERT, and encryption-key provisioning before updating the schema marker. Selected counts imply prior branch/salary baseline rows exist, but do not prove that every backfill/DDL is a no-op.
- The recorded `eh7_setup_backend_backup_path` points to an **old 5 September 2026 V7 backend backup**. This is NOT verified as a complete, current WordPress SQL + uploads restore point.
- WPVibe's WP-CLI emulation exposes `db query` but does NOT offer `db export` or a full restore. Remote Desktop Commander device was offline. Direct Hostinger hPanel backup access is not connected.
- The site health reports `staging_safety.sanitized=false` and `active_mobile_sessions_zero=false`; this is additional unresolved UAT isolation risk.

## NO-GO condition (currently applies)
**Do not run any DDL/DML, update the schema version option, activate V8, deactivate V7, uninstall the old Setup Assistant, or install the bundled read-only web preview** until a current, restorable backup is verified. An old code ZIP is not a database backup.

## Required restore point
1. Obtain a fresh **full WordPress database backup AND wp-content files/uploads** for the correct Office staging site, preferably Hostinger hPanel's website backup or separately downloaded `.sql.gz` database and files backup. Keep it out of the public web root.
2. Record source database identity (without credentials), backup completion time/date, storage path, archive size, SHA-256, and a non-destructive restore validation to an isolated database/host or independently verified backup integrity.
3. Verify no manual changes/employee sessions are being overwritten and capture pre-migration row counts for employees, balances, journal entries, salary revisions, attendance, settlements and stock ledger.
4. Require a staged migration execution procedure with fail-closed checks against exact source schema `7.3.5-performance-indexes-1` and exact target schema `7.3.8-reminder-review-center-1`.

## Execution checklist after backup verification
1. Freeze Office staging writes / confirm UAT user isolation without damaging live accounts.
2. Recheck V7 health and DB marker. Ensure the V8 ZIP's source-head and required code are unchanged.
3. Create only the required three reporting tables under the correct `wp_eh7_` prefix using WordPress' current DB charset/collation (or reviewed idempotent migration), with follow-up schema checks.
4. Reconcile any historical salary / branch / clearing-account backfills only after dry-run counts and exception review. **No fictitious sales, stock or payroll entries.**
5. Update schema marker only after all expected tables and indexes exist and the accepted migration path has passed. Do not mask a failed migration by changing the marker alone.
6. Deactivate V7 **without deletion**; activate installed V8 plugin. Verify canonical `/wp-json/excel-herbal-erp/v7/health`, roles, counts, employee profile, stock and ledger totals.
7. In V8 Setup Center, install the SHA-verified *bundled read-only* web preview with previous web folder retained for rollback. Independently compare live `main.dart.js` and manifest hashes.
8. Roll back from verified backup on any migration/data inconsistency; reinstall/activate V7 only after schema compatibility is checked. Do NOT delete old plugins until a separate post-UAT handover approval.

## Result
Read-only compatibility analysis **completed**. New V8 ZIP was already built and tested (249 Flutter tests, PHP lint for 93 files, 33 web file hashes; GitHub Actions run 39568995690 PASS). **Actual database migration / V8 activation BLOCKED pending fresh verified full backup.**
