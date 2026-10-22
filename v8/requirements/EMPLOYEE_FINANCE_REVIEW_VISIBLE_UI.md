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
