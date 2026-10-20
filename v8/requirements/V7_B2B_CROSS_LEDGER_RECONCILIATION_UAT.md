# Excel Herbal V8 — Canonical V7 B2B Cross-Ledger Reconciliation Gate

**Development UAT only**, using existing V7 stock/GL and V8 signed tender
staging on **one disposable MariaDB `v8_test`**. No new production route,
migration, payroll account, payment-provider integration or journal writer.

## Independent read-only verification

`V7B2BCrossLedgerAuditUat::inspect($authorizedAccountingActor,$branch,$saleId)`
requires authenticated canonical V7 `ACCOUNTING_VIEW` plus effective
company/branch scope. It repeats the exact writer's development-only
environment and database guard. It loads persisted rows afresh; it does **not**
accept expected invoice amounts, balances, Cash/UPI verification claims, or
journal lines from the mobile UI.

It checks one posted retailer sale end-to-end:

1. Exactly one posted source with retailer outstanding = zero and consistent
   field/warehouse custody selection.
2. Canonical V7 sale product lines, integer quantity and paise arithmetic,
   price multiplication, COGS sum and exact sale/header totals.
3. Exactly one matching V7 StockService OUT ledger row per sale product/batch
   and exact custodian; no unaccounted or duplicated stock.
4. Independent V8 immutable sale/payment intents, consumed tender reservation,
   original consumed tender/evidence, independently verified tender identity
   and single-use canonical tender bound to the posted source.
5. Exactly four V7 posted accounting lines with exact expected account codes:
   Dr Cash / UPI Clearing / Employee Cash-in-Transit; Cr SALES; Dr COGS;
   Cr INVENTORY. Amounts must equal locked sale and product COGS, Dr = Cr.
6. Field Cash alone may have employee cash custody outstanding.
   `pending_cashier_handover` is an honest expected intermediate state, **not**
   a claim that a branch cashier physically received Cash.
7. When Cash handover exists, an independent exact cashier receipt is
   consumed by one remittance, with one additional canonical two-line
   Dr BRANCH_CASH / Cr EMPLOYEE_CASH_IN_TRANSIT journal tagged to that employee.
8. Counter Cash and UPI must have no employee cash-remittance posting.

Mismatch responses carry explicit `mismatch_codes` and
`cross_ledger_consistent=false`. They do not repair/ignore accounting
errors, adjust stock or mark balances reconciled by implication.

## Evidence limitations

This service verifies **integrity of the records in disposable UAT only**.
It cannot prove actual notes physically handed to a cashier, an actual
external UPI bank settlement in production, compliant GST/HSN invoicing,
refunds, reversal policy, or mobile device payment verification.
Return flags for live cash/bank verification, statutory approval and
production posting are **always false** even on green local UAT rows.

## Test contract

Real MariaDB `v8_test` inserts and posts an actual canonical counter Cash
sale, field Cash sale plus independent cashier handover, and UPI sale.
Read-only audit must accept consistent source/stock/GL records, separately
show pending field Cash before handover, then reconcile full handover and
detect malicious edits to sale-line arithmetic, stock OUT quantity,
canonical journal values, cashier receipt amount and UPI tender source.
Each injected corruption is rolled back immediately. Incorrect
accounting-role and cross-company attempts are denied.

**Release gate:** No production deployment, PR merge or B2B WordPress REST
writer exposure without explicit approved GST/refund/payment policy,
independent source evidence, staging end-to-end acceptance and owner signoff.
