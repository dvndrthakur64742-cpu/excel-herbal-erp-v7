# Employee 360 — canonical V7 read-only REST integration (development only)

## Agreed purpose
A single employee profile joins monthly sales, performance incentive points, attendance, employee-custodied stock and eligible person-wise journal entries. It uses EXISTING V7 tables; it does not create a second sales or accounting book. The employee **dashboard** remains restricted to own sales and points and is not changed by this work. GPS remains the existing authorized route/point endpoint; automatic duty GPS must remain 10:30–17:00 without employee start/stop.

## Wired V7 API endpoint (when this development branch is installed in a test site)

`GET /wp-json/excel-herbal-erp/v7/organization/employees/{id}/360?from=YYYY-MM-DD&to=YYYY-MM-DD`

- Authenticated ERP actor required. Dates default to current business month when omitted; maximum 366 days.
- Self-profile is allowed for the current employee ID, and permits historical records after branch transfer. It NEVER reads another employee's records.
- Viewing other employees requires `organization.employee.view`, the V7 reporting hierarchy scope, and target employee's assigned branch authority. Manager's historical aggregation only covers their authorized branches.
- Tagged accounting journal details are returned **only** if actor has `finance.accounting.view`. No ledger SQL is executed without that capability.
- Source tables: `eh7_employees`, `eh7_daily_cycles` joined to `eh7_evening_settlements` (BOTH completed/posted), `eh7_performance_entries` (points kept separate from sales), `eh7_attendance`, `eh7_stock_balances` joined to `eh7_products` (employee custody), `eh7_journal_lines` joined to `eh7_journal_entries`/`eh7_accounts` (`party_type='employee'`, posted only).
- The visible journal is **tagged journal entries only**. It cannot yet be represented as a complete Tally person ledger: old journal entries may be missing employee party tagging. Employee cash remittance/outstanding is explicitly `not_available_in_canonical_v7_employee_ledger`, not invented or shown as zero.
- Response deliberately excludes stock purchase cost, employee payroll amount, raw GPS coordinates, and salary-fund allocation. The separate GPS route API keeps its existing permissions. No prices are added to the **employee dashboard**.
- All DB access is read-only and prepared with explicit company/employee/branch restrictions. No schema change, activation hook, new permissions, mutation endpoints, migration or production deployment.

## Verification / release blockers

Development regression: `php -d zend.assertions=1 -d assert.exception=1 backend/excel-herbal-erp-v7/tests/employee360_regression.php` (37/37 locally).

Before UI release: run V7 WordPress integration UAT on a disposable authorized test site, verify branch transfers, multi-branch manager visibility, datetime/timezone, percent escaping in MySQL DATE_FORMAT with WordPress `wpdb::prepare`, production-scale query performance, cash transit attribution, complete person ledger with source-level links and granular finance permissions. Verify the existing employee dashboard price-hiding rule separately. No deployment permitted from this change.

## 2026-10-21 — consolidated read-only Employee 360 correctness batch

The Employee Profile monthly sales/points projections now reject duplicated
source months, impossible or out-of-request months, or malformed fixed-point
money/point figures rather than silently replacing a value. Points reversals
may be signed; posted sales totals are nonnegative and stay separate from
incentives and tagged GL. Profile attendance source rows must have unique,
real, in-period business dates so duplicates do not inflate days-present.

Profile attendance, stock and finance-visible tagged GL rows now retain
canonical branch provenance and are checked against the actor's effective
manager branch authority in addition to query-level guards. The detailed
sales, requests, stock and daily reconciliation registers similarly reject
out-of-branch source rows and invalid or out-of-period business dates.

Person Ledger additionally rejects duplicate event IDs within a page,
negative posted GL debit/credit movement, negative period stock IN/OUT and
overfull source pagination. Signed historical opening stock is still valid.

The source is strictly read-only, built from V7 canonical records. Monthly
profile fields come from separately issued queries and do not constitute a
transactional snapshot of Sales, Attendance, Stock or GL. The response makes
snapshot_atomic=false explicit. Tagged GL and Daily Order totals do NOT
establish independent physical Cash handover or bank-verified UPI settlement.
All prior employee dashboard price restrictions remain unchanged.

Release gates: existing PHP 8.3, PHP 8.4, GitHub-hosted Windows and isolated
MariaDB checks, additional negative source tests, no migration or live deploy.
Production workflow, physical device verification and merge still require
separate explicit review and approval.

