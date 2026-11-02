# Prepaid Return / Refund — Implementation Slice 1 (2026-11-02)

**Development only — NOT a working cash/UPI refund, credit-note posting, or production release.**

## Implemented

The `PrepaidReturnService` is an additive, fail-closed return-intake workflow for **complete prepaid invoices only**. It never posts stock, cash/bank, refund, tax, or accounting entries. Existing full-prepayment and generic-reversal safety rules remain in force.

State transitions:

```
Posted prepaid invoice (unchanged)
        |
        v
Return request (requested)
        | distinct inspector; physical-reference evidence
        v
Physically inspected (received)
        | third, independent approver
        +---- rejected
        |
        v
Refund approved but NOT disbursed (refund_pending)
```

The original invoice/paid order remain **posted** and the original payments remain **confirmed**. This is not a customer-credit note; stock is not automatically returned to saleable inventory after a physical check. It must remain physically quarantined/off-ledger pending an atomic settlement release.

## Controls and limitations

- Company and effective branch scope required on every operation.
- Requester requires `finance.reversal.create`; physical inspector and final approver require `finance.reversal.approve`; all readers require `sales.view`.
- Requester, inspector and approving employee must be **three different identities**. No approval before physical inspection.
- Order and sale must both be posted, fully prepaid and consistent; every payment must be confirmed, sum to the invoice total, and there must be stock lines.
- A unique index `(company_id, order_id)` prevents duplicate or concurrent return intake on the same invoice. **A rejected request also blocks subsequent requests** in this first fail-closed version; reopening/reissue needs a separately authorized procedure.
- Only a **complete invoice** return is representable; no partial return, exchange or tax credit treatment yet.
- `inspection_reference` records a physical check; it is **not bank confirmation or proof that the refund occurred**.
- No refund endpoint exists in this slice. `refund_pending` must not be presented to a customer as `refunded`. The generic `FinanceReversalService` still refuses direct reversal of linked prepaid sales with `prepaid_refund_workflow_required`.
- Schema migration adds only the `eh7_prepaid_return_requests` table. It does not delete/rename existing tables or reset credentials. Requires a backup, rollback plan and exact-source approval before any shared environment upgrade.

## API (authenticated Bearer + idempotency header on writes)

| Method | Route | Handler | Purpose |
| --- | --- | --- | --- |
| GET | `/sales/returns?branch_id=N` | `sales.return_list` | Branch-scoped returns queue |
| GET | `/sales/returns/{id}` | `sales.return_detail` | Return status |
| POST | `/sales/orders/{id}/return` with `reason` | `sales.return_request` | Begin full prepaid return |
| POST | `/sales/returns/{id}/inspect` with `inspection_reference`, optional `notes` | `sales.return_inspect` | Independently check physical goods |
| POST | `/sales/returns/{id}/decision` with `approve` boolean | `sales.return_decision` | Third-person decision, not disbursement |

Feature flags: `prepaid_return_intake_v1=true`, `prepaid_refund_disbursement_v1=false`, `prepaid_credit_note_posting_v1=false`. The contract version is `7.3.11-contract-return-intake-1` and schema version `7.3.11-prepaid-return-intake-1`.

## Synthetic MariaDB acceptance checks

`tests/integration_prepaid_sales.php` now includes a real MariaDB exercise with:
- missing/too-short return reason and unposted invoice rejection;
- unique return request, independent inspection and three-person approval;
- duplicate intake/review and cross-branch inspection denial;
- no stock-balance, stock-ledger, journal or collected-payment mutation at any stage;
- `refund_pending` status, never `refunded`.

Only mark these checks **passed** after the corresponding PHP/MariaDB GitHub CI run completes successfully. The earlier CI failures during implementation were fixed before this report; confirm the latest run SHA, not an earlier/queued run.

## Remaining design/implementation gates

1. Verified customer request and full/partial return lines with tax/GST handling and original price/cost snapshots.
2. Physical receipt quarantine, inspection disposition, batch/expiry controls and inventory acceptance posting.
3. Independent Cash/UPI refund evidence and bank reconciliation; handle multi-tender payments including split refunds.
4. Credit-note numbering, issued credit note document, statutory reporting and reversal of points/commissions/tax.
5. **One atomic transaction** for refund, stock custody, prepaid order/payment state, invoice and accounting journal; concurrency/idempotency and reversals.
6. Authenticated BM/HO REST and Flutter desktop/Android acceptance, migration rehearsal, backup-restore and live release approval.

No paid Railway plan is required for local source/CI work. The Windows localhost ERP remains pinned to the older verified `2e40eba` commit, untouched.
