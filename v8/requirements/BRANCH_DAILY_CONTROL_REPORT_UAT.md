# Excel Herbal ERP V8 — Branch Daily Control (read-only development batch)

New authenticated GET `/reports/branch-daily?branch_id={id}&date=YYYY-MM-DD`
uses V7's existing Actor/Guard::branch(REPORTS_VIEW), company scope and
business timezone. It is surfaced as **Reports → Branch Daily Control** in
Flutter with an explicit business-date picker and authorized branch selector.

## Canonical report sources — never duplicate sale, stock or GL tables

- V7 daily_cycles + evening_settlements: one Daily Order per employee/day;
  only completed cycles with posted evening settlements count as sales.
- V7 daily_requests + daily_issue_lines: pending manager stock requests
  and actual issued PCS. Multi-batch quantities pre-aggregated by cycle.
- V7 evening_lines: independently pre-aggregated sold and returned PCS and
  line-level sale amounts; prevents joins multiplying money/stock.
- V7 stock_ledger: actual employee custody IN/OUT, UTC business-day window,
  with branch warehouse (null custodian) explicitly excluded from totals.
- V7 performance_entries: employee points for the business day, distinct
  from monetary sales or salaries.
- V7 counter_sales: posted counter sales shown as a separate source with
  paid/outstanding amounts; never added to Daily Order employee totals.

The report includes employees with activity but no Daily Order, pending
approvals/issues, unposted cycles, quantity mismatches and posted amount
split mismatches. No fabricated status; a draft evening has **zero posted
sales** until it is posted.

## Explicit financial / operational limitations

- Cash and UPI are **posted Daily Order tender allocations**. They are
  not independently verified cashier handover, physical cash deposit,
  UPI bank settlement or bank reconciliation.
- Current branch stock balance, audited physical stock and GL cash
  reclassification are separate controls; they are not proven here.
- Optional retailer B2B UAT preview sales are not included until their
  canonical production schema/source is approved. No price/cost/salary
  distribution fields are returned in the employee rows.

Security and data integrity: server-side company/branch guard, a single
business date, explicit source branch validation, exact integer-scaled
INR/PCS/points arithmetic, overflow and malformed-source fail closed,
bounded complete reads (not silently truncated), and no shadow ledger.
The read-only report does not write or deploy a business transaction.

## Verification / release

PHP 8.3/8.4 and Windows permission, boundary, pending and arithmetic tests;
real disposable MariaDB `v8_test` verification with multi-batch issue,
posted Cash/UPI, draft employee, separately posted counter sale, points,
cross-company/branch denial; Flutter cloud UI contract and compilation.
Live WordPress/mobile UAT, production deployment and PR merge are
separate approval gates.
