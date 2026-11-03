# ERP V7 — Prepaid Refund Evidence Reconciliation Preflight
Date: 2026-11-03
Status: Development source only; not a refund-posting feature or deployed release.

## Problem and boundary
The existing return intake and Cash/UPI evidence workflow records a physically received,
independently approved full-invoice return. Manual evidence verification is NOT proof of
bank payout and must never silently reverse a paid invoice, issue a GST credit note,
recreate saleable stock, or mark the original prepaid order as refunded.

## Implementation
- Added `Sales/PrepaidRefundEvidencePreflight.php`: pure, read-only, exact-paise validator.
- The existing authenticated, branch-scoped `GET /sales/returns/{id}` response now
  includes `refund_evidence_check`; no new endpoint, route number or schema migration.
- Evaluates approved `refund_pending` state, company/branch/order/return IDs, exact
  confirmed original Cash/UPI totals, matching evidence amount, method and account,
  independent reviewer and verification reference, missing/duplicated/foreign evidence.
- Response fields: `evidence_complete`, `blockers`, `expected_amount`,
  `original_payment_count`, `verified_evidence_count`,
  `verified_evidence_amount`, `manual_evidence_only=true`, and always-false
  `refund_disbursed`, `credit_note_posted`, `stock_posted`.
- Detail is read-only and queries by authenticated company/branch. All mismatches block
  evidence completeness. No payment account credentials or bank secrets are returned.

## Tests
- 17 isolated PHP assertions: valid split tender, no artificial payout or stock change,
  missing/duplicate/pending evidence, under/over by 1 paisa, wrong branch/account,
  self-verification, bad reference, return not approved, unconfirmed/incorrect original
  tender totals, unrelated proof, missing tender and invalid money.
- Wired into `tests/run.sh` for PHP 8.2 and PHP 8.3 GitHub quality gates.
- Added real MariaDB integration assertions to `tests/integration_prepaid_sales.php`:
  incomplete Cash-only proof, branch denial, both tender proofs reconciled, and still
  no actual refund or credit note. Passing CI must be checked against the last commit.

## Intentionally not implemented
No payout, bank API attestation, GST/credit-note numbering and tax computation,
stock quarantine/quality release, reversal journal, fiscal-period correction, partial
returns, offline device flow, or rollback automation is authorized by this slice.
The existing generic prepaid invoice reversal remains fail-closed.

## Required next implementation
Design a separate reviewed atomic posting transaction with receipt confirmation,
serialised GST credit-note fields as applicable, signed payout evidence, bank/cash
settlement, quarantined goods inspection, deduplicated journal and inventory entries,
and repeat-post/concurrent-call protection; obtain tax/finance approval and run
MariaDB + WordPress REST + Android/Web UAT before offering it to staff.

## Release safety
Source branch: `feature/v7-v15-staging-source-ci-20261031` (draft PR #28).
No live `office.excelherbal.in` WordPress files/database, the pinned Windows
localhost database, or Railway services were modified by this change.
Full production files+DB backup, restoration rehearsal and source reconciliation
remain required before any release promotion.
