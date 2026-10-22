# Employee Cash Control — V7 canonical posted settlement audit (v0.15)

## Business distinction and release policy

1. Daily Order `evening_settlements` marked `posted` and `daily_cycles` marked `completed` are **sales/settlement records**.
2. The existing V7 `DailyOrderService::finalPost` posts Cash/UPI directly to configured branch payment accounts through a journal source of `daily_cycle`. This records a general-ledger debit; **it does not prove** handover of the field employee's cash to a cashier, physical count, bank deposit, or PSP settlement.
3. The new read-only finance report compares each posted cycle's expected Cash/UPI to journal debit totals for company-scoped Cash and UPI asset accounts. It reports missing, duplicate and mismatched journals.
4. It deliberately reports `cash_remittance_status=not_available_in_legacy_v7` and each cash record `cash_remittance_proof=not_evidenced_in_legacy_v7`, even when the journal amounts match. Never derive cashier confirmation from posted sales alone.
5. No missing cash should be converted to employee shortage automatically. Shortage, partial remittance, reversals and policy-exception workflows require owner approval.

## Authenticated endpoint (development source only)

`GET /wp-json/excel-herbal-erp/v7/organization/employees/{id}/360/cash-control?from=2026-10-01&to=2026-10-19&page=1&page_size=25`

- Requires **finance.accounting.view**; if target is another employee, additionally requires **organization.employee.view**, permitted reporting hierarchy and target branch scope; self requests with finance capability are possible.
- The application shows the `Cash Control` tab only for finance-authorized users, but all enforcement happens server-side.
- Company-scoped SQL `SELECT` over canonical `eh7_daily_cycles`, `eh7_evening_settlements`, `eh7_journal_entries`, `eh7_journal_lines`, `eh7_accounts`, only completed/postable sources. Bound employee, period, and branch IDs. No duplicate master or migration.
- Enforces date bounds <=366 days, one-to-one posted journal source matching, strict paise arithmetic, pagination size <=100; totals and alert counts are **page scoped**, not complete-period totals.
- Status definitions: `journal_amounts_match`, `missing_journal`, `duplicate_journal`, `journal_amount_mismatch`. None mean “Cash received by cashier.”
- UPI bank settlement is not independently verified by this report. `bank` account entries are not assumed to be `upi` without explicit subtype.

## Security and test gate

- New PHP test suite: `backend/excel-herbal-erp-v7/tests/employee_cash_control_regression.php` — 40 isolated regression assertions for authorization, exact amount matching, SQL scope, identity mismatches, invalid money/date, journal anomalies and statement honesty.
- Flutter UI `Cash Control` read-only tab wired under the Employee 360 profile, not the dashboard.
- Flutter compilation/device runs and MariaDB/WordPress UAT have not been performed by this change. GitHub hosted workflow still failed before steps; user's Windows self-hosted runner lacks `php` on PATH.
- No posting endpoint, migrations, production deploy, PR merge, actual cash settlement recording, or live DB mutation.

## Next actual booking milestone

Approved canonical journal source and accounts for `EMPLOYEE_CASH_IN_TRANSIT` plus verifiable cashier receipt, distinct company/branch/employee money buckets; one atomic stock+invoice+GL posting and a separate cash-deposit reclassification entry; bank reconciliation. Must be modeled before any real cashier-confirmed status is exposed.

## 2026-10-21 — branch-isolated canonical Cash/UPI GL projection

Cash Control now groups posted journal entries by company, branch and source
daily_cycle ID, and joins them against all three dimensions of the completed
employee cycle. Previously, a mis-tagged posted journal in another branch
with the same company/source ID could inflate the employee's GL debit and
journal-count results. The old matcher was insufficiently branch-specific.

The change makes NO new financial proof claim: correct accounting debit totals
still do not prove an employee deposited Cash with a cashier, physical cash
receipt or bank-verified UPI. Mis-tagged external journals now cannot silently
masquerade as in-branch GL for this cycle.

Real MariaDB UAT runs in disposable v8_test, in an existing rollback-only
fixture. It inserts a wrong-branch posted journal with matching source ID
and ₹999 debit, proves the original cycle's GL totals and count remain
unchanged, and proves other-branch period filters do not inherit that cycle.
PHP 8.3/8.4 and Windows CI now explicitly run the canonical Cash Control
regression when these paths change.

