# V8 UAT: Issuing Immutable Retailer Sale + Payment Intent from Canonical Checkout

**Status:** isolated backend development only; not deployable; no production routes or real payments.

## Why this module

Previous modules offered (1) a read-only canonical V7 Checkout Preview, (2) trusted cash/UPI evidence, and (3) a reserved tender-to-sale binding. The sale intent/payment intent pair had been inserted by test fixtures instead of created through a validated issuer. This increment adds **server-side creation of that immutable paired intent** in disposable `v8_test` MariaDB, with strict idempotency and duplicate-request prevention.

## Confirmed business rules

- B2B customer is a **shopkeeper/retailer** linked to the canonical V7 customer party ID.
- **Cash or UPI only**, full payment; no credit, no partial settlement, no self-proclaimed UPI verification.
- Customer outstanding and employee cash custody are **distinct** responsibilities.
- Counter sale consumes branch stock; Field sale consumes employee-custodied stock.
- No duplicate Sales/Stock/GL books.

## UAT contract

1. Trusted server recomputes `CanonicalRetailerCheckoutPreview::compose` using authorized actor, company, branch, user and business time. Its result is ephemeral; the browser must **not** provide or amend it.
2. `ImmutableRetailerIntentIssuer::issue` checks canonical party identity, computed digest, positive/whole unit-priced product rows, no credit or posting permissions, matching full INR amount, and a server-issued 32–64 lowercase hex request key.
3. Under one transaction `lockRequest` creates/locks `(company_id, request_key)` in `v8_b2b_intent_issuance_requests_uat`, rechecks issuer access, and either returns an *identical* existing pair or writes a sale/payment/link/issuance receipt together.
4. UPI generates a random UAT merchant-order placeholder; production order IDs must come from approved PSP integration. Cash does not use an order ID.
5. A paired intent is **awaiting_payment**, not **paid** or **posted**. It is compatible with the existing TrustedTenderIntake and SaleIntentTenderBinding formats, but only in disposable `v8_test` UAT.
6. The existing binding reserves trusted evidence; it **does not** mutate the canonical V7 Sales Register, Stock Ledger, GL, Employee Settlement, or generate a statutory invoice.

### Source mapping / limits

- `backend/src/B2B/ImmutableRetailerIntentIssuer.php` — authorization boundary, canonical quote digest & amount validation, idempotency and fail-closed response.
- `backend/src/B2B/PdoImmutableRetailerIntentGateway.php` — disposable MariaDB `v8_test`-only InnoDB transaction writer (uses staging tables; no WP connection).
- `backend/schema/006_immutable_checkout_intents_UAT.sql` — unique request-key and paired issuance receipt, requires UAT schemas 004 and 005.
- `backend/tests/immutable_intent_issuance.php` — 26 unit/security regressions, all locally tested with a fake gateway.
- `backend/tests/immutable_intent_mariadb.php` — optional full UAT: issue → collect Cash → bind unique tender, **not yet run against MariaDB**.

## Release blockers (do not remove to speed deployment)

- Approved Retailer Price List, discounts, taxes, GST/HSN invoice policy, Return/Credit Note and B2B Points.
- Trusted PSP/bank verification integration and authorized cashier/field-custody permissions.
- Production WordPress API route/ActorResolver integration; canonical V7 customer classification migration review.
- **Real atomic canonical writer:** one transaction must revalidate rate, stock, period, branch day, payment, invoice and posting; register source in AccountingService, move stock via StockService, and enforce reversal/refund.
- Real MariaDB concurrent-requests tests, PHP/GitHub CI success, field mobile UAT, permission boundary UAT and production security review.

The `posting_allowed=false` and `stock_reserved=false` invariants remain unchanged. Never rename UAT tables to `eh7_*` or apply this schema to the live site.

## Test commands

```bash
php -d zend.assertions=1 -d assert.exception=1 v8/backend/tests/immutable_intent_issuance.php
# Optional disposable MariaDB ONLY:
V8_TEST_DSN='mysql:host=127.0.0.1;dbname=v8_test;charset=utf8mb4' V8_TEST_USER=v8 V8_TEST_PASSWORD=v8 \
  php -d zend.assertions=1 -d assert.exception=1 v8/backend/tests/immutable_intent_mariadb.php
```

**Overall V8 progress** remains roughly **15% engineering estimate**, not UAT-certified completion.
