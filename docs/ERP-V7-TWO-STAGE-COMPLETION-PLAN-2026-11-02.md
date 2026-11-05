# Excel Herbal ERP V7 — Next Work Backlog & Two-Stage Completion Plan

**Plan date:** 2026-11-02 (Asia/Kolkata)  
**Scope:** Continue the existing approved V7 blueprint with V15 field-sales business logic; do not start a replacement project.  
**Source of truth:** Draft PR #28 on `feature/v7-v15-staging-source-ci-20261031`.  
**Status:** Plan approved in principle by task request; this file is a development plan, **not evidence that the listed work is implemented or released**.

## Verified baseline (2026-11-02)
- Three GitHub Actions workflows PASS at commit `3c1946d6`: PHP 8.2/8.3 + MariaDB/prepaid integration, Flutter unit/widget + compatibility/build, and synthetic isolated WordPress UAT image.
- Live WordPress was previously inspected with V7 and V15 as separate active plugins. Their `eh7_*` and `eoe_*` databases cannot be collapsed without a verified table-by-table mapping and data owner audit.
- Last employee-link audit: 27 records (2 valid, 16 broken, 9 unlinked). Recheck read-only before changing anything; **never bulk-create passwords or silently adopt WordPress accounts**.
- Railway isolated-UAT project: 5 services OFFLINE and a staged destructive patch with a delete action for a UAT service; **do not accept blindly**.
- Live code has not been updated to the current draft PR version.

## Stage 1 — Functional ERP + Integrated UAT

### P0.1 — Restore isolated persistent UAT safely
- Inspect Railway project/env/service/volume/DB details and the staged destructive patch.
- Reject or reconcile the staged deletion **only after verifying dependencies and backup**, or create a new isolated staging target without reusing the live database.
- Pin WordPress/PHP/MariaDB image versions and exact GitHub commit; seed synthetic data, disable indexing, and verify source-head + sanitized markers.
- **Exit:** UAT URL responds, matching plugin schema/commit, backup recovery verified, no live user sessions or unsanitized data.

### P0.2 — Employee mobile login and startup
- Read-only audit branch/employee/WordPress identity links, including duplicates and privileged-role collisions.
- Repair each user only after identity ownership is verified via the existing audited credentials workflow; secure password issuance without plaintext logs.
- New subscribers use normalized mobile-number WordPress usernames; existing accounts are not automatically renamed.
- Verify both Flutter Web and Android auth: successful/failed login, bearer refresh rotation, logout, branch navigation, bootstrap, revoked session, device collisions.
- **Exit:** All authorized active employees can sign in; unauthorized or stale links cannot; mobile and desktop startup shows no error.

### P1.1 — Sales / payments / discount / stock full workflow
- Channels: B2C, B2B, distributor.
- Distributor rate determined by configured per-order quantity slabs; preserve historical price snapshots.
- Normal approved sales automatic; manager handles regular discounts; large discounts escalate to HO. **Discount threshold remains configurable and must not be presented as an approved numeric default.**
- Full confirmed Cash or independently verified UPI settlement **before final invoice**; reject shortfall, duplicate receipt, payment replay and unsupported credit.
- HO/branch stock reservations, transfer, receipt, ledger, returns and stock reconciliation, including concurrency tests.
- V15 field workflow: attendance gate → morning request → independent review → final approval → physical employee receipt → field sale → evening unsold returns → cash/UPI reconciliation.
- **Exit:** Business acceptance cases pass with real transactional MariaDB + REST and Flutter screens, including rejection/rollback cases.

### P1.2 — Attendance/GPS and reporting acceptance
- Implement and test HO-only exception approval with audit evidence; clarify how existing automatic 10:30–17:00 duty scheduling and exceptions co-exist before deploying.
- Validate salary/expenses/branch & finance totals against posted invoices and stock movements.
- **Exit:** Exceptions cannot be approved by branch employees; GPS and payroll reporting reconcile by branch and role.

**Stage 1 release gate:** Functional UAT sign-off on web/mobile; no P0/P1 business or permission failures; staging restoration repeatable. No production rollout yet.

## Stage 2 — One Plugin + Production-Ready Release

### P0.3 — V7/V15 consolidation strategy
- Inventory BOTH active plugins: registered routes, menus, cron, admin pages, web paths, dependencies, and `eh7_*` / `eoe_*` tables.
- Establish a single authoritative V7 plugin boundary and map needed V15 business functionality module-by-module.
- Create a **non-destructive**, versioned, idempotent schema/data migration; validate duplicate identity and transaction keys, audit row-count/reconciliation by company/branch.
- Keep V15 active on the live website until compatibility is proven on a clone. No drop, rename, direct SQL patch, plugin deactivation, or rollout without approval.
- **Exit:** One deployable main plugin runs needed functionality in UAT with no lost records or broken routes.

### P1.3 — Finance, HR, UI and audit hardening
- Accounting: cash/UPI, settlement, invoice, stock, expenses, finance close, payroll and branch reports reconcile.
- Usability: consistent responsive navigation, error states, accessible forms and mobile performance.
- Security: company/branch scoping, maker-checker separation, idempotency, rate limiting, permissions and audit trails.
- Test: PHP 8.2/8.3, Flutter analyze/widget, Docker WordPress/MariaDB UAT, realistic workflow tests, load/retry tests and cross-branch denial.
- **Exit:** Zero open critical blockers, complete acceptance checklist and release notes.

### P0.4 — Controlled rollout
- Confirm GitHub reviewed PR, immutable commit, signed-off version manifest, release ZIP SHA256 and matching Flutter build.
- Database/plugin/Flutter backups with successful restore rehearsal, staged migration and rollback plan.
- Deploy in a controlled approved window only; monitor login, API health, invoice, stock balance, journals, GPS and error rates.
- **Exit:** Live desktop/mobile smoke tests pass and accounting/stock totals match pre- and post-release; rollback ready.

## Work execution sequence
1. Railway staged-change audit and safe isolated UAT restoration.
2. Employee identity and Flutter auth/boot with synthetic identities, then individually verified employee repair.
3. Multi-channel end-to-end sales, discount/price, prepayment, stock, field returns and GPS HO exceptions.
4. V15→V7 dependency/data audit and staged consolidation.
5. Finance/payroll/reporting, full regression, backup/rollback, production release.

## Status discipline
- **Code merged** ≠ **UAT passed** ≠ **Production deployed**.
- Report each item as: source commit / test evidence / staging result / live result / remaining blocker.
- The previously quoted ~65% is a rough engineering estimate, **not** a measured completion percentage; do not increase it without objective acceptance results.
- Avoid inventing fixed completion dates or discount thresholds. No live site, database, user credentials, paid Railway resources, or plugin activations changed by adding this plan.
