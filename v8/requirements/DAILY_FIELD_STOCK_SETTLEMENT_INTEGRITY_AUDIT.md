# Excel Herbal V8 — Daily Orders Field Stock / Evening Settlement Integrity Audit

## Goal

Continue from the **canonical V7** workflow; do not build another Sales/Stock
posting engine. Existing `DailyOrderService` already has:
- Employee morning stock request, ASM/ASAM approval and segregated issue.
- Canonical V7 warehouse OUT plus employee custody IN ledger postings.
- Evening retail/wholesale sales and warehouse returns.
- Final-post employee custody OUT, cash/UPI **reported** payment split,
  one canonical V7 GL journal header and one employee performance entry.

The new `DailyFieldStockAudit::inspect` is an **independent READ-ONLY
finance-only integrity diagnostic**, not another posting service, new
database table, public REST route, or migration.

## Checks

* Company comes strictly from authenticated `Actor`; the actor needs
  `finance.accounting.view` and **effective authority over the branch**.
* Every `daily_issue_line` must belong to an issued request for the cycle.
* The original issue must have warehouse **OUT** and employee **IN**,
  with exact per-product, per-batch, per-request quantity.
* Evening issued lines must each be closed **exactly once** with the same
  product/batch; `issued = return + retail + wholesale` at 0.001 precision.
* For a completed cycle, sold retail+wholesale must equal employee **OUT**
  in `stock_ledger` with `source_type=daily_sale`.
* Return must have employee **OUT** and warehouse **IN** with
  `source_type=daily_return` and **no double subtraction**.
* A completed cycle must have one posted canonical GL journal **header**
  and one employee-linked performance entry. Reported Cash + UPI must equal
  expected sales total. **Individual GL debit/credit lines are not audited
  by this milestone**, and no physical cashier or independent UPI bank
  proof is available from the legacy Daily Orders flow.
* Open cycles may have a reconciled issued-stock position, but must not
  be classified as posted sales or production-approved finance.
* Any foreign company/branch row, duplicate movement ID, duplicate issued
  line, unexpected source, missing issue, missing closing, incorrect
  status, unexpected posting, partial pagination (>250 issue/closing
  lines, >3000 movement rows), invalid decimal precision, or malformed
  source fails closed or yields explicit exceptions.
* No SQL writes, posting, reconciliation "repair", notifications,
  scheduled tasks, real cash acceptance or bank settlement occur.

## Verified evidence / limitations

- PHP 8.3/8.4 and Windows pure canonical-domain regression exercises
  duplicate movement, sale quantity mismatch, return discrepancy, batch and
  custodian scope, company/branch guards, missing GL/performance, open-cycle
  state, overflow and Cash/UPI amount mismatch.
- The **real disposable MariaDB** UAT creates the eight exact canonical
  schema tables (if absent), inserts fully synthetic Daily Order + stock +
  posted header/performance **inside a transaction**, tampers actual SQL
  data using savepoints and ultimately **rolls back everything**.
- The read-only audit currently executes separate queries, **without an
  MVCC snapshot**, and cannot certify consistent concurrent postings.
  Future production-readiness requires a reviewed snapshot protocol, full
  GL line reconciliation, verified employee-to-cashier remittance,
  independently proven UPI settlement, and mobile/branch UAT.

**No WordPress REST exposure. No backend deployment. No B2B posting.
No PR merge. Office preview deployment is paused separately.**
