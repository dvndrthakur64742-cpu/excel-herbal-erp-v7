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