No new schema, posting endpoint, shadow ledger, merge or deployment.


## 2026-10-22 — Complete Cash/UPI vs GL Dr/Cr fail-closed reconciliation

The original read-only Employee Cash Control checked only Cash/UPI *debit*
against the posted evening Cash/UPI split, plus the posted journal count. A
journal with a matching Cash debit but an unexpected Cash credit, an
understated SALES credit or an unbalanced total could have been displayed as
`journal_amounts_match`.

Finance-only `/organization/employees/{id}/360/cash-control` now checks the
original canonical V7 posted `daily_cycle` journal's **Cash and UPI debit
and credit**, exact `SALES` income account credit, **whole-journal debit and
credit totals**, and foreign/missing account-line references (LEFT JOIN).
A match requires one correct posted journal, Cash and UPI debit equal to the
settlement split, no Cash/UPI reverse credit, SALES credit equal to expected
sales, a balanced journal and zero invalid account references. Each check is
visible separately as a read-only diagnostic; discrepancies produce
`journal_amount_mismatch` and never silently authorize a cash handover.

Tests add pure PHP examples of balanced yet unexpected Cash credit, understated
Sales revenue, 0.01 unbalanced journal and orphan account. Disposable MariaDB
adds a synthetic independently balanced Cash/UPI/SALES journal with savepoint
mutation of reverse Cash credit and understated SALES, restored before full
transaction rollback. These are accounting consistency tests only; **cashier
receipt, physical remittance, bank deposit, real PSP UPI confirmation, and
salary impact remain unverified**. This scope introduces no schema migration,
posting endpoint, staging write, production release or data repair.

## 2026-10-22 — Legacy Daily Order vs B2B employee Cash source separation (UAT only)

`V7EmployeeCrossSourceCashAuditUat::inspect` is a disposable-`v8_test`,
server-authorized, finance-only, read-only cross-source projection. It brings
together **two independently identified sources**, not two newly posted
financial ledgers:

- **Legacy Daily Order:** Completed `eh7_daily_cycles` with posted
  `eh7_evening_settlements`, reported Cash/UPI, and original posted
  `daily_cycle` GL. Recheck Cash/UPI debit, reverse payment credits, SALES
  credit, full GL debit/credit balance and missing/duplicate journals. A
  matched bookkeeping journal **does not prove physical cashier remittance
  or independently verified UPI bank settlement**.
- **Canonical B2B field Cash:** Posted `eh7_b2b_retailer_sales` under the
  target employee/company/branch and date. Call the existing
  `V7B2BCrossLedgerAuditUat` for each source ID; a complete cashier-handover
  state requires an independently attested receipt and the existing canonical
  V7 GL remittance journal. Non-Cash B2B (UPI, counter) is intentionally not
  an employee cash liability and is excluded from this custody report.

Identifiers are namespace-qualified (`daily_cycle:<id>` and
`b2b_retailer_sale:<id>`) and two source lists have separate pagination.
**Do not sum or net them.** There is no trustworthy bridge proving whether
an old daily closing and a B2B retailer sale refer to the same physical sale.
The returned `combined_sale_total_paise` and
`combined_employee_cash_outstanding_paise` are explicitly NULL. A source
match does not prove inter-source deduplication or actual Cash/UPI settlement.
Source snapshots are not guaranteed atomic; the report cannot certify a
complete period or physical deposit.

A server-side authorization callback must approve the exact actor, company,
branch and target employee in addition to the V7 Finance/branch guard. Tests
exercise dual-source sample records in disposable real MariaDB, corruption of
legacy Sales journal credit independent of the B2B handover, empty periods,
unauthorized finance scope and target employee. No WordPress production HTTP
route, schema migration, shadow GL, Cash write, PR merge or deployment.

## 2026-10-22 — Step 1: bounded cross-source duplicate-risk review (development only)

The two systems do not share a verified event-level sale reference. V7 legacy
Daily Order is a **whole employee-day closing**; B2B retailer sale is an
**individual sale**. A daily settlement can contain multiple retailer sales.
Treating the same employee/date/amount as a one-to-one match would silently
distort turnover, stock, Cash custody, points and payroll.

The finance-gated, disposable-v8_test read-only employee Cash cross-source
projection now supplies a separate suspected_overlap_review:

- same_day_equal_cash: legacy daily Cash amount equals a posted B2B field Cash
  sale for the same company, branch, employee and business date.
