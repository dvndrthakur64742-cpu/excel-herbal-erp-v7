#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
php -r 'if (PHP_VERSION_ID < 80100) {fwrite(STDERR, "PHP 8.1+ required\n"); exit(1);}'
while IFS= read -r file; do php -l "$file"; done < <(find src tests -type f -name '*.php')
php -l excel-herbal-erp-v7.php
php tests/field_sales_rules.php
php tests/employee_link_integrity.php
php tests/employee_credential_authorization.php
php tests/employee_identity_attestation.php
php tests/employee_mobile_username.php
php tests/employee_login_preflight.php
php tests/staging_safety.php
php tests/attendance_schedule_contract.php
php tests/gps_morning_issue.php
php tests/daily_issue_preflight_contract.php
php tests/daily_search_contract.php
php tests/daily_draft_edit_contract.php
php tests/daily_cancellation_contract.php
php tests/daily_request_disposition_contract.php
php tests/security_scope_regression.php
php tests/salary_authority_regression.php
php tests/salary_structure_contract.php
php tests/reward_adjustment_contract.php
php tests/promotion_review_contract.php
php tests/access_escalation_regression.php
php tests/workforce_scope_contract.php
php tests/self_performance_contract.php
php tests/hr_read_scope_contract.php
php tests/reports_contract_regression.php
php tests/employee_picker_contract.php
php tests/distributor_volume_pricing.php
php tests/prepaid_order_rules.php
php tests/prepaid_orders_contract.php
php tests/prepaid_refund_evidence_preflight.php
php tests/bootstrap_contract.php
php tests/regression.php
