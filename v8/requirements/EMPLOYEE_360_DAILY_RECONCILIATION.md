# Employee 360 Daily Reconciliation (UAT/read-only)

New type=reconciliation for the EXISTING authorized Employee 360 register route.
Flutter profile adds "Daily Reconciliation", without touching the employee dashboard.

This is a cycle-scoped comparison across canonical V7 Daily Order issue lines,
evening settlement/closing lines and employee-custody stock ledger:
- issued = evening issued = sold + returned
- same-cycle employee stock IN from daily_issue = issued
- daily_sale employee stock OUT = sold
- daily_return employee stock OUT = returned
- posted evening expected amount = closing line amount = Cash + UPI split

Checks run ONLY when both cycle=completed and evening=posted.
Otherwise status=awaiting_posted_evening, not confirmed. Differences yield mismatch.
All counts derive from separate aggregates, without multi-batch multiplication.
No new shadow stock, shadow GL, write endpoint or prices on employee dashboard.

CRITICAL: This report does NOT establish independent UPI bank verification,
employee-to-cashier cash handover, live physical stock count, or a balanced GL.
Legacy V7 finalPost posts Cash/UPI accounting without those independent proofs.
Those items remain blocked for financial production release.

GitHub CI PHP unit tests and disposable real MariaDB regression required.
Flutter source/widget tests separately required. Live WordPress and physical-device
validation pending. No deployment/merge/production migration.

## 2026-10-22 — Two-sided warehouse/employee stock custody controls

The original Employee 360 daily check could show `cycle_sources_match` even when
an employee's stock IN matched issue lines but the original warehouse OUT was
missing, or when an employee's return OUT had no warehouse receipt IN.
This is a false-positive for physical stock transfer bookkeeping.

The read-only reconciliation now joins separately aggregated canonical source rows:

- Warehouse `daily_issue OUT` is tied to issued `daily_requests`, the same
  daily cycle, company and branch, and `custodian_employee_id IS NULL`.
- Warehouse `daily_return IN` is tied to the same cycle source ID, company,
  branch and null custodian.
- Posted cycles must reconcile issued quantity to warehouse OUT and employee
  IN; returns must reconcile employee OUT and warehouse IN; net warehouse OUT
  minus returned warehouse IN must equal sold quantity.
- The existing `type=reconciliation` response adds warehouse movement quantities,
  net-out PCS and explicit failure flags. Unposted cycles remain awaiting review.
- PHP regression and isolated real MariaDB tests use a synthetic cycle and
  savepoint rollback to prove missing warehouse OUT / missing return IN cannot
  be confused with a valid cycle. No real database or Office staging is changed.

Passing is a source-ledger consistency check, **not** independent physical
stocktake, cash handover, bank-confirmed UPI, or a verified GL close.
No table migration, new route, balance posting or production deployment.
