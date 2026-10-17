# Scheduled Duty Operations Runbook

Status: staging/UAT guidance only. This document does not authorize a production rollout.

## Duty policy
- Server-owned window: 10:30:00–17:00:00 in the configured WordPress site timezone.
- Employees cannot manually start or stop duty through the attendance API.
- Approved leave and active company-wide/branch holidays are excluded.
- GPS points must be recorded inside the duty window and business date.
- The employee dashboard must show only the employee's sales count and incentive points; monetary prices remain hidden there.

## Important distinction: scheduled duty is not proof of physical presence
The scheduler materializes a scheduled attendance row for eligible active employees. This row is an automated duty-window record, not evidence that the employee was physically present or that GPS was received. Before treating it as payroll-grade attendance, HR must explicitly accept this business rule and confirm how missing GPS / absent staff are represented in reports. Do not infer route coverage from an attendance row alone.

## WordPress-Cron reliability
WordPress-Cron is traffic-triggered, so a quiet site can run the 5-minute event late. For reliable timing, configure the hosting scheduler to invoke WordPress cron at least every five minutes (preferably through WP-CLI where available), and disable page-load spawning only after the host scheduler has been verified. Example host-side command pattern (adapt paths, user, and site URL to the staging host):

```sh
*/5 * * * * cd /path/to/wordpress && wp cron event run --due-now --quiet
```

Do not paste this example into production without host-specific review. Never expose cron secrets or administrative credentials in the repository.

## Staging acceptance checklist
1. Confirm WordPress site timezone and server clock are correct.
2. Verify the recurring `eh7_scheduled_attendance_tick` event is registered and runs at 5-minute intervals.
3. Test before 10:30, at/after 10:30, and at/after 17:00 using controlled staging data and a fixed test date.
4. Confirm approved leave, company-wide holiday, branch holiday, inactive employee, and inactive branch are excluded.
5. Run the scheduler twice and verify idempotency: one attendance row per employee/business date, no duplicate row.
6. Verify automatic checkout time is 17:00 local time converted to UTC; do not use the cron execution time as checkout time.
7. Verify manual check-in and check-out endpoints return HTTP 403 with `attendance_manual_disabled`.
8. Verify GPS is accepted only inside the policy window and recorded route points render on the road map.
9. Compare the attendance report against the raw test fixtures and get HR approval for the scheduled-row versus physical-presence distinction.
10. Capture workflow run links, test evidence, site timezone, cron configuration proof, and HR sign-off in the staging release record.

## Release gate
Do not merge this draft PR or deploy to production until CI passes on the exact PR head, backup/restore and security gates pass, Android GPS is tested on a physical device, finance/report reconciliations pass, and authorized reviewers approve the staging evidence.