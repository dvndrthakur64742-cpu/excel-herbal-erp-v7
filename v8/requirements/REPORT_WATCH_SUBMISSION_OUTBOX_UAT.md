# Manager Reporting Watch → Submission Registry + Draft-Only Reminder Outbox

**Development / UAT:** No WordPress production migration, GitHub PR merge,
email/SMS/WhatsApp/push delivery, cron, external recipients, or automatic
scheduled dispatch. Latest V7 schema version is
`7.3.7-report-reminder-drafts-1` (only a code definition on the dev branch).

## 1. Verified report status from canonical submissions

GET `/reports/manager-watch?date=YYYY-MM-DD&branch_id=optional` still uses
the authenticated actor's active company/branch authority and the original
read-only Daily Closing / FSE-roster calculation.

The same HTTP handler now projects the durable manager report attestations
already stored in `report_submissions`, scoped to those active branches and
that **exact nominal period date**. Weekly report, Monday and Tuesday orders,
1st monthly report, and the 10th salary receipt report are each distinct
types. Status is one of `not_submitted`, `submitted`, `approved`,
`rejected`, with revision and submission ID where present. Regional summaries
show approved/awaiting-review/rejected/missing separately; no false
`all submitted` aggregation if one branch has not attested.

**Salary privacy:** actor without `payroll.salary.view` receives no salary
report slot, state, owner or revision. No report note/text, salary amount or
payment GL is exposed by the projection. The status is a manager attestation,
NOT independent cash handover, bank, stock, UPI or payroll verification.

**Deadline discipline:** Mon/Tue order, weekly and salary receipts have no
explicit clock time. A historical date without that time is shown as
`date_passed_deadline_unspecified`, never a fabricated specific clock-time
overdue. The monthly 1st at 10:30 and daily closing at 19:30 retain their
explicit cutoffs in Asia/Kolkata/WordPress business timezone.

## 2. Manual deduplicated draft-only outbox

Role: `reports.review` + `reports.view` and branch authority.

POST `/reports/reminder-drafts/prepare` with `branch_id`, `date`.
The endpoint re-reads the verified Reporting Watch; it may create ONLY
`state='draft'` records. It derives candidates from the existing eligible
FSE Daily Closing after 19:30 and report types with a **specified past-due
clock** (1st monthly at 10:30). Unspecified deadlines cannot generate a
date/time-based missed-deadline draft. There is NO public recipient address
or messaging channel. Repeated preparation has a DB-enforced SHA-256
`dedupe_key` unique key and returns created/duplicates_skipped counts.

GET `/reports/reminder-drafts?branch_id=...&date=...` returns only
branch-authorized draft metadata. Neither endpoint can mark sent, queued,
delivered or even create a provider job. The API always returns
`dispatch_enabled=false` and `notifications_sent=0`. The existing
`audit_log` records manual preparation. This is staging only, not a
working email or push notification integration.

## 3. Release gate

- PHP 8.3, 8.4, GitHub-hosted Windows: strict scope, duplicate source, branch
  mixture, false status, salary redaction, absent deadline, no-delivery
- Disposable real MariaDB `v8_test`: canonical report submission approval
  reflected on Watch, prepare twice creates one draft, scope and anti-spam,
  monthly due cutoff and 19:30 Daily Closing
- Flutter screen compiles and distinguishes submission statuses from bank/UPI
  verification, and displays branch-specific status
- No production deployment, live schema migration or PR merge
- Real physical-device testing and permission review before any deployment
- Explicit additional approval required before notification delivery adapters

## 4. Scope caveat

This registry stores `summary_text` manually entered by the BM, not
a full submitted PDF, sale reconciliation attachment or e-signature.
A regional `approved` means reviewed human assertion only. Later business
approval may require document attachments and reconciliation evidence.

## 5. Reviewer inbox authorization and dismissal history (2026-10-21)

- GET /reports/reminder-drafts with branch_id and date remains a
  draft-only, read-only company+branch-scoped reviewer inbox.
- Optional state=dismissed returns manually dismissed audit-history records,
  including dismissed_at, dismissed_by and dismissal_reason. state=all returns
  active drafts and dismissed records in ID order. Unsupported state is 422.
- Salary reminder metadata must never be visible without the independent
  payroll.salary.view capability, even to an otherwise authorized reports.review
  user. Filtering executes in SQL before pagination; the same restriction
  covers the locked dismiss lookup, returning not found on unauthorized IDs.
- Default list behavior remains backward-compatible. No schema alteration.
  Dismissals remain manual reviewed actions with a reason and audit entry.
- This is review history, NOT a source freshness guarantee. A draft can become
  stale after report submission; source revalidation remains later work.
- No salary amounts, outbound notifications, cron, posting, migration,
  deployment or PR merge.

## 6. Manual stale-draft freshness preview (2026-10-21)

GET /reports/reminder-drafts/freshness?branch_id=...&date=YYYY-MM-DD
accepts the same optional state=draft|dismissed|all as the inbox.
Only a user with reports.view + reports.review plus authority for the
active company/branch can use this endpoint. It reads the existing canonical
Manager Watch projection ONCE and compares the current candidate fingerprints
against the persisted reviewer draft rows. The endpoint performs NO writes.

Each returned row contains source_eligibility:
- currently_eligible: the verified Watch still considers this reminder due.
- not_currently_eligible: Watch no longer shows it as due; for example a
  monthly report was submitted/approved or a field evening was completed,
  the FSE was removed from the eligible roster, or due conditions changed.
- dismissed: reviewer already dismissed it manually; retains audit reason.

This is NOT automatic clearance, a bank/payment validation, or a guaranteed
atomic point-in-time read: the Watch and draft queries are separate. Fail
closed on malformed candidate/draft fingerprint, unauthorized branch or
unavailable source. For historical dates outside the 31-day Watch window,
the endpoint rejects validation rather than claiming an expired item is
definitively resolved. Manual dismissal remains the only state mutation.
No message dispatch, release, database schema migration or live deployment.

Disposable MariaDB regression: genuine monthly draft is rechecked after
submitted/rejected/resubmitted/approved transitions and remains stored for
review; original FSE daily candidate stays independent.

