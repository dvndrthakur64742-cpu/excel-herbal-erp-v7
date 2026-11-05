# ERP V7 — Refund Evidence Intake & Manual Verification (Development Slice 2)

**Date:** 2026-11-02. **Scope:** Development branch, synthetic MariaDB CI. Not deployed on Windows persistent localhost or the live company ERP.

## What this slice implements

After a prepaid invoice's **full return** is independently requested, physically inspected and approved as `refund_pending`, the ERP can register one **supporting document/reference per original confirmed tender**, and a different authorized reviewer can manually review it. This is a documentation and control workflow; it **does not transfer money, issue a credit note, or restock products**.

- `eh7_prepaid_refund_evidence` is a new versioned, additive table with unique `(company_id, order_payment_id)`, `(company_id, evidence_reference)` and `(company_id, verification_reference)`.
- Every record belongs to the original return, company, branch and **confirmed** original Cash/UPI payment. The amount must match that payment **exactly**; no arbitrary refund amount or cross-order refund evidence is accepted. Split Cash + UPI orders therefore need two independently traced records.
- Evidence is initially `evidence_submitted` and can transition once to `evidence_verified`. The verifier cannot be the evidence submitter.
- Cash review requires `finance.reversal.approve`. Manual UPI review requires `finance.bank_reconcile`, a bank/UPI account and a separately recorded verification reference. **This is not a live bank API check and is not proof that a bank has actually sent/received funds.**
- Company/branch access checks are enforced for lists, registration and verification. Invalid amount, duplicate payment evidence, reused references, missing verification, wrong role and wrong branch fail closed.
- All post-review return states remain **`refund_pending`**, even if every evidence row is manually verified. Original `prepaid_sales_orders`, `counter_sales`, original payment statuses, balances, stock ledger and journals do not change.
- Existing `FinanceReversalService` guard preventing generic reversal of a linked prepaid invoice remains in force.

## REST API (Bearer authentication, `X-Idempotency-Key` for writes)

| Method | Route | Input | Output |
| --- | --- | --- | --- |
| GET | `/sales/returns/{id}/refund-evidence` | Return ID | Branch-scoped list |
| POST | `/sales/returns/{id}/refund-evidence` | `original_payment_id`, exact `amount`, `evidence_reference` | `evidence_submitted`, `refund_disbursed=false` |
| POST | `/sales/refund-evidence/{id}/verify` | `verification_reference` | `evidence_verified`, `manual_evidence_only=true`, `refund_disbursed=false` |

Schema version: `7.3.12-prepaid-refund-evidence-1`. API contract version: `7.3.12-contract-refund-evidence-1`. Published contract has **242 routes**. Feature flag `prepaid_manual_refund_evidence_v1=true`; `prepaid_refund_disbursement_v1=false` and `prepaid_credit_note_posting_v1=false`.

## MariaDB regression coverage

`tests/integration_prepaid_sales.php` exercises:
1. Two original confirmed tender lines, one Cash and one previously independently verified synthetic UPI.
2. Reject wrong amount, nonexistent original payment, cross-branch evidence registration and duplicate record for the same original payment.
3. Record only supporting Cash and UPI references; prevent the submitter from verifying their own Cash evidence.
4. Accept independent Cash reviewer; reject UPI review by Cash-only role and require appropriate evidence-reference length.
5. Accept separate Finance/BANK_RECONCILE reviewer for UPI, reject double verification.
6. Confirm return stays `refund_pending` and the original paid order, payment evidence, warehouse, stock ledger and journals remain unchanged.
7. Preserve existing unconditional generic reversal guard for the paid prepaid invoice.

Confirm the **latest SHA's** CI run is green before treating this slice as verified.

## Mandatory next slice before any real refund

Design and test **verified actual payout + credit note + stock disposition + atomic accounting**, including full/partial-return rules, original tender splits, GST/tax adjustments, refund bank reconciliation, customer receipt, stock quarantine/release, maker-checker permissions, refunds after closed accounting periods, immutable numbers, race/idempotency, and rollback. Do not mistake `evidence_verified` for money paid.

**Safety:** D: local installation remains pinned to verified old source `2e40eba`. No Git pull, local DB migration, real payment, or live deployment was performed in this slice. Railway paid plan not required.
