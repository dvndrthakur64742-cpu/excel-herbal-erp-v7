# B2B Branch-Day REPEATABLE READ Consistent Snapshot — Development/UAT

## Motivation

The previous independent `V7B2BBranchDayPreflightUat` audited every posted
B2B retailer sale, StockService OUT ledger, signed payment intent, canonical GL
and independent Cash handover. It correctly reported
`snapshot_isolation_guaranteed=false`: its separate SQL reads can otherwise
observe commits from different points in time.

This milestone adds **`V7B2BConsistentSnapshotUat::inspect`**. It is a
**development-only read-only wrapper** around the *existing* branch/day
preflight, not a second financial posting engine.

## Transaction protocol and fail-closed checks

- Requires development-only V7 canonical UAT gate and **actual** database
  `v8_test`. No live WordPress REST route or release flag is provided.
- Requires `ACCOUNTING_VIEW`, effective company and branch authorization.
- Requires the **identical PDO object** used by the canonical V7
  `Db::wpdb()->pdo` adapter; refuses a different database connection even
  if both connect to `v8_test`.
- Requires PDO MySQL with exception-mode errors and an idle connection. It
  **refuses to nest** inside someone else's existing transaction.
- Queries `information_schema.TABLES` before beginning and verifies **all
  14 source tables** used by the combined V7/V8 audit exist and use
  **InnoDB** (including staging sale/payment intents and cash receipts).
  MyISAM/missing tables cannot receive a false MVCC guarantee.
- Executes `SET TRANSACTION ISOLATION LEVEL REPEATABLE READ` followed by
  `START TRANSACTION WITH CONSISTENT SNAPSHOT, READ ONLY`. The complete
  branch/day source and every per-sale journal/tender read then happen on
  the **same connection and snapshot**.
- Ends with **ROLLBACK even on success**; in any failing case, attempts to
  roll back and propagates the error. Does not leave a transaction active
  after a successful response.
- Only after successful rollback and result contract verification, reports
  `snapshot_isolation_guaranteed=true` and
  `snapshot_boundary=mariadb_innodb_repeatable_read_consistent_snapshot`.
- The 250-sales/251st-row overflow gate, company/branch authority, false
  financial-verification disclosures and UAT-only production blockers from
  the existing preflight are retained unchanged.

This is a **transactionally coherent staging view**, not a guarantee that
the database will remain unchanged after the snapshot ends. It is still
possible for an independent writer to commit *after* the inspection. No
production ledger posting or cashier process is authorized by the result.

## Real concurrent MariaDB regression

Use two distinct PDO connections to disposable `v8_test`:

1. Post actual V7 canonical Counter Cash, Field Cash (with independently
   verified cashier handover), and UPI sales through the previous UAT writer.
2. Verify complete 14-table MVCC snapshot returns an internally consistent
   result, branch-sale counts and **still never claims live bank or Cash
   provider verification**.
3. Check wrong-PDO and nested transaction attempts are rejected without
   touching the existing caller's transaction.
4. Start a consistent snapshot, then use a second PDO connection to **COMMIT
   a tampered invoice-line amount**. The original snapshot remains internally
   consistent. Outside that snapshot, the current branch/day audit must show
   `blocked_ledger_mismatch`. A **new** consistent snapshot must also
   report the mismatch.
5. Restore the test row in `finally`; ensure original source books and
   transaction state are intact.

## Approval gates still blocked

This engineering step does **not** approve GST/HSN invoicing, discount
policy, refunds/credit notes, reversals, a production bank gateway, real
cashier proof, WordPress production migration, mobile-device UAT, or
financial go-live approval.

**No production deployment or Draft PR #25 merge.** This utility has no
automatic write, notification or public REST path.
