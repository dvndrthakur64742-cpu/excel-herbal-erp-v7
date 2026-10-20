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
