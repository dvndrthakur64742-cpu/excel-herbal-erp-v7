# Excel Herbal ERP V8 — Isolated Development Foundation

**Created:** 2026-10-17  
**Repository base:** `codex/office-dev-approved-deploy-20261017`  
**Development branch:** `codex/erp-v8-foundation-20261017`  
**Stage:** first vertical slice (PHP domain/persistence-port + isolated tests), **NOT a deployable ERP**.

## Sources and precedence

1. Explicit owner decisions: retailer B2B = shopkeepers, **immediate complete Cash OR UPI payment, NO credit**; GPS duty 10:30–17:00 automatic and employees cannot manually start/stop; employee home shows only own sale/performance points, no monetary prices.
2. Owner's BRD: `Pasted text.txt`, dated 17 October 2026, is a requirements proposal, **not fully approved**; its 09:00/18:00 manual attendance contradicts #1.
3. Clean V7 repository services: business/accounting precedent (commercial split, double-entry journals, stock custody, maker-checker).
4. Uploaded Enterprise v14 ZIP: legacy *reference*, not an approved runtime or migration source.

## What has actually been built in V8 first slice

- `backend/src/B2B/RetailerCashSale.php`: typed business service, gateway contract and integer-paise money controls.
- Only `retailer` parties; one full Cash **or** UPI payment; no credit, partial, split, cheque or unverified tender.
- Server-owned price lookup and four-way price allocation integrity; independent `purchase_cost` (4-decimal total valuation).
- Branch vs employee custody, whole pieces, duplicate line rejection, no negative stock, original price/cost snapshots.
- **Retailer outstanding = 0** and separate **employee cash-in-transit liability** for field cash.
- Balanced abstract journals, idempotency request fingerprint, atomic persistence boundary, guard against unauthorized branch/employee actions.
- No points/salary incentive posting until the owner approves B2B points rules.
- `backend/tests/run.php`: isolated fake-gateway regression tests (no external database, no live API).

## Tests

```bash
php -l v8/backend/src/B2B/RetailerCashSale.php
php -l v8/backend/tests/run.php
php -d zend.assertions=1 -d assert.exception=1 v8/backend/tests/run.php
```

## What is **not** complete

**This is NOT ready for use by real customers/employees.** Not yet wired to WordPress/Flutter, MariaDB transactions, REST APIs, retailer registration UI, invoice tax/GST, receipt verification providers, authenticated backend role resolver, branch closing, physical stock locks, print/export or production cash drawer. The `RetailerSaleGateway` is an interface; a durable DB adapter must enforce UNIQUE idempotency and `SELECT ... FOR UPDATE` in an ACID transaction. The included fake gateway is for tests only, and does not establish concurrency safety. Journal account codes are design placeholders until approved chart of accounts / tax policy. Do not register routes or enable automatic deployment.

## Owner decisions to finalize before production integration

- GST/tax-inclusive vs exclusive price, invoices, HSN, applicable compliance and returns/refunds;
- Retailer rates, bulk discounts, relation to V7 50:50 wholesale allocation;
- B2B performance points and salary fund attribution;
- Whether Cash + UPI may be mixed on the same invoice (currently **blocked**);
- Employee unsold stock: same-day return vs carry-forward;
- Attendance manual policy (BRD conflict) distinct from GPS duty.

## Next source implementation gates

1. Real business/customer/retailer schema and WordPress secured gateway with atomic postings; exact account and tax decision.
2. Branch/custody stock/batch locked posting; correction/returns/refund; reconciliation plus MariaDB integration tests.
3. Employee 360°, Retailer Ledger, Management/Sales Register and safe read-only reports.
4. Flutter UI with authority-based screens, physical-device GPS tests and complete UAT.

**No database migration, existing V7 modification or deployment is part of this foundation.**