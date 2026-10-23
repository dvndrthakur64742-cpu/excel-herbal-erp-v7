# Excel Herbal V8 — Employee 360 Finance Review (visible Flutter UI)

**Implemented on development branch 2026-10-22.** This is an actual, finance-gated
Flutter Employee 360 tab, not another UAT-only PHP class. The frontend fetches
two already-existing authenticated, company/branch/employee-scoped V7 REST APIs:
`/organization/employees/{id}/360/cash-control` and
`/organization/employees/{id}/360/register?type=person_ledger`.
The server still controls accounting permissions and authorized employees.

## Actual screen behavior

- Admin / authorized finance user opens **Employee 360 → Finance Review**.
  General employees without `finance.accounting.view` do not see the tab.
- Read-only review cards show first-25 **Daily Cash booked**, **Daily UPI
  booked**, **journal mismatch count**, **unproven Cash handover count**.
  A visible notice warns about additional pages: the figures are not period
  totals. The existing **Cash Control** tab retains paging.
- A three-part evidence panel explicitly says: **Cashier handover NOT VERIFIED**,
  **UPI bank settlement NOT VERIFIED**, and **Daily Order/B2B link NOT VERIFIED**.
  It neither invents a signed receipt nor equates Cash booking with remittance.
- Shows original daily-cycle IDs, date, tender breakdown and GL mismatch state.
- Shows employee-tagged general-ledger **opening and closing Dr minus Cr**
  by account (up to 30 visible; Person Ledger holds full source balances).
  No mixing of per-page Daily amounts with account balance, no phantom cash
  shortage or combined cross-source Sales total.
- Respects parent date filter and employee selection. Panel has its own
  Refresh button and explicit Retry for network/API failures.
- Fail-closed frontend response contract checks enforce read-only scope,
  canonical ledger balance basis, exact employee identity, page size,
  no handover or bank-proof claims, safe monetary precision and page flags.
  All existing V7 server gates remain essential; UI checks are not a
  replacement for API authorization.

## Delivery / release limits

- No database schema migration, B2B posting route, duplicate suppression,
  legacy DailyOrder accounting rewrite, PSP verification, live Cash proof,
  new financial writes, employee dashboard price change or production deploy.
- Screen is **in GitHub only until separately approved staging plugin/web
  release**. Installing a build and actual-device UAT are still necessary
  before saying the Office web UI has this feature.
- Flutter UI unit/widget tests cover actual labels, metric values, finance
  source isolation and forged/mismatched API responses.

## 2026-10-22 — Live Office REST acceptance and selected-period guard

After the certified CanvasKit web deployment, **read-only authenticated
Office staging V7 REST checks were executed** for an existing employee in
October 2026, without modifying any business/finance record. The Employee 360
profile, Cash Control (2 canonical posted-cycle rows) and employee Person
Ledger endpoints all returned successful, employee-bound read-only responses.
The person-ledger event page returned 25 records with `has_more=true`; its
full-history account balances must not be confused with the paged event list.
All 11 shape/security checks across the two finance contracts passed. No
private employee identifiers, mobile numbers or amounts are included here.

QA found that the first implementation validated employee identity but
**did not compare the actual reporting period from Cash Control and Person
Ledger to the selected UI dates**. This could show an out-of-period finance
summary if a stale or inconsistent API response were returned. The screen now
fails closed unless both API period objects have exactly the requested
`from`/`to`; it also validates every closing business date, exact ledger
page size and page-1 identity and ledger event-page bounds. A visible notice
warns finance users when more Person Ledger events exist and directs them to
the existing paginated Person Ledger tab. This does not imply the account
balance is page-limited, nor that Cash/UPI was physically settled.

New Flutter regression cases cover mismatched Cash/Ledger dates, wrong ledger
page and page size, out-of-range closing date, oversized ledger event page,
and visible continuation wording. This is **development code only** until a
new separately approved web-only release; no WordPress files, REST handlers,
real data, payroll or posting rules changed in this QA commit. Full browser
Admin/Manager interaction, actual device/mobile testing and negative role UAT
are still pending. Staging remains unsanitized and mobile sessions exist.

## 2026-10-22 — Employee manager shortcut (development only)

Read-only browser QA confirmed that the Office staging Flutter ERP is open
inside the user's authorized Chrome session. Enabling its accessibility
semantics exposed live module navigation. Existing Employee 360 is reached
through **Organization & Masters → Employees → employee actions → Sales,
Points & Stock**, after which a finance-authorized reviewer previously needed
to scroll to the 11th horizontal tab to reach **Finance Review**. Live Chrome
navigation was stopped when another operator changed the browser screen, to
avoid disrupting concurrent work. A full logged-in finance-tab walkthrough
and actual device testing therefore remain pending, not claimed PASS.

The employee action sheet now offers a **Finance Review** shortcut only
if both `organization.employee.view` and `finance.accounting.view` are
granted. It opens the same `Employee360Screen` via its existing Navigator
route, requesting the already-authorized Finance Review tab as initial
tab. If the finance tab is not visible because the canonical profile or
role omits finance access, Employee 360 opens at the safe Summary tab
instead. Existing API/server identity, branch and capability checks still
apply. No new REST route, duplicated dashboard, journal, settlement posting,
data copy, schema migration or WordPress staging deployment was introduced.

Test coverage asserts the two-capability shortcut, its original Employee 360
Navigator route, the finance-tab lookup, Summary fallback and unchanged
read-only finance APIs. This development change still requires authorized
interactive browser QA before a separately approved web-only release.

## 2026-10-23 — Direct access to full Cash and Person Ledger pages

In the Employee Finance Review card, authorized managers now have two
read-only action buttons: **Open Cash Control** and **Open Person Ledger**.
They navigate to the *existing* paginated Employee 360 tabs using the
`DefaultTabController`; dynamic index discovery avoids breaking navigation
when optional GPS or finance tabs differ by role. No separate endpoint,
journal, cash proof or cross-source combined totals were added. A dedicated
Flutter widget regression exercises both real button callbacks and source
tests verify the destination tabs are dynamically resolved.

At this checkpoint, `office.excelherbal.in` remains the previously
verified `bdcc617` web bundle (SHA `f57e8fe8...`); the new shortcut and
buttons are still in the development branch pending staging rollout. The
Windows Desktop Commander is offline, so an authenticated Chrome admin
walkthrough was not possible. Staging is not sanitized; some mobile sessions
remain active. No live DB writes, WordPress plugin changes or new deployment
were performed. WPVibe read-only health and schema verification passed.
