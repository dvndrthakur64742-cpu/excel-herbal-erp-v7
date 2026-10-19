# Excel Herbal ERP V8 — Immutable Sale Intent ↔ Trusted Cash/UPI Evidence (v0.8)

**Status:** UAT-only reservation design/code. No production migration, API route, completed B2B sale, or live ERP posting. Owner's agreed retailer policy: immediate full Cash/UPI only, no credit.

## Problem solved by the new contract

The v0.7 `TrustedTenderIntake` verifies a cash collector or a settled bank payment against a **server-created payment intent**. It does not prove the intended retailer invoice matches that payment. A checkout binding must prove *who, what, where, how much and for which immutable quotation* before any future canonical invoice writer may consume the evidence.

## Binding invariants

1. Server-authenticated actor and branch-specific authority; user cannot supply claims of the collector's role, prices, company or branch.
2. `sale_intent_id` locks one **company- and branch-scoped** retail business-customer order; immutable `quote_digest`, canonical `party_id`, retailer ID, priced total and channel must exist.
3. `payment_intent_id` must already be **immutably linked** to the same sale, quote, company, branch, amount, mode, merchant order, and field/counter custody.
4. Confirmed intake evidence and the *actual* verified tender must agree on bank/cash reference, amount, mode, branch, status and employee. Evidence already consumed by a sale is rejected.
5. Field cash creates **employee custody**, not branch settlement. Counter cash creates branch cashier custody. UPI requires reconciled `bank_settlement`; no screenshot/typed UTR qualifies.
6. Single reservation per sale, single reservation per tender, single payment-intent link to sale; a matching retry may return the original reserved response. A different sale, changed quote or reused tender is rejected.
7. Reservation **never updates canonical stock, finance, employee points, invoice, payroll or cash settlement**. Its return is `posting_allowed=false`, including on successful binding.
8. Payment and sale intents must be created by trusted backend code. UAT schema has no HTTP entry points or WordPress auto-loader wiring and refuses database names other than `v8_test`.

## Release-blocking integrations

- Owner signoff: retailer rate/discount allocation; GST/HSN and invoice totals; refund, reversal and exception procedures; authority for field cash and UPI verification.
- Trusted server checkout which takes canonical V7 customer ID, locked commercial revision, tax policy and stock snapshot to generate immutable sale/payment intents. Simultaneous quotes and stock updates need deterministic locks.
- Canonical write gateway and registered GL journal source, with **one atomic database transaction** for evidence consumption + idempotent invoice + StockService movement + balanced AccountingService posting. Holding reservations in UAT is *not* that transaction.
- PSP/bank webhook signatures and replay validation; privileged Cash collector role rules; employee remittance to branch separation; PCI/privacy/security review where applicable.
- Successful PHP 8.3/8.4 hosted jobs, actual disposable MariaDB tests, concurrency tests, end-to-end Flutter/WordPress UAT on exact GitHub head. GitHub runner failure before executing a step is an **unverified test**, not proof the application passed or failed.

## CI test commands

```
php -d zend.assertions=1 -d assert.exception=1 v8/backend/tests/sale_tender_binding.php
# Optional on isolated disposable DB named v8_test only:
V8_TEST_DSN='mysql:host=127.0.0.1;dbname=v8_test;charset=utf8mb4' V8_TEST_USER=v8 V8_TEST_PASSWORD=v8 \
 php -d zend.assertions=1 -d assert.exception=1 v8/backend/tests/sale_tender_mariadb.php
```
