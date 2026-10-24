# Independent cashier Cash receipt — V8 isolated integration v0.16

## Business flow

1. Retailer pays full **Cash** to the authorized field employee: the retailer is fully paid; the employee has outstanding **Cash in Transit**.
2. Independently authenticated branch cashier physically counts the employee's complete Cash and confirms a unique receipt (`IndependentCashierReceipt::attest`). Caller-supplied amount and paid flag are ignored. Server role/branch and maker != checker are mandatory.
3. A real InnoDB transaction locks the posted field sale and pending cash-custody row; `v8_b2b_verified_branch_receipts` and `v8_b2b_cashier_receipt_attestations` are written atomically. Unique company/sale attestation and receipt reference provide replay protection.
4. Only a signed attestation is accepted by `MariaDbEmployeeRemittanceGateway::confirmedBranchReceipt`, which then atomically consumes the receipt and books **DR BRANCH_CASH / CR EMPLOYEE_CASH_IN_TRANSIT** in the **isolated UAT journal**. All-or-nothing, no partial/shortage exception.
5. No retail invoice or receivable change occurs during employee-to-branch deposit. No double sale or double stock deduction.

## Safety limitations

- **UAT only**: PDO adapter refuses databases other than exactly `v8_test`. SQL schema file `008_cashier_attestation_UAT.sql` is manual/test-only and must never be installed on production.
- **No live WordPress cashier authorization, no POS provider, no canonical V7 stock or GL writer** is wired. Calling the PHP class from a browser without a genuinely authenticated cashier and physical confirmation would be unsafe; no such route exists.
- Existing V7 `daily_cycle` journal may book Cash at evening closing already; DO NOT add another DR Branch Cash on its behalf. A canonical migration/reclassification and maker-checker policy need approval before live transactional integration.
- The `v8_b2b_verified_branch_receipts.verified_source` string alone is not proof. The attestation and the verified source must match the exact employee, branch, sale and amount.
- Failures to confirm a partial/short deposit must remain unresolved rather than silently clearing employee liability.

## Regression acceptance

- `php -d zend.assertions=1 -d assert.exception=1 v8/backend/tests/independent_cashier_receipt.php` (20 isolated checks)
- `V8_TEST_DSN=mysql:...;dbname=v8_test... php ... v8/backend/tests/mariadb_integration.php` (not run here without `pdo_mysql` + disposable MariaDB).
- Verify unsigned forged receipt refused, cashier actor distinct from original sale actor, full correct amount, branch RBAC, replay exactly once, signed event consumed only once, remittance journals balanced.

## Release gates

Production posting remains forbidden; Tax/GST policy, source-table journal registration, reversal support, verified bank payment, canonical identity/stock locking, real cashier evidence and MariaDB/Flutter UAT must be approved and passed first.
