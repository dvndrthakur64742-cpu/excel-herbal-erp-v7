# V8 v0.11 — Immutable Quote Lines + Canonical Revalidation (BUILD / UAT ONLY)

**Date:** 2026-10-19. **Status:** implemented in development source, production posting disabled.

## Gap closed

V8 v0.10 persisted an immutable quote **digest and invoice total**, but not the full priced product lines or business-local datetime in the database. That was insufficient to reconstruct and independently verify the exact batch, quantity and commercial price revision at eventual stock and ledger posting.

The UAT-only `007_immutable_sale_line_snapshots_UAT.sql` adds two persistent tables:

- `v8_b2b_sale_intent_lines_uat`: one ordered row per product/batch, including quantity (whole PCS), commercial revision, unit price in paise and line total in paise. Unique sale/batch. No double allocation.
- `v8_b2b_issued_sale_context_uat`: persisted business-local datetime and copy of priced quote digest associated with the issued sale-intent ID.

`PdoImmutableRetailerIntentGateway::createPair()` inserts **sale header, business time, line snapshots, payment intent, payment link and idempotency receipt in one InnoDB transaction**. Failure in any INSERT rolls back everything. The existing-pair path now reads the persisted lines and business datetime with `FOR UPDATE`; `ImmutableRetailerIntentIssuer::assertPair()` verifies the *actual saved rows* against the same server-generated preview, rather than trusting only the original digest.

`CanonicalQuoteSnapshotRevalidation::compare()` is a pure fail-closed integrity check of **persisted issued header + saved priced lines + reserved verified tender + newly assessed canonical V7 price/stock and current retailer/customer identity**. It refuses stale commercial revisions, batch changes, different price/quantity, crossing branch or custodian, partial payment, wrong proof source, bad digest, and consumed tender. It does not trust a browser-provided price or `payment_verified` value. It returns `posting_allowed=false` and `stock_reserved=false` in all successful results.

## Critical accounting/integration distinction

1. **The UAT line snapshot is NOT a stock reservation**; stock may be sold or become expired. Future final posting must re-evaluate price, stock, batch, employee custody, and day/accounting locks **within the SAME transaction** used for sale, stock movement and GL journal.
2. **Cash custody is not cash remittance.** Verified field cash remains an employee responsibility until the cashier confirms deposit. Retailer outstanding stays zero on a posted fully-paid invoice, but no such production invoice is posted in v0.11.
3. **A quote revalidation check is not a legal tax invoice, payment settlement, official approval or a green CI check**. The statutory GST/tax/HSN/discount policy, verified bank PSP integration, approved B2B accounting source mapping, reversal controls, canonical writer, and full WordPress/Flutter integration are not complete.
4. **Never run UAT schema against live WordPress or an ERP database.** `PdoImmutableRetailerIntentGateway` is hard-locked to the disposable database named exactly `v8_test` and no public route or migration is registered.
5. For existing disposable `v8_test`, apply 007 via the optional `immutable_intent_mariadb.php` test or a controlled non-production migration. Old issued rows (without saved line snapshots) fail closed and must be discarded in the test database, never silently converted.

## Verification

From the repository root:

```sh
php -d zend.assertions=1 -d assert.exception=1 v8/backend/tests/immutable_intent_issuance.php
php -d zend.assertions=1 -d assert.exception=1 v8/backend/tests/canonical_quote_revalidation.php
```

`immutable_intent_mariadb.php` also tests saved line rows in MariaDB, but *has not been executed against a real DB from this environment*. The GitHub-hosted Linux PHP/MySQL CI and Windows self-hosted PHP toolchain remain independent gates. **Local regression suite: 277/277 PASS** (existing 235 + 14 extra immutable line/date tests + 28 quote revalidation tests). PHP syntax: 35/35 PASS.

**Overall V8 estimate: approximately 15%** until a properly permitted, atomic canonical writer, REST interfaces, role-visibility UAT and other operational modules pass acceptance. PR remains draft and unmerged, production untouched.
