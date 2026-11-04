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

## 4 Nov 2026 — Complete 83/85-table column & index compatibility inspection

This is a **read-only production inventory**, not a migration run. Source:
authenticated WordPress/WPVibe information_schema.COLUMNS/STATISTICS SELECT;
expected source: canonical Git PHP Schema::definitions(), checked as
**85 definitions**. Full per-table reports stay on the authorized PC in
D:\ERP7-Release-Candidates\live-schema-column-diff-20261104.json and
D:\ERP7-Release-Candidates\live-schema-index-diff-20261104.json.
Full live DDL metadata is deliberately **not committed to GitHub**.

| Measurement | Verified count |
| --- | ---: |
| Live V7 / reviewed V7 source tables | 83 / 85 |
| Shared tables checked column by column | 80 |
| Columns missing on Live in shared tables | 0 |
| Shared column type/unsigned/NULL differences | 0 |
| Extra Live columns, preserved | 2 |
| Required new tables | 5 |
| Live-only report tables, preserve | 3 |
| Missing source-defined indexes on Live | 1 |
| Extra Live indexes, preserve | 16 |
| Shared index definition/uniqueness differences | 0 |

Both live-only stock_quarantine columns,
`unit_cost_snapshot` and `journal_entry_id`, are retained; their
ownership and financial use need review before migration. The single
missing index is the nonunique **mobile_sessions.employee_device**
on `employee_id,wp_user_id,device_key`. It may be created on the
separate migrated site but **must not be added directly to Live now**.
All 16 additional Live indexes are to be preserved until there is
a reviewed explicit removal reason, never dropped automatically.
The three live-only Reports tables presently have zero rows; they
are not deleted. The five new Reward, Payroll, Promotion table
definitions are additive in the reviewed source; do not assume
that creating them is sufficient to certify their business logic.

### Pre-migration backfill, read-only evidence

Compared current Employees and related tables using COUNT/NOT EXISTS
(aggregate values only): **0 active employees missing a current branch
history**, **0 employees missing a salary revision**, and **0 active
companies missing INTER_BRANCH_CLEARING**. These counts rule out those
specific initial backfills under the observed snapshot, not all
possible side effects or changes after the snapshot. The migration
code still calls `dbDelta`, account maintenance,
`backfillEmployeeBranchHistory()`, salary baseline INSERT and
`DocumentVault::provisionKey()`; they all require an authorized
migration/recovery rehearsal on a disposable **host-data copy**.

There are 18 unexpired Mobile Sessions to preserve/validate. The
mobile-session table's 12 existing columns match the source. This is
schema compatibility only: refresh-token rotation, active-login role
visibility and actual device compatibility still need explicit
testing before a Live rollout.

### Workflow and non-destructive rules

- Reusable offline read-only comparators:
  `uat/release/compare-schema-columns.mjs` and
  `uat/release/compare-schema-indexes.mjs`.
  They require the authorization-bound *private* live metadata exports
  in `D:\ERP7-Release-Candidates`; no live network writes.
- 7 Node tests in `uat/release/schema-migration-inventory.test.mjs`
  check DECIMAL splitting, unsigned/null metadata, missing columns,
  corrupt inventory rejection, composite index behavior, code
  migration side effects and release gate blockers.
- Live release gate now explicitly checks Column/Index review
  rather than accepting only a matching table count or schema marker.
  It remains **BLOCKED** until new-table creation, index addition,
  session preservation and non-destructive migration+rollback
  are verified against the real-data clone.
- No Live plugin ZIP, table changes, user credentials or WordPress
  site settings were changed by this analysis.

## 4 Nov authentication continuity fix

Read-only inspection of the **actual Office V7 MobileAuth.php** identified
an additional REST bearer-token authentication filter that was absent from
the newer development checkout: `rest_authentication_errors` at priority
90 in addition to `determine_current_user` at priority 20. The original
filter is scoped only to `/excel-herbal-erp/v7` routes and only runs
for a presented Bearer header; WordPress cookie/nonce authentication and
other REST namespaces are left unchanged.

