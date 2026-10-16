<?php
define('EH7_INTEGRATION_LIBRARY_ONLY', true);
require __DIR__.'/integration_mariadb.php';

use ExcelHerbal\ERP7\Database\Db;
use ExcelHerbal\ERP7\Database\Schema;
use ExcelHerbal\ERP7\Domain\DomainException;
use ExcelHerbal\ERP7\Purchase\PurchaseService;
use ExcelHerbal\ERP7\Security\Actor;
use ExcelHerbal\ERP7\Security\Capabilities;

function pc_actor(): Actor {
    return new Actor(
        9201,
        102,
        1,
        1,
        [1],
        [Capabilities::PURCHASE_CREATE, Capabilities::SUPPLIER_PAYMENT],
        'SYSADMIN'
    );
}

function pc_insert(Eh7IntegrationWpdb $db, string $table, array $row): void {
    if ($db->insert(Db::table($table), $row) === false) {
        throw new RuntimeException('Insert '.$table.' failed: '.$db->last_error);
    }
}

function pc_rebuild(Eh7IntegrationWpdb $db): void {
    $definitions = Schema::definitions();
    $db->query('SET FOREIGN_KEY_CHECKS=0');
    foreach (array_keys($definitions) as $name) {
        if ($db->query('DROP TABLE IF EXISTS '.Db::table($name)) === false) {
            throw new RuntimeException('Drop '.$name.' failed: '.$db->last_error);
        }
    }
    foreach ($definitions as $name => $definition) {
        if ($db->query('CREATE TABLE '.Db::table($name).' ('.$definition.') ENGINE=InnoDB DEFAULT CHARSET=utf8mb4') === false) {
            throw new RuntimeException('Create '.$name.' failed: '.$db->last_error);
        }
    }
    $db->query('SET FOREIGN_KEY_CHECKS=1');
}

function pc_seed(Eh7IntegrationWpdb $db): void {
    pc_insert($db, 'companies', [
        'id' => 1, 'name' => 'Purchase Concurrency Co', 'status' => 'active',
        'created_at' => '2026-01-01 00:00:00',
    ]);
    pc_insert($db, 'branches', [
        'id' => 1, 'company_id' => 1, 'code' => 'B1', 'name' => 'Purchase Concurrency Branch',
        'is_head_office' => 1, 'status' => 'active', 'created_at' => '2026-01-01 00:00:00',
    ]);
    pc_insert($db, 'employees', [
        'id' => 102, 'company_id' => 1, 'employee_code' => 'E102', 'wp_user_id' => 9201,
        'designation_code' => 'SYSADMIN', 'assigned_branch_id' => 1,
        'full_name' => 'Purchase Concurrency User', 'mobile' => '9000000102',
        'monthly_salary' => 0, 'joining_date' => '2026-01-01',
        'status' => 'active', 'created_at' => '2026-01-01 00:00:00',
    ]);
    pc_insert($db, 'suppliers', [
        'id' => 301, 'company_id' => 1, 'name' => 'Concurrency Supplier',
        'mobile' => '9000000301', 'status' => 'active',
        'created_at' => '2026-01-01 00:00:00',
    ]);
    pc_insert($db, 'products', [
        'id' => 100, 'company_id' => 1, 'sku' => 'PC-P100',
        'name' => 'Purchase Concurrency Product', 'uom' => 'PCS',
        'batch_tracking' => 'off', 'expiry_tracking' => 0, 'status' => 'active',
        'created_at' => '2026-01-01 00:00:00',
    ]);
    foreach ([
        [1, 'CASH', 'Cash', 'asset', 'cash'],
        [2, 'INVENTORY', 'Inventory', 'asset', 'inventory'],
        [3, 'AP', 'Accounts Payable', 'liability', 'payable'],
    ] as [$id, $code, $name, $type, $subtype]) {
        pc_insert($db, 'accounts', [
            'id' => $id, 'company_id' => 1, 'code' => $code, 'name' => $name,
            'type' => $type, 'subtype' => $subtype, 'active' => 1,
        ]);
    }
}

function pc_wait(float $startAt): void {
    while (($remaining = $startAt - microtime(true)) > 0) {
        usleep((int)min(50000, max(1000, $remaining * 1000000)));
    }
}

function pc_payment_worker(float $startAt, int $billId): never {
    eh7_setup_global_db();
    pc_wait($startAt);
    try {
        $result = PurchaseService::payment(pc_actor(), $billId, 70.0, 1);
        echo json_encode(['ok' => true, 'result' => $result], JSON_THROW_ON_ERROR);
        exit(0);
    } catch (DomainException $e) {
        echo json_encode([
            'ok' => false,
            'code' => $e->codeKey,
            'http' => $e->httpStatus,
            'message' => $e->getMessage(),
        ], JSON_THROW_ON_ERROR);
        exit(0);
    } catch (Throwable $e) {
        fwrite(STDERR, get_class($e).': '.$e->getMessage());
        exit(2);
    }
}

