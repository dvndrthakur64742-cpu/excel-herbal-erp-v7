# Excel Herbal V8 — B2B Branch-Day Staging Preflight (Development Only)

## Scope and rationale

The existing disposable MariaDB UAT already posts **one canonical V7 stock
movement and GL journal** for each independently settled Cash/UPI retailer
sale. The previous per-sale `V7B2BCrossLedgerAuditUat` checks the full
invoice, stock, tender, GL and Cash-in-Transit chain.

This milestone adds `V7B2BBranchDayPreflightUat::inspect($actor,$branch,$day)`.
It is a **read-only developer-only check** of the entire authorized branch
business day, rather than a new writer, bank service, payment receipt, ledger,
migration or public REST endpoint.

### What the gate verifies

1. An authenticated accountant with `ACCOUNTING_VIEW` and the exact branch
   can request a business date. Company comes from the authenticated actor.
2. The source is **all** canonical V7 `b2b_retailer_sales` records for the
   company, branch and business date, ordered by primary key.
3. Maximum 250 source sales per run; the query includes a **251st-row
   sentinel**. More than 250 **throws** rather than silently certifying
   only a subset. Invalid/duplicate/out-of-order/cross-branch source rows
   also fail closed. A future pagination/snapshot UAT design is required for
   larger batches.
4. Every sale independently runs `V7B2BCrossLedgerAuditUat`, including
   confirmed original tender, consumed immutable payment/sale intents,
   canonical stock OUT, invoice line arithmetic, COGS and balanced V7 GL.
5. Counter Cash, employee field Cash and UPI sales are counted separately.
   An open employee Cash-in-Transit liability is **not** a false GL mismatch,
   but makes the branch-day result `blocked_unremitted_field_cash`.
6. After a separate authenticated cashier's whole-amount handover, V7 GL
   remittance must balance, one-use receipt must be consumed, and the
   resulting accounting state can become `uat_books_consistent_not_production_certified`.
7. A mismatch in **any one** of the batch's sales blocks the entire batch,
   with explicit per-sale and overall exception codes.
8. Zero sales returns `no_sales_to_assess`, never a success certification.

### Important limitations

This check is an **unlocked, read-only multi-query UAT inspection**; it
does not hold a repeatable-read snapshot or block a concurrent production
writer. The API explicitly sets `snapshot_isolation_guaranteed=false`.
It must **not** be used as an actual posting control or production
balance-sheet signoff without an approved atomic snapshot strategy.

For **all** results, including UAT-consistent results, the following remain
FALSE: physical Cash verified in live ERP, real UPI bank/provider verified,
GST/HSN tax policy approved, reversal/refund policy approved, and
production release authorized. Release blockers are listed explicitly.

The class itself refuses any database except the disposable `v8_test`,
requires the development-only posting gates, and has no WordPress route
or UI entry. It is a testing instrument, not a live ERP module.

### Regression evidence required

- PHP 8.3/8.4 and Windows fake-source tests: empty day, proper role and
  branch scope, duplicate/unordered company rows, 251-row overflow,
  failed query, production refusal, corrupted source header,
  pending/cleared Cash, single mismatched UPI in an otherwise clean batch
- MariaDB 11.4 real `v8_test` test:
  - 1 posted counter Cash sale: UAT-only consistent
  - 2 sales, including employee field Cash: **blocked** until independent cashier handover
  - cashier handover: pending amount clears and valid canonical GL confirms
  - 3 sales including settled UPI: all counted once; still no live bank proof
  - poison a real invoice line inside a rollback-only transaction:
    one inconsistent sale blocks the entire branch-day preflight
- No commits or routes alter production, no PR merge or production deployment

### Next release blockers

Independent real bank/cashier provider connections, GST/HSN invoicing,
approved refunds/reversals, staging WordPress transactional gateway,
mobile role-based regression, explicit Accounts report signoff, full
database migration and rollback rehearsal, and owner's go-live approval.
