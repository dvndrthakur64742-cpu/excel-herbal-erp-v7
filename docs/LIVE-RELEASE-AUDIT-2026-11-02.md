# Excel Herbal ERP — Live vs Development Release Audit
**Checked:** 2026-11-02 (Asia/Kolkata)  
**Release policy:** Staging-only until Flutter, database and login UAT pass.

## Live WordPress (read-only via WPVibe)
- Site: https://office.excelherbal.in
- WordPress 7.1.4; PHP 8.3.36.
- **Two distinct ERP plugins ACTIVE**: `excel-herbal-erp-v7` (7.3.6-rc1) and `universal-office-erp-platform` (15.0.0).
- V7 health: schema installed (`7.3.6-field-sales-2`), API contract `7.3.6-contract-2`; `source_head_match=false`, `sanitized=false`, `uat_bootstrap.seeded=false`.
- Administrator bootstrap succeeds; this is **not** a verified employee Flutter login.
- Both plugins register independent codebases; DO NOT deactivate either until pages, APIs, shortcodes, cron, frontend URLs, data tables, and active user dependencies are mapped.

## GitHub development branch
- Draft PR #28 contains later source (`7.3.10-rc2` candidate), not yet deployed on live WordPress.
- PHP staging quality gates and isolated WordPress image generation passed on recent commits.
- At the baseline 2026-10-31 source revision, Flutter compatibility gate failed 11 of 48 tests; several checks expected inlined hierarchy filtering that had been centralized into `EmployeeChoiceService`.
- 2026-11-02 fixes in draft PR: expose daily initial requester / latest additional stock request metadata; enforce delegated-duty visibility for both parties; allow scoped Employee Manage read access; restrict role-directory to Access Manage; update Flutter contract tests to validate central employee picker hierarchy, branch filter and active-only scope.
- Run final CI at the most recent commit. Never interpret string-contract tests alone as complete security UAT.

## Railway — Excel Herbal ERP - Isolated UAT
- Railway environment label `production` within the **UAT project** is not the live WordPress website.
- At the 2026-11-02 check, WordPress-UAT, WordPress-UAT-Deploy, wordpress-uat-init, Primary, and MariaDB all reported OFFLINE (no active deployment).
- Staged patch `e8334e2b-68b2-4d0e-9b78-940bbbfbc9ce` is destructive: it would delete WordPress-UAT-Deploy and update WordPress-UAT source/image settings. Do not accept it blindly.
- Rebuild a fresh isolated UAT only after validating DB, service config, sanitized fixtures, and any cost impacts.

## Release-blocking work
1. Run Flutter UI functional tests and authenticated employee bootstrap on UAT; trace failed status/response, not just administrator bootstrap.
2. Repair employee identities safely with verified owner and audited credential provisioning; no bulk password changes.
3. Build a tested, unified plugin migration strategy for V15 modules, including `eoe_*` ↔ `eh7_*` data and plugin route ownership.
4. Verify distributor price slabs, discount escalation, 100%-verified Cash/UPI payment before final invoice, branch stock and evening settlement.
5. Test GPS exception approval by Head Office, payroll, financial reconciliation, and role/branch isolation.
6. Verify database migrations and rollback restore before any production upgrade.

## Change safety
This audit and its PR commits **did not** change production plugins, WordPress employee accounts, WordPress passwords, or Railway deployments.
