# ERP V7 — Release Blockers (Read-only audit: 2026-10-31)

## Current facts
- **Source PR:** #28 is still a DRAFT staging-only branch (now tracking the 7.3.10-rc2 development candidate). PHP 8.2/8.3 regression and synthetic MariaDB gates run in GitHub Actions. Passing CI is not acceptance/UAT sign-off.
- **Live WordPress:** `https://office.excelherbal.in` reports V7 `7.3.6-rc1`, API contract `7.3.6-contract-2`, and schema `7.3.6-field-sales-2`.
- **Admin bootstrap:** returns success as the connected WordPress administrator. This does **not** prove Flutter employee login or frontend startup.
- **Live environment safety:** `environment=staging`; `sanitized=false`, `source_head_match=false`, and `active_mobile_sessions_zero=false`. This is **not release-safe**.
- **Employee identity links (aggregate only):** 27 ERP employees; 2 valid WordPress links, 16 stale/broken links, 9 unlinked. No credentials or personal employee records captured here.
- **Railway isolated UAT:** WordPress-UAT service is running; five previously staged config changes include **destructive deletion** of `WordPress-UAT-Deploy`. Do not apply pending patch without explicit review.
- **Flutter:** editable `flutter-app/` source is now present in PR #28, restored from an existing GitHub branch; a pinned Flutter UAT CI workflow exists. Its test/build status must be checked at the exact release commit, and there is no verified employee-login end-to-end run yet.

## 2026-10-31 development hardening (branch only)
- Employee login status uses a real WordPress user join rather than trusting a non-null `wp_user_id`.
- ERP employee managers cannot reset WordPress administrator, editor, custom-role or otherwise elevated credentials; only dedicated subscriber logins are eligible for ERP password maintenance.
- Linking an existing elevated WordPress user to a newly created employee requires WordPress administrator authorization; an executable synthetic regression covers these denials.
- WordPress ERP administration shows aggregate linked/broken/unlinked counts, including active-only totals, without auto-creating or resetting any user.
- These changes are only in source PR #28 until reviewed, deployed and verified. Production employee link counts remain unchanged.

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
