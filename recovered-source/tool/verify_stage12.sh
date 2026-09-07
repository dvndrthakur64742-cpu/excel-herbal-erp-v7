#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/flutter/excel_herbal_erp"

echo '== Clean source gates =='
php "$ROOT/tests/business_policy_contracts.php"
python3 "$ROOT/tests/source_invariants.py"
python3 "$ROOT/tests/api_contracts.py"
python3 "$ROOT/tests/uat_workflow_contracts.py"
python3 "$ROOT/tests/schema_write_contracts.py"
python3 "$ROOT/tests/transaction_integrity_contracts.py"
python3 "$ROOT/tests/flutter_static_integrity.py"

mapfile -t PHP_FILES < <(find "$ROOT/backend/excel-herbal-erp-v7" -type f -name '*.php' | sort)
for f in "${PHP_FILES[@]}"; do php -l "$f" >/dev/null; done
echo "PASS PHP lint ${#PHP_FILES[@]}/${#PHP_FILES[@]}"

echo '== Flutter compiler gates =='
"$ROOT/tool/verify_flutter.sh"
