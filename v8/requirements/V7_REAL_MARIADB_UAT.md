# Real V7 Stock/GL MariaDB transaction UAT — development-only

This test is deliberately isolated to the exact database **v8_test** and WordPress development-mode stubs. It does NOT register any route, apply any production migration, run against a live ERP database, or establish statutory GST/HSN/reversal readiness.

**What it tests:** canonical V7 `StockService::move`, `AccountingService::post`, `NumberSeries::next` and V7 `Transaction::run` using a single PDO-backed minimal wpdb adapter, not mocked stock or journal services. Original V8 issued sale/payment intents, quote lines, tender reservations, evidence and canonical source are written to the same disposable MariaDB, with explicit test-only approved gates.

**Assertions:** posted canonical sale and balanced journal; one stock OUT; source/tender/payment/reservation finalization; idempotent replay; journal insertion failure rolls back stock, sale header, evidence and idempotency key.

**Limitations:** synthetic test fixtures manually construct the independently confirmed cashier/payment proof; this does not constitute an authenticated PSP/cashier production bridge. Not a real WordPress bootstrap, Flutter device test or multi-connection concurrency test. All financial and statutory release gates remain CLOSED outside UAT. Real MariaDB PASS must be verified by the latest GitHub workflow before claiming success.

**CI file:** `.github/workflows/v8-foundation-ci.yml`, isolated MariaDB job.

## Expanded Cash/UPI journal custody scenarios

The same real MariaDB test now also checks Field Cash taken from employee-custodied stock, tagged to the employee and debited into `EMPLOYEE_CASH_IN_TRANSIT` without implying cashier remittance; and separately verifies a provider-evidence fixture for UPI is booked to `UPI_CLEARING` rather than cash. These are **manually constructed disposable test fixtures**, not a real bank or cashier webhook. Local PHP syntax check passed; MariaDB runtime evidence must be taken from the exact commit's GitHub Actions job. Test count: 20 assertions in the real canonical V7 service transaction scenario.

## Real two-session MariaDB locking / concurrency tests (v0.20)

The existing canonical V7 service integration test now creates a **second independent PDO database session** holding a real InnoDB `SELECT ... FOR UPDATE` row lock on an immutable sale intent while the primary V7 Stock/GL writer attempts to post. It intentionally reduces the primary session's `innodb_lock_wait_timeout` to one second. The blocked writer must fail atomically without leaving sale, stock or payment mutations; after releasing the lock, a single posting succeeds and the same issued tender cannot be reused with a different idempotency key. A second test holds an uncommitted unique checkout key in another session and verifies the conflicting writer cannot post; after rollback of the conflicting session, the legitimate writer succeeds and replays idempotently. Adds **10** real concurrency checks (20 → **30** total checks in this test). These are deterministic *two-connection lock contention tests*, not two workers simultaneously completing a posting; a distinct load/race stress test remains needed before production. The test operates only on disposable `v8_test` and does not install production schema.

## v0.21: automatic V8 evidence-to-canonical tender bridge (UAT only)

The real-service MariaDB test no longer hand-inserts `wp_eh7_b2b_verified_tenders`. The locked reader now promotes validated original tender/intake evidence into the canonical V7 tender table **inside** the existing `Transaction::run`, then the V7 writer consumes it alongside V8 states. Newly added evidence checks: absent preseeded canonical proof, correct one-time creation, rollback of promoted proof on journal failure, rejection of conflicting reservation verified-source, and Field Cash / UPI source preservation. **37** real MariaDB UAT assertions after +7 (formerly 30). All evidence originates from synthetic disposable UAT fixtures, not a live bank SDK or cashier callback; no REST endpoints or production deployment.

## v0.22: real guarded V8 tender intake through the canonical bridge

The disposable MariaDB scenario now uses the **actual** `TrustedTenderIntake` + `PdoTrustedTenderIntakeGateway` to create original Cash/UPI confirmed evidence, rather than hand-seeding `v8_b2b_verified_tenders` and `v8_b2b_tender_intake_evidence_uat`. Field Cash collection is attributed to the field actor, Counter Cash to a separate cashier actor, and UPI settlement to a distinct synthetic bank-verifier actor with exact amount/order/merchant checks. The existing `V7UatCanonicalTenderBridge` then promotes the confirmed row and the V7 writer posts Stock/GL atomically. Adds two assertions (37 → 39). **All actor/bank callbacks are hard-coded disposable UAT fixtures, not real bank or WP authentication.** Statutory and release gates remain CLOSED.

## v0.23 — HMAC-sealed internal bank-reconciliation read boundary (UAT ONLY)

`SignedBankReconciliationLookupUat` reads a **separate, internal bank-reconciliation feed** through the same PDO MariaDB transaction as the original locked payment intent. It accepts *only* `v8_test`; validates an explicit 256-bit-or-longer backend key from an injected server key resolver; binds a fixed ordered canonical payload including company, branch, lookup, status, INR amount, merchant, original order, bank transaction ID, key ID and UTC observation timestamp; uses constant-time HMAC-SHA256 comparison and a strict maximum evidence age of 48 hours / future clock tolerance of 5 minutes. It returns no verified payment for absent/expired/tampered/unknown-key evidence. The `TrustedTenderIntake` service additionally enforces signed company/branch scope when the signed adapter returns those fields. MariaDB enforces one payment reference per merchant account.

**Critical scope limitation:** the test fixture itself signs rows with a synthetic key. An external authenticated bank/PSP reconciliation worker, safe key custody/rotation, bank-provider API verification, independent cashier role mapping, real WP authentication, GST/HSN and reversal approvals, and real payment-reconciliation deployment are NOT implemented by this patch. Never accept browser-submitted signed rows or let sale actors hold signing keys. No public REST route or automatic migration. `010_signed_bank_reconciliation_UAT.sql` is disposable-only. GitHub hosted MariaDB job must pass before this stage is called verified.
