<?php
/**
 * Disposable GitHub CI WordPress+MariaDB additive migration rehearsal.
 *
 * NEVER run against a hosted, persistent, or user-populated database.
 * This script deliberately drops ONLY EMPTY v7.3.12 additive tables to
 * simulate upgrading from a v7.3.10 schema. A separate, explicit CI guard
 * and synthetic-only attestation must both succeed before any write.
 */
if (!defined('ABSPATH')) {
    fwrite(STDERR, "FAIL: WordPress not bootstrapped\n");
    exit(1);
}
if (getenv('EH7_CI_ISOLATED') !== '1' ||
    function_exists('wp_get_environment_type') && wp_get_environment_type() !== 'staging') {
    fwrite(STDERR, "FAIL: refused non-disposable/non-staging migration rehearsal\n");
    exit(1);
}
$seed = \ExcelHerbal\ERP7\Administration\FreshUatBootstrap::status();
$safety = \ExcelHerbal\ERP7\Administration\StagingSafety::status();
if (($seed['seeded'] ?? false) !== true ||
    ($seed['synthetic_only'] ?? false) !== true ||
    ($safety['sanitized'] ?? false) !== true ||
    ($safety['source_head_match'] ?? false) !== true) {
    fwrite(STDERR, "FAIL: synthetic-only source/safety attestation missing\n");
    exit(1);
}
global $wpdb;
$prefix = $wpdb->prefix . 'eh7_';
$toRebuild = [
    'prepaid_return_requests' => ['uq_prepaid_return'],
    'prepaid_refund_evidence' => [
        'uq_refund_original_payment',
        'uq_refund_evidence_ref',
        'uq_refund_verify_ref',
    ],
    'salary_structure_versions' => [
        'employee_effective',
        'uq_salary_revision_id',
    ],
    'reward_adjustments' => [
        'company_branch_status',
        'employee_status',
        'maker_review',
    ],
    'promotion_requests' => [
        'company_branch_status',
        'employee_status',
        'maker_review',
    ],
];
$preservedTables = [
    $wpdb->users,
    $wpdb->usermeta,
    $prefix . 'companies',
    $prefix . 'branches',
    $prefix . 'employees',
    $prefix . 'stock_balances',
    $prefix . 'stock_ledger',
    $prefix . 'journal_entries',
    $prefix . 'prepaid_sales_orders',
    $prefix . 'prepaid_sales_order_payments',
    $prefix . 'mobile_sessions',
];
function eh7_ci_table_exists(string $table): bool {
    global $wpdb;
    return (string) $wpdb->get_var(
        $wpdb->prepare('SHOW TABLES LIKE %s', $table)
    ) === $table;
}
function eh7_ci_snapshot(array $tables): array {
    global $wpdb;
    $out = [];
    foreach ($tables as $table) {
        if (!eh7_ci_table_exists($table)) {
            throw new \RuntimeException("Preserved source table missing: " . $table);
        }
        // Names are internal, fixed and validated (never user input).
        $pk = $table === $wpdb->usermeta ? 'umeta_id' : ($table === $wpdb->users ? 'ID' : 'id');
        $rows = $wpdb->get_results("SELECT * FROM `{$table}` ORDER BY `{$pk}` ASC", ARRAY_A);
        if (!is_array($rows)) {
            throw new \RuntimeException("Cannot snapshot source table: " . $table);
        }
        $out[$table] = [
            'count' => count($rows),
            'sha256' => hash('sha256', wp_json_encode($rows)),
        ];
    }
    return $out;
}
try {
    $before = eh7_ci_snapshot($preservedTables);
    // Migrating older synthetic users may legitimately INSERT missing baseline
    // salary records. Existing salary revision rows must remain byte-for-byte
    // unchanged; do not require the row COUNT to remain unchanged.
    $salaryRevisionTable = $prefix . 'salary_revisions';
    $existingSalaryRows = (array) $wpdb->get_results(
        "SELECT * FROM `{$salaryRevisionTable}` ORDER BY id", ARRAY_A
    );
    $assertOldSalaryPreserved = static function () use (
        $wpdb, $salaryRevisionTable, $existingSalaryRows
    ): void {
        foreach ($existingSalaryRows as $beforeRow) {
            $id = (int) $beforeRow['id'];
            $actual = $wpdb->get_row($wpdb->prepare(
                "SELECT * FROM `{$salaryRevisionTable}` WHERE id=%d", $id
            ), ARRAY_A);
            if ($actual !== $beforeRow) {
                throw new \RuntimeException(
                    "Existing salary revision mutated during upgrade: " . $id
                );
            }
        }
    };
    foreach ($toRebuild as $name => $_keys) {
        $table = $prefix . $name;
        if (!eh7_ci_table_exists($table)) {
            throw new \RuntimeException("Expected new table missing before rehearsal: " . $name);
        }
        $count = (int) $wpdb->get_var("SELECT COUNT(*) FROM `{$table}`");
        if ($count !== 0) {
            throw new \RuntimeException("Refusing to drop nonempty additive table: " . $name);
        }
    }
    foreach (array_keys($toRebuild) as $name) {
        $table = $prefix . $name;
        if ($wpdb->query("DROP TABLE `{$table}`") === false) {
            throw new \RuntimeException("Disposable table drop failed: " . $name);
        }
    }
    update_option('eh7_schema_version', '7.3.10-prepaid-sales-1', false);
    $expected = \ExcelHerbal\ERP7\Database\Schema::VERSION;
    if ($expected !== '7.3.12-promotion-review-4') {
        throw new \RuntimeException('Unexpected migration release: ' . $expected);
    }
    if (\ExcelHerbal\ERP7\Database\Schema::maybeUpgrade() !== true ||
        (string) get_option('eh7_schema_version', '') !== $expected) {
        throw new \RuntimeException('Failed additive schema upgrade to current version');
    }
    foreach ($toRebuild as $name => $requiredKeys) {
        $table = $prefix . $name;
        if (!eh7_ci_table_exists($table)) {
            throw new \RuntimeException("Upgrade failed to recreate: " . $name);
        }
        $indexes = $wpdb->get_results("SHOW INDEX FROM `{$table}`", ARRAY_A);
        $present = array_unique(array_map(
            static fn(array $row): string => (string) ($row['Key_name'] ?? ''),
            (array) $indexes
        ));
        foreach ($requiredKeys as $key) {
            if (!in_array($key, $present, true)) {
                throw new \RuntimeException("Upgrade missing uniqueness guard: " . $name . '.' . $key);
            }
        }
    }
    $assertOldSalaryPreserved();
    if (eh7_ci_snapshot($preservedTables) !== $before) {
        throw new \RuntimeException('Existing synthetic identity/stock/finance data changed after upgrade');
    }
    // Explicitly rerun the installer, not just the option-version no-op.
    \ExcelHerbal\ERP7\Database\Schema::install();
    $assertOldSalaryPreserved();
    if (eh7_ci_snapshot($preservedTables) !== $before ||
        (string) get_option('eh7_schema_version', '') !== $expected) {
        throw new \RuntimeException('Repeated schema installation changed existing rows/version');
    }
    if (!empty(get_option('eh7_schema_migration_error', ''))) {
        throw new \RuntimeException('Schema migration left a recorded error');
    }
    echo "PASS synthetic v7.3.10-to-7.3.12 refund/salary additive migration\n";
    echo "PASS refund and salary uniqueness indexes; existing salary revision IDs and identity/stock/journal preserved\n";
    echo "PASS repeated schema install is idempotent on disposable WordPress/MariaDB\n";
} catch (\Throwable $e) {
    fwrite(STDERR, "FAIL disposable additive upgrade rehearsal: " . $e->getMessage() . "\n");
    exit(1);
}
