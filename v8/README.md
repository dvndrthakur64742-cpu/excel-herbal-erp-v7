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

- `backend/src/B2B/CanonicalRetailerCheckoutPreview.php` combines approved V7 retailer/customer identity and canonical stock/pricing read-only assessments.
- Checks business context, branch authority, active linked retailer party, outstanding=0, whole PCS, effective price revision, correct branch/employee stock custody, full Cash/UPI total, and business date.
- SHA256 `preview_digest` is for stale-quote detection, NOT payment proof. No COGS, GL IDs or Salary Fund are surfaced in the UI-facing result.
- Always `posting_allowed=false`, `stock_reserved=false`, `requires_locked_revalidation=true`. No executable WordPress REST route, financial journal or invoice has been enabled.
- 17 new isolated regression tests; total local PHP regression count: **209/209**. Statutory invoice/tax/HSN policy, trusted payment, locked stock+GL writer, MariaDB UAT and successful CI still remain release blockers.
- Overall V8 completion is approximately **15% (engineering estimate)**, not certified.

See `requirements/CANONICAL_CHECKOUT_PREVIEW.md` for the complete scope and trust constraints.

## 2026-10-19 increment: server-issued immutable B2B sale/payment intents (v0.10)

- `backend/src/B2B/ImmutableRetailerIntentIssuer.php`: issues a **single priced UAT-only sale/payment-intent pair** from a fresh server-produced canonical checkout preview. Recomputes quote digest; rejects incorrect company/branch, quantity/price, credit, field custody, unapproved states, actor roles and repeat request changes. Result always `posting_allowed=false`.
- `backend/src/B2B/PdoImmutableRetailerIntentGateway.php` + `backend/schema/006_immutable_checkout_intents_UAT.sql`: disposable `v8_test`-only InnoDB pair writer and company-scoped request-key serialization. Writes no V7 customer/stock/finance table and exposes no WordPress route.
- `backend/tests/immutable_intent_issuance.php`: **26 new isolated unit/security tests**; local total **235/235** (209 previous +26). Optional `backend/tests/immutable_intent_mariadb.php` covers paired issuance → cash collection → tender evidence binding, but requires a real disposable MariaDB and **has not been run here**.
- Self-hosted Windows GitHub runner is connected but still cannot execute PHP tests until `php.exe` is installed and on runner service PATH. `ubuntu-latest` jobs also remain blocked. Never represent this increment as successful GitHub CI, invoicing, trusted provider integration, or live canonical stock/GL posting.
- See `requirements/IMMUTABLE_INTENT_ISSUANCE.md`. Overall ERP readiness remains ~15%, because no new operational module has yet passed real WordPress+DB+Flutter UAT.

## 2026-10-19 incremental development: immutable quote lines + fresh V7 revalidation (v0.11)

- Fixed a critical v0.10 deficiency: Sale Intent's individual product/batch/quantity/commercial-revision/price rows and business-local datetime now persist alongside the intent/payment pair **inside the same disposable MariaDB transaction** (`schema/007_immutable_sale_line_snapshots_UAT.sql`). An idempotent replay must match actual saved rows; digest alone is insufficient.
- `backend/src/B2B/CanonicalQuoteSnapshotRevalidation.php` compares saved quote and reserved tender against fresh canonical retailer identity and V7 stock/pricing read model, refusing price changes, expired/changed stock context, cross-branch or employee mistakes and tender reuse. This is pure integrity logic, not production posting.
- `backend/tests/immutable_intent_issuance.php`: now **40** cases. New `backend/tests/canonical_quote_revalidation.php`: **28** cases. **277/277 local isolated PHP tests PASS** across 11 suites, **35/35 PHP syntax PASS**.
- Optional MariaDB UAT now checks saved product line persistence, but could not be executed in the present environment; GitHub-hosted runner and Windows self-hosted runner are not PASS.
- Real WordPress API, approved tax invoice, actual V7 StockService and AccountingService atomic writer, trusted PSP settlement and whole-system UAT **remain blocked**. No live deployment, no PR merge, no production DB changes. Overall V8 engineering completion estimate remains ~15%.

Details: `requirements/IMMUTABLE_QUOTE_REVALIDATION.md`.

## 2026-10-19 accelerated integration: employee 360 linked to actual V7 REST service

