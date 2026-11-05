# Excel Herbal ERP V7 — 7.3.6-rc1 — V15 Field-Sales Workflow Integration

**Status: STAGING CANDIDATE ONLY. Not deployed to WordPress. Not production approved.**

## Origin and compatibility
- Derived from locally available `Excel-Herbal-ERP-V7-WordPress-Admin-Fix.zip` (V7 7.3.5-rc1). The source is not proven identical to the live WordPress installation.
- The uploaded `universal-office-erp-platform-v15.0.0-foundation.zip` is a *business workflow reference*. The V15 `eoe_*` schema is NOT imported, installed, overwritten, or merged.
- The V7 `eh7_*` tables are preserved; new fields/tables use an incremental schema migration.
- This release intentionally changes daily request states and REST contracts. **The Flutter frontend must be updated and tested before activating this candidate on live ERP.**

## Implemented business logic
1. Morning Product Request requires an employee's dated, branch-matched GPS check-in record.
2. Independent review step by same-branch SM/ASM (system administrator recovery exception); maker and stock beneficiary cannot review.
3. Final approval by BM/ZI/RC/RM/AGM (system administrator recovery exception), excluding maker, beneficiary and reviewer.
4. Approved stock allocation is **staged** (`awaiting_receipt`); no stock ledger movement at allocation time.
5. Only the beneficiary confirms physical stock receipt. The actual custody transfer is executed atomically at receipt confirmation; duplicate status transitions are rejected.
6. Evening Settlement computes actual retail sale as issued minus returns minus wholesale, validates quantity conservation, and requires saved reconciliation before submission.
7. Unapproved wholesale price markdown is blocked (pending full B2B/Distributor quotation and discount workflow).
8. Field settlement requires Cash + UPI exactly equal to expected sales. UPI amount must match separately verified payment references, with independent finance review and bank evidence references.
9. Legacy counter-sale path forbids partial/credit posting and bank payment; UPI is fail-closed there until its pre-invoice verification workflow is implemented. Historic customer credit receipts are preserved for recovery.
10. All new state-mutating HTTP routes use existing authentication, branch checks, audit and idempotency framework.

## New REST routes (base `/wp-json/excel-herbal-erp/v7`)
- `POST /daily/requests/{id}/review` — submitted → reviewed; no JSON required.
- `POST /daily/requests/{id}/approve` — reviewed → approved (existing route, stricter prerequisites).
- `POST /daily/requests/{id}/issue` — approved → awaiting_receipt (existing route, now staged, body `allocations`).
- `POST /daily/requests/{id}/receive` — awaiting_receipt → issued, authenticated stock beneficiary.
- `POST /daily/cycles/{id}/upi-receipts` — body `{ "reference": "UPI2026ABC123", "amount": 100 }`, creates pending receipt.
- `POST /daily/upi-receipts/{id}/decision` — body `{ "approve": true, "bank_evidence_ref": "BANK123456" }` or `{ "approve": false, "reason": "Reference not found" }`; finance user only.
- Existing evening routes unchanged, but `evening/submit` now requires valid saved reconciliation and `final-post` validates verified UPI amounts.
- All authenticated writes require unique `X-Idempotency-Key` and proper Bearer session.

## New / extended schema
- `daily_requests`: nullable `reviewed_by`, `reviewed_at`, `allocated_at`, `received_by`, `received_at`.
- `evening_settlements`: nullable `reconciled_by`, `reconciled_at`.
- New `daily_upi_receipts` table with unique payment reference and unique bank evidence reference in company scope.
- `Schema::VERSION` updated to `7.3.6-field-sales-2`; existing schema migration path remains incremental.

## Deployment gate — DO NOT SKIP
1. Back up live WordPress database, plugin and uploads; verify restore.
2. Inspect actual live V7 plugin version and schema before applying; produce checksum and code diff; reconcile customizations.
3. Stage the ZIP on a cloned/sanitized environment, not directly on production.
4. Run PHP lint, `bash tests/run.sh`, `python tests/static_checks.py` and disposable MariaDB `tests/integration_uat_smoke.php` with the required environment variables; this build could NOT run the latter due to missing `mysqli` and MariaDB server locally.
5. Update Flutter/WordPress UI to support review, awaiting receipt, employee receive, UPI evidence and new errors. Old clients that call issue → evening directly will fail.
6. Verify migration against copy of real schema/data and older vouchers.
7. Verify attendance, role hierarchy, finance permissions, branch isolation, settlement, invoice, stock and reversals end-to-end.
8. Only then consider version-controlled rollout and rollback plan.

## Scope not complete
- Live Flutter startup/login and existing 27 employee identity links not repaired here.
- B2B and Distributor order pricing, quantity slabs, discount escalation, full pre-invoice UPI for counter orders: **not implemented**.
- GPS exception approval by Head Office: **not implemented**.
- Live UI updates, production deployment, database integration and full UAT: **not done**.
- Manual bank-evidence verification is not a bank/payment-gateway API integration; the authorized reviewer must actually inspect the payment record.
- The V15 front-end design files have not been copied to this V7 plugin.
