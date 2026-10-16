# Excel Herbal ERP — Controlled Office BUILD/UAT correction

**Environment:** BUILD/UAT only (`office.excelherbal.in`). This file is documentation of owner-authorized code corrections, **not a production release sign-off**.

## Fix scope

- Wholesale discount allocated 50% to BM Profit and 50% to Salary Fund, with HO Amount, Office Expense, Points unchanged; reject allocations below zero.
- Closing submit/final post verify Sale = HO + BM Profit + Office Expense + Salary Fund; stock, accounting and performance retain maker/checker.
- System Admin access Save uses a single database transaction for roles plus employee capability grants/denies; validates scope and self-lockout and rolls back on error.
- GPS Check-Out ends tracking with the server-owned `checked_out` status; Check-In shows actual/scheduled/error status rather than an unverified success claim.
- Admin permissions navigation and change reason validation improved; strict API Contract includes atomic access endpoint.

## Deploy policy

- GitHub workflow `[deploy-uat-current]` first requires a successful exact-head Flutter Analyze/tests/web build AND PHP lint/regressions/routes/disposable MariaDB suite; deployment jobs require both.
- Deployment is limited to the controlled Office BUILD/UAT backend and web bundle with SHA manifest verification. Host audit and no-implicit-business-cleanup CI guard remain enforced.
- This action must NOT reset, cancel, reopen, delete or modify existing live UAT orders, stock, payroll, attendance, permissions or HR personal records. Specifically do not modify completed Daily Order #9 or canceled cycle #8.
- Human Accounts report approval and Owner/HR/Accounts pilot signoffs remain PENDING, `production_approved=false`, PR #8 remains Draft.
- After success, verify `/wp-json/excel-herbal-erp/v7/health` backend/web exact source head and host hardening; only then schedule read-only web UX acceptance. If packaging/upload/attestation fails, document failure and do not claim deployment complete.

**Note:** Office BUILD/UAT is not sanitized. Tests that mutate orders and permissions must run only on the disposable MariaDB fixtures.