A **read-only** V7 development REST handler `org.employee_360` was added to the existing V7 route registry/dispatcher, using a real `Employee360Service` backed by canonical V7 daily cycles, posted settlements, performance points, attendance, employee stock and journal party tagging. Employee self/supervisor hierarchy and finance permission gates are server-side. This does **not** modify the employee dashboard and does not imply that all tagged V7 journal entries form a complete Tally-style employee ledger. Regression: 37 tests in `backend/excel-herbal-erp-v7/tests/employee360_regression.php` (separate from V8 B2B tests). Actual WordPress/MariaDB UAT and UI integration remain pending; no deployment. See `requirements/EMPLOYEE_360_READ_ONLY_INTEGRATION.md`.

## 2026-10-19 accelerated V7 Employee 360 detailed registers (v0.13)

- Added a real development-only V7 GET route `organization/employees/{id}/360/register` for `type=sales` or `type=stock` with bounded page/date parameters.
- Sales are assembled per completed Daily Order and **posted** Evening Settlement using group-per-cycle accounting; split cash and UPI are history, NOT proof the employee remitted cash to branch.
- Stock is read from employee-custodied `eh7_stock_ledger` with UTC business-date bounds, no price/cost leakage or inventory mutation.
- Reuses Employee360 company, active session, reporting hierarchy and branch authorization; no new privileges.
- 33 new PHP regression assertions; total prior V8 277 plus previous employee 360 37 plus 33 = **347 isolated tests**. Live WordPress and MariaDB UAT remains unverified.
- The employee dashboard is untouched; employee profile links to these read-only registers, not independent stock/ledger books. No merge or deployment.

See `requirements/EMPLOYEE_360_DETAILED_REGISTERS.md`.


## 2026-10-19 v0.16 — independent physical-cash cashier attestation (disposable UAT)

- New `backend/src/B2B/IndependentCashierReceipt.php` requires server-authorized branch cashier distinct from the field-sale actor, full pending employee Cash, no credit/partial amount, company/branch custody matching and a unique cashier receipt reference. Exact retries return the same receipt; mismatched retries and re-use fail closed.
- `PdoIndependentCashierReceiptGateway.php` writes signed receipt + immutable attestation in **one `v8_test` transaction only**, using schema `008_cashier_attestation_UAT.sql`.
- `MariaDbEmployeeRemittanceGateway::confirmedBranchReceipt()` now checks **signed independent attestation**, not merely the untrusted `verified_source='cashier'` field. Missing signature prevents remittance even if a receipt row was manually forged.
- `backend/tests/mariadb_integration.php` now uses the actual independent signer rather than inserting privileged receipt evidence with raw SQL; also verifies unsigned receipt rejection. An actual MariaDB UAT run is still required; the local environment does not have `pdo_mysql` or a disposable database.
- `backend/tests/independent_cashier_receipt.php`: 20 new isolated security and lifecycle tests. Old local regressions 387, new total **407 isolated checks**, no actual MariaDB PASS claimed. No WordPress REST endpoints, migrations, production writes or merging.
- This **only closes the cashier receipt attestation gap for the isolated V8 UAT**. Canonical V7 accounting integration, sale/source registration, tax decision, branch Cash/Employee Cash in Transit postings and reversals remain owner-approved release gates. V7 currently books evening Cash directly to cash; do not double-count it as new cash on remittance.

## 2026-10-19 same-connection canonical V7 stock/journal writer (v0.17)

- New `backend/src/B2B/V7CanonicalPostingSinkUat.php` is a strict **UAT-only, non-production** adapter to the actual V7 `Transaction::run`, `StockService::move`, `AccountingService::post` APIs and a *single canonical* B2B sale source. No parallel stock/GL.
- Development V7 AccountingService source whitelist now recognizes `b2b_retailer_sale` (target `eh7_b2b_retailer_sales`); new source table is defined in an **unapplied** disposable `v8_test` DRAFT schema. No WordPress routes or schema installer.
- Checks immutable line-level quote digest, original price revisions, authorized retailer/canonical customer, legacy credit, actual DB `v8_test`, accounting period, branch close, exact trusted tender, company+actor-bound idempotency, effective V7 stock cost and balanced GL. Field Cash tags employee-to-remit journal line, without falsely treating cash as cashier-deposited.
- 34 new PHP fake-DB/rollback tests, previous 407 local regression checks => **441/441 local checks** in the combined development tree. **No real WordPress or MariaDB write UAT has run.**
- The WordPress trusted same-DB lock/read service, verified PSP/cash source, GST/HSN/discount policy and reversal/remittance rules **remain missing**. The guard will not run on production, and no live DB migration is performed.
- See `requirements/V7_CANONICAL_ATOMIC_WRITER_DRAFT.md`. No deployment or PR merge.

