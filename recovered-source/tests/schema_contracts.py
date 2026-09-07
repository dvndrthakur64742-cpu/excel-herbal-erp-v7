from pathlib import Path
import re
p=Path(__file__).resolve().parents[1]/'backend/excel-herbal-erp-v7/src/Database/Schema.php'
s=p.read_text()
tables=re.findall(r"\$c\['([^']+)'\]=",s)
assert len(tables)>=45, len(tables)
assert len(tables)==len(set(tables))
required={'companies','branches','employees','products','stock_ledger','stock_balances','daily_cycles','counter_sales','purchase_bills','journal_entries','journal_lines','payroll_runs','audit_log','mobile_sessions','idempotency_keys'}
assert required.issubset(set(tables)), required-set(tables)

receipt=re.search(r"\$c\['customer_receipts'\]=\"([^\"]+)\";",s)
assert receipt, 'customer_receipts schema missing'
receipt_body=receipt.group(1)
assert 'sale_id BIGINT UNSIGNED NOT NULL' in receipt_body, 'customer receipt must target one sale'
assert 'customer_receipt_allocations' not in tables, 'parallel receipt allocation table must not exist'

print(f'PASS clean schema {len(tables)} tables with sale-specific customer receipts')
