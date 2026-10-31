# ERP V7 — Release Blockers (Read-only audit: 2026-10-31)

## Current facts
- **Source PR:** #28; automated PHP 8.2 and 8.3 tests passed after employee-link status fix.
- **Live WordPress:** `https://office.excelherbal.in` reports V7 `7.3.6-rc1`, API contract `7.3.6-contract-2`, and schema `7.3.6-field-sales-2`.
- **Admin bootstrap:** returns success as the connected WordPress administrator. This does **not** prove Flutter employee login or frontend startup.
- **Live environment safety:** `environment=staging`; `sanitized=false`, `source_head_match=false`, and `active_mobile_sessions_zero=false`. This is **not release-safe**.
- **Employee identity links (aggregate only):** 27 ERP employees; 2 valid WordPress links, 16 stale/broken links, 9 unlinked. No credentials or personal employee records captured here.
- **Railway isolated UAT:** WordPress-UAT service is running; five previously staged config changes include **destructive deletion** of `WordPress-UAT-Deploy`. Do not apply pending patch without explicit review.
- **Flutter:** compiled Web bundle is available in older packaged archives; Flutter/Dart SDK was not found on Windows PATH, and editable Flutter source has not yet been confirmed.

## Release-blocker tasks
1. Produce a reproducible sanitized UAT seed and source-head match; do not copy unsanitized production employee/customer records.
2. Fix ERP employee identity links via existing audited credential-repair API, with identity verification and secure password delivery. Never mass link accounts via direct SQL.
3. Test mobile employee login + refresh + authenticated bootstrap and Flutter startup against the same UAT build.
4. Implement distributor volume slabs, discount escalation, and invoice-after-verified-full-payment for all channels.
5. Add MariaDB integration tests covering stock custody, prepayment, approvals, and double-posting concurrency.
6. Review/reconcile Railway pending destructive patch before any UAT redeploy.
7. Verify restoration from backup and obtain release approval before touching production.

## Audit constraints
No production changes, WP user creation, password resets, destructive SQL, Railway deployment, or source migration were performed during this inspection. CI success indicates local/static correctness, not release readiness.
