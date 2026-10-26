# ERP V8 Phase 1 — Field-Day End-to-End Acceptance Gates
Date: 2026-10-26
Development branch: codex/erp-v8-foundation-20261017
Scope: Employee stock request → ASM/ASAM approval → issue → evening retail/wholesale return → finance final-post → Employee 360 source reconciliation.

## Verified by automated synthetic disposable MariaDB UAT (not live Office)

The existing canonical V7 `backend/excel-herbal-erp-v7/tests/integration_uat_smoke.php` already exercises the real `ApiDispatch`, real MariaDB tables and original business services. Phase 1 makes this **full suite a required V8 GitHub CI gate** in `.github/workflows/v8-foundation-ci.yml`, instead of relying only on mock/read-only audit tests.

Additional fail-closed assertions now cover **both additional-stock states**, before and after ASM approval:
- Employee's submitted Additional Request blocks Evening Closing with `additional_request_pending` (HTTP 409).
- ASM-approved Additional Request that has not yet been issued also blocks Evening Closing.
- Rejected or cancelled Additional Request releases the block; exactly one original Closing may start.
- For each denied attempt, actual MariaDB status remains `issued`; no new `evening_settlements`, `daily_sale`/`daily_return` stock movements or `daily_cycle` journal entries are written.

Inherited UAT already covers: out-of-hierarchy operations, no self approval, stock preflight and allocation integrity, duplicate issue prevention, wholesale pricing and return maths, stale-save rejection, independent maker-checker Final Post, deliberate Cash+UPI mismatch rollback, one GL journal, no double post, stock warehouse/employee custody quantities, sale/point/salary-fund sources and authorised Employee 360 registers. These are exercised in a **temporary CI MariaDB service with synthetic data**, never the Office database.

## Real user acceptance — not yet passed

| Gate | Acceptance criterion | Status |
|---|---|---|
| FE stock request | Employee can request stock for permitted branch/day only; whole PCS and exact products | HUMAN UAT PENDING |
| ASM/ASAM approval | Right reporting hierarchy, separate approver, rejection reason, no cross-branch write | HUMAN UAT PENDING |
| Custody movement | Warehouse OUT and employee IN match issue lines with batch and day | HUMAN UAT PENDING |
| Additional Stock | Pending request blocks closing; approval and second issue work as shown in UI | HUMAN UAT PENDING |
| Evening closing | Issued = Return + Retail Sold + Wholesale Sold per batch, prices/discount validated | HUMAN UAT PENDING |
| Finance posting | Authorised checker, Cash+UPI sum and journal/stock/performance source totals | HUMAN UAT PENDING |
| Cash proof | Physical employee→cashier signed receipt from independent verifier | NOT VERIFIED |
| UPI proof | Independent bank/PSP matched settlement, not just employee-entered amount | NOT VERIFIED |
| Employee 360 | Original historical orders, points, stock, ledger, role scopes and denied cases | HUMAN UAT PENDING |
| Deployment | Exact build on isolated/sanitized staging, rollback tested, multi-device screenshots | NOT READY |

## Release and safety boundaries

- **Office currently runs read-only V8 web preview** from `54b791a327ceccabce9008916fb41b077a89de4f`, backend `95a9e2806edef95257cd6b6aee6f1d56ca632d6b`. A newer development CI pass does not install new frontend.
- Source database on Office is not sanitized and active mobile sessions are present; never run destructive/mutating e2e transactions against Office.
- The new GitHub job uses only the disposable MariaDB container. The test seeds synthetic data and never connects to staging or production.
- Cash/UPI recorded in existing canonical financial journal is **reported/tally evidence**, not actual physical handover or bank verification. Full financial release stays blocked.
- Any test failure holds Phase 1 `CI_VERIFIED` status until repaired and green on the exact PR head. Never infer overall ERP percent from CI pass.

## 2026-10-26 — UI fail-closed request targeting and actor separation

- Root cause: the pre-existing Daily Order UI could select the first request matching only a `submitted` or `approved` status, irrespective of initial/additional request type, cycle stage or actor identity; reject/cancel used an independent `candidates.last` heuristic. REST still had canonical effective-role and state checks, but an ambiguous UI request could be sent to the wrong endpoint.
- New pure `DailyOrderActionTarget.select` resolves only **one** matching request, requiring a positive cycle/request ID, correct parent cycle, expected initial/additional type and lifecycle state, appropriate approval/issue capability, and a known distinct requester/checker for approve/issue/reject. Invalid or duplicate entries fail closed.
- `my_work_daily_order.dart` now re-fetches detail before approve, reject, cancel-additional and issue, then uses this selector. The canonical `dailyApprove`, `dailyReject`, `dailyCancelAdditional`, and `dailyIssuePreflight`/stock issue endpoints remain the sole writers and separately recheck actual database state.
- Negative test matrix includes old cancelled additional request, mismatched cycle, duplicate pending targets, self-approval/issue, missing actor/requester IDs, unpermitted roles and wrong lifecycle action. Pure Dart tests cannot establish live WordPress/field-role acceptance; keep user-facing UAT and financial release gates open.

## 2026-10-26 — Independent Finance Checker negative-role UAT gate

The original mixed Cash/UPI canonical Daily Order case now checks **three additional real SQL denial scenarios before legitimate Final Post**:
1. A same-branch manager identity with `daily_order.approve` but **without** `daily_order.review` attempts financial Final Post.
2. A reviewer with `daily_order.review` limited to **another branch** attempts to final-post this branch's settlement.
3. A synthetic ASM reviewer with the permission but **outside the employee's reporting hierarchy** attempts to post.

