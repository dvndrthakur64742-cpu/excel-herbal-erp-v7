# Windows Local UAT — Independent Branch Manager, Stock Approval and Employee Receipt

**Test date:** 2026-11-02 (Asia/Kolkata). **Result:** PASS for the *synthetic PHP service and MariaDB workflow* below; **not** a full authenticated Branch Manager Flutter/REST login, invoice or settlement sign-off.

## Isolation and provenance

- Local WordPress: `http://127.0.0.1:18880/erp-uat/`. WordPress 7.1.4, PHP 8.3.36, MariaDB 10.11, `WP_ENVIRONMENT_TYPE=staging`.
- Live running plugin/source pinned to **`2e40eba61d97ef26b543c631682d0701af75b3bd`**; this GitHub report belongs to the *development branch*, which has advanced beyond that deployed local commit.
- Confirmed synthetic-only, sanitized and exact source match both before writes and after the test.
- Snapshot saved **before** creating the third actor / stock at `E:\ERP-Backups\eh7-before-bm-stock-approval-20261102` (database dump 220,097 bytes plus WordPress config).
- Fresh `BM` designation and separate `UAT-BM` employee row created with the normal `OrganizationEmployeeService::createEmployee` service. **No WordPress login was provisioned for this synthetic BM**. The PHP tests constructed a branch-limited Actor carrying capabilities explicitly; thus they prove the domain methods' authorization paths, **not** authentication or role provisioning through the REST API.
- No live WordPress, Railway, old employee, customer or production inventory records changed.

## Evidence and expected separation

| Operation | Tested actor | Result |
| --- | --- | --- |
| Earlier GPS verified and morning request submitted | Synthetic Field Employee ID 2 | PASS |
| Initial request reviewed | Synthetic System Admin Employee ID 1 | PASS |
| Attempt reviewer to final-approve own reviewed request | Employee ID 1 | **DENIED** `maker_checker_required` |
| Create +10 synthetic warehouse units via `InventoryService::adjustment` | Employee ID 1 | `pending` |
| Stock adjustment maker tries approving own entry | Employee ID 1 | **DENIED** `maker_checker_required`, ledger untouched |
| Branch Manager independently approves stock adjustment | Employee ID 3 | `approved`, 10 warehouse units and journal entry 1 |
| Duplicate adjustment approval | Employee ID 3 | **DENIED** |
| Branch Manager final-approves reviewed morning request | Employee ID 3 | `approved` |
| Requester/beneficiary tries allocating their own stock | Employee ID 2 | **DENIED** `maker_checker_required` |
| Branch Manager allocates requested two units | Employee ID 3 | `awaiting_receipt`; **warehouse stock still 10** |
| Non-beneficiary tries confirming receipt | Employee ID 1 | **DENIED** `daily_receipt_forbidden` |
| Field Employee confirms receipt | Employee ID 2 | `issued` with custody transfer |
| Duplicate physical receipt | Employee ID 2 | **DENIED** `daily_request_state_invalid`, no duplicate ledger |

## Post-test read-only database reconciliation

- Daily request **`issued`**: requested_by=2, reviewed_by=1, approved_by=3, issued_by=3, received_by=2. Cycle status `issued`.
- Adjustment maker=1, approver=3, with an accounting journal linked.
- Stock balances: warehouse/custodian 0 = **8 units** at average cost 20; field employee/custodian 2 = **2 units** at average cost 20. Total 10.
- Stock ledger: `stock_adjustment IN 10`; `daily_issue OUT 2` (warehouse); `daily_issue IN 2` (employee). Net conservation verified.
- No second receipt applied.
- Synthetic-only/staging/sanitized/source-match still true.
- The separate **Cash/UPI verification → invoice → evening return/settlement** workflows were **not exercised in this acceptance slice**.

## Next acceptance tasks

1. Provision scoped *synthetic* BM/SM roles and verify permission flows via real REST login (the present BM has no WP login).
2. Use an isolated, idempotent HTTP UAT harness and inspect payment-before-invoice rejects; no real payment credentials.
3. Verify B2C retail, distributor slabs, UPI receipt review, evening returns and ledger reconciliation.
4. Exercise Flutter Web/Android UI on synthetic data; retain backups and source/DB migration review before changing localhost deployed commit.

**Safety:** no unreviewed `git pull`, live plugin deployment, production data import, or weakening of maker-checker separation.
