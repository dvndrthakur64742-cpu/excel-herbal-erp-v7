# Branch Reporting Submission, Review and Immutable History — V8 Development UAT

## Workflow

The Reports → Reporting Submissions & Approvals screen uses existing ERP
login, company, selected branch and effective role capabilities. It adds a
small, real transactional V7 reporting attestation registry:

- **BM** with `reports.submit` creates one human-authored summary for a
  valid scheduled reporting period from the actor's *assigned* branch.
  No employee can supply a different company or submitted_by ID.
- **RM, Regional Coordinator, AGM, ZI, MD/CM** with `reports.review`
  can approve/reject an authorized branch's submission. The system
  *always* prevents an employee from approving their own submission,
  even if they hold both capabilities.
- A rejected submission can be revised only by its original submitter;
  its period identity does not change and revision increments.
- Already approved/submitted reports cannot be silently overwritten,
  and reviewed status cannot be changed without another submission.
- Every atomic transition appends a `report_submission_events` entry
  with snapshot, SHA-256, revision, actor, timestamp and reviewer notes.
  The existing V7 `audit_log` receives the same transitions.

Accepted period keys:
`weekly_report` / `product_order_mon` = Monday,
`product_order_tue` = Tuesday, `monthly_report` = month day 1,
`salary_receipts` = month day 10. Note that day 10 is the nominal
receipt-report deadline, not proof salary was paid. Approved/rejected
reports may be submitted after the nominal day, but no future period
or report older than 180 days can be freshly attested.

## Security and proof limits

Dedicated role capabilities: `reports.submit`, `reports.review`,
plus `payroll.salary.view` for salary-receipt reports. RM review is
scoped to authenticated authorized branches, BM submit to assigned
branch only, company ID always server-bound. Staff lacking review
permission can see only their own submission records and history.

**Approval confirms a human report attestation, not independent sales,
stock, attendance, bank, UPI settlement or salary receipt validation.**
The business totals continue to use canonical V7 Daily Order and GL
records. There is no shadow stock, sale, GL or salary ledger.

REST paths (all authenticated):
- GET `/reports/submissions?branch_id=...&status=all|submitted|approved|rejected`
- GET `/reports/submissions/{id}/history`
- POST `/reports/submissions` with `branch_id`, `report_type`,
  `period_date`, `summary_text`
- POST `/reports/submissions/{id}/decision` with `decision=approve|reject`
  and `note`. Rejection requires an explanation.

POST calls inherit the existing API X-Idempotency-Key middleware,
row-level `FOR UPDATE`, unique period key, checked update rows and
database transactions. The new `report_submissions` and
`report_submission_events` V7 schema definitions are versioned as
`7.3.6-branch-report-submissions-1`; schema changes are **not run**
against any live WordPress installation in this milestone.

## Reminders / delivery status

Read-only Manager Reporting Watch continues to surface deadline
candidates. No WhatsApp, email, FCM push, cron or repeated delivery was
enabled; notification outbox, policy opt-in, operational retry, actual
delivery receipts and submission-to-watch integration are later separate
work requiring signoff. This prevents spam and false delivery claims.

## CI / release gate

PHP 8.3, 8.4 and Windows Cloud state transition, maker-checker,
schedule, salary permission, idempotent duplicate and append-only events
regressions; real disposable MariaDB `v8_test` revisions, approval,
audit and company/branch isolation; Flutter screen compilation and UI
contract. **No production deployment or PR merge.** Live WordPress
migration, mobile device UAT and actual notification delivery await
separate authorization.
