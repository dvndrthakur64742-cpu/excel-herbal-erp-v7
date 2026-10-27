# ERP V8 — Partial Purchase Returns / Supplier Credit Notes: Policy and Acceptance Contract

**Date:** 2026-10-26  
**Scope:** Future standalone **partial** supplier return and credit-note feature. This document is **proposed requirements**, not authorization to post stock, GST, or AP credits. Current V7 service has purchase bills, supplier payments, and **full-bill controlled finance reversal** only. No production return-posting API, return table or supplier credit-note journal is added in this batch.

## Non-negotiable separation

| Operation | Existing canonical behavior | V8 acceptance |
|---|---|---|
| Purchase Bill | Posted purchase increases warehouse inventory and AP | Existing implemented |
| Supplier Payment | Reduces posted bill AP; no supplier advances | Existing implemented |
| Whole-Bill Reversal | Separate reversal maker/checker; reverse payment dependencies first, then entire bill and stock when all quantity available | Extended synthetic regression this batch |
| **Partial Purchase Return** | **No canonical return line ledger / credit-note service** | **NOT IMPLEMENTED; specification awaiting owner policy** |
| Physical Stock Adjustment | Inventory variance action; not supplier credit, not GST credit note | Must **never** be used as a substitute for Purchase Return |

## Proposed future lifecycle (not active)

1. Initiate return request linked to a **single original Purchase Bill**, supplier, branch, product line, batch, expiry and original cost/tax snapshots. Attach reason and supporting images/documents.
2. Validate current quantity in warehouse, original purchased quantity, cumulative previously returned quantity and credits. Never return more than purchased or in custody. Serialise updates using row locks/idempotency.
3. Independent purchaser/manager checker approves or rejects, with original maker excluded. Check both branch and tenant boundaries and open accounting period.
4. Stock dispatch to supplier may be a **separate custody event** from credit-note acceptance. No GL/AP credit before approved supplier evidence unless the owner explicitly chooses the alternate accrual policy.
5. Match supplier credit note number, date, original bill and GST/HSN/tax details, if applicable. Credit AP or record supplier receivable/refund only under approved finance policy; cash refund and adjustments to previously paid amounts are **not automatic**.
6. Post balanced source-referenced journals through the original AccountingService; exactly-once audit with reversal support. Preserve original bill and payments for historical reporting, don't overwrite them as full reversal.
7. Show approved and pending return lines in Purchasing, Inventory and branch AP ageing; keep physical dispatch, supplier acceptance and settlement statuses separate.

## Owner decisions required before creating financial write endpoints

- **Tax/GST:** Whether and how GST/ITC, discounts, HSN and tax adjustments apply, and who verifies supplier-issued credit notes.
- **Return valuation:** Original purchase line cost (recommended candidate) vs other approved inventory valuation policy, including mixed batches and expired stock.
- **AP and refunds:** Apply against outstanding invoice, supplier credit balance or separate receivable when invoice already paid; cash/UPI bank verification controls.
- **Custody recognition:** At dispatch, at supplier receipt, or after supplier accepted credit note. Which events affect stock versus AP?
- **Permissions:** Maker/checker designation and whether two-stage stock dispatch and Finance credit-note approvals are required.
- **Time and documents:** Credit-note date, closed fiscal period, mandatory supplier acknowledgement, and duplicate-credit-note handling.

## Implementation gates for the future PR

- Schema/API changes introduced only **after** the above decisions. Use separate purchase_return header, lines, allocation and credit-note ledger references rather than a reused stock_adjustment or full reversal.
- MariaDB concurrent returns never exceed original purchased/current warehouse quantity; duplicate idempotency returns the same result and cannot create duplicate stock/GL/audit.
- Denied actions (bad branch, no permission, own approval, negative/non-finite quantity, invalid/duplicate credit note, closed period, batch mismatch, no stock, incomplete approval) have zero stock/AP/GL side effects.
- Valid return verifies source bill balance, matched supplier credit note and journal arithmetic under the approved GST model. Recovery and reversal tests cover failed external supplier confirmation.
- Real human Purchasing/Stores/Finance UAT, approved document evidence and physical stock verification on isolated **sanitized** staging required before any Office release.

## Current batch — existing full-bill cancellation controls, not a partial return

Exact code: `FinanceReversalService::reversePurchaseStock`. It now blocks when either cached paid_amount is positive **or a posted supplier_payments record remains**, including synthetic inconsistency where the cached paid amount was incorrectly zeroed. The bill's paid and outstanding columns must reconcile with its original total before full reversal. The isolated UAT also checks maker/checker, branch denial, bank/cash payment reversal before bill reversal, actual availability of all purchased PCS, GL rollback, successful full stock/AP reversal and duplicate suppression.

**Safety:** Staging Office currently contains unsanitized operational records and active sessions. No live accounting writes, schema migrations, production releases, or Office backend deployment are authorized by this design/test-only change.
