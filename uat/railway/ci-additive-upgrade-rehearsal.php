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
// Imported fixture is limited to disposable, synthetic, uniquely named CI DB.
// Its dummy rows and live-shaped extra columns/indexes must survive migration.
require '/tmp/eh7-ci-live-shaped-fixture.php';
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
    'reward_payroll_link_proposals' => [
        'uq_company_reward',
        'company_branch_status',
        'payroll_item',
        'beneficiary',
    ],
    'reward_payroll_allocations' => [
        'uq_reward_allocation',
        'uq_payroll_item_allocation',
        'uq_proposal_allocation',
        'company_run',
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
    $prefix . 'stock_quarantine',
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

function eh7_ci_assert_live_shape_upgraded(string $prefix): void {
    global $wpdb;
    foreach (['report_reminder_drafts','report_submissions','report_submission_events'] as $name) {
        $table=$prefix.$name;
        if (!eh7_ci_table_exists($table) ||
            (int)$wpdb->get_var("SELECT COUNT(*) FROM {$table}")!==1) {
            throw new \RuntimeException('Live-only synthetic report or its row lost: '.$name);
        }
    }
    $stock=$prefix.'stock_quarantine';
    $stockColumns=(int)$wpdb->get_var("SELECT COUNT(*) FROM information_schema.COLUMNS " .
        "WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='{$stock}' " .
        "AND COLUMN_NAME IN ('unit_cost_snapshot','journal_entry_id')");
    $quarantine=$wpdb->get_row("SELECT unit_cost_snapshot,journal_entry_id,quantity " .
        "FROM {$stock} ORDER BY id LIMIT 1", ARRAY_A);
    if ($stockColumns!==2 || !$quarantine ||
        abs((float)$quarantine['unit_cost_snapshot']-12.34)>.00001 ||
        abs((float)$quarantine['quantity']-.25)>.00001 ||
        $quarantine['journal_entry_id']!==null) {
        throw new \RuntimeException('Live-only stock quarantine columns/data were not preserved');
    }
    $sessionIndex=(array)$wpdb->get_results("SHOW INDEX FROM {$prefix}mobile_sessions " .
        "WHERE Key_name='employee_device'", ARRAY_A);
    usort($sessionIndex,static fn(array $a,array $b):int =>
        (int)$a['Seq_in_index'] <=> (int)$b['Seq_in_index']);
    $cols=array_column($sessionIndex,'Column_name');
    if ($cols!==['employee_id','wp_user_id','device_key']) {
        throw new \RuntimeException('Missing required mobile session composite index after upgrade');
    }
    $dummy=$wpdb->get_row($wpdb->prepare(
        "SELECT employee_id,wp_user_id,revoked_at,refresh_expires_at FROM {$prefix}mobile_sessions WHERE access_hash=%s",
        hash('sha256','CI-MIGRATION-DUMMY-ACCESS')),ARRAY_A);
    if (!$dummy || (int)$dummy['employee_id']<1 || (int)$dummy['wp_user_id']<1 ||
        $dummy['revoked_at']!==null || $dummy['refresh_expires_at']<=gmdate('Y-m-d H:i:s')) {
        throw new \RuntimeException('Existing active synthetic session revoked or lost during migration');
    }
    $employeeIndex=(array)$wpdb->get_results("SHOW INDEX FROM {$prefix}employees " .
        "WHERE Key_name='branch_status'", ARRAY_A);
    usort($employeeIndex,static fn(array $a,array $b):int =>
        (int)$a['Seq_in_index'] <=> (int)$b['Seq_in_index']);
    if (array_column($employeeIndex,'Column_name')!==['company_id','assigned_branch_id','status']) {
        throw new \RuntimeException('Live-only employee lookup index was dropped/changed');
    }
    // Preserve ALL 16 observed historical lookup indexes, including exact
    // column order and nonunique status, on both upgrade and second install.
    $preservedIndexCount = 0;
    foreach (eh7_ci_live_only_index_map() as $table => $indexes) {
        foreach ($indexes as $name => $expectedColumns) {
            $actual = (array)$wpdb->get_results($wpdb->prepare(
                'SELECT COLUMN_NAME,NON_UNIQUE FROM information_schema.STATISTICS ' .
                'WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME=%s AND INDEX_NAME=%s ORDER BY SEQ_IN_INDEX',
                $prefix.$table,$name),ARRAY_A);
            if (array_column($actual,'COLUMN_NAME') !== $expectedColumns ||
                array_unique(array_map(static fn(array $row):string =>
                    (string)$row['NON_UNIQUE'],$actual)) !== ['1']) {
                throw new \RuntimeException('Historical Office lookup index changed: '.$table.'.'.$name);
            }
            $preservedIndexCount++;
        }
    }
    if ($preservedIndexCount !== 16) {
        throw new \RuntimeException('Incomplete historical Office index preservation');
    }
}
try {
    $liveShapePreserved = eh7_ci_live_shaped_fixture();
    $preservedTables = array_merge($preservedTables, $liveShapePreserved);
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
    if ($expected !== '7.3.12-reward-payroll-allocated-6') {
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
    eh7_ci_assert_live_shape_upgraded($prefix);
    $assertOldSalaryPreserved();
    if (eh7_ci_snapshot($preservedTables) !== $before) {
        throw new \RuntimeException('Existing synthetic identity/stock/finance data changed after upgrade');
    }
    // Explicitly rerun the installer, not just the option-version no-op.
    \ExcelHerbal\ERP7\Database\Schema::install();
    eh7_ci_assert_live_shape_upgraded($prefix);
    $assertOldSalaryPreserved();
    if (eh7_ci_snapshot($preservedTables) !== $before ||
        (string) get_option('eh7_schema_version', '') !== $expected) {
        throw new \RuntimeException('Repeated schema installation changed existing rows/version');
    }
    if (!empty(get_option('eh7_schema_migration_error', ''))) {
        throw new \RuntimeException('Schema migration left a recorded error');
    }
    // With preservation assertions complete, validate auth against the dummy
    // active session and delete it BEFORE CI REST login/safety checks run.
    $_SERVER['HTTP_AUTHORIZATION']='Bearer CI-MIGRATION-DUMMY-ACCESS';
    try {
        $resolved=(int)\ExcelHerbal\ERP7\Security\MobileAuth::user(0);
    } finally {
        unset($_SERVER['HTTP_AUTHORIZATION']);
    }
    $dummyHash=hash('sha256','CI-MIGRATION-DUMMY-ACCESS');
    $sessionTable=$prefix.'mobile_sessions';
    $session=$wpdb->get_row($wpdb->prepare(
        "SELECT id,wp_user_id FROM {$sessionTable} WHERE access_hash=%s",$dummyHash),ARRAY_A);
    if (!$session || $resolved!==(int)$session['wp_user_id']) {
        throw new \RuntimeException('Preserved synthetic bearer session failed post-migration authentication');
    }
    if ($wpdb->delete($sessionTable,['id'=>(int)$session['id']])!==1 ||
        (int)$wpdb->get_var("SELECT COUNT(*) FROM {$sessionTable}")!==0) {
        throw new \RuntimeException('Synthetic active session not cleaned before follow-up REST tests');
    }
    echo "PASS dummy active session survived upgrade, authenticated and was cleaned before REST tests\n";
    echo "PASS synthetic v7.3.10-to-7.3.12 refund/salary additive migration\n";
    echo "PASS refund and salary uniqueness indexes; existing salary revision IDs and identity/stock/journal preserved\n";
    echo "PASS repeated schema install is idempotent on disposable WordPress/MariaDB\n";
    echo "PASS live-shaped report tables, quarantine financial columns and custom employee index preserved\n";
    echo "PASS missing employee_device composite index recreated without session changes\n";
} catch (\Throwable $e) {
    fwrite(STDERR, "FAIL disposable additive upgrade rehearsal: " . $e->getMessage() . "\n");
    exit(1);
}
