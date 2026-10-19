# Excel Herbal ERP V8 — Isolated Development Foundation

**Updated:** 2026-10-19  |  **Branch:** `codex/erp-v8-foundation-20261017`  |  **No deployment permitted**

## Confirmed owner-approved business rules
- B2B buyers are **shopkeepers/retailers**; field and counter are sales **channels**.
- **B2B-PAY-001:** Full immediate Cash **or** UPI payment; **no credit, partial payments, or retailer outstanding**. Mixed tender has **not** been approved and is blocked in this prototype.
- Retailer settled at ₹0 does NOT erase money held by a field employee: cash remittance to branch is a separate liability.
- Stock issues are not sales; stock cannot go negative; warehouse and employee custody are separate.
- GPS route duty auto 10:30–17:00 with no manual start/stop. Employee dashboard must show own sales/points only and hide prices.
- Product commercial split: Sale Price = HO Amount + BM Profit + Salary Fund + Office Expense. Purchase Cost and Points remain separate.

## What is in this build
- `backend/src/B2B/RetailerCashSale.php` — stable sale domain service (validated full tender, custody/stock, money in paise, balanced abstract journal, dedup key, price snapshots).
- `backend/src/B2B/RetailerMaster.php` — registration and read model with branch-scoped gateway, optional mobile/GSTIN and registration idempotency.
- `backend/src/B2B/RetailerApi.php` — framework-independent controller. It binds company/branch/actor from **trusted authenticated caller arguments**, drops client claims and never exposes internal fingerprints. **It does NOT register HTTP endpoints.**
- `backend/src/B2B/MariaDbRetailerGateway.php` — real transactional PDO/InnoDB adapter for isolated V8 preview tables. Unique idempotency, SELECT FOR UPDATE and guarded stock decrement, single-use trusted tender, sale/line/stock/journal/retailer statement/employee cash remittance all committed together. Backend AUTHZ callback is required and must deny unauthorized actor/branch/employee.
- `backend/schema/001_b2b_preview_mysql.sql` — BUILD/UAT schema for development fixture only, **NOT production migration**. Preview product and stock tables intentionally stand alone; integration with canonical V7 data requires separately approved mapping/migration.
- `backend/tests/run.php` — 25 isolated domain/unit tests including overflow protection.
- `backend/tests/retailer_flow.php` — 11 retailer registry/API flow tests.
- `backend/tests/mariadb_integration.php` — sale AND cashier remittance integration checks requiring a disposable database exactly `v8_test`.
- `backend/src/B2B/EmployeeCashRemittance.php` — full cashier-confirmed field Cash deposit: Retailer remains paid; Employee Cash-In-Transit is cleared into Branch Cash. No partial-remittance policy assumed.
- `backend/src/B2B/EmployeeRemittanceApi.php` — trusted-context cashier adapter, not an HTTP route, cannot mint its own payment evidence.
- `backend/src/B2B/MariaDbEmployeeRemittanceGateway.php` — isolated UAT InnoDB persistence with locked receipt, unique settlement per sale, balanced reclassification entries and idempotent posting.
- `backend/schema/002_cash_remittance_uat.sql` — preview remittance tables, NOT a production migration.
- `backend/tests/cash_remittance.php` — 18 remittance and API boundary regressions.
- `.github/workflows/v8-foundation-ci.yml` — lint, isolated tests and disposable MariaDB 11.4 job; **NO deploy action**.

## Run isolated tests

```sh
find v8/backend -name '*.php' -print0 | xargs -0 -n1 php -l
php -d zend.assertions=1 -d assert.exception=1 v8/backend/tests/run.php
php -d zend.assertions=1 -d assert.exception=1 v8/backend/tests/retailer_flow.php
php -d zend.assertions=1 -d assert.exception=1 v8/backend/tests/cash_remittance.php
```

Current local verification (re-run required after each code change): **25/25 domain + 11/11 retailer + 18/18 remittance tests PASS; MariaDB integration SKIPPED** because local PHP lacks `pdo_mysql` and no disposable DB is configured. GitHub Actions jobs have not yet produced executed steps in the observed attempt, so a green CI result is not established. The integration script SKIPs without `V8_TEST_DSN`. The GitHub CI job is configured with an ephemeral MariaDB 11.4 container. Local PHP environment might not include `pdo_mysql`; do not call MariaDB tests PASS until the CI runner proves them.

