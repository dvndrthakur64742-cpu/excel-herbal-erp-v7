# Excel Herbal ERP V7 — 7.3.10-rc1 — Staging Candidate ONLY

## Implemented: prepaid B2C/B2B/distributor sales
- Versioned `distributor_price_slabs` per product. Authorized configuration requires both product-management and ERP access-management permissions. Effective-date version and chosen slab ID are snapshotted into each order line.
- `prepaid_sales_orders`, line snapshots, and per-payment receipt records in separate database tables (new schema `7.3.10-prepaid-sales-1`).
- 10 new authenticated REST routes: distributor quote/config; discount policy read/config; order create/detail; independent discount approval; cash/UPI receipt; independent UPI verification; final order posting.
- No invoice or stock movement occurs on order creation. Discounted orders remain `discount_pending` until separately approved.
- Numeric Branch Manager vs Head Office discount escalation cutoff has **NO DEFAULT**. A specifically authorized Head Office role must first configure an explicit percent. Until configured, discount approval is blocked.
- Cash receipt is recorded as confirmed by an authorized cashier; UPI is **pending** until a different finance verifier attests to bank evidence and confirms the payment. This is manual attestation, not direct bank-API verification.
- Posting obtains a row lock, requires approved order, rejects pending payments, requires exact 100% confirmed Cash/UPI, and performs invoice + stock + accounting journal in one transaction. Duplicate post returns the posted invoice without moving stock twice.
- No credit, partial-payment invoice, or UPI-without-verification posting path in the new order system.
- Uses the existing counter sale/stock ledger/journal structures for historical reporting compatibility; every critical state change is audit-logged.

## New DB schema objects
`distributor_price_slabs`, `prepaid_sales_orders`, `prepaid_sales_order_lines`, `prepaid_sales_order_payments`.

Migration occurs through standard WordPress `dbDelta` on plugin activation/upgrade. **Back up before UAT, test data preservation and restore before any Production migration.**

## Code quality
- Source / contract static tests verify new routes, schema, payment gates, review controls, locks and journal/stock call sites.
- Pure PHP regression exercises exact decimal paise, 100% prepayment, pending UPI, overpayments, fail-closed discount policy and configurable Branch/HO escalation.
- PHP 8.2/8.3 CI is mandatory; these tests do NOT substitute for MariaDB transactions or Flutter/browser E2E validation.

## Known blockers — DO NOT MERGE/DEPLOY
1. MariaDB-backed synthetic end-to-end tests, concurrent posting tests, failure rollback, actual invoice/stock/journal reconciliation **not yet run**.
2. GST/tax finalization, credit note/refunds, bank-reconciliation evidence attestation and exception handling require review.
3. Earlier Flutter/PHP compatibility audit still fails. Flutter order UI and customer-facing invoice printing must be integrated.
4. Railway isolated UAT had old WordPress REST rewrite issues and a destructive staged patch; do not apply it automatically.
5. The old legacy counter sale and field-sales flows have not yet been replaced by this order API. New workflow uses distinct endpoints and is NOT globally activated for existing POS screens.
6. Money and quantity snapshots must be tested against live-like stock batch, returns, and approved discount scenarios before business go-live.

This is a **development/staging milestone**, not a finished or production-certified ERP.
