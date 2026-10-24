# Excel Herbal ERP V8 — Cashier Receipt, UPI Proof and Employee Ledger Rollout Blueprint
Date: 2026-10-24
Status: DESIGN / AUDIT ONLY — awaiting explicit owner implementation approval.
Repository: dvndrthakur64742-cpu/excel-herbal-erp-v7
Development branch: codex/erp-v8-foundation-20261017
No financial writer, schema migration, WordPress deployment or release approval granted by this document.

## Verified existing code / integration boundary

1. Canonical V7 DailyOrderService::finalPost accepts independently reviewed final
   Cash + UPI = sales amount and immediately posts DR configured Cash account
   (type/subtype cash) / DR configured UPI account (type/subtype upi),
   CR SALES, plus DR COGS / CR INVENTORY when applicable. It also creates
   employee performance/stock movements. It does NOT verify a later employee
   -> cashier physical receipt or independent bank/PSP settlement.
2. EmployeeCashControl and Employee360PersonLedger are read-only and
   explicitly mark employee Cash handover and UPI bank proof as NOT VERIFIED.
   The new Evidence Pending worklist is page-scoped, not an employee receivable.
3. V8 includes isolated v8_test UAT for independently authenticated cashier
   attestation, exact-amount replay safety, canonical V7 B2B Cash-in-Transit
   reclassification, and signed UPI bank-reconciliation lookup. These apply
   to ORIGINAL canonical B2B field Cash sale sources, not V7 DailyOrder cycles.
   DRAFT table schemas 008, 010, 011 must never be installed on Office or
   production without migration review.
4. Canonical V7 FinanceBankService already has a bank statement match/finalize
   workflow with branch/account checks and maker-checker. It does NOT by
   itself provide a trusted PSP ingestion service tied to original UPI intents.
5. V7 Daily Orders and canonical B2B sales may describe overlapping physical
   activity. No verified same-transaction linking key exists today. Do not
   sum, de-duplicate, or clear these ledgers by time or matching amount.

## Scope for proposed development AFTER explicit owner approval

A. Canonical custody semantics for *new* field Cash sales after a cutover:
   first recognize employee custody (DR EMPLOYEE_CASH_IN_TRANSIT with employee
   tag / CR SALES) rather than automatically recognizing physical Branch Cash;
   no extra customer sale, points, stock movement or receivable.
   Cashier handover on independent proof: DR BRANCH_CASH / CR
   EMPLOYEE_CASH_IN_TRANSIT, scoped to employee and source. Never post this
   second DR when the first DR already targeted BRANCH_CASH. Avoid silent
   historical restatement: legacy DailyOrder remains as originally posted,
   displayed under an explicit legacy evidence-unproven state.
   Account and period design must be verified against the actual installed
   Chart of Accounts and V7 journal schema.

B. Cashier receipt: Finance/cashier authenticated from server, separate from
   seller and closing maker; company/branch scope; source_type+source_id,
   employee_id, exact original Cash paise, cashier ID, received-at timestamp,
   unique receipt reference and idempotency key. Do not trust mobile-submitted
   amounts or roles. Same DB transaction locks original posted source,
   cashier receipt and custody posting; exact replay returns same receipt;
   changed reference/amount/branch must return 409. No self-attestation.
   No partial/short Cash receipt posting until shortage/partial policy approved.

C. UPI: "paid at retailer" and "settled to merchant account" are DIFFERENT
   facts. Verified settlement must come from authenticated PSP/bank feed with
   merchant account, original payment/order ID, amount paise, INR, transaction
   reference, terminal status and unique provider transaction key. Free-text
   UTR, customer screenshot or browser callback is NOT proof. Add provider
   idempotency and amount/reference/company mismatch and reversal checks;
   reconcile against canonical V7 UPI clearing/bank accounting without
   duplicate receipt. Source and fee/refund policy are separate approval gates.

D. Employee 360 single read-only timeline: original employee/request/issue,
   stock sale, tender booked, independent cashier receipt, verified bank
   settlement and journal reference with source IDs and business dates.
   Show distinct 'Booked', 'Receipt Verified', 'Bank Verified',
   'Evidence Pending', 'Disputed/Reversed' statuses. Employee price hiding
   remains LIMITED to employee dashboard per policy. Finance-sensitive tabs
   and accounting amounts remain behind existing view capability + target
   hierarchy/branch checks. No combined employee outstanding unless BOTH
   sources have verified identity links and custody journal rules.

E. No-overlap gate: original DailyOrder vs B2B source binding must use a
   durable cross-source transaction ID or signed source mapping. Matching
   employee/day/amount is a REVIEW CANDIDATE only, never identity evidence.
   No global outstanding or sales aggregate until linking and refunds tested.

## Proposed permissions and screens

- Field employee: view own stock requests, issued/returned/sold quantities,
  points, submitted closing, own handover receipts after server verification;
  cannot mark Cash/UPI verified, cannot self-authorize.
- ASM/ASAM: approve original stock issue; review field closings; cannot act
  as same-sale cashier or authoritatively verify PSP settlement.
- Branch cashier: physically count and attest source-bound Cash receipt.
  Cannot attest own sale; cannot alter original sale or stock.
- Finance checker: validate/authorize cashier posting with segregation of
  duties; verify bank statement evidence through trusted importer; approve
  exceptions as a distinct audited action if policy approved.
- Admin: audit evidence, permissions, exceptions and reconciliation; no
  silent bypass of cashier/PSP proof.
- Employee 360 / Cash Control / Person Ledger: *one* canonical transaction
  history; no duplicate shadow financial ledger, no implicit netting.

## Transaction rules and failure paths

- Validate source and branch/company/employee under row lock.
- Derive exact amount from immutable posted source, not request payload.
- Immutable receipt events; unique company+branch+reference, source identity,
  provider ID, receipt ID and idempotency key.
- Original stock/performance/sales postings never repeat on handover.
- Replays use existing verified journal and receipt, no new stock movement.
- Reject unexpected journal legs, wrong-side amounts, changed CASH/UPI split,
  wrong period, closed branch day or duplicate pending transitions.
- Reversal/chargeback creates explicit compensating source, not deletion or
  update of original ledger. Maker-checker and audit history remain immutable.
- Failed network response must re-read idempotency state; never auto-repost.
- Preserve full backup / point-in-time restore and migration rollback tested
  on sanitized isolated UAT before any Office staging installation.

## Test gates (mandatory before staging)

1. Synthetic MariaDB: request 5 PCS -> issue 5 -> retail 2 + wholesale 2 ->
   return 1 -> Cash 200 + UPI 160 -> sale 360 -> 8 points -> exact ledger.
2. Partial/short tender refused; no fictitious shortage balance.
3. Cashier receipt by different authorized actor; no self-attestation;
   independent maker-checker; duplicate reference/replay/concurrent attempts.
4. Cash custody transfer posts ONE Dr Branch Cash / Cr Employee Cash in
   Transit only for eligible NEW custody-source sales; legacy already-booked
   Branch Cash never receives a second debit.
5. Bank UPI verified only by authenticated PSP/bank evidence; reject fake UTR,
   stale signatures, wrong merchant/company/branch/amount, duplicate PSP IDs,
   settlement failures, refund/chargeback, fees until approved.
6. Exactly one original sale, one stock deduction, one incentive record;
   no duplicate original DailyOrder/B2B source event.
7. Employee 360 counts and profile/ledger/cash report reconcile to exact
   original source, page boundaries and role restrictions.
8. Real browser Admin/ASM/employee/cashier/finance acceptance, desktop/mobile
   and performance tests, sanitized UAT backup/restore rehearsal.
9. Dedicated deployment approval and staged build hashes checked before and
   after rollout. No automatic production deployment.

## Explicit owner decisions required for implementation

1. Handover scope: start NEW field-Cash Daily Orders only, or canonical B2B
   field Cash first, with the other source kept in read-only legacy mode?
   Recommended: start only one canonical source, not both concurrently.
2. Partial/short Cash receipts: recommended initial release = FULL EXACT amount
   only; partial/shortage exceptions must be defined separately.
3. Cashier and Finance checker: distinct people required? Recommended YES.
4. Retroactive existing Cash journals: recommended NO automatic migration;
   preserve original history and show 'legacy evidence not proven'.
5. UPI provider/bank statement source and service-charge/refund policy:
   requires verified external integration details.
6. Tax/GST/HSN, cancellations, cash reversal, bank settlement chargeback
   policies: owner/Accounts approval before transactional API activation.

### Approval boundary
Approval to REVIEW this design is NOT approval to modify production/staging,
run migrations, or post real Cash/UPI journals. Request an explicit,
scope-limited development-only authorization before implementing any new
receipt/settlement write path; deployment is a separate later approval.