## Important safety boundaries
- This does not create a runnable website or deployable WordPress plugin. API class is not wired to `register_rest_route`, authentication, or Flutter.
- **Do not point the preview schema/migration at `office.excelherbal.in`.** Do not copy legacy v14 tables into this V8 schema without a deliberate mapping.
- `v8_b2b_verified_tenders` is intentionally writable only through a separate **trusted** cashier acknowledgment / payment-provider verification process, **not** via B2B endpoints. Such integration has not been implemented. Merely receiving a UPI screenshot/reference must never allow a sale.
- Account codes are placeholders and must map to an approved Chart of Accounts. Tax/GST, HSN, billing, discount/retailer price list and returns/refunds require owner/accounts decisions. Current amounts are basic tax-exclusive preview amounts and must NOT be used to issue statutory invoices.
- `v8_b2b_catalog_preview` and `v8_b2b_stock_bins_preview` are isolated test fixtures: replacing them with the canonical master, branch data, batch FEFO rules and existing employee-custody stock is a release gate.
- Attendance manual policy conflicts with old BRD; do not merge it with confirmed GPS duty rules without a separate owner decision.

## Next steps
1. Run CI MariaDB integration and audit any failures; enforce real concurrency locks with two sessions.
2. Map V8 preview records onto canonical product/branch/warehouse and account masters without duplicate source of truth.
3. Implement signed payment-verification source and refund/reversal flows after relevant policy approvals.
4. Register secured WordPress REST endpoints and Flutter retailer registration/invoice/read-only ledger screens in an isolated UAT instance.
5. Staff role UAT, trial balance and stock reconciliation, backups/restore, physically tested GPS, explicit deployment sign-off.

**Current status: backend development implementation only. No deployment, no production DB migrations, no live transaction access.**

## 2026-10-19 incremental development: field Cash custody closing

- Only field **cash** receipts create an employee remittance obligation. Counter cash and UPI do not. Customer/retailer stays fully paid, never becomes debtor because an employee is holding funds.
- Branch cashier must independently confirm exact amount + sale + employee, bound to company/branch; no screenshot, employee acknowledgement or client-request role is accepted as proof. A separate trusted back-office mechanism to CREATE this confirmation is **not yet implemented**.
- Settling posts DR `BRANCH_CASH` and CR `EMPLOYEE_CASH_IN_TRANSIT` once, with a locked, one-use receipt; journal account strings remain placeholders for future canonical V7/ERP8 Chart of Accounts mapping.
- Until an explicit owner policy approves shortages/partial deposits, full deposit is the only allowed closing; a shortage requires an exception workflow that is **not implemented**.
- No real WordPress REST registration, production DB installation, working POS, canonical stock integration, statutory tax invoice, or deployment has been performed.

## 2026-10-19 incremental development: canonical V7 read-only integration gate

- `backend/src/B2B/CanonicalV7Readiness.php` and `WpV7CanonicalReader.php` read existing **canonical eh7_ product, effective commercial revisions, batch, branch, employee, stock balances and Chart of Accounts**. They **never write** to V7 and register **no REST endpoint**.
- The V7 `StockService::cost()` uses **current stock bucket average unit cost**; the original V8 isolated prototype instead uses commercial `purchase_cost`. This gate explicitly maps and checks the canonical cost before estimating COGS.
- `backend/tests/canonical_readiness.php` adds **28 isolated regressions**; these are not live WordPress/database integration tests.
- Critical live-posting dependencies are still blocked: canonical retailer-party identity, Cash/UPI verification, approved account IDs and tax pricing, supported AccountingService source, atomic stock+GL writer, reversal path, access checks and live MariaDB UAT.
- **`posting_allowed=false` is hardcoded by design.** See `requirements/CANONICAL_V7_MAPPING.md`; DO NOT treat the preflight as a deployed feature.


## 2026-10-19 incremental development: canonical paid-sale atomic posting contract

- `backend/src/B2B/CanonicalPostingContract.php` introduces `CanonicalPostingGateway` (interface),
  `CanonicalPostingPlan` (strict integer-paise/whole-PCS canonical journal mapper) and
  `CanonicalRetailerAtomicPosting` (transaction choreography). A true gateway MUST use ONE
  database transaction and the canonical V7 StockService/AccountingService writer, never the
  preview `v8_b2b_*` stock/GL tables. **No real canonical posting gateway is shipped.**
