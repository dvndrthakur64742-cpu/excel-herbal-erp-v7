# Excel Herbal ERP V7 — Prepaid Sales 7.3.10-rc2 (Staging Only)

## End-to-end backend implementation
Versioned per-product distributor pricing, 10 authenticated REST endpoints, and a MariaDB-backed prepaid sales workflow for B2C, B2B and distributor orders. Order, line, price-slab, cash/UPI receipt and review state are persisted independently from posted invoices.

**Invoice posting is blocked until exact 100% confirmed Cash/UPI has been recorded.** Cash receipt is confirmed by a cashier-authorized user. UPI remains pending until a different authorized finance user attests a bank-evidence reference. No UPI proof is automatically obtained from banking APIs; an independent human must verify the external bank evidence.

Discounted orders require an independent checker. Branch/HO escalation cutoff has **no default**: Head Office must explicitly configure a cutoff. Amounts above that cutoff require the distinct Head Office capability. Every completed invoice posts sale, stock ledger, journal and audit records in one atomic transaction. Order locks and receipt-row locks prevent concurrent duplicate invoice/UPI verification.

## Automated verification
- PHP 8.2/8.3 lint, field rules, source route/contract snapshot and isolated policy regressions.
- Dedicated ephemeral MariaDB 11.4 service and **synthetic test data only**.
- MariaDB tests create B2C, B2B and distributor orders; verify partial-payment and pending-UPI blocks, cross-role approval, balanced debits/credits, exact stock deduction, rollback on insufficient stock, repeat posting and concurrent double-posting safety.
- All test execution is through GitHub Actions, with a staging ZIP and checksum artifact; the CI-built ZIP embeds the exact reviewed Git commit.

## Outstanding production blockers
- Full WordPress + Flutter REST/UAT/browser tests (a later Flutter 7.4.0 source still has cross-module compatibility failures).
- Railway isolated UAT routing, host-hardening and a previously staged destructive patch need review.
- No live bank API integration. Before operations, validate independent evidence review and cash custody procedures.
- No posted-order refunds/cancellations or customer credit notes, final GST/tax/invoice-printing certification, E2E concurrency load tests, or merchant reconciliation.
- No existing staff/customer data migrations were run. New database tables have not been tested against a copy of the live schema or full backup/restore.
- Legacy POS and Field Sales screens are NOT automatically switched to the new prepaid order endpoints.

**Deployment status:** Review/UAT candidate only. Do NOT merge to main or deploy to live WordPress before the unresolved gates pass.
