# V8 Canonical Retailer Checkout Preview — v0.9 (2026-10-19)

**State: read-only internal code, no REST route, no staging/production deployment.**

## What was integrated

This slice composes TWO independent existing V8 gates against canonical V7 master/stock records:

1. `CanonicalRetailerIdentity::resolve` — branch/company-authorized retailer link to the existing `eh7_parties` customer, checks active link/status and zero existing customer receivables.
2. `CanonicalV7Readiness::assess` — branch/employee permissions, whole PCS, effective price revision, approved commercial distribution, stock custodian, batch/expiry, live canonical average-cost validation, available chart-of-accounts mappings and open branch/accounting date.

`CanonicalRetailerCheckoutPreview::compose` combines these reads **without** producing any sale, invoice, receipt, payment evidence, stock reservation, GL journal, payroll/points event, or external side effect.

- Output includes canonical party/retailer ID, branch, channel, employee custody, tender mode, price revision and line totals, and `preview_digest` (SHA-256 over the validated visible snapshot).
- Never includes COGS, GL IDs, purchase cost, or Salary Fund distribution in the public preview.
- Always outputs `posting_allowed=false`, `stock_reserved=false`, `requires_locked_revalidation=true` and `payment_verification_status=not_verified_by_preview`.
- **Preview digest is NOT an authorization token or payment proof**; server must re-read and lock stock, pricing, retailer status and payment proof during final posting.
- Cash OR UPI as a single full tender is the approved current B2B policy. Split tender not assumed.
- Statutory invoice/GST/HSN policy remains pending owner signoff; preview cannot be used as a taxable invoice or quotation promise.

## Trust boundary

The `trusted` PHP argument MUST come from a server-side actor resolver and authorized scope; it must not be constructed directly from a browser's client-claimed actor/company/employee. Field cashier role and payment proof are NOT asserted here.

Both readers are read-only. The WordPress bridge is not registered as a REST API. Canonical source records can change between preview and purchase; final writer must perform ALL gates inside its own database transaction. The branch/accounting lock, payment-consumption, reversal/refunds, and unique source journal registration remain unimplemented.

## Verification

```
php -d zend.assertions=1 -d assert.exception=1 v8/backend/tests/canonical_checkout_preview.php
```

17 isolated fake-source regression tests, including identity denied, other branch, open AR, closed period, stock shortage, malformed commercial price, underpayment, unsupported split tender, digest change, field custody and no sensitive finance fields in UI preview. **No actual WordPress/PDO database was used** in these 17 tests.

Next owner-approved work: explicit retailer rate/tax policy, server-created canonical sale intent with validated UPI provider/cash cashier evidence, and ONE authoritative transaction posting both stock and V7 General Ledger. Must not bypass release gates.