if (($argv[1] ?? '') === 'purchase-payment-worker') {
    pc_payment_worker(
        (float)($argv[2] ?? microtime(true)),
        (int)($argv[3] ?? 0)
    );
}

function pc_parallel_payments(int $billId): array {
    if (!function_exists('proc_open')) throw new RuntimeException('proc_open unavailable');
    $startAt = microtime(true) + 0.35;
    $spec = [0 => ['pipe', 'r'], 1 => ['pipe', 'w'], 2 => ['pipe', 'w']];
    $workers = [];

    for ($i = 0; $i < 2; $i++) {
        $pipes = [];
        $process = proc_open(
            [PHP_BINARY, __FILE__, 'purchase-payment-worker', sprintf('%.6F', $startAt), (string)$billId],
            $spec,
            $pipes
        );
        if (!is_resource($process)) throw new RuntimeException('Unable to start purchase payment worker');
        fclose($pipes[0]);
        $workers[] = [$process, $pipes];
    }

    $out = [];
    foreach ($workers as [$process, $pipes]) {
        $stdout = stream_get_contents($pipes[1]); fclose($pipes[1]);
        $stderr = stream_get_contents($pipes[2]); fclose($pipes[2]);
        $exit = proc_close($process);
        if ($exit !== 0) throw new RuntimeException('purchase payment worker failed: '.$stderr);
        $out[] = json_decode($stdout, true, 512, JSON_THROW_ON_ERROR);
    }
    return $out;
}

$wpdb = eh7_setup_global_db();
$failed = 0;

function pc_case(string $name, callable $fn): void {
    global $failed;
    try {
        $fn();
        echo "PASS {$name}\n";
    } catch (Throwable $e) {
        $failed++;
        echo "FAIL {$name}: {$e->getMessage()}\n";
    }
}

pc_case('concurrent_supplier_payments_do_not_overpay_bill', function () use ($wpdb) {
    pc_rebuild($wpdb);
    pc_seed($wpdb);

    $bill = PurchaseService::bill(
        pc_actor(),
        1,
        301,
        'PC-001',
        Db::today(),
        [['product_id' => 100, 'quantity' => 1, 'unit_cost' => 100.0]]
    );
    $billId = (int)$bill['id'];

    $results = pc_parallel_payments($billId);
    $successes = array_values(array_filter($results, static fn($row) => ($row['ok'] ?? false) === true));
    $failures = array_values(array_filter($results, static fn($row) => ($row['ok'] ?? false) !== true));

    if (count($successes) !== 1 || count($failures) !== 1) {
        throw new RuntimeException('expected one payment success and one controlled rejection: '.json_encode($results));
    }
    if (($failures[0]['code'] ?? '') !== 'supplier_advance_disabled' || (int)($failures[0]['http'] ?? 0) !== 409) {
        throw new RuntimeException('losing payment did not fail with supplier_advance_disabled/409: '.json_encode($failures[0]));
    }

    $row = $wpdb->get_row(
        $wpdb->prepare('SELECT paid_amount,outstanding_amount FROM '.Db::table('purchase_bills').' WHERE id=%d', $billId),
        ARRAY_A
    );
    $paid = (float)($row['paid_amount'] ?? -1);
    $outstanding = (float)($row['outstanding_amount'] ?? -1);
    $payments = (int)$wpdb->get_var(
        $wpdb->prepare('SELECT COUNT(*) FROM '.Db::table('supplier_payments').' WHERE purchase_bill_id=%d AND status=\'posted\'', $billId)
    );
    $paymentAmount = (float)$wpdb->get_var(
        $wpdb->prepare('SELECT COALESCE(SUM(amount),0) FROM '.Db::table('supplier_payments').' WHERE purchase_bill_id=%d AND status=\'posted\'', $billId)
    );
    $paymentJournals = (int)$wpdb->get_var(
        "SELECT COUNT(*) FROM ".Db::table('journal_entries')." WHERE source_type='supplier_payment' AND status='posted'"
    );
    $unbalanced = (int)$wpdb->get_var(
        'SELECT COUNT(*) FROM (SELECT je.id FROM '.Db::table('journal_entries').' je JOIN '.Db::table('journal_lines').
        ' jl ON jl.journal_entry_id=je.id GROUP BY je.id HAVING ABS(SUM(jl.debit)-SUM(jl.credit))>0.005) x'
    );

    if (abs($paid - 70.0) > 0.001 || abs($outstanding - 30.0) > 0.001) {
        throw new RuntimeException("supplier bill invariant failed paid={$paid} outstanding={$outstanding}");
    }
    if ($payments !== 1 || abs($paymentAmount - 70.0) > 0.001 || $paymentJournals !== 1 || $unbalanced !== 0) {
        throw new RuntimeException(
            "supplier payment atomicity mismatch payments={$payments} amount={$paymentAmount} journals={$paymentJournals} unbalanced={$unbalanced}"
        );
    }
});

echo ($failed ? 'FAILED' : 'PASSED')." purchase concurrency suite\n";
exit($failed ? 1 : 0);
