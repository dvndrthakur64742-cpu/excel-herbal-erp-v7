# Local UAT: Field Evening Settlement + Fully Prepaid B2C Cash/UPI — 2026-11-02

## Environment and traceability

- **Actual tested application:** local Windows XAMPP WordPress 7.1.4, PHP 8.3.36, MariaDB 10.11 at `http://127.0.0.1:18880/erp-uat/`.
- **Deployed ERP source SHA:** `2e40eba61d97ef26b543c631682d0701af75b3bd`, ERP V7 7.3.10-rc2. The GitHub branch has newer un-deployed commits. No pull or migration was performed during this test.
- Local WordPress environment `staging`, timezone `Asia/Kolkata`, synthetic seed present, sanitizer true, source marker matched.
- Local-only simulated employees `UAT-ADMIN`, `UAT-FIELD`, `UAT-BM`; synthetic product `UAT-GPS-STOCK-0001`. The separate BM is **not yet an authenticated WordPress user**; PHP services used explicit synthetic Actor identities for the review and bank-verification steps.
- Database snapshots recorded before the evening mutation in `E:\ERP-Backups\eh7-before-evening-settlement-20261102` and before prepaid tests in `E:\ERP-Backups\eh7-before-prepaid-orders-20261102`. No files or secrets copied to GitHub.
- All amounts and UPI references are **synthetic test fixtures**; these are NOT actual collections or externally verified bank transactions. Tests were made against WordPress-bootstrapped PHP domain services and persistent localhost MariaDB, not through the Flutter UI or remote REST endpoints.

## Field duty: evening settlement and custody reconciliation

**Scenario:** prior stock issue of 2 units already acknowledged by synthetic employee; 1 unit sold (retail rate ₹100), 1 unit returned.

| Assertion | Result |
| --- | --- |
| Issue cycle → evening draft | PASS |
| Cannot submit before saving reconciliation | PASS |
| 1 retail sale + 1 return totals exactly ₹100 | PASS |
| Employee submits evening settlement | PASS |
| Final post rejects ₹0, ₹50 and ₹101 instead of required ₹100 | PASS — `payment_mismatch` |
| Same employee cannot final-post own settlement | PASS — `maker_checker_required` |
| Without configured Cash ledger final post rejected and stock/journal rolled back | PASS — `payment_accounts_missing` |
| Configure synthetic-only daily Cash/UPI account IDs with audit | PASS |
| Independent BM final-posts ₹100 Cash, no outstanding difference | PASS |
| Custody ledger: warehouse 8 → 9 after return, employee 2 → 0 (1 sold, 1 returned) | PASS |
| One field-sale stock OUT, paired return OUT/IN and balanced journal | PASS |
| Duplicate final posting | Rejected |

## Branch-counter B2C prepaid invoices

**Separate flow:** branch-counter invoices debit the **warehouse custodian**, not the employee's field custody, to avoid double-counting the Daily Order sale.

### Cash B2C

- Created one ₹100 B2C order with **no invoice at creation**.
- Invoice refused with **₹0 paid** and again at **₹40 of ₹100 paid**, with `full_prepayment_required`.
- Accepted ₹40 Cash plus ₹60 Cash; rejected extra ₹1 as `payment_overpaid`.
- After full collection, exactly one invoice posted, one journal recorded, warehouse 9 → 8 and repeat invoice posting was idempotent.

### UPI B2C

- Created a distinct ₹100 B2C order, recorded a synthetic UPI reference as **pending**.
- Invoice refused before verification with `upi_verification_required`.
- Seller could not verify their own UPI — `maker_checker_required`.
- Separate synthetic BM recorded a **fake UAT bank-evidence reference** and payment became confirmed; duplicate UPI verification rejected.
- Exactly one full-pay invoice posted, warehouse 8 → 7, and repeat invoice posting was idempotent.

## Final persistent SQL verification

Read-only reconciliation of MariaDB after tests:

- Daily cycle = `completed`; two prepaid B2C orders = `posted`, each ₹100.00, exactly two counter sale invoices.
- Confirmed Cash receipts = ₹40.00 + ₹60.00, confirmed synthetic UPI = ₹100.00 with verifier employee ID 3.
- Final stock: **warehouse 7 units**, **field employee custody 0 units**.
- Four journal entries (stock adjustment; daily field cycle; B2C cash sale; B2C UPI sale). Debit and credit balanced **individually** for all four. Journal totals include cost-of-goods/inventory lines, not just payment amounts.
- No changes to real WordPress employee identities, live invoices, the Railway project, or the production database.

## Follow-up: do not mark full ERP/UAT complete

1. Real **authenticated** BM/RM/SM/ASM roles via REST/Flutter, not merely synthetic in-memory Actor objects.
2. B2B/distributor registered-customer and volume-slab pricing, approval thresholds, discount maker-checker and invoice / return reversal.
3. UPI verification against real bank reconciliation integration or appropriately approved evidence; the fixture tests **only authorization and posting logic**.
4. Flutter Web and Android real-device end-to-end workflows, physical collection/return procedures and restore rehearsal.
5. Versioned plugin ZIP from tested branch after safe migration planning, production deployment approval and live smoke checks.

**Safety:** never blindly pull GitHub code into the persistent local junction, reset test data or mark the live office ERP upgraded. The tested SHA remains pinned until its migration/rollback plan is reviewed.
