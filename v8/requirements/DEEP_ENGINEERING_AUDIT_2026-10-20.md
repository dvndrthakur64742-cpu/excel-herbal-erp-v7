# Excel Herbal ERP V8 — Source- and Release-Gate Audit (2026-10-20)

## Exact audit baseline

- Canonical repo: `dvndrthakur64742-cpu/excel-herbal-erp-v7`
- Review branch: `codex/erp-v8-foundation-20261017`, Draft PR #25.
- Starting audited SHA: `a0a97018b34743452e718604b6d49334a22cbcde`.
- PR: **138 changed files; +15,760/-13 lines** (includes tests and documentation,
  not evidence of 15,760 lines of deployable features).
- Tree: 546 blobs: 87 canonical backend PHP source files, 21 canonical
  backend PHP test files, 46 Flutter screen files and 53 Flutter test files,
  29 separate V8/B2B PHP source files and 22 corresponding test scripts.
- Latest previously green CI on starting SHA:
  Linux PHP 8.3/8.4, disposable MariaDB, Windows PHP and targeted Flutter.
- Existing `release-gates/v7.4.0.json`: automated baseline passed,
  production_approved=false. Manual gates **5 passed, 2 pending**:
  `business_report_review`, `pilot_signoff`. V7 Android GPS pilot
  passed on its own earlier build but is not acceptance of new V8 screens.

## Verified implementation versus blocked launch scope

| Area | Code exists | Important gap preventing full V8 sign-off |
|---|---|---|
| Identity/role/branch and hierarchy | Canonical V7 services, access guards, maker-checker | live V8 scenario matrix and independent privilege/security UAT |
| Employees, HR, Employee 360/person ledger | canonical V7 and new V8 read-only projections/UI | all-role profile UAT; cross-source evidence, migration |
| Product and purchasing/warehouse stock | canonical V7 product, purchase, inventory, stock | full end-to-end multi-branch physical reconciliation |
| Field morning/evening | actual V7 request/approval/issue/closing ledger logic | real field-device and cash handover/UPI verification |
| Counter sales | canonical V7 sales services | new V8 channel-level reconciliation in realistic staging |
| B2B retailer | substantial V8 isolated domain/real MariaDB UAT | canonical live WordPress REST integration, GST/tax policy, refunds/reversals, verified tender signoff, posting gate |
| Accounting, GL, cashier and bank | V7 GL and finance services; isolated V8 remittance/tender UAT | independent physical cashier/bank provider proof and canonical migration |
| Attendance/GPS/leave | V7 workforce, GPS policy and an earlier physical-device pilot | V8 route maps/permission outage device UAT; resolve attendance policy conflicts |
| Payroll/performance | V7 payroll and performance services; Employee 360 points | real payroll/HR/accounts sign-off, salary-fund policy reconciliation |
| Reports/approvals | daily, weekly, monthly, multi-branch, reporting watch, submission/approval, draft-only outbox | live UAT submission evidence; delivery adapter explicitly disabled |
| Flutter UX | 46 screens and multiple focused UI tests | systematic every-control role/mobile regression and duplicate-view inspection |
| Production release | no V8 deployment, no PR merge | Accounts report approval, pilot sign-off, migration/rehearsal and owner approval |

## Estimate rubric — NOT a measured completion metric

The prior conversational **34%** was an approximate V8 target-scope
engineering figure, not a verified task-counter. Based on canonical V7
reuse + V8 isolated tests and remaining integration/gate risk, a **35–40%
engineering-completion band** remains reasonable. Avoid a fictional
fractional percent, or deriving completion from lines/files/tests counts.

- Core end-to-end transactional/financial/B2B work: materially incomplete;
  the highest-risk integration and trusted payment evidence still block release.
- HR, Employee 360 and workforce: meaningful existing canonical foundation,
  but real multi-role/device UAT and V8 policy decisions remain.
- Reporting/dashboard/UI: more advanced on development branch; still requires
  browser/mobile staging and actual business-user acceptance.
- Release readiness: **NOT APPROVED**, regardless of green CI.

### What is NOT evidence of completion

- A PHP unit/CI pass is not evidence that a WP plugin is deployed and usable.
- Isolated V8 `v8_test` schema is not an approved production migration.
- Branch Watch "approved" = human attestation, not reconciled Cash/UPI,
  stock count, bank settlement or confirmed salary payment.
- Deduplicated reminder draft = neither a queued nor delivered notification.
- V7 physical GPS gate is not a test of every new V8 screen.
- A PR with 138 files changed cannot be equated with 138 finished tasks.

## Next recommended work sequence

1. Complete authenticated internal Manager Notification Center (list,
   reviewer-only prepare, audit-logged dismissal, no messaging) on Draft PR.
2. Disclose expired/invalid reminder draft lifecycle and test real MariaDB
   branch scope, repeated prepare and safe reviewed/dismissed transitions.
3. Add staging WP REST and Flutter role-by-role UAT, in particular BM/RM,
   finance and salary capabilities, attendance and GPS on physical devices.
4. Resolve payment/cashier/UPI/tax/carry-forward policy before any canonical
   B2B or Cash-in-Transit posting to production.
5. Rehearse migration/rollback, human Accounts review and named pilot
   sign-off, then request separate explicit production approval.

**Operational safety:** No deployment, no merge, no production database
changes or automatic messages authorized by this audit.