- `backend/tests/canonical_atomic_posting.php` adds **32 isolated contract tests** using an
  in-memory rollback simulator, including debit/credit balancing, actor/branch scope, unique
  idempotency, tender single-use, locked stock, retry behavior, rollback after stock/GL failures,
  and immutable retailer paid-state. NOT a MariaDB or WordPress integration proof.
- `CanonicalV7Readiness::assess` still always reports `posting_allowed=false`; the new posting
  contract rejects that value. A future locked source gateway may return true only after
  independently approved live release gates, a canonical retailer mapping, a trusted payment
  verifier, a registered canonical GL source, invoices/taxes, reversals and verified transaction
  locks exist. Do not flip a boolean or use an HTTP client flag to bypass those requirements.
- The source code is added to the `v8/` development area only; no runtime registration,
  plugin activation, database migration, merged PR or production deployment.

## 2026-10-19 incremental development: canonical B2B retailer identity (v0.6)

- `backend/src/B2B/CanonicalRetailerIdentity.php` defines a read-only, fail-closed
  **retailer classification → canonical V7 customer party** mapping. Shopkeepers are
  `eh7_parties.type=customer` plus the proposed `eh8_retailer_party_links` classification;
  field/counter remains the sales channel. No duplicate party name/contact/GL master.
- `backend/src/B2B/WpV7RetailerIdentityReader.php` reads the V7 party through the
  exact company/branch constrained join and separately checks existing posted V7 customer
  receivables. Requires server-trusted authorization callback, refuses SQL read failures;
  registers NO WordPress HTTP route and mutates NO database rows.
- `backend/schema/003_canonical_retailer_identity_DRAFT.sql` is an **unapplied migration
  design**, not production SQL. It requires owner-approved and DBA-reviewed activation
  before its table would exist. Until then, real WordPress requests correctly fail closed.
- Canonical atomic posting now requires a positive actual **party ID** from the
  gateway's retailer authorization step, stores it on the sale source alongside retailer
  classification ID, and still refuses real posting via release gates.
- `backend/tests/canonical_retailer_identity.php` adds 17 read-only identity regressions;
  `canonical_atomic_posting.php` now covers party linking and missing-party denial (34
  tests). Total local isolated tests: **133/133** (25+11+18+28+34+17).
- **Still missing**: write-side retailer onboarding/sidecar migration, approved retailer
  rate/GST/invoice policy, trusted tender verification, canonical WordPress atomic writer,
  runtime REST/Flutter connection, real MySQL integration and successful GitHub CI.
  Never interpret this component as an enabled B2B sale.

## 2026-10-19 incremental development: Cash custody and bank-settled UPI intake (v0.7)

- `backend/src/B2B/TrustedTenderIntake.php` implements server-side, fail-closed payment intake from a **server-created locked payment intent**, not from client-supplied amounts, screenshots or verification flags.
- Cash is accepted only by an authenticated, branch-authorized collector: **assigned employee custodian** for Field Cash, or authorized cashier for Counter Cash. WP actor/user ID != employee ID; the trusted authority callback must resolve the mapping. This DOES NOT settle field cash to branch.
- UPI requires a trusted, pre-reconciled bank/PSP result with **settled INR amount, correct destination merchant bank account, matching merchant order and unique bank transaction ID**; a UTR typed by an employee is not verification.
- `backend/src/B2B/PdoTrustedTenderIntakeGateway.php` + `backend/schema/004_trusted_tender_intake_UAT.sql` provide **disposable** PDO/InnoDB persistence of one-time evidence, with cross-branch replay uniqueness. They register no routes, cannot authorize roles by themselves and are not production migrations.
- `backend/tests/trusted_tender_intake.php` adds **30 local isolated fake-gateway tests**. `backend/tests/trusted_tender_mariadb.php` adds separate optional `v8_test` UAT tests; no MariaDB PASS may be claimed without an actual database run.
- **Critical:** the pre-existing isolated sale gateway **does not yet consume these new evidence classifications** because there is no approved canonical sale-intent binding. This is a safety gate, not a completed end-to-end API. `posting_allowed=false` remains intact.
- Local regression total after this change: **163/163** (25+11+18+28+34+17+30), without any actual MariaDB run. GitHub hosted runners previously failed before job steps began; new CI runs must be inspected before claiming CI success.

Detailed trust and missing release gates: `requirements/TRUSTED_TENDER_INTAKE.md`.

