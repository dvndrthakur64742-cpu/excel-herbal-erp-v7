# Excel Herbal ERP V8 — Branch Weekly / Monthly Control (UAT read-only)

**Delivery:** a single consolidated feature, wired into existing V7 REST and
Flutter Reports pages. No new stock, GL, Cash, salary, sales or points table.

## Manager workflow

In **Reports → Branch Weekly Performance** or **Branch Monthly Performance**,
pick an authorized branch and any business date. The service resolves an ISO
Monday–Sunday week or the full calendar month containing that date, plus the
previous full week/month for a branch-over-time comparison.

GET `/reports/branch-period?branch_id=...&mode=week|month&date=YYYY-MM-DD`

Visible per employee: original posted Daily Order sale totals, cash/UPI
allocations (not verified), actual issued/sold/returned PCS, employee-custody
IN/OUT PCS, performance points, days posted, pending closing days, pending
stock requests, stock/amount mismatch alerts. Posted Counter Sales are
separate from employee Daily Orders and not double counted.

**Manager without finance.accounting.view** receives no GL Cash liability.
Finance-capable actors additionally see posted, employee-tagged, branch-scoped
Cash-in-Transit GL opening Dr-minus-Cr, period debit, credit, closing, from
canonical V7 journal_lines/journal_entries/accounts. Do NOT describe this
as an independently confirmed cashier handover, Cash deposit, Cash balance
physically counted, or bank reconciliation. Negative opening GL can reflect
historical corrections. This projection is not a complete company GL trial
balance or a physical stock count.

## Implementation constraints

* Branch access is checked using existing REPORTS_VIEW + authenticated branch
  BEFORE any source query; company and branch scoped in ALL V7 SQL streams.
* Separate SQL grouped requests/issue-lines/closing-lines, employee stock,
  performance, Counter Sales and optionally finance GL. NO 31-day N+1 loop.
* Financial amounts fixed-point 2 decimals; PCS fixed-point 3; points signed
  performance units (not INR); overflow and invalid precision fail closed.
* Unposted Daily Orders have zero sale amount but retain issued inventory
  and pending stock approval/closing counts. Multi-batch lines pre-aggregate.
* Week/month previous period is a full calendar comparator; a current partial
  week/month is **not** working-day-normalized to compare against a complete
  prior period. Avoid suggesting the sales delta is like-for-like pacing.
* Cash/UPI still require independent provider/cashier corroboration, no
  automatic physical or GL proof in the non-finance report.
* Optional retailer B2B UAT preview sales are excluded until a canonical
  V7 production source is signed off.
* A bounded complete read fails closed rather than truncating totals,
  and there is no report endpoint that mutates accounting or inventory.

## Release gate

PHP 8.3/8.4 and Windows unit tests (week/month/Jan year rollover,
authorities, negative points, exact-decimal mismatch, finance privacy,
previous period). Disposable MariaDB integration using original V7
cycles, issue/closing lines, stock, counter sales, journal and points;
Flutter compile and UI contract test. Live WordPress and physical-device UAT
are independent blockers. **No production deployment or PR merge.**