## 2026-10-19 same-database locked V7 sale/payment evidence bridge (v0.18)

- `v8/backend/src/B2B/V7UatLockedCheckoutReader.php` is a concrete **development-only** callback for the v0.17 guarded canonical writer. It reads issued immutable sale lines, business timestamp, linked payment intent, reserved confirmed tender, independent attestation, canonical proof and **fresh V7 price/stock/accounts** under `SELECT ... FOR UPDATE` on the same wpdb connection.
- Supports Field Cash (employee custody), Counter Cash (cashier), and bank-confirmed UPI; exact amount, unique intent, employee/branch, quote digest and approval-source checks. It performs **no writes** itself.
- Draft schema `009_v7_canonical_retailer_posting_DRAFT.sql` now includes the missing immutable proof linkage and currency/status/attestor fields; **do not apply on production**. Independently authenticated PSP/cashier source that populates the canonical tender bridge is still missing, as are statutory GST/HSN/tax, reversal and real concurrent MariaDB/UAT signoff.
- **46 new fake-wpdb regressions PASS** (previous 441 +46 = **487 local isolated checks**). No success claim for GitHub-hosted MariaDB, Windows runner PHP or Flutter. Writer release gates stay closed and there is no REST registration.
- See `v8/requirements/V7_SAME_DB_LOCKED_PAYMENT_READER_UAT.md`.

## v0.19 — Cross-ledger atomic finalization (UAT-only; no production deployment)
The V7 same-DB B2B writer now consumes **both** canonical `eh7_b2b_verified_tenders` and original `v8_b2b_verified_tenders`, transitions the reservation + payment intent to `consumed`, and marks the sale intent `posted` in the same V7 stock/GL transaction. All row updates must affect exactly one matching original row; otherwise the sale, stock and journal roll back. The locked reader rejects already-consumed payment intents. 43 canonical-writer and 47 locked-reader isolated regressions pass; **497 combined local checks** including existing Employee360 V7 suites, but MariaDB/WordPress UAT and Flutter tests remain unverified. Details: `requirements/V7_CROSS_LEDGER_FINALIZATION_UAT.md`. External trusted PSP/cash ingestion and owner tax/reversal approvals remain blocking.

## 2026-10-19 real canonical V7 same-DB MariaDB UAT (Step 2)

Adds `backend/tests/v7_canonical_real_mariadb.php` (relative to `v8/`) to the disposable MariaDB CI job. Exercises **actual V7 services**, not a fake stock/GL adapter, including success/replay and forced journal-failure rollback. Full evidence/status transitions on the same connection. Tests run only in `v8_test`; no live migration or REST writer. Details: `requirements/V7_REAL_MARIADB_UAT.md`. CI result must be checked and recorded independently; no runtime PASS claimed by this commit alone.

### Real MariaDB V7 stock/accounting UAT — channel coverage

Real V7 service test extended to Field Cash (employee stock + Cash in Transit) and Counter UPI (UPI clearing). UAT-only verified evidence fixtures, no production payment bridge. See `requirements/V7_REAL_MARIADB_UAT.md`.

## 2026-10-20: verified-tender bridge in real V7 Stock/GL UAT (v0.21)

`V7UatCanonicalTenderBridge` promotes locked V8 issued/reserved verified Cash/UPI proof to the V7 canonical tender table within the **same existing V7 accounting transaction**. Unlike v0.20, disposable MariaDB fixtures no longer manually seed canonical verified tenders. This is UAT-only; the external independently authenticated payment-provider / physical cashier ingestion is **still missing** and cannot be claimed complete. Updated disposable MariaDB acceptance suite to 37 assertions. See `requirements/V7_REAL_MARIADB_UAT.md`.

## 2026-10-20: internal signed bank settlement read barrier (UAT v0.23)

Added HMAC-sealed bank-reconciliation record lookup on an isolated `v8_test` table, with strict source, age and company/branch assertions and MariaDB negative tests. Demonstrates a safe input contract for `TrustedTenderIntake`, **not a real PSP API / signature format / webhook**. Provider selection and independent source authentication remain required before live payments. See `requirements/V7_REAL_MARIADB_UAT.md`.
