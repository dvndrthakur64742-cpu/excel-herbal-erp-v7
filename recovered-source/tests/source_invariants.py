from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
roots=[ROOT/'backend/excel-herbal-erp-v7',ROOT/'flutter/excel_herbal_erp/lib']
files=[]
for r in roots:
    files.extend(p for p in r.rglob('*') if p.is_file() and p.suffix in {'.php','.dart','.yaml'})
text='\n'.join(p.read_text(errors='ignore') for p in files)
forbidden=['ERPv4','ERPv5','ERPv6','EHV4_','EHV5_','EHV6_','/excel-herbal-erp/v5','serviceWorker','ServiceWorkerRegistration','handler_not_yet_connected','501)','Batch ID (optional)']
failed=[x for x in forbidden if x in text]
assert not failed, failed
assert 'ExcelHerbal\\ERP7' in text
assert 'excel-herbal-erp/v7' in text
assert "BATCH_MODE = 'optional'" in text
assert 'eh7_' in text
assert "TRANSFER_CANCEL='inventory.transfer.cancel'" in text
assert "BranchDayGuard::assertOpen" in text
assert "STOCK_VARIANCE" in text
assert "reversal_already_pending" in text
assert "bank_reconciliation_overlap" in text
assert "bank_journal_already_matched" in text
assert "_uncertainMutations" in text and "retainedMutationKey" in text

assert 'a.valid_from<=%s' in text
assert 'missing_period_end_branch_closings' in text
assert 'employee_custody_nonzero' in text
assert 'negative_stock' in text
assert 'Accounting Period close blocked' in text
assert 'New Branch' in text and 'New Employee' in text and 'New Product' in text
assert 'New Customer' in text and 'New Supplier' in text
assert 'Additional Branch Authority' in text and 'New Commercial Revision' in text

assert 'future_transfer_not_supported' in text
assert 'customer_receipt_allocations' not in text
assert "'/sales/open-sales'" in text
assert "get_param('sale_id')" in text
assert 'Receipt exceeds selected sale outstanding' in text
assert 'purchase_bill_id' in text and 'supplier_advance_disabled' in text


# Canonical payment-ledger and idempotency hardening.
assert 'paymentAccount(Actor $a,int $id)' in text or 'paymentAccount(Actor $a, int $id)' in text
assert 'bankAccount(Actor $a,int $id)' in text or 'bankAccount(Actor $a, int $id)' in text
assert 'payment_account_invalid' in text and 'bank_account_invalid' in text
assert 'idempotency_store_failed' in text and 'idempotency_in_progress' in text

# Stock adjustment must reconcile stock and accounting and be reversible.
assert 'unit_cost_snapshot' in text and 'journal_entry_id' in text
assert "'stock_adjustment'" in text and 'reverseStockAdjustment' in text

# Payroll canonical lifecycle: generate -> branch-aware review -> approve -> pay -> reversal.
assert "PAYROLL_PAY='payroll.pay'" in text
assert "'payroll.detail'" in text and "'payroll.item_update'" in text and "'payroll.pay'" in text
assert 'payment_journal_entry_id' in text and 'payment_date DATE NULL' in text
assert 'employee_branch_history' in text and 'branch_id=%d AND employee_id=%d' in text
assert "source_type='payroll_payment'" in text or "'payroll_payment'" in text
assert 'Only approved payroll can be paid.' in text
assert 'Pay Payroll' in text and 'Save Review' in text

print(f'PASS source invariants across {len(files)} source files')

# Branch bootstrap/security invariants
org=(ROOT/'backend/excel-herbal-erp-v7/src/Organization/OrganizationService.php').read_text()
api=(ROOT/'backend/excel-herbal-erp-v7/src/Http/Api.php').read_text()
main=(ROOT/'flutter/excel_herbal_erp/lib/main.dart').read_text()
assert "public static function branches(Actor $a):array{if(!$a->branchIds)return[];" in org, 'authorised branch projection must not require Branch Master permission'
assert "branch_access_required" in api and "!$actor->branchIds" in api, 'zero-branch identities must be blocked from business APIs'
assert "Business Access Blocked" in main, 'Flutter must block business navigation for zero-branch identities'
print('PASS branch bootstrap and zero-branch business block')

# Fresh-install and access-management completeness.
setup=(ROOT/'backend/excel-herbal-erp-v7/src/Setup/SetupService.php').read_text()
access=(ROOT/'backend/excel-herbal-erp-v7/src/Security/AccessService.php').read_text()
schema=(ROOT/'backend/excel-herbal-erp-v7/src/Database/Schema.php').read_text()
assert 'setup_already_initialized' in setup and 'SYSTEM_ADMIN' in setup and 'OFFICE_GENERAL' in setup
for code in ['INVENTORY','AR','AP','SALES','COGS','STOCK_VARIANCE','PAYROLL_EXPENSE','PAYROLL_PAYABLE']:
    assert f"['{code}'" in setup, f'missing canonical setup account {code}'
assert 'access.role_caps' in (ROOT/'backend/excel-herbal-erp-v7/src/Http/Api.php').read_text()
assert 'self_access_lockout' in access and 'access.employee_roles' in (ROOT/'backend/excel-herbal-erp-v7/src/Http/Api.php').read_text()
assert 'active TINYINT(1) NOT NULL DEFAULT 1,created_at DATETIME NULL,updated_at DATETIME NULL' in schema
print('PASS fresh setup and access-management invariants')

# Clean-10 integrity / self-service read contracts.
assert '7.1.0-clean-10' in schema
assert 'branch_id BIGINT UNSIGNED NULL,employee_id BIGINT UNSIGNED NOT NULL,leave_type' in schema
assert 'exclusion_reason VARCHAR(255) NULL' in schema
assert "'/workforce/field-visits/current'" in (ROOT/'backend/excel-herbal-erp-v7/src/Http/RouteRegistry.php').read_text()
assert "'/workforce/leave/mine'" in (ROOT/'backend/excel-herbal-erp-v7/src/Http/RouteRegistry.php').read_text()
