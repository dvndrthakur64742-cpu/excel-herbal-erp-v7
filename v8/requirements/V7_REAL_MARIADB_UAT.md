# Real V7 Stock/GL MariaDB transaction UAT — development-only

This test is deliberately isolated to the exact database **v8_test** and WordPress development-mode stubs. It does NOT register any route, apply any production migration, run against a live ERP database, or establish statutory GST/HSN/reversal readiness.

**What it tests:** canonical V7 `StockService::move`, `AccountingService::post`, `NumberSeries::next` and V7 `Transaction::run` using a single PDO-backed minimal wpdb adapter, not mocked stock or journal services. Original V8 issued sale/payment intents, quote lines, tender reservations, evidence and canonical source are written to the same disposable MariaDB, with explicit test-only approved gates.

**Assertions:** posted canonical sale and balanced journal; one stock OUT; source/tender/payment/reservation finalization; idempotent replay; journal insertion failure rolls back stock, sale header, evidence and idempotency key.

**Limitations:** synthetic test fixtures manually construct the independently confirmed cashier/payment proof; this does not constitute an authenticated PSP/cashier production bridge. Not a real WordPress bootstrap, Flutter device test or multi-connection concurrency test. All financial and statutory release gates remain CLOSED outside UAT. Real MariaDB PASS must be verified by the latest GitHub workflow before claiming success.

**CI file:** `.github/workflows/v8-foundation-ci.yml`, isolated MariaDB job.
