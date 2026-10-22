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
