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

## 2026-10-21 — Cross-source Closing Line and Performance Totals Audit

The read-only finance-only Daily Field Stock Audit now compares individual
canonical closing-line sales INR, points and salary-fund amounts against
the posted settlement and its source-linked employee performance record.
Values are parsed into exact paise or separate hundredths of incentive
points, and never added to one another.

For each completed Daily Order:
- Sum of closing-line total_amount must equal evening expected_amount.
- Sum of closing-line points must equal posted performance_entries.points.
- Sum of closing-line salary_fund must equal posted performance_entries.salary_fund.
- Existing reported Cash/UPI, GL debit/credit, issue/sale/return stock
  movement and employee/branch authority tests remain independent.
- Fail closed on malformed, negative or non-two-decimal financial amounts.
- Expose the source subtotals and distinct reconciliation booleans, while
  always maintaining the financial signoff and physical proof warnings.

PHP regression and real disposable MariaDB UAT tamper each dimension with a
one-paisa/one-hundredth source difference, then restore the fixture using
savepoints. No new accounting or payroll writer, duplicate stock/GL engine,
schema change, outward-facing API route, deployment or production mutation.

A matching performance entry is NOT proof of actual payroll disbursement,
and a matching Cash/UPI journal is NOT proof of cashier handover or bank
settlement. Source readers remain non-atomic separate queries.


## 2026-10-23 — Business-flow Employee 360 end-to-end acceptance gate

The disposable **real MariaDB `integration_uat_smoke.php`** already
posts a full employee-day business cycle: employee requests 5 units;
ASM/manager approves and issues; evening returns 1, sells retail 2 and
wholesale 2; finance checker posts **INR 200 Cash + INR 160 UPI**;
canonical warehouse/employee custody, Stock Register, 8 performance points
and INR 20 salary fund are verified. A new *subsequent* case checks that
this **same original posted cycle** appears consistently in the
employee's own authorized Employee 360 monthly summary, ASM-issued
stock request register, sale register, 10-part quantity/amount
reconciliation, finance-authorized Cash Control and the person-wise
source-linked Tally-style ledger timeline. The case checks the
ledger balance source disclosure and that independent physical Cash and
UPI bank proofs remain false, and asserts all these reads do not
write additional GL, stock or performance records.

The negative role gate is checked against the real ApiDispatch: the field
employee has Daily Order self permissions, but no finance permission and
MUST NOT read Cash Control or the finance-only Person Ledger. This is
a disposable/synthetic test environment only. It does NOT introduce
a new payment posting, field Cash acceptance, cross-source Daily/B2B
deduplication, or production migration. Stock timestamps follow the
source UTC movement time, unlike the historical business day used in
this synthetic test; source-based reconciliation uses the cycle date.

A **PASS** demonstrates connected canonical READ/WRITE pathways on
disposable MariaDB, not actual physical deposits, payroll payouts,
mobile-device acceptance, or production launch approval.
