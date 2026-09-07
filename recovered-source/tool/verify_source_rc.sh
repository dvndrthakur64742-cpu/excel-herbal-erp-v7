#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
php "$ROOT/tests/business_policy_contracts.php"
python3 "$ROOT/tests/source_invariants.py"
python3 "$ROOT/tests/schema_contracts.py"
python3 "$ROOT/tests/api_contracts.py"
python3 "$ROOT/tests/uat_workflow_contracts.py"
python3 "$ROOT/tests/schema_write_contracts.py"
python3 "$ROOT/tests/transaction_integrity_contracts.py"
python3 "$ROOT/tests/flutter_static_integrity.py"
"$ROOT/tool/verify_uat_safety.sh"
mapfile -t PHP_FILES < <(find "$ROOT/backend/excel-herbal-erp-v7" -type f -name '*.php' | sort)
for f in "${PHP_FILES[@]}"; do php -l "$f" >/dev/null; done
echo "PASS PHP lint ${#PHP_FILES[@]}/${#PHP_FILES[@]}"
if grep -RInE '(BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY|password\s*[:=]\s*["'"'][^"'"']+["'"']|api[_-]?key\s*[:=]\s*["'"'][^"'"']+["'"'])' "$ROOT" --exclude-dir=.git --exclude='*.md' --exclude='*.example' >/tmp/eh7-secret-scan.txt; then
  echo 'FAIL potential committed secret:' >&2; cat /tmp/eh7-secret-scan.txt >&2; exit 1
fi
echo 'PASS committed-secret scan'
if grep -RInE '\bDELETE FROM\b|->delete\(' "$ROOT/backend/excel-herbal-erp-v7/src" >/tmp/eh7-delete-scan.txt; then
  echo 'FAIL direct destructive SQL/delete path:' >&2; cat /tmp/eh7-delete-scan.txt >&2; exit 1
fi
echo 'PASS no direct business DELETE path'
