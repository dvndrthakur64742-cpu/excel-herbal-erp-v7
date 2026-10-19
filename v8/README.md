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
- `backend/tests/mariadb_integration.php` — integration checks requiring a disposable database exactly `v8_test`.
- `.github/workflows/v8-foundation-ci.yml` — lint, isolated tests and disposable MariaDB 11.4 job; **NO deploy action**.

## Run isolated tests

```sh
find v8/backend -name '*.php' -print0 | xargs -0 -n1 php -l
php -d zend.assertions=1 -d assert.exception=1 v8/backend/tests/run.php
php -d zend.assertions=1 -d assert.exception=1 v8/backend/tests/retailer_flow.php
```

Current local verification: **25/25 domain + 11/11 retailer tests PASS; MariaDB integration SKIPPED** because local PHP lacks `pdo_mysql` and no disposable DB is configured. GitHub Actions jobs have not yet produced executed steps in the observed attempt, so a green CI result is not established. The integration script SKIPs without `V8_TEST_DSN`. The GitHub CI job is configured with an ephemeral MariaDB 11.4 container. Local PHP environment might not include `pdo_mysql`; do not call MariaDB tests PASS until the CI runner proves them.

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