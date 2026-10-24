# V8 Trusted Tender Intake — Cash/UPI (UAT-only)

**Updated:** 2026-10-19. **Status:** implemented as isolated, non-routed application service and disposable MariaDB UAT adapter; **not enabled in WordPress**. No migrations have been executed against the user's site.

## Confirmed business rule

`B2B-PAY-001`: a retailer/shopkeeper pays the **full amount immediately with either Cash or UPI**, not credit. We do **not** assume mixed tender is approved. Payment to a field employee and remittance of that cash to a branch are **distinct events**.

## Trust boundaries

| Event | Authorized origin | Funds state |
|---|---|---|
| Field employee accepts Cash | Authenticated employee mapped to the *assigned custodian employee ID*, in active company/branch authority | Customer fully paid; `EMPLOYEE_CASH_IN_TRANSIT` liability until branch cashier accepts remittance |
| Branch counter accepts Cash | Authorized branch cashier / counter collecting role | Customer fully paid; branch cash confirmed |
| UPI transfer settled | Authorized server-side financial verification job reading authenticated bank/provider reconciliation | Customer fully paid only if `settled`, currency INR, amount matches server intent exactly, merchant account **and merchant order** match |
| Field Cash remitted to branch | Separate `EmployeeCashRemittance` workflow: independently confirmed deposit | DR branch Cash / CR employee Cash-in-Transit (no second sale) |

An employee saying “paid,” a pasted UPI UTR, a screenshot, a client-provided `is_verified` flag, and a WhatsApp receipt **are not bank/provider verification**. UPI transaction lookup keys may be supplied as search candidates but are not proof.

**Actor ID caveat:** V7 `Actor::userId` and `Actor::employeeId` are not interchangeable. `canCollectCash` must resolve authenticated WordPress user → active employee + branch/team authority. Comparing the numeric user ID directly with an employee ID is incorrect.

## New source files

- `TrustedTenderIntake.php` — `cashCollected(...)` and `upiSettled(...)` take only server-resolved tenant/branch/actor + previously created *locked* server-side sale intent. Price/amount/customer are **never taken from the payment request**.
- `PdoTrustedTenderIntakeGateway.php` — UAT InnoDB gateway. Explicit backend authorization, bank-record lookup and merchant-account lookup callbacks are mandatory, with no allow-all defaults. A full DB transaction protects source and evidence rows. Do not perform slow external network lookups while holding the DB transaction; use pre-reconciled trusted bank records.
- `004_trusted_tender_intake_UAT.sql` — standalone UAT-only server-created payment-intent and one-to-one tender-evidence tables, with DB-unique `(company_id, payment_mode, payment_reference)` **across branches**; verified parent `v8_b2b_verified_tenders` stays one-use for the sale writer. *Do not run this script as a site migration.*
- `trusted_tender_intake.php` — 30 independent unit tests with fake gateway, including fail-closed, replay, cross-branch scoping, actor/employee mapping, wrong destination, and order mismatch.
- `trusted_tender_mariadb.php` — isolated `v8_test`-only real SQL path and duplicate UTR rollback checks; `SKIP` without `V8_TEST_DSN`. MySQL integration is **not** certified until its workflow actually executes.

## Known incomplete integration — fail closed

The **existing** isolated V8 sale writer `MariaDbRetailerGateway::confirmedTender` still recognizes legacy `verified_source` values `cashier`/`provider`, while this new intake uses precise `employee_cash_custody`, `branch_cashier_cash`, and `bank_settlement`. This is **deliberately NOT silently bridged** until the canonical sale intent ID, retailer/party ID, payment reference and invoice total are bound to the SAME order in the sale writer. Merely changing an allowed-source string would create an attribution hole. The existing production V7 ledger is not modified. The `CanonicalV7Readiness` gate remains `posting_allowed=false`.

Additional blockers: owner-approved statutory invoice/tax/HSN design, payment provider integration and callback authentication, official cash collection roles and exception policy, canonical write adapter with registered V7 journal source, reversal/refunds, disposable MariaDB concurrency test, GitHub-hosted runner provisioning and whole-workflow UAT.

## Local verification

From the project root:

```sh
php -d zend.assertions=1 -d assert.exception=1 v8/backend/tests/trusted_tender_intake.php
# Optional, only against dedicated disposable database named v8_test:
V8_TEST_DSN='mysql:host=127.0.0.1;dbname=v8_test;charset=utf8mb4' V8_TEST_USER=v8 V8_TEST_PASSWORD=v8 \
  php -d zend.assertions=1 -d assert.exception=1 v8/backend/tests/trusted_tender_mariadb.php
```

No HTTP endpoints, WordPress permissions, verified payment provider integration, production DB writes, CI approval or live deployment are provided by this file.
