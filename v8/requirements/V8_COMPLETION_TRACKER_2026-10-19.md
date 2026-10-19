# Excel Herbal ERP V8 — engineering completion tracker

**Date:** 2026-10-19  | **Branch:** `codex/erp-v8-foundation-20261017` | **Production deployment:** NO

## Estimated whole-system progress: ~22% (±5 percentage points)

**This is a conservative weighted engineering estimate, not production readiness, not a percentage inferred from passing isolated tests, and not an audited sprint-velocity forecast.** Re-evaluate when a real vertical slice passes deployment-free UAT and its exact-head CI.

| Capability area | Project weight | Evidence-backed earned points | Remaining gate |
|---|---:|---:|---|
| BRD consolidation, legacy rule extraction and conflict register | 10 | 6 | Owner signoff on contested attendance, custody, pricing and tax policies |
| Retailer B2B pure-domain rules, custody and verified-tender contracts | 15 | 8 | Server checkout/payment/retailer pricing/reversal authorization |
| Canonical customer, stock and GL integration | 20 | 5 | Actual V7 StockService/AccountingService verified on disposable MariaDB; production trust bridge, statutory policy, WordPress runtime and multi-worker stress testing still missing |
| Purchase, stock, daily employee operations, branch close | 15 | 0 | Fully integrated and tested workflows under V8 UI/API |
| Employee 360°, HR, payroll and GPS | 15 | 0 | Required operational functions and real-device UAT |
| Secure role-based UI / Flutter and backend APIs | 10 | 0 | Backend-authorized actual API integration and usable screens |
| Ledgers, reports, finance reconciliation | 5 | 0 | Accurate posting, reversal and reconciliation across branches |
| Real CI, integration, concurrency, UAT and deployment rehearsal | 10 | 3 | Hosted PHP 8.3/8.4 PASS, real V7 MariaDB 30/30 including two-connection lock conflict/retry PASS; Windows PHP runner, multi-worker load, real WordPress and Flutter UAT remain |
| **TOTAL** | **100** | **22** | **~78 points remaining** |

## Verified versus unverified (latest exact-head evidence)

- **GitHub Actions run [39251143974](https://github.com/dvndrthakur64742-cpu/excel-herbal-erp-v7/actions/runs/39251143974): SUCCESS** for PHP 8.3, PHP 8.4 and MariaDB jobs, exact commit `7f48a571131ecbe3c088a53782b01f6a6271a543`.
- The new disposable `v8_test` real-service integration checks report **30/30 PASS**: actual V7 `StockService::move`, `AccountingService::post`, number series, and same-database stock/journal/evidence transaction; Counter Cash, Field Cash-in-Transit/person journal, and UPI Clearing; idempotent replay; injected journal failure rolling back the sale, stock and evidence status.
- **GitHub Actions [39252955902](https://github.com/dvndrthakur64742-cpu/excel-herbal-erp-v7/actions/runs/39252955902): SUCCESS on commit `dea72b45feaf09ab267f88acabbb0eb7f2275571`**. Added ten real MariaDB two-connection lock-contention tests (original 20 → **30/30 PASS**) for sale-intent row locks, in-flight idempotency-key uniqueness, fail-closed rollback, successful retry after release and no duplicate stock/GL. These are controlled lock-timeout tests **not multi-worker load/stress tests**.
- Existing PHP unit suites also succeeded on both PHP versions, but the 30 real-service checks are **not** a real WordPress bootstrap, independently authenticated payment provider, production-ready GST invoice, concurrent-writer test, Flutter app/device UAT, or live operation. The new test manually constructs tender proof **only as a synthetic UAT fixture**.
- Windows self-hosted PHP check still fails; its optional runner is separate from the successful hosted PHP+MariaDB run.
- These weights are **engineering estimates** reflecting one verified canonical vertical slice and restored CI, not a measured percentage of all application screens or business transactions. The older historical figures **192/192** and **15%** described early foundation only; neither is a latest test tally.
- Current work stays on unmerged development PR #25; no production database, WordPress plugin or live deployment changes.

## Next acceptance milestone

Trusted company/branch/role-checked checkout → server-priced immutable retailer quote → matching verified Cash/UPI evidence → canonical stock-custody and GL transaction under ONE InnoDB transaction → receipt and reversal handling → full reporting reconciliation and UAT. **No live deployment without separate approval.**
