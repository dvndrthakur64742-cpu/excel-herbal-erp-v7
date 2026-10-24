# Excel Herbal ERP V8 — Attendance / GPS Separate Duty Contract (Development Only)

## Owner-approved business rule

- **Attendance:** employee manually checks in starting 9:00 AM, with actual time recorded; employee self-checkout from 6:00 PM to 8:00 PM; system closes remaining open check-ins at 8:00 PM using site-business-timezone clock. Late arrivals record actual time; check-in is accepted only before 6 PM. No GPS control at attendance buttons.
- **GPS duty:** separately server-owned automatic window 10:30 AM–5:00 PM; staff cannot manually start or stop. GPS point storage still references an existing attendance record. This dependency is an acknowledged current structural limitation; do not claim route data will exist for staff who never check in. True unattended GPS independent of attendance needs its own schema and explicitly approved design.
- WordPress Cron every five minutes is best effort and requires site traffic or a proper external host scheduler. The 8:00 PM timestamp is recorded as the business cutoff even if the cron fires late that evening. Cron updates **today's** already-open attendance only and never fabricates attendance or backfills past days.
- Check-in/out is self-only (authenticated `workforce.attendance.self`, active employee, assigned branch, no approved leave/holiday). Repeat requests are rejected and audited without duplicate attendance rows.
- Old 10:30 / 17:00 attendance data remains **unchanged**; do not retroactively rewrite payroll history. Any correction needs separate HR approval and an audit trail.
- Existing Office web deployment stays **read-only**, blocking all attendance POSTs. No WordPress deployment in this development change.

## Testing

`php backend/excel-herbal-erp-v7/tests/attendance_separate_policy.php` checks time boundaries, branch permission, duplicate prevention, actual insert/update, audit events, non-destructive auto close and unchanged GPS window.

`flutter test` validates employee controls, read-only denial, independent automatic GPS and workspace boundaries. Unified V8 ZIP build runs the PHP contract test and PHP lint; staging deployment remains a separate gated action.

## Release gate

Before staging deployment: test real employee, ASM, BM roles with a disposable/sanitized UAT dataset, server scheduled WP-Cron reliability, GPS duty reference handling for no-attendance employees, and complete browser/device test. Existing 38 unrevoked staging mobile sessions must be assessed, not mass revoked without a dedicated decision.

## Follow-up: GPS duty independent of attendance (no schema migration)

The existing WordPress staging database has a **nullable** `wp_eh7_gps_points.attendance_id` column, independently verified. A dedicated authenticated GET `/workforce/gps/duty` returns the employee's server-owned duty status (not an attendance record). Employee must be active, have an active assigned branch, and must not be on approved leave/holiday. The GPS POST verifies that duty is active, the position belongs to the correct business day and 10:30–17:00 window, and the timestamp is within 15 minutes before/2 minutes after server time. A GPS point can have `attendance_id=NULL` if the employee did not self-check-in; this **never fabricates attendance**. Manager route summary now finds the latest GPS point by employee/time even if attendance is absent.

Flutter requests the dedicated GPS duty endpoint and keeps all manual GPS toggles unavailable. Android background GPS still depends on OS authorization and an active authenticated service; web browser tabs are foreground-only. Do not claim that location can be collected without device permission or with a closed website. Old attendance and GPS rows are untouched. This is development-only until isolated role/device UAT and release approval.

## Verified full MariaDB GPS write coverage

The isolated real MariaDB UAT now verifies employee GPS POST at 11:00, correct tenant/branch/employee ownership, `attendance_id=NULL`, unchanged attendance count, retrieval through the GPS route endpoint, and rejection at 17:00 without an extra GPS row. The GPS server clock uses WordPress `current_time('mysql')`, consistent with `Db::today()` and self-attendance. No real Office or business transactions are used.

## 2026-10-22 Genuine WordPress GPS REST/role UAT follow-up (development only)

- Genuine local WordPress + disposable MariaDB HTTP tests now cover GPS duty GET and an actual GPS POST with a mandatory idempotency key, replay/mismatch detection, and a route readback with `attendance_id=NULL`. No real staff data or live WordPress requests are used.
- Synthetic UAT roles: field employee, ASM, BM, regional manager and system admin. Management `workforce.gps.team.view` is now included by default for ASM/SM/BM/regional/senior management; manager routes remain constrained by existing hierarchy and company/branch scope. Field employees never receive team GPS capability by default.
- GPS team requests with an explicit branch outside assigned authority fail with HTTP 403 instead of returning an ambiguous empty list. Self/peer GPS route access, cross-branch restrictions and no manual start route are covered via real WordPress REST.
- The CI test adjusts only a disposable WordPress installation's configured timezone to give a deterministic 11 AM business clock. It never changes the GitHub runner clock or staging settings. This ensures the 10:30–17:00 write is exercised by a genuine WordPress request regardless of the CI run hour.
- Rollout remains blocked pending an explicit staging approval, backed-up plugin rollback, on-device GPS permissions and background tracking checks, and inspection of existing staging mobile sessions. No database schema change is introduced here.
