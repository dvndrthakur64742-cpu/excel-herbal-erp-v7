#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
find "$ROOT/backend" -name '*.php' -print0 | xargs -0 -n1 php -l >/tmp/eh7_php_lint.txt
php "$ROOT/tests/business_policy_contracts.php"
python3 "$ROOT/tests/source_invariants.py"
python3 "$ROOT/tests/schema_contracts.py"
python3 "$ROOT/tests/api_contracts.py"
python3 "$ROOT/tests/uat_workflow_contracts.py"
python3 "$ROOT/tests/schema_write_contracts.py"
python3 "$ROOT/tests/transaction_integrity_contracts.py"
echo "PASS PHP lint $(wc -l </tmp/eh7_php_lint.txt) files"
