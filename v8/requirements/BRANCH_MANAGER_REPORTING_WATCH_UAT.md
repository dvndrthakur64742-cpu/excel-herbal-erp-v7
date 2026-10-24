# Branch Manager Reporting Watch & Regional Exception Dashboard (Development UAT)

## Business schedule

The **Reports → Manager Reporting Watch** screen evaluates schedule obligations
for a selected business date in the WordPress business timezone (Asia/Kolkata
in the user acceptance test).

- Every evening **7:30 PM**: FSE Daily Order evening closing, independently
  corroborated by original V7 `daily_cycles` + `evening_settlements`.
- Every **Monday**: weekly branch report and Monday product order.
- Every **Tuesday**: Tuesday product order.
- Every **1st day of the month at 10:30 AM**: monthly branch report.
- **10th day of each month**: salary receipt report due by the date (no
  invented clock hour; treated as end-of-day).

**Critical evidence policy:** only an employee's Daily Order evening status
is machine-verifiable from the existing V7 canonical tables. Weekly, monthly,
product-order and salary-receipt submissions are scheduling obligations, NOT
verified submissions: the system explicitly labels
`submission_state=verification_unavailable`. It must NOT declare these
reports missing or submitted until a canonical submission/receipt registry
and policies are separately designed/approved.

## Manager/regional dashboard

Authenticated `GET /reports/manager-watch?date=YYYY-MM-DD[&branch_id=ID]`
uses REPORTS_VIEW, original company and effective branch IDs (at most 12),
and requires each branch to be active and company-owned.

For each branch, count active **FSE** employees assigned to the branch,
excluding approved leave and active global/branch holidays for the date.
A Daily Order with completed cycle AND posted evening is posted; an absent
cycle is `no_daily_cycle`, and a present but unposted evening is
`evening_not_posted`. Only after 19:30 local may those two become overdue
candidate actions. Non-FSE field roles are NOT included until role policy
is explicitly expanded.

Sales and pending requests are taken from the existing canonical
`BranchDailyControlReport`, with strict read-only/source-contract checks;
the watch does not recalculate sales or touch stock/GL.

Undispatched follow-up candidates carry SHA-256 deterministic
`deduplication_key` per company/branch/date/employee/obligation.
**The system does not send notifications, WhatsApp, email or push from
this module; no WP-Cron job is registered and no new submission is written.**
The dashboard is schedule-aware on request/refresh. Actual recurring
notification delivery, retry/outbox idempotency, channel opt-in, cadence and
submission attestations remain a separate approval and release milestone.
This is deliberate to avoid spamming users or claiming messages sent.

A 31-day operational lookback, max 12 active branches, max 2000 eligible FSE
per branch, duplicate roster/source rejection, exact local time boundary,
company/branch cross-scope authorization, leave/holiday exclusions and
zero unauthorized finance exposure are verified in regressions.

## Gates

PHP 8.3/8.4 and Windows tests; disposable MariaDB real canonical posting,
active company-owned branches, eligible roster, approved leave, holiday,
cross-company denial; Flutter UI contract/widget test.

**Not deployed or merged.** Live WordPress data and device UAT remain
unverified. Cash/UPI reports are allocation amounts, not cashier/bank proof.