- same_day_b2b_cash_within_daily_cash: positive field Cash sale amount fits
  within that day's larger posted legacy Cash total.
- No candidate if the relevant Daily Cash is lower than the whole B2B Cash
  payment or the business day differs. Such absence **does not prove** two
  physical sales are distinct.
- Each pair has namespaced source keys and a deterministic SHA-256 **review
  snapshot digest** from original IDs, scope, day, amounts and risk rule.
  This digest detects a changed review snapshot; **it is not independent
  proof** of the transaction. It is not an external receipt signature.

Every candidate is explicitly suspected_overlap_unverified with
may_deduplicate=false, may_net_or_adjust_stock=false and no original
shared-sale reference. verified_transaction_links=[] and
cross_source_duplicate_prevention_active=false. Both combined financial
totals and employee Cash outstanding remain NULL. Separate pages of at most
100 rows per source mean **candidate review is only for current pages**;
exhaustive_full_period_review=false, including on empty pages. This review
must not drive a release sign-off, sale cancellation, payroll deduction,
financial posting or automatic stock movement.

Existing real-MariaDB UAT inserts a posted canonical B2B Cash sale and
an independent completed Daily Order. It checks non-equal Cash, equal Cash,
Daily Cash containment, deterministic/change-sensitive review digest,
wrong-day isolation and strict no-netting. Tampering is restored after each
test. No production/office staging DB migration, HTTP endpoint or deployment.

**Next release blocker:** implement an owner-approved immutable shared source
identifier supported by original receipt/payment/order-line provenance, plus
a distinct independently authorized review workflow. Without that original
identity evidence, *verified* deduplication must remain unavailable.


## 2026-10-22 — Step 1: original order/receipt reference evidence gate (UAT only)

New V7CrossSourceReferenceReviewUat and isolated
012_cross_source_reference_UAT.sql demonstrate **how an independently
witnessed and independently finance-reviewed original document reference
could be checked** against the real V7 source rows.

- Synthetic evidence explicitly names the original Daily **cycle + evening
  line** and B2B **sale + sale line**, company, branch, employee, date,
  original order reference, original receipt reference, external-document
  SHA-256, product, batch (looked up in canonical source), whole PCS,
  monetary paise, distinct witness and reviewer IDs.
- A server-owned secret signs the scope and all immutable document-reference
  attributes using HMAC-SHA256; a separate authenticated finance reviewer
  must own the evidence's reviewer identity. Wrong key, altered receipt,
  self-approval and revoked source lineage fail closed.
- Read-only validation fetches canonical V7 Daily cycle, posted settlement,
  evening line, original issued-stock request, posted B2B sale/line, B2B
  cross-ledger audit and independently reconciled Daily GL. It refuses
  wrong company/branch/employee, date, source product, quantity or amount.
- Unique synthetic source-line keys prevent a given source line from being
  asserted against multiple sale lines on the disposable database. This
  is NOT a real transaction-id uniqueness guarantee across source systems.
- Outcomes are missing_original_document_evidence or
  signed_line_association_reviewed_uat. The latter proves only a **signed
  UAT witness assertion plus current canonical line/account agreement**;
  neither legacy V7 nor B2B currently emits the same immutable source
  reference through a trusted production bridge.

### Explicit release gate still CLOSED

A day-wide Daily Order and a per-retailer B2B sale may both be accurate
records describing overlapping activity. A manual witness attestation or
same Cash/product/quantity is not guaranteed original-order identity. A
real independently authenticated originating Order/Receipt API or other
owner-approved original evidence source must first supply a shared durable
event-level ID, transaction conflict rules, maker-checker authorization,
and replay-safe posting-time enforcement before declaring a true verified
duplicate. Until then verified_transaction_links=[],
may_deduplicate=false, release_duplicate_prevention_ready=false,
all combined financial totals NULL and zero automatic ledger/stock/salary
writes. No staging install, production migration, site deploy, or new
WordPress write endpoint has been performed.

Real disposable MariaDB UAT includes a signed original-reference fixture,
missing evidence, wrong server signing key, altered receipt, 0.01 legacy line
corruption, cross-cycle stock issue, changed product quantity, database
CHECK rejection of self-review, valid-HMAC substitution of a different
reviewer, and restored records. All test data is synthetic.
