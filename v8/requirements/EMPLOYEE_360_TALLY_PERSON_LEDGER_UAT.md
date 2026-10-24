# Excel Herbal ERP V8 — Tally-style Employee Person Ledger (Development/UAT)

Read-only `type=person_ledger` on the existing authenticated
`/organization/employees/{id}/360/register` endpoint. No new financial writer,
shadow GL, shadow stock, customer invoice, or live schema migration.

## Independently sourced events

- **GL**: employee-tagged journal_lines joined to posted V7 journal_entries and V7 Chart of Accounts
- **Stock**: custody-specific V7 stock_ledger IN/OUT movements with product and batch IDs
- **Sales**: completed Daily Order + posted evening settlement; INR sale reference, not a second GL posting
- **Points**: original performance_entries; performance/incentive metric only

One UNION timeline has deterministic global pagination across all four sources,
instead of concatenating independently paginated lists. Original event
source_type/source_id are retained so entries can be traced back to their
canonical source.

## Opening and closing

Per-account INR: tagged debit minus credit opening from **all posted history
before the period**, plus in-period debit minus credit = closing.

Per-branch/product/batch PCS: signed IN/OUT movement-derived opening before
the period, plus period IN minus period OUT = closing.

These aggregates are executed separately from LIMIT/OFFSET, so page 1, page 2,
and page 100 return the same complete-history financial and stock balances.
No single INR+PCS+points total is allowed; sales reference values are never
summed with GL balances. Points do NOT have a monetary opening/closing.

**Important limitations:** Employee-tagged GL is not the whole company GL
balance. Stock movements may not include historical physical opening counts.
A journal entry alone does not confirm physical Cash-to-cashier receipt,
external bank settlement, or UPI verification. No proof is inferred.

## Access and release protection

- Strict finance.accounting.view capability, even for the employee's self view
- Original employee profile company/ID, reporting hierarchy and manager branch scope
- Read-only SQL on canonical V7 tables, parameter-bound company, employee,
  business period, UTC stock bounds and branch authority
- Employee dashboard and employee-facing prices unchanged
- PHP 8.3/8.4 role/finance/pagination/precision regressions
- Disposable real MariaDB source-linked events, opening/closing arithmetic,
  negative authorization and paginated consistency tests
- GitHub-hosted Windows PHP and Flutter UI contract tests

**No production deployment, no PR merge, no live WordPress write.**
