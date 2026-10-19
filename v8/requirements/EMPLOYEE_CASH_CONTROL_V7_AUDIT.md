# Employee Cash Control — V7 canonical posted settlement audit (v0.15)

## Business distinction and release policy

1. Daily Order `evening_settlements` marked `posted` and `daily_cycles` marked `completed` are **sales/settlement records**.
2. The existing V7 `DailyOrderService::finalPost` posts Cash/UPI directly to configured branch payment accounts through a journal source of `daily_cycle`. This records a general-ledger debit; **it does not prove** handover of the field employee's cash to a cashier, physical count, bank deposit, or PSP settlement.
3. The new read-only finance report compares each posted cycle's expected Cash/UPI to journal debit totals for company-scoped Cash and UPI asset accounts. It reports missing, duplicate and mismatched journals.
4. It deliberately reports `cash_remittance_status=not_available_in_legacy_v7` and each cash record `cash_remittance_proof=not_evidenced_in_legacy_v7`, even when the journal amounts match. Never derive cashier confirmation from posted sales alone.
5. No missing cash should be converted to employee shortage automatically. Shortage, partial remittance, reversals and policy-exception workflows require owner approval.

## Authenticated endpoint (development source only)

`GET /wp-json/excel-herbal-erp/v7/organization/employees/{id}/360/cash-control?from=2026-10-01&to=2026-10-19&page=1&page_size=25`

- Requires **finance.accounting.view**; if target is another employee, additionally requires **organization.employee.view**, permitted reporting hierarchy and target branch scope; self requests with finance capability are possible.
- The application shows the `Cash Control` tab only for finance-authorized users, but all enforcement happens server-side.
- Company-scoped SQL `SELECT` over canonical `eh7_daily_cycles`, `eh7_evening_settlements`, `eh7_journal_entries`, `eh7_journal_lines`, `eh7_accounts`, only completed/postable sources. Bound employee, period, and branch IDs. No duplicate master or migration.
- Enforces date bounds <=366 days, one-to-one posted journal source matching, strict paise arithmetic, pagination size <=100; totals and alert counts are **page scoped**, not complete-period totals.
- Status definitions: `journal_amounts_match`, `missing_journal`, `duplicate_journal`, `journal_amount_mismatch`. None mean “Cash received by cashier.”
- UPI bank settlement is not independently verified by this report. `bank` account entries are not assumed to be `upi` without explicit subtype.

## Security and test gate

- New PHP test suite: `backend/excel-herbal-erp-v7/tests/employee_cash_control_regression.php` — 40 isolated regression assertions for authorization, exact amount matching, SQL scope, identity mismatches, invalid money/date, journal anomalies and statement honesty.
- Flutter UI `Cash Control` read-only tab wired under the Employee 360 profile, not the dashboard.
- Flutter compilation/device runs and MariaDB/WordPress UAT have not been performed by this change. GitHub hosted workflow still failed before steps; user's Windows self-hosted runner lacks `php` on PATH.
- No posting endpoint, migrations, production deploy, PR merge, actual cash settlement recording, or live DB mutation.

## Next actual booking milestone

Approved canonical journal source and accounts for `EMPLOYEE_CASH_IN_TRANSIT` plus verifiable cashier receipt, distinct company/branch/employee money buckets; one atomic stock+invoice+GL posting and a separate cash-deposit reclassification entry; bank reconciliation. Must be modeled before any real cashier-confirmed status is exposed.
