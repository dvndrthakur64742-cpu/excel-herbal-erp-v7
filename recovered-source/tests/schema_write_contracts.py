#!/usr/bin/env python3
from pathlib import Path
import re
ROOT=Path(__file__).resolve().parents[1]
schema=(ROOT/'backend/excel-herbal-erp-v7/src/Database/Schema.php').read_text()
tables=set(re.findall(r"\$c\['([^']+)'\]",schema))
assert len(tables)==60, len(tables)
texts='\n'.join(p.read_text() for p in (ROOT/'backend/excel-herbal-erp-v7/src').rglob('*.php'))
# Every literal table used by canonical writes must exist in the clean schema.
write_tables=set(re.findall(r"Db::mustInsert\([^,]+,Db::table\('([^']+)'\)",texts))
write_tables |= set(re.findall(r"Db::table\('([^']+)'\)",texts))
missing=sorted(write_tables-tables)
assert not missing, f'code references undefined tables: {missing}'
# Schema includes clean-9/10 data-integrity additions.
assert 'branch_id BIGINT UNSIGNED NULL,employee_id BIGINT UNSIGNED NOT NULL,leave_type' in schema
for col in ['exclusion_reason VARCHAR(255) NULL','excluded_by BIGINT UNSIGNED NULL','excluded_at DATETIME NULL']:
    assert col in schema
assert "VERSION='7.1.0-clean-10'" in schema
print(f'PASS schema write contracts across {len(write_tables)} referenced tables; schema={len(tables)} tables')
