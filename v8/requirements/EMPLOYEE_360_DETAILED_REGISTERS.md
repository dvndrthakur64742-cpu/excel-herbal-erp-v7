# Employee 360 — Detailed Canonical Registers (development only)

## Owner-approved workflow served

An employee's profile remains linked to the **same canonical V7 employee ID**. Historical registers are not stored again. The operational sale/points and stock audit trail use existing Daily Order, evening settlements, and employee stock ledger. This is intentionally **read-only** and separate from the price-hidden employee *dashboard*.

## REST read route

`GET /wp-json/excel-herbal-erp/v7/organization/employees/{id}/360/register?type=sales&from=2026-10-01&to=2026-10-19&page=1&page_size=50`

`type=stock` returns employee-custodied movements. `type=sales` returns one summary record per completed Daily Order cycle with a **posted** evening settlement, including sold and returned quantities, sale amount, Cash/UPI split and incentive points. The aggregate is grouped by `daily_cycle.id` so multiple product rows do **not** multiply the header's paid/sale total.

The stock source is canonical `eh7_stock_ledger`, only for `custodian_employee_id={id}`, `IN/OUT` movements, company, authorized branches, and UTC-bounded business dates. It **never** exposes purchase cost, commercial breakdown or GL account IDs.

**Access controls:** authenticated V7 actor; self access; other employee requires `organization.employee.view`, reporting hierarchy scope and branch authority. Managers' records limited to authorized branches. Dates valid, at most 366 days. Server-bounded pages 1–500, 1–100 rows per page, plus one sentinel to return `has_more`.

**Important semantics:** Historical posted `cash_amount` and `upi_amount` describe what Daily Order settlement recorded; they do NOT certify Cash moved from employee to cashier. Stock movement is not a bank receipt or inventory reconciliation, and no unsettled Cash transit is falsely marked complete. Retails/B2B outside posted Daily Orders are not falsely included. A separate eventual B2B canonical register is necessary when its writer is approved. No new employee dashboard prices, no GPS or attendance rules changed.

## Test and release gates

- `backend/excel-herbal-erp-v7/tests/employee360_registers_regression.php`: 33 assertions for role/branch/employee scope, dates, pagination and source SQL guards.
- `backend/excel-herbal-erp-v7/tests/employee360_regression.php`: prior 37 assertions remain.
- Real V7 WordPress + MariaDB UAT, large pagination UAT, access policy UAT and client profile UI are **not yet passed**. Neither CI, schema migrations nor deployment is implied.
- This is code committed only to `codex/erp-v8-foundation-20261017`, draft PR #25. No PR merge or production deployment.