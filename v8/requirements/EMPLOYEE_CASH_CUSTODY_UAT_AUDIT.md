# Employee Cash Responsibility / Cashier Handover UAT Audit

Read-only UAT adapter `UatEmployeeCashCustodyHistory` is built on existing
preview sales, employee cash responsibility, independent cashier attestation,
receipt consumption and remittance journal records in disposable `v8_test`.
No new stock table, ledger table, sales header or public WordPress route.

For each original field-Cash retailer sale:
- Before handover: employee_cash_pending, remitted zero.
- Only a consumed cashier receipt with independent actor and exact full
  remittance, matching balanced two-line custody journal, can report
  cashier_remittance_evidenced.
- Missing/tampered evidence: reconciliation_mismatch, remitted zero.
- Handover NEVER creates another retailer sale or retail income.
- Finance viewer must be permitted by a trusted server-side authority.
- All UAT readers and remittance writers reject wrong DB and schema switch.

**Release gate:** This is NOT canonical V7 GL posting and not real bank
deposit verification. Existing V7 Cash-in-Transit debit at sale can be posted
through canonical B2B UAT, but its corresponding V7 GL reclassification on
cashier handover is NOT implemented here. That requires owner-approved
canonical source type, reversal policy, period close rules, maker/checker
and real WordPress MariaDB UAT. No production deployment or PR merge.

## 2026-10-24 — Finance-only Employee source-linked cashier review (UAT only)

Before this change the canonical B2B field Cash employee report exposed a
boolean `cash_handover_verified`, but not its original physical cashier
attestation and the *different* Finance checker's posted canonical journal
in a single reviewer record. A manager could not follow the true evidence
chain from a finance-scoped employee review row.

The existing read-only `V7EmployeeCrossSourceCashAuditUat::inspect` now
exposes `cashier_finance_evidence` per canonical B2B field-Cash source
**only after** `V7B2BCrossLedgerAuditUat` fully verifies all canonical
journal lines, source identity, maker/checker separation and original
cashier receipt. The proof chain uses a second read-only join of original
`b2b_cash_remittances`, `b2b_cashier_receipts_uat` and V7
`journal_entries`. Company, branch, employee and sale must agree, and
the cashier, Finance checker, receipt, consumed-remittance and journal
author/source IDs must be consistent. Wrong, malformed, missing or duplicated
evidence fails closed.

The authorized report includes original source key, receipt ID/reference,
cashier user/employee, exact amount paise, finance checker user/employee,
canonical remittance/journal IDs and an explicit `*_uat` state. Legacy
Daily Orders have **no such proof chain**, no automated B2B identity,
and retain `cash_handover_verified=false`. Pending/failed B2B Cash
has `cashier_finance_evidence=null`; neither status is a debt calculation.
The whole report remains `read_only=true` and
`production_financial_status=not_certified`, with no second GL, price
visibility change, staging API, cashier confirmation, bank claim or live
production payment posting.

The disposable V7 canonical MariaDB test additionally verifies the original
cashier and independent Finance checker identities, the same original
source-linked posted journal, forged receipt-reference fail-close,
recovery without a second financial write, and original role/branch
authorization. Changes in the audit class trigger the dedicated isolated
Cashier/Finance-checker/UPI MariaDB workflow.

**Release status:** isolated development/UAT code only. To show this in an
actual Office browser, the new scope-limited finance API and authorized
Flutter screen must be designed, staged on sanitized infrastructure,
and independently approved. The current live Office backend has no
canonical cashier receipt action for this source.

## 2026-10-24 — UAT-only Finance Review component; no live API activation

The existing Flutter `EmployeeFinanceReviewView` now optionally renders a
`CashierEvidenceUatSection` ONLY if the caller explicitly supplies a
strictly parsed `CashierEvidenceUatPage`. Its parser validates the isolated
`V7EmployeeCrossSourceCashAuditUat::inspect` payload contract: read-only,
company, branch, employee, exact period, bounded first page, independence
of Daily Order and B2B sources, original B2B posted-sale ID / date / amount,
and original independently authenticated cashier receipt, Finance checker,
remittance and V7 posted GL journal IDs. Different cashier and checker user
and employee IDs are mandatory; UAT-only scope, unverified-live flag and
source-specific evidence stages are required. Duplicate source, receipt and
journal IDs, tampered amount, altered company/period, fake bank proof and
employee outstanding assertions fail closed. No totals are aggregated.

The independent component shows the receipt -> cashier -> Finance checker ->
canonical remittance/GL chain with an unmistakable **UAT ONLY / NOT Office
Cash proof / NOT bank settlement / NOT employee outstanding** disclaimer.
The old Daily Order renderer remains unchanged and explicitly lacks physical
Cash attestation. The existing `EmployeeFinanceReviewPanel._fetch` retains
ONLY canonical live V7 Cash Control and person ledger REST GET calls; it does
NOT fetch isolated v8_test data or present synthetic evidence as live fact.

A dedicated Flutter widget/contract suite covers acceptance and tamper
rejection. Pending **authorized** staging API integration, no runtime caller
passes `cashierEvidenceUat`, so this is a previewable development component,
not a live Cashier Receipt UI or a production ready workflow. This change
contains no REST route, financial posting, migration or Office deployment.
