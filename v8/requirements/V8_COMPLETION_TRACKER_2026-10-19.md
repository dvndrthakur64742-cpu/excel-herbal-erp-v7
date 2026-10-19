# Excel Herbal ERP V8 — engineering completion tracker

**Date:** 2026-10-19  | **Branch:** `codex/erp-v8-foundation-20261017` | **Production deployment:** NO

## Estimated whole-system progress: ~15% (±5 percentage points)

**This is a conservative weighted engineering estimate, not production readiness, not a percentage inferred from passing isolated tests, and not an audited sprint-velocity forecast.** Re-evaluate when a real vertical slice passes deployment-free UAT and its exact-head CI.

| Capability area | Project weight | Evidence-backed earned points | Remaining gate |
|---|---:|---:|---|
| BRD consolidation, legacy rule extraction and conflict register | 10 | 6 | Owner signoff on contested attendance, custody, pricing and tax policies |
| Retailer B2B pure-domain rules, custody and verified-tender contracts | 15 | 8 | Server checkout/payment/retailer pricing/reversal authorization |
| Canonical customer, stock and GL integration | 20 | 1 | One trusted canonical writer with real DB locks and end-to-end transaction |
| Purchase, stock, daily employee operations, branch close | 15 | 0 | Fully integrated and tested workflows under V8 UI/API |
| Employee 360°, HR, payroll and GPS | 15 | 0 | Required operational functions and real-device UAT |
| Secure role-based UI / Flutter and backend APIs | 10 | 0 | Backend-authorized actual API integration and usable screens |
| Ledgers, reports, finance reconciliation | 5 | 0 | Accurate posting, reversal and reconciliation across branches |
| Real CI, integration, concurrency, UAT and deployment rehearsal | 10 | 0 | GitHub Actions runners, disposable MariaDB tests and UAT pass |
| **TOTAL** | **100** | **15** | **~85 points remaining** |

## Verified versus unverified

- **192/192 local isolated domain/regression assertions passing**, split as 25+11+18+28+34+17+30+29 across eight suites; **27/27 PHP syntax checks passing**. No MariaDB/PDO MySQL driver installed in the current local container; optional MySQL integration tests are **not verified**.
- Code only under isolated `v8/` on a draft PR, not merged or deployed. Exact GitHub CI status must be rechecked after every commit; previous runs failed without runner execution steps.
- New v0.8 binding is a **reservation only**. It never claims stock posting, invoice creation, paid GL entry or actual employee remittance. `posting_allowed` remains **false**.
- This percentage explicitly does **not** count older V7/v14 modules as completed V8 features until integrated, revalidated and regression-tested.

## Next acceptance milestone

Trusted company/branch/role-checked checkout → server-priced immutable retailer quote → matching verified Cash/UPI evidence → canonical stock-custody and GL transaction under ONE InnoDB transaction → receipt and reversal handling → full reporting reconciliation and UAT. **No live deployment without separate approval.**
