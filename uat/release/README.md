# Excel Herbal ERP — Controlled Live Release and UX Contract (4 Nov 2026)

**Live target:** https://office.excelherbal.in
**Release state:** **BLOCKED / NO LIVE WRITE PERFORMED**
**Development source reviewed:** 39c8b0a1dd845d48a670901ec4b5ed012fed7b8a
**Plugin ZIP:** review artifact only, not eligible for direct production install.

## Read-only evidence, collected directly from Office WordPress

- WordPress 7.1.4, PHP 8.3.36, site authenticated as administrator via WPVibe.
- Active V7 Plugin **7.3.10-rc2**; V15 **15.0.0** installed but inactive.
- Live ERP database **83 V7 tables**, **27 employee records**, **441 attendance rows**, **502 audit-log events**, **24 unrevoked mobile sessions**.
- Live schema: **7.3.12-prepaid-refund-evidence-1**.
- Current development source schema: **7.3.12-reward-payroll-allocated-6**.
- Live ERP Health source marker: **local-integrated-v15-workflow-unverified**, and **source_head_match=false**.
- Live WP/ERP environment self-reports **staging**, yet host is the user-visible Office production domain.
- Live health is **NOT sanitized** and **NOT synthetic_only**; do not clear the database merely because the owner has not yet rolled out employee work.
- Live V15 data/table ownership and migration path are not yet validated.
- The source-pinned candidate `erp-uat-candidate` and the local synthetic DB prove backend GPS/stock, Cash/UPI and settlement integration, **not** upgrades against the actual hosted data or real device acceptance.

## Why no direct overwrite

Installing the tested source over Office would change active code while 24
existing sessions and 27 employee records remain in a schema that does not
match the candidate. Evidence is insufficient to show that sessions,
employee identity, attendance and audit logs would survive the upgrade.
A rollback of plugin files **alone** cannot reverse a schema migration.
Changing an active WordPress plugin's files is NOT equivalent to loading a
static preview. The latest review ZIP cannot be treated as an approved
deployment artifact.

**Immediate gated release path:**

1. Reconcile every live V7/V15-owned table and actual schema against the
   tested code using a disposable *copy* of the host data; preserve existing
   employee/attendance/audit/session history.
2. Obtain one verified recoverable DB+WP files checkpoint **before migration**.
   This is not a request for routine, large backups on every development
   commit; it is a one-time guard against irrecoverable loss.
3. Rehearse forward migration, downgrade/rollback, and session preservation
   against that separate copy. No production PHP/SQL write during discovery.
4. Verify role-based login, dashboard, Stock, Sales, UPI, GPS, approvals and
   finance in browser and Android before enabling business writes.
5. Review the single-plugin release package SHA/source schema, exact website
   plugin directory, and actual production runtime marker.
6. Approve a small release window and deploy with post-install smoke checks,
   keeping a tested rollback plan. Halt on any guardrail failure.
7. Report precisely what became visible on Live; **never label GitHub CI,
   synthetic tests or an artifact ZIP as a completed live deployment**.

The executable read-only gate `uat/release/live-deployment-gate.mjs` checks
these prerequisites using a sanitized snapshot, and the Node regression
suite refuses direct rollout today. For a current review:

```powershell
$env:EH7_RELEASE_SHA=(git -C D:\ERP7-Development rev-parse HEAD).Trim()
$env:EH7_RELEASE_SCHEMA='7.3.12-reward-payroll-allocated-6'
node D:\ERP7-Development\uat\release\live-deployment-gate.mjs
```

Expected result for the current Office snapshot: **BLOCKED**. The process
does not issue a network request or write to the live database. Refresh the
snapshot from an authenticated read-only WordPress inspection before use.

## UI/UX design contract — apply to every module

- **Design reference:** appfixer.ai.studio is for inspiration **only**;
  do not copy another platform's screens or business logic. Continue with
  Excel Herbal's distinctive brand and a consistent enterprise design system.
- **Desktop:** persistent clear sidebar, employee identity and branch
  context, role-based dashboard, searchable/filterable tables, export and
  drill-down actions.
- **Mobile:** easy bottom navigation, task-based quick actions, field
  workflows within two navigation steps when feasible. Preserve accessible
  navigation, even under 320px width or enlarged text.
- **Role dashboards:** show Sales, Collections, GPS Attendance, Stock,
  Approvals and Branch Performance according to actual access permissions.
- **Forms:** visible labels, inline validation, clear approval/deny reasons,
  currency/date/quantity formatting, explicit confirmation for posting and
  real draft preservation. Never offer dead buttons or mismatched fake
  actions.
- **States:** loading, ready, empty, error, retry, success and incompatible
  backend. Error panels must show business-friendly explanations, recoverable
  next action and support reference; don't dump raw traces.
- **Accessibility:** 8-point spacing rhythms, minimum **48px** interactive
  targets, text-scale and screen-reader support, focus-visible navigation,
  readable contrast and aligned numbers.
- **Acceptance:** Responsive at phone and desktop widths, real async Retry,
  protected staff/branch scope and backend permissions, Flutter widget
  tests, authenticated role UAT and live smoke verification after rollout.

Current implementation improvement: `flutter-app/lib/widgets/async_panel.dart`
empty and error states now scroll at small sizes and provide screen-reader
live regions; `flutter-app/test/async_panel_small_phone_test.dart` checks
320px devices with 2.5x text scaling and that Retry performs a fresh request.

## Release package manifest correctness

The plugin-review GitHub workflow was previously inconsistent: it validated
the real source schema **7.3.12-reward-payroll-allocated-6** but wrote the
older **7.3.12-prepaid-refund-evidence-1** into the ZIP's text/JSON manifest.
The release metadata is now corrected and automatically checked against
the actual source by `uat/release/release-metadata-ux.test.mjs`.
A valid SHA and correct manifest **do not** override the live deployment gate.


## 4 Nov addendum — explicit table-ownership delta

A fresh read-only `information_schema` inventory compared all **83 live**
V7 tables against the **85** definitions in Git SHA 39c8b0a. Result:

- Live-only (3): `report_reminder_drafts`, `report_submissions`,
  `report_submission_events`. All **0 rows** today; still preserve
  until a reviewed retirement/mapping decision.
- Candidate-only (5): `reward_adjustments`,
  `reward_payroll_link_proposals`, `reward_payroll_allocations`,
  `promotion_requests`, `salary_structure_versions`.
- Existing V15/legacy namespace currently has **190 eoe tables**
  (do not assume they are empty or owned by the current V7 plugin).
- The 24 not-revoked mobile sessions include **18 unexpired refresh
  sessions** based on both NOW() and UTC_TIMESTAMP() read-only queries.
  All 27 V7 employee records have active status.

The live-deployment gate now blocks any unresolved table-inventory delta,
even if a future package happens to advertise the same schema version.
Table existence/row counts are only a first check; column definitions,
indexes, ownership, foreign references, real staff identity and migration
data must also be compared against a disposable copy before a live write.

**UX:** the existing Excel Herbal brand remains distinct; the requested
appfixer.ai.studio reference is not copied. The 320px mobile accessible
Retry/Empty state improvement is a code + widget-test change, not a live
asset deployment.
