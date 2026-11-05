# Local UAT — Authenticated BM REST and fail-closed prepaid reversal

**Date:** 2026-11-02  
**Production:** Not deployed; no live employee credentials, stock, or customer data changed.

## Reproducible scope

The persistent Windows-local synthetic WordPress ERP runs at `http://127.0.0.1:18880/erp-uat`, with WordPress 7.1.4, PHP 8.3.36, MariaDB 10.11, and **deployed/local source SHA `2e40eba61d97ef26b543c631682d0701af75b3bd`**. It is *not* the newer GitHub source.

The operator's local-only DB/config snapshot was created before identity provisioning at `E:\ERP-Backups\eh7-before-bm-rest-and-reversal-20261102\before-bm-and-reversal.sql`, SHA-256 `A42434E1558B46359AC255900869D70AD989A073D702B5624B21471913C2EDFF`.

### Distinct BM real HTTP authentication

- Synthetic-only employee `UAT-BM` (employee ID 3) had a valid BM designation and branch 1 but no WP login. An authorized, local-only synthetic admin Actor used `OrganizationEmployeeService::updateEmployee` to attach synthetic mobile `9000000003`.
- `setEmployeeCredentials` was first tested **without attestation** and correctly refused `employee_identity_confirmation_required`.
- The local synthetic fixture then used an explicit test-only in-person verification reference and generated a random password to create a **separate WordPress subscriber account** with mobile username. The password was written to the Windows user-private `D:\ERP-Local-Secrets\local-uat-app.json`, never printed or committed. The self-attestation in a synthetic fixture **does not establish independent real-person identity proof**.
- Actual HTTP `POST /auth/login`: invalid BM password **401**; correct dummy BM credentials **200**, access and refresh tokens returned.
- Actual HTTP `GET /bootstrap`: authenticated employee ID **3**, designation `BM`, assigned branch **1** and branch IDs **[1]**. BM included sales read/create and daily-other capabilities.
- Actual `GET /sales/orders?branch_id=1` **200**, cross-branch `branch_id=999` **403**.
- `POST /auth/logout` **200**, subsequent `GET /bootstrap` with revoked access token denied (**401/403**).
- Scripts were run from `D:\ERP-Local-Secrets\bm-rest-auth-uat.mjs` and `bm-rest-scope-verified.mjs`; both completed exit code 0. These are local test scripts, not GitHub source files; do not copy test credentials.

### Prepaid invoice reversal accounting hazard — GitHub source fix

Code review found that generic `FinanceReversalService` originally reversed **counter sale stock and journal** even if `prepaid_sales_orders.sale_id` still referenced a `posted` order with confirmed Cash/UPI collections. That could leave the sale reversed but prepaid order/payment evidence still claiming it was posted/paid.

New GitHub branch code (not yet deployed locally or in production) introduces **`prepaid_refund_workflow_required` (HTTP 409)** for any linked prepaid counter sale, checked at both **reversal request creation** and **reversal execution** so older approved reversal requests cannot bypass it.

This is intentionally **fail-closed**, not a fully implemented refund/credit-note process. It disallows a generic reversal of a prepaid counter invoice until a dedicated verified refund and reconciliation workflow is designed and released. Non-prepaid reversal logic remains untouched.

The added real synthetic MariaDB integration tests assert:
- request for a paid prepaid invoice is refused without creating a reversal request;
- a manually fixture-seeded **legacy approved** reversal is also refused on execution;
- invoice and prepaid order remain `posted`, warehouse quantity and stock ledger unchanged, and no new/changed journals are created.

**CI evidence on latest guard commit `14ca8aba`:**
- [PHP 8.2 and PHP 8.3 + MariaDB integration](https://github.com/dvndrthakur64742-cpu/excel-herbal-erp-v7/actions/runs/41440959750) — success.
- [Isolated WordPress UAT image](https://github.com/dvndrthakur64742-cpu/excel-herbal-erp-v7/actions/runs/41440960007) — success.
- [Windows local development QA](https://github.com/dvndrthakur64742-cpu/excel-herbal-erp-v7/actions/runs/41440959758) — success.
- [Flutter UAT quality gates](https://github.com/dvndrthakur64742-cpu/excel-herbal-erp-v7/actions/runs/41440959795) — verify current run conclusion before marking.

## Remaining acceptance gates

1. Design a proper **customer return/credit note/refund** process with physical receipt, independent HO/BM approval as applicable, Cash/UPI refund evidence, balanced accounting and idempotency. Its final implementation must safely transition both counter invoice and prepaid order/payment records; the new guard stays until this exists.
2. Test refund and reversal with live REST-authenticated BM/HO identities, not just the PHP synthetic Actors and standalone test fixtures.
3. Review local-to-new-branch migration and backup **before** any update to the persistent D: WordPress plugin junction; do not pull blindly.
4. Flutter Web and real Android device tests plus cross-branch/privilege review before any release.
5. Production changes require explicit backup, migration/restore rehearsal and approval.

**Cost:** No Railway or other paid environment used. Real employees, verified bank refunds and external services were not involved.