The reviewed code now **restores the same REST bearer guard**, including
401 on an invalid/expired token while respecting previous WP_Error and
valid WordPress identity resolution. A new mocked, offline PHP regression
`plugin/excel-herbal-erp-v7/tests/mobile_rest_authentication.php`
verifies filter registration, anonymous/cookie-only bypass, unrelated
routes, previous errors, invalid bearer rejection and synthetic valid
session acceptance. It is wired into both Windows QA and Plugin Review
CI. No real users/tokens were read or mutated in those tests.

This is a **source-level continuity fix**, not confirmation that all
18 currently unexpired Office sessions survive the source update.
An approved clone-based HTTP/WordPress/UAT refresh/revocation test remains
required. Do not install this update directly over Office until migration
and session acceptance passes; original live V7 remains unchanged.

## 2026-11-04 — Office-shaped disposable migration rehearsal (no live database clone)

The connected Office WordPress CLI exposes read-only `db query`, not a
full database export/import operation. A **real hosted-data clone has not
been obtained**, so existing employee passwords, sessions and financial
records have NOT been copied to the developer machine or CI.

Instead, the existing GitHub disposable WordPress + MariaDB CI test
(`uat/railway/ci-additive-upgrade-rehearsal.php`) now prepares a
**live-shaped synthetic schema fixture** with:

- Exactly the three legacy report tables (reminder drafts, report
  submissions and submission events), seeded with one **dummy** row each.
  All three dummy rows and table structures must survive.
- The two Office-only stock quarantine columns
  `unit_cost_snapshot DECIMAL(14,4)` and
  `journal_entry_id BIGINT UNSIGNED NULL` with a **dummy quarantine row**
  (0.250 units, cost snapshot 12.3400). They must remain intact.
- The additional Office employee index `branch_status`, which must not
  be dropped.
- The missing Office mobile-session composite index
  `employee_device(employee_id,wp_user_id,device_key)`, removed only
  from the **CI synthetic database**, which must be recreated by
  WordPress `dbDelta` after migration.

The real WordPress Schema::maybeUpgrade() and a second Schema::install()
both verify preserved synthetic WordPress users, employee identities,
session rows, stock, GL, prepaid data, three reports and quarantine row
byte-for-byte, and the complete post-migration indexes/columns. The
disposable containers/database are torn down after CI. The fixture
checks `EH7_CI_ISOLATED=1`, WordPress staging type, exact synthetic
database `eh7_ci_synthetic`, and an `eh7-ci-mariadb-` host before its
first write. CI-only DROP statements affect only checked **empty**
additive tables in this disposable container, never Office.

Safety contracts live in
`uat/railway/ci-live-shaped-fixture.test.mjs`, wired into Windows Quick
QA and the GitHub isolated UAT WordPress workflow. CI migration is a
**synthetic representative schema rehearsal**, not approval to run
migrations over existing hosted Office data. The release gate remains
BLOCKED until a recoverable real-data **host backup/clone**, staff-session
UAT, forward/reverse rehearsal and authorized deployment.

### Active mobile session migration regression (CI-only)

Extended the disposable Office-shaped schema rehearsal to seed exactly
**one unexpired synthetic bearer/refresh session** bound to the synthetic
field employee. The migration snapshots the session's row and verifies
that both the forward upgrade and repeated install preserve it unchanged,
including its future refresh expiry and nonrevoked state. Only after
these assertions is the dummy bearer resolved by the real
`MobileAuth::user(0)` implementation and the one CI-only session
deleted. A hard zero-session assertion prevents this dummy token from
leaking into subsequent HTTP login tests.

This test uses fixed CI-only token material and **never accesses,
reads, logs or revokes a real Office mobile session**. It is evidence of
synthetic schema/identity preservation, not an approved Live auth
upgrade. Offline safety contracts: 6/6 passed locally; actual
WordPress/MariaDB Docker evidence is recorded in GitHub CI.
