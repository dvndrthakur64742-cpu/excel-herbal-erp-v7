# V8 Retailer B2B ↔ Canonical V7 Mapping: Read-only Phase

**Stage:** 2026-10-19 read-only development assessment. **No approved live posting or migration.**

## Identified canonical V7 sources

| Business entity | V7 canonical table / existing service | V8 mapping rule |
|---|---|---|
| Company/branch | `eh7_companies`, `eh7_branches` | Scope by company/branch from server authentication; branch active |
| Field employee | `eh7_employees`, branch authority / Guard | Employee active; branch/hierarchy permission must be enforced by trusted caller |
| Product | `eh7_products`, `StockService::product` | Company product active, whole PCS, real `batch_tracking`/`expiry_tracking` policy |
| Effective selling price and split | `eh7_product_commercial_revisions`, `StockService::commercial` | Latest active effective revision, split equals sale price; no client price or unapproved retailer discount |
| Batch | `eh7_batches`, `StockService::validateBatch` | Same company/product; active, expiry-valid |
| Stock | `eh7_stock_balances` | Exact company+branch+product+batch_key+custodian_key, no cross-bucket aggregation |
| Stock movements | `eh7_stock_ledger`, `StockService::move` | **Canonical writer only**; do not simultaneously write V8 preview movements |
| Cost of goods sold | `eh7_stock_balances.average_unit_cost` | V7 stock-move valuation is **not** equivalent to commercial `purchase_cost`; block zero/missing valuation if nonzero purchase cost |
| Finance accounts | `eh7_accounts`, `AccountingService::accountByCode` | Resolve company-owned actual account IDs and validated types, never placeholder journal strings |
| GL | `eh7_journal_entries`, `eh7_journal_lines`, `AccountingService::post` | **Canonical writer only**; requires newly supported journal source and existing company/period locks |
| Period and business-day close | `eh7_accounting_periods`, `eh7_branch_closings` | Read-only preflight; must re-check **under transaction lock** before posting |
| Customer | `eh7_parties`, `eh7_counter_sales` | **Not yet mapped**: V7 party `customer` is not yet a typed B2B retailer; do not silently merge customers |
| Field Cash responsibility | V8 preview `v8_b2b_employee_remittance` | **Not yet mapped**: need canonical cash-in-transit Chart of Accounts and settlement source |

## Deliverable in this step

- `CanonicalV7Readiness.php`: read-only side-effect-free preflight against a constrained `V7CanonicalReader` interface. Validates authorized server scope, active company branch and employee, branch/accounting closes, whole-PCS stock custody, product/batch and expiry, effective commercial split, available stock valuation, paid-in-full Cash OR UPI, and company-owned account codes.
- `WpV7CanonicalReader.php`: read-only WordPress `$wpdb` implementation against `wp_prefix + eh7_` tables, requires a trusted caller-provided **authorization callback**, does not register any WordPress route or update records.
- `canonical_readiness.php`: isolated fake data tests (including a `$wpdb` SQL read-only spy). **This is not a live V7 database integration test.**

## Architecture constraints for actual posting (BLOCKING)

1. The existing `AccountingService::sourceTable()` does **not** accept a retailer B2B sale source. Introduce a complete canonical source registration and reversal model after approval, not an unreferenced manual GL row.
2. V8's existing `MariaDbRetailerGateway` writes isolated `v8_b2b_*` preview sale/stock/journal tables. Those are **test fixtures**; they cannot coexist as a second inventory or GL book of record.
3. Design one **atomic** transaction with protected idempotency record, trusted verified tender single-use consumption, canonical sale/invoice, stock (custodian) deduction, balanced canonical GL, and cash-in-transit liability. Roll back all on any exception.
4. `BRANCH_CASH`, `UPI_CLEARING` and `EMPLOYEE_CASH_IN_TRANSIT` are **proposed V8 labels**. Only actual approved V7 Chart-of-Accounts IDs can be posted; do not guess that those codes exist.
5. Field Employee receiving Cash settles **Retailer balance immediately** but owes Branch until authorized Cash deposit. This is not customer credit.
6. Tax/GST/HSN and retailer price/discount are **not yet approved**. A preflight amount is not an invoice and must not create a statutory sale.
7. Actual WordPress REST and Flutter screens, trusted Cash/UPI verification, refunds/reversals, RLS/branch authority, real MariaDB tests, concurrent transactions and successful CI are **not demonstrated** by this phase.

## Explicit release gate

`CanonicalV7Readiness::assess()` always returns **`posting_allowed=false`**, even after all read-only checks succeed. The caller has no operation capable of posting. The result is a **mapping assessment**, never authorization or proof of an operational integration. V8 preview schemas must never be applied to `office.excelherbal.in`.


## Atomic canonical posting: new contract, not an enabled writer (2026-10-19)

`CanonicalRetailerAtomicPosting` specifies the required transaction order, for a future
trusted V7 adapter **once authorized by the owner**:

1. `BEGIN`, lock unique request/idempotency key; exact replay returns the original receipt.
2. Enforce deployment release gates; verify actor, company, branch and canonical Retailer party.
3. Lock/re-read accounting period, branch day, product/batch, effective pricing and the EXACT
   stock custody buckets. Do not reuse read-only preflight counts for debit/credit posting.
4. Build deterministic whole-PCS sales/COGS and balanced GL lines using canonical account IDs.
   The field Cash debit belongs to Employee Cash-in-Transit, never Retailer Receivable.
5. Consume **one-use, server-confirmed** Cash/UPI receipt (no employee reference/screenshot only).
6. Insert one canonical Sales source, move stock once with canonical StockService, post one
   registered source journal with AccountingService, and finalize the source/idempotency receipt.
7. Commit. Any exception must roll back ALL above writes including consumed tender evidence;
   on retry, a different payload for the same key MUST be rejected.

### Deployment blockers

There is currently **no concrete `CanonicalPostingGateway` for WordPress**, and there is no
registered B2B `AccountingService::sourceTable` type, no canonical retailer-party migration,
no finalized statutory invoice/GST or B2B price policy, no production trusted tender verifier,
and no approved reversal/refund workflow. The read-only `posting_allowed=false` preflight stays.
The 32 tests use a fake transactional gateway to prove control flow, **not real InnoDB locks**.

Do not attempt to wire the preview `MariaDbRetailerGateway` as the concrete V7 writer: it
would create a duplicate stock/finance source. These release blockers cannot be waived by a
request flag or by passing the fake gateway to production.