## 2026-10-19 incremental development: verified tender linked to immutable retailer sale (v0.8)

- `backend/src/B2B/SaleIntentTenderBinding.php`: server-trusted UAT contract binds **one immutable priced sale intent to exactly one confirmed tender**, checking canonical retailer/party, branch, employee custody, Cash/UPI source, quote digest, amount, merchant order, and replay protection. This is **reservation, not posting**. Response always sets `posting_allowed=false`.
- `backend/src/B2B/PdoSaleIntentTenderBindingGateway.php` and `backend/schema/005_sale_intent_tender_binding_UAT.sql`: disposable `v8_test`-only InnoDB tables and transactional locking. Canonical V7 database is untouched; this adapter refuses any database not named `v8_test`.
- `backend/tests/sale_tender_binding.php`: 29 local fake-gateway regression tests; `backend/tests/sale_tender_mariadb.php`: extra optional disposable MariaDB UAT, which must not be claimed as executed unless an actual database is available.
- Previous 163 local regressions remain; total after this milestone: **192 local tests** (163+29). No hosted CI PASS can be claimed while runners fail to provision.
- **Critical integration caveat:** No server-created canonical checkout route, approved tax/discount/HSN pricing engine, real WordPress gateway, verified bank provider adapter or stock/journal transaction writer exists in this slice. Existing `CanonicalV7Readiness` gate stays `posting_allowed=false`.
- The sale and its immutable payment association must be **created only by a trusted backend**. UAT fixture creates them directly; never derive IDs, totals, merchant order, quote digest or roles from a browser request.

See `requirements/SALE_TENDER_BINDING.md` for release gates and accounting separation.

## 2026-10-19 incremental development: canonical retailer checkout preview (v0.9)

- `backend/src/B2B/CanonicalRetailerCheckoutPreview.php`: composes the existing authoritative V7 retailer/customer identity reader and canonical stock/pricing/period validation into one **read-only, fail-closed** retailer checkout preview.
- Verifies company, branch, actor, linked canonical party, stock custody, whole PCS, product/batch, effective commercial revision, no outstanding/credit, Cash/UPI full total and business date. Returns a preview digest for change detection, not as payment proof.
- Omits purchase cost, COGS, GL IDs and Salary Fund figures from the public-facing preview. Always returns `posting_allowed=false`, `stock_reserved=false`; this is not a GST invoice, credit authorization, receipt or real stock/GL posting.
- `backend/tests/canonical_checkout_preview.php`: **17** new isolated tests; total **209/209 local PHP regressions** (prior 192 +17). No MariaDB runtime UAT or successful hosted/self-hosted runner execution is implied.
- See `requirements/CANONICAL_CHECKOUT_PREVIEW.md`. Canonical writer, statutory tax/rate policy, trusted payment and atomic stock+GL posting remain blocked. **ERP overall engineering estimate remains ~15%.**
## 2026-10-19 increment: server-issued immutable B2B sale/payment intents (v0.10)

- `backend/src/B2B/ImmutableRetailerIntentIssuer.php`: issues a **single priced UAT-only sale/payment-intent pair** from a fresh server-produced canonical checkout preview. Recomputes quote digest; rejects incorrect company/branch, quantity/price, credit, field custody, unapproved states, actor roles and repeat request changes. Result always `posting_allowed=false`.
- `backend/src/B2B/PdoImmutableRetailerIntentGateway.php` + `backend/schema/006_immutable_checkout_intents_UAT.sql`: disposable `v8_test`-only InnoDB pair writer and company-scoped request-key serialization. Writes no V7 customer/stock/finance table and exposes no WordPress route.
- `backend/tests/immutable_intent_issuance.php`: **26 new isolated unit/security tests**; local total **235/235** (209 previous +26). Optional `backend/tests/immutable_intent_mariadb.php` covers paired issuance → cash collection → tender evidence binding, but requires a real disposable MariaDB and **has not been run here**.
- Self-hosted Windows GitHub runner is connected but still cannot execute PHP tests until `php.exe` is installed and on runner service PATH. `ubuntu-latest` jobs also remain blocked. Never represent this increment as successful GitHub CI, invoicing, trusted provider integration, or live canonical stock/GL posting.
- See `requirements/IMMUTABLE_INTENT_ISSUANCE.md`. Overall ERP readiness remains ~15%, because no new operational module has yet passed real WordPress+DB+Flutter UAT.