For each test, the original `daily.final_post` API must deny with HTTP 403. MariaDB before/after snapshots must be identical for the original Daily Order state, submitted Evening Settlement, Daily Sale/Return stock-issue postings, source financial journal, employee performance entries and Final Post audit event. The authorised separate Finance Checker must still post exactly once and retain balanced journal totals.

Scope: synthetic data on isolated CI MariaDB. Real Office staging remains unsanitized; no role simulation or financial mutation is authorized there. **A green synthetic UAT is not a verified Cashier handover receipt, external bank proof, or live role/device sign-off**.

## 2026-10-26 — Fail-closed Final Post for non-finite amounts

- Observed in canonical `DailyOrderService::finalPost`: the existing `$cash < 0` and `$upi < 0` checks are not sufficient for PHP `NAN` because comparisons are false. Route adapters cast incoming amounts to floats and the service may also be called internally. An invalid number must never reach StockService or AccountingService.
- Original Final Post now explicitly rejects `!is_finite($cash)`, `!is_finite($upi)` or negative tender amounts as `payment_amount_invalid` HTTP 422 **before** stock/GL/performance writes. Canonical business amounts, accounting service, maker/checker, bank-proof semantics and other workflows remain unchanged.
- Real disposable MariaDB UAT tests cash/UPI mismatch, negative tender, `NAN` on each component, plus positive and negative `INF`. For every rejection, before/after snapshots of cycle, settlement, source stock ledger, journal entries, performance and Final Post audit count must be identical. Then the legitimate ₹200 reported cash + ₹160 reported UPI final post and double-post denial must still pass.
- This provides synthetic service-level financial safety evidence only. It does **not** prove physical cash custody, independent UPI bank settlement or Office acceptance. No Office deployment or staging data mutation is authorized.


## 2026-10-26 — Purchase and Supplier Payment finite-amount safety

- Existing PurchaseService supplier Bill and Payment flows accepted PHP NAN and INF as float arguments without explicit finite checks. Such values can bypass numerical comparisons and risk invalid stock valuation, supplier AP or GL posting. PurchaseService::bill now rejects non-finite/negative quantity or cost before batch creation, and rejects non-finite calculated line and grand totals before the purchase transaction. PurchaseService::payment rejects non-finite, negative, zero, or sub-cent amounts that round to zero. These guard failures return 422 validation codes.
- Disposable real MariaDB UAT now submits 7 invalid supplier bills (NAN, positive/negative INF in quantity/cost, and finite operands whose line total overflows), requiring identical before/after counts of purchase headers, lines, purchase stock ledger, journal, audit and stock balances.
- One valid supplier purchase of 2 PCS × INR 40 = INR 80 must produce one bill, an IN stock movement, and an AP journal. Six invalid supplier payments (NAN, positive/negative INF, negative, zero and rounds-to-zero) must preserve the bill outstanding, payment history, AP journal, stock and audit. One valid INR 30 supplier payment must leave INR 50 outstanding and a single posted payment journal and audit event.
- Original canonical supplier payable, warehouse stock and accounting services remain the only financial writers, without any parallel ledger. Synthetic CI evidence does NOT certify real Office suppliers, independent bank settlement, live UAT, or production readiness.

## 2026-10-26 — Inventory Transfer / Stock Adjustment / Quarantine finite-input guard

- Canonical InventoryService had no explicit finite numeric guard on transfer-create quantity, transfer received quantity, stock-adjustment delta/optional positive-adjustment cost, or quarantine hold quantity. PHP NAN can defeat regular positive/negative comparisons and INF can contaminate stock balances and valuations. Validation is now explicit before canonical business mutations; new errors return HTTP 422.
- Disposable synthetic MariaDB: test NAN, +INF and -INF for transfer creation; reject before any transfer header/line, stock ledger, journal or audit persists. Use a legitimate 5 PCS transfer to reach in-transit state, reject three non-finite receipts with unchanged status/destination stock/SQL counts, then complete normal receipt and verify branch stock deltas.
- Disposable synthetic MariaDB: test non-finite positive/negative stock-adjustment deltas and explicit adjustment unit costs (6 cases) and non-finite quarantine hold quantities (3 cases). Reject attempts with unchanged adjustments, lines, quarantine records, stock balances/movements, journals and audit counts.
- No parallel finance ledger, no table migrations, no bank or physical inventory acceptance assertions. Office staging remains UNSANITIZED: no live mutation or backend deployment was authorized. Human role-wise UAT, independent cash/UPI verification, and production sign-off remain pending.

## 2026-10-26 — Inter-branch transfer shortage checker, role and accounting gate

- New rule in the **canonical InventoryService::transferAction approve-correction**: checker must possess ADJ_APPROVE plus **effective authority for BOTH source and destination branches**, and may not be the transfer's creator. An authorized source-only actor can no longer approve a shortage in an unassigned destination branch. This guard is confined to the correction action; original transfer stock and GL writers remain unchanged.
- New real disposable MariaDB UAT creates and dispatches 4 PCS, receives 3 PCS at the destination and enters difference_reported, then denies source-only, destination-only, missing-capability, maker self-approval and short-note corrections. Each denial must preserve transfer status, received quantity, warehouse custody, stock ledger, transfer journal and audit counts.
- A distinct authorized checker then resolves exactly 1 PCS shortage: verifies the variance journal equals the captured per-unit dispatch cost, source/destination stock does not move during accounting-only correction, inter-branch clearing account has zero net debit after dispatch + receive + variance, and a duplicate correction cannot create a second journal or audit event.
- This is synthetically verified only if the exact-head required V8 CI passes. Real physical shortage documents, branch checker sign-off and controlled restore remain **UNVERIFIED**. No Office backend or DB writes.
