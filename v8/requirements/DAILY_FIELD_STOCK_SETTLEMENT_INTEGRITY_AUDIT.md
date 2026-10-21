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

## Phase 2 — Canonical GL line amount reconciliation

The same read-only finance-only audit now loads the actual V7
`journal_lines` and scoped `accounts` for the sole posted
`daily_cycle` journal. It requires at most 20 rows and checks:

- The full posted header is linked to the requested company, branch and
  cycle. All journal line IDs and account IDs must be unique, valid and
  belong to that canonical journal and **same company**.
- Cash account (`asset/cash`) **debit** matches reported evening Cash;
  UPI account (`asset/upi`) **debit** matches reported evening UPI.
- `SALES` **credit** matches evening expected sales, and
  `COGS` debit equals `INVENTORY` credit. Repeated or
  unknown account roles, wrong direction, missing journal lines, unbalanced
  debits/credits and tampered amounts block the cycle.
- Amounts are parsed strictly to **integer paise**. A 1-rupee mutation
  fails. Actual PDO/MariaDB tests use savepoints for ledger tampering and
  ultimately roll back all synthetic rows.
- Report fields `canonical_gl_line_totals_match`,
  `canonical_gl_totals_paise`, and `journal_line_count` describe
  *internal accounting reconciliation only*. They are **NOT** proof of
  employee-to-cashier physical remittance, real UPI bank settlement, tax
  compliance, or finance approval.

**Limitations unchanged:** no cross-query MVCC consistent snapshot; source
reads must not be described as an atomic view under concurrent writers.
V7 final-post may have legacy Cash/UPI policy gaps; the audit detects
inconsistency, never changes policy or posts/repairs books. The Office
WordPress deployment remains paused by the owner. No new route or database
migration is included.
