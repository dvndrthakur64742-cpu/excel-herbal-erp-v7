# V7 Canonical Retailer Atomic Posting — UAT-only draft

**Status:** no web route, no live schema migration, no provider SDK, no operational approval. This is *not* an integrated production sale workflow.

## Why a single database connection

Earlier v8_test intent/tender prototypes cannot safely post money in a separate WordPress/V7 transaction. If tender consumption commits in PDO but V7 StockService fails in another connection, cash and inventory diverge. The correct writer must lock the immutable sale intent, independently authenticated tender, branch, price, stock and canonical customer **on one InnoDB connection** and commit them together with V7 stock and ledger changes. A status flag alone is not payment verification.

## What is implemented in `V7CanonicalPostingSinkUat.php`

- A draft UAT-only adapter using `ExcelHerbal\ERP7\Database\Transaction::run()` and the actual `StockService::move()` and `AccountingService::post()` APIs. It writes a *single canonical sale source* `eh7_b2b_retailer_sales`, sale lines, V7 stock ledger and V7 journal; never a parallel `v8_b2b_journal`.
- Holds a company financial period lock, idempotency row lock, and closed-period/branch-day checks. Uses the existing `eh8_retailer_party_links` classification pointing at `eh7_parties`, and rejects customers with old outstanding V7 credit.
- Requires a trusted internal `lockedReader` to return fresh revalidated V7 assessment, stored immutable quote and independently verified tender, **already row-locked on the same wpdb connection**. This callback has **not** been implemented for a real WordPress installation. An API request/preview/typed UTR cannot substitute for it.
- Uses current V7 moving-average stock cost, checks it matches the quote's locked cost before committing, tags *field Cash-in-Transit* journal line to the employee, and consumes one payment evidence record in the same transaction. Failure must roll back **all** side effects, including stock, journal, sale and tender consumption. A cashier remittance remains a later, independent event.
- Distinct audit records and an explicit B2B journal source map need a **proposed** `AccountingService::sourceTable` mapping `b2b_retailer_sale` to `b2b_retailer_sales` in development (see paired branch edit); the approved source schema is NOT in live V7 Schema.

## Permanent fail-closed release guard

`assertNonProductionEnvironment` requires *all* explicit approvals (none are supplied), WordPress environment `development`, safe WordPress prefix and **actual SQL `SELECT DATABASE() = v8_test`**. Any live WordPress database is rejected even if someone accidentally enables a config flag. The draft DDL is in `009_v7_canonical_retailer_posting_DRAFT.sql`, not a migration runner; running it on office.excelherbal.in is forbidden.

## Missing before production

The server-side `lockedReader` and trustworthy tender ingestion need to be built; immutable quote snapshot and date rechecks must be verified against real V7 row locks; HSN/GST, discount, invoice numbering, refund/reversal and remittance accounting must be approved. Use real MariaDB single-transaction and concurrent retry UAT. `php -l` and fake-DB regressions prove only local correctness, **not** durable MariaDB/WordPress behavior. This code may not be bound to a live REST endpoint, deployed, or its development feature guard lifted.
