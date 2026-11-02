# Windows Local UAT — B2B + Distributor Pricing + Discount Approvals

**Test date:** 2026-11-02 | **Environment:** user-owned, loopback-only Windows XAMPP at `http://127.0.0.1:18880/erp-uat/`.

## Execution provenance and safety

- **Actually deployed/tested commit:** `2e40eba61d97ef26b543c631682d0701af75b3bd` (V7 7.3.10-rc2). This is deliberately older than current GitHub development branch; the live company WordPress ERP remains unmodified.
- WordPress 7.1.4; PHP 8.3.36; MariaDB 10.11; `staging` environment; synthetic-only seed and sanitizer health gates both verified. Backend PHP domain methods ran against the actual persistent **local** MariaDB, **not** through authenticated BM REST or Flutter UI.
- **Pre-test backup:** `E:\ERP-Backups\eh7-before-b2b-distributor-20261102\b2b-distributor-before.sql`, SHA-256 `4AC5F292FFB262E6E651ED716E44BC1D66D02EFD053B8D7905EB9ACE8DB9085E`. Backup and credentials stay off GitHub.
- All customer, products, prices, Cash collections, UPI evidence and employee identities used in this series are synthetic. No real stock, employees, customers, bank activity or external integrations were exercised.
- **Business-policy caveat:** To exercise routing the local UAT site was explicitly configured with a **TEST-ONLY HO discount cutoff of 10%**; no real Excel Herbal cutoff is approved, established or deployed. Price slabs below are also **TEST-ONLY**, not approved trading rates.

## Actual local acceptance tests

| Test | Local result |
| --- | --- |
| B2B without a registered customer | PASS — rejected `customer_required` |
| Distributor without registered customer | PASS — rejected `customer_required` |
| Invalid nonexistent customer | PASS — rejected `customer_invalid` |
| Gap in distributor slabs | PASS — rejected `price_slabs_gap` with no database writes |
| Three contiguous test slabs: 1 @ ₹95, 2–4 @ ₹90, 5+ @ ₹80 | PASS — quantity 1/2/4/5 boundaries and totals verified |
| No discount percentage policy configured | PASS — refuses to guess HO cutoff, `discount_policy_unconfigured` |
| Create one registered **synthetic** customer | PASS |
| Distributor 2-unit order, price slab ID 2, gross ₹180, invoice not created at order creation | PASS |
| Distributor invoice attempted without Cash/UPI | PASS — rejected `full_prepayment_required` |
| Distributor full ₹180 test Cash collection then exactly one invoice | PASS, idempotent repeated posting |
| Test-only 10% HO discount threshold | PASS — explicitly local fixture; never promote as a business rule |
| B2B ₹100 order with ₹5 discount | PASS — `discount_pending` until different synthetic BM approves; creator cannot self-approve |
| B2B ₹95 full Cash and invoice after independent BM review | PASS |
| Separate B2B ₹100 order with ₹15 discount | PASS — local 10% test threshold routes `head_office`; BM-level capability insufficient and different synthetic HO identity approved |
| B2B ₹85 full Cash and invoice after HO approval | PASS |
| All invoices, payment totals and stock | PASS — five counter invoices, ₹560 paid, ₹0 outstanding, warehouse 3 units, employee 0 units |
| Journal balances | PASS — **all seven journals independently debit=credit** |

## Final read-only MariaDB accounting verification

Five prepaid counter orders, all `posted`:

| Order ID | Channel | Gross | Discount | Net | Approver |
| --- | --- | ---: | ---: | ---: | --- |
| 1 | B2C Cash | 100 | 0 | 100 | n/a |
| 2 | B2C synthetic UPI | 100 | 0 | 100 | n/a |
| 3 | Distributor test slab, 2 units | 180 | 0 | 180 | n/a |
| 4 | B2B test discount | 100 | 5 | 95 | synthetic BM employee ID 3 |
| 5 | B2B test discount | 100 | 15 | 85 | synthetic HO/admin employee ID 1 |

Counter-invoice paid total: **₹560.00**, outstanding: **₹0.00**. This excludes the **separate ₹100 synthetic field-sale evening settlement** previously verified and journaled; do not double count field custody sales with warehouse-counter invoices.

Final stock: branch warehouse **3 units**, field employee custody **0 units**. Total journal entries: **7** (initial stock adjustment, Daily Order evening, five prepaid counter invoices), each balanced.

## Important limits before release

1. Local test actors were constructed by PHP service tests, **not authorized employees authenticated end-to-end through real BM/HO REST mobile sessions**. BM has a distinct local employee row without WordPress login.
2. Test-only discount threshold `10.00` is not an approved real-company business rule. Require explicit policy values before seeding any live environment.
3. Real registered customers, pricing agreements, taxes/GST, real UPI bank evidence, supplier purchases, employee mobile GPS hardware and production recovery are **not yet tested**.
4. Return/reversal approvals, B2B/Distributor cancellation and credit/refund accounting need dedicated tests. Android/Flutter UI and production promotion remain pending.
5. **Do not deploy** the current development branch to the persistent local UAT via a blind `git pull`: local plugin is a live junction; use source-pinned, backed-up and migration-reviewed promotion.

**Next test:** independently authorized customer return/reversal workflow on an isolated synthetic order, plus role-scoped REST/Flutter sign-in for the distinct BM.
