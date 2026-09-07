#!/usr/bin/env python3
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]

def read(rel): return (ROOT/rel).read_text()

ns=read('backend/excel-herbal-erp-v7/src/Core/NumberSeries.php')
db=read('backend/excel-herbal-erp-v7/src/Database/Db.php')
acct=read('backend/excel-herbal-erp-v7/src/Finance/AccountingService.php')
fin=read('backend/excel-herbal-erp-v7/src/Finance/FinanceService.php')
stock=read('backend/excel-herbal-erp-v7/src/Inventory/StockService.php')
inv=read('backend/excel-herbal-erp-v7/src/Inventory/InventoryService.php')
work=read('backend/excel-herbal-erp-v7/src/Workforce/WorkforceService.php')
idem=read('backend/excel-herbal-erp-v7/src/Security/Idempotency.php')
api_client=read('flutter/excel_herbal_erp/lib/core/api_client.dart')
app_state=read('flutter/excel_herbal_erp/lib/state/app_state.dart')
main=read('flutter/excel_herbal_erp/lib/main.dart')

assert 'ON DUPLICATE KEY UPDATE id=id' in ns
assert 'FOR UPDATE' in ns and 'last_number=%d WHERE id=%d AND last_number=%d' in ns
assert 'mustInsert' in db and 'database_insert_failed' in db
assert 'lockSource' in acct and 'ORDER BY id DESC LIMIT 1 FOR UPDATE' in acct
assert "'reversal'=>'reversals'" in acct
assert 'sourceRow=' in fin and 'FOR UPDATE' in fin and 'reversal_already_pending' in fin
assert 'exclusion_reason' in fin and 'excluded_by' in fin and 'excluded_at' in fin
assert 'bank_statement_balance_mismatch' in fin
assert 'accountTable' in fin and 'bank_reconciliation_overlap' in fin
assert 'ON DUPLICATE KEY UPDATE id=LAST_INSERT_ID(id)' in stock
assert 'stock_balance_store_failed' in stock and "Db::table('stock_ledger')" in stock
assert 'transfer_receive_duplicate_line' in inv and 'transfer_receive_incomplete' in inv and 'transfer_receive_unknown_line' in inv
assert "'branch_id'=>$branch" in work and 'leave_branch_missing' in work
assert "ORDER BY id LIMIT 1 FOR UPDATE" in work
assert 'field_visit_party_invalid' in work and 'attendance.check_out' in work

# Mandatory business inserts must fail closed. Only Db helper and Idempotency race reservation may use raw $db->insert().
raw=[]
for p in (ROOT/'backend/excel-herbal-erp-v7/src').rglob('*.php'):
    text=p.read_text()
    if '$db->insert(' in text:
        raw.append((str(p.relative_to(ROOT)),text.count('$db->insert(')))
allowed={
 'backend/excel-herbal-erp-v7/src/Database/Db.php':1,
 'backend/excel-herbal-erp-v7/src/Security/Idempotency.php':1,
}
assert dict(raw)==allowed, f'unapproved raw inserts: {raw}'
assert 'if($inserted===false)' in idem and 'idempotency_in_progress' in idem

# Mobile reliability: identical in-flight POST is deduped; transient failures retain session.
assert '_inFlightMutations' in api_client and 'identical(_inFlightMutations[fingerprint], future)' in api_client
assert 'status == 401 || status == 403' in api_client
refresh=api_client[api_client.index('Future<bool> _performRefresh'):]
assert 'await session.clear()' in refresh
assert 'bootstrapRecoveryRequired' in app_state
bootstrap=app_state[app_state.index('Future<void> refreshBootstrap'):]
assert 'if (e.statusCode == 401)' in bootstrap
assert "state = AppState(loading: false, authenticated: true" in bootstrap
assert 'ERP temporarily unavailable' in main and "label: const Text('Retry')" in main

print('PASS transaction/data-integrity and mobile-reliability contracts')
