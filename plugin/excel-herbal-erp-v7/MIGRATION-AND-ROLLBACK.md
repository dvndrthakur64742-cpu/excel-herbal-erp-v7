# Database migration & rollback notes — 7.3.6-rc1

Preflight: full database snapshot and restore test; compare current `eh7_schema_version`, live `daily_requests`, `evening_settlements`, and any custom extensions.

When activated on staging, `Schema::maybeUpgrade` runs `dbDelta` for definitions and `ensureColumn` for optional columns. Existing `eh7_*` tables and rows remain. The new table is `wp_eh7_daily_upi_receipts` (actual prefix varies).

No SQL data deletion, `DROP TABLE`, old-voucher rewriting, or `eoe_*` import is performed by the patch. Existing historic `issued` vouchers remain accepted for evening processing. New vouchers require review and receipt confirmation.

Rollback is **not simply reinstalling older code** after new-style vouchers have been created. Old clients and older plugin versions may not recognize `reviewed` / `awaiting_receipt` statuses. Roll back using a restored staging-validated database snapshot together with its matching plugin/frontend version, or plan an explicit forward-fix migration.

No destructive SQL migration is supplied. Test restoration first, then monitor failed operations and attendance/stock/finance reconciliation.
