<?php
define('EH7_INTEGRATION_LIBRARY_ONLY', true);
require __DIR__.'/integration_mariadb.php';

use ExcelHerbal\ERP7\Database\Db;
use ExcelHerbal\ERP7\Database\Schema;
use ExcelHerbal\ERP7\Domain\DomainException;
use ExcelHerbal\ERP7\Sales\SalesService;
use ExcelHerbal\ERP7\Security\Actor;
use ExcelHerbal\ERP7\Security\Capabilities;

function sc_actor(): Actor {
    return new Actor(9101, 101, 1, 1, [1], [Capabilities::SALES_CREATE, Capabilities::RECEIPT_CREATE], 'SYSADMIN');
}

function sc_insert(Eh7IntegrationWpdb $db, string $table, array $row): void {
    if ($db->insert(Db::table($table), $row) === false) {
        throw new RuntimeException('Insert '.$table.' failed: '.$db->last_error);
    }
}

function sc_rebuild(Eh7IntegrationWpdb $db): void {
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

function sc_seed(Eh7IntegrationWpdb $db): void {
    sc_insert($db, 'companies', [
        'id' => 1, 'name' => 'Sales Concurrency Co', 'status' => 'active', 'created_at' => '2026-01-01 00:00:00',
    ]);
    sc_insert($db, 'branches', [
        'id' => 1, 'company_id' => 1, 'code' => 'B1', 'name' => 'Sales Concurrency Branch',
        'is_head_office' => 1, 'status' => 'active', 'created_at' => '2026-01-01 00:00:00',
    ]);
    sc_insert($db, 'employees', [
        'id' => 101, 'company_id' => 1, 'employee_code' => 'E101', 'wp_user_id' => 9101,
        'designation_code' => 'SYSADMIN', 'assigned_branch_id' => 1, 'full_name' => 'Sales Concurrency User',
        'mobile' => '9000000101', 'monthly_salary' => 0, 'joining_date' => '2026-01-01',
        'status' => 'active', 'created_at' => '2026-01-01 00:00:00',
    ]);
    sc_insert($db, 'parties', [
        'id' => 201, 'company_id' => 1, 'branch_id' => 1, 'type' => 'customer',
        'name' => 'Concurrency Customer', 'mobile' => '9000000201', 'status' => 'active',
        'created_at' => '2026-01-01 00:00:00',
    ]);
    sc_insert($db, 'products', [
        'id' => 100, 'company_id' => 1, 'sku' => 'SC-P100', 'name' => 'Concurrency Product', 'uom' => 'PCS',
        'batch_tracking' => 'off', 'expiry_tracking' => 0, 'status' => 'active', 'created_at' => '2026-01-01 00:00:00',
    ]);
    sc_insert($db, 'product_commercial_revisions', [
        'id' => 1, 'company_id' => 1, 'product_id' => 100, 'effective_from' => '2026-01-01 00:00:00',
        'mrp' => 120, 'sale_price' => 100, 'ho_amount' => 20, 'bm_profit' => 10, 'salary_fund' => 5,
        'office_expense' => 5, 'points' => 2, 'purchase_cost' => 40, 'reason' => 'Concurrency pricing',
        'status' => 'active', 'approved_by' => 101, 'created_at' => '2026-01-01 00:00:00',
    ]);
    sc_insert($db, 'stock_balances', [
        'id' => 1, 'company_id' => 1, 'branch_id' => 1, 'product_id' => 100,
        'batch_key' => 0, 'custodian_key' => 0, 'quantity' => 5, 'average_unit_cost' => 40,
        'updated_at' => '2026-01-01 00:00:00',
    ]);

    foreach ([
        [1, 'CASH', 'Cash', 'asset', 'cash'],
        [2, 'SALES', 'Sales', 'income', 'sales'],
        [3, 'COGS', 'Cost of Goods Sold', 'expense', 'cogs'],
        [4, 'INVENTORY', 'Inventory', 'asset', 'inventory'],
        [5, 'AR', 'Accounts Receivable', 'asset', 'receivable'],
    ] as [$id, $code, $name, $type, $subtype]) {
        sc_insert($db, 'accounts', [
            'id' => $id, 'company_id' => 1, 'code' => $code, 'name' => $name,
            'type' => $type, 'subtype' => $subtype, 'active' => 1,
        ]);
    }
}

function sc_wait(float $startAt): void {
    while (($remaining = $startAt - microtime(true)) > 0) {
        usleep((int)min(50000, max(1000, $remaining * 1000000)));
    }
}

function sc_worker(float $startAt): never {
    eh7_setup_global_db();
    sc_wait($startAt);
    try {
        $result = SalesService::counter(
            sc_actor(),
            1,
            null,
            400.0,
            1,
            [['product_id' => 100, 'quantity' => 4]]
        );
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

if (($argv[1] ?? '') === 'sales-worker') {
    sc_worker((float)($argv[2] ?? microtime(true)));
}

function sc_receipt_worker(float $startAt, int $saleId): never {
    eh7_setup_global_db();
    sc_wait($startAt);
    try {
        $result = SalesService::receipt(
            sc_actor(),
            1,
            $saleId,
            70.0,
            1,
            'parallel-receipt'
        );
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

if (($argv[1] ?? '') === 'receipt-worker') {
    sc_receipt_worker(
        (float)($argv[2] ?? microtime(true)),
        (int)($argv[3] ?? 0)
    );
}

function sc_parallel_two(): array {
    if (!function_exists('proc_open')) throw new RuntimeException('proc_open unavailable');
    $startAt = microtime(true) + 0.35;
    $spec = [0 => ['pipe', 'r'], 1 => ['pipe', 'w'], 2 => ['pipe', 'w']];
    $workers = [];

    for ($i = 0; $i < 2; $i++) {
        $pipes = [];
        $process = proc_open(
            [PHP_BINARY, __FILE__, 'sales-worker', sprintf('%.6F', $startAt)],
            $spec,
            $pipes
        );
        if (!is_resource($process)) throw new RuntimeException('Unable to start sales concurrency worker');
        fclose($pipes[0]);
        $workers[] = [$process, $pipes];
    }

    $out = [];
    foreach ($workers as [$process, $pipes]) {
        $stdout = stream_get_contents($pipes[1]); fclose($pipes[1]);
        $stderr = stream_get_contents($pipes[2]); fclose($pipes[2]);
        $exit = proc_close($process);
        if ($exit !== 0) throw new RuntimeException('sales worker failed: '.$stderr);
        $out[] = json_decode($stdout, true, 512, JSON_THROW_ON_ERROR);
    }
    return $out;
}

function sc_parallel_receipts(int $saleId): array {
    if (!function_exists('proc_open')) throw new RuntimeException('proc_open unavailable');
    $startAt = microtime(true) + 0.35;
    $spec = [0 => ['pipe', 'r'], 1 => ['pipe', 'w'], 2 => ['pipe', 'w']];
    $workers = [];

    for ($i = 0; $i < 2; $i++) {
        $pipes = [];
        $process = proc_open(
            [PHP_BINARY, __FILE__, 'receipt-worker', sprintf('%.6F', $startAt), (string)$saleId],
            $spec,
            $pipes
        );
        if (!is_resource($process)) throw new RuntimeException('Unable to start receipt concurrency worker');
        fclose($pipes[0]);
        $workers[] = [$process, $pipes];
    }

    $out = [];
    foreach ($workers as [$process, $pipes]) {
        $stdout = stream_get_contents($pipes[1]); fclose($pipes[1]);
        $stderr = stream_get_contents($pipes[2]); fclose($pipes[2]);
        $exit = proc_close($process);
        if ($exit !== 0) throw new RuntimeException('receipt worker failed: '.$stderr);
        $out[] = json_decode($stdout, true, 512, JSON_THROW_ON_ERROR);
    }
    return $out;
}

$wpdb = eh7_setup_global_db();
$failed = 0;

function sc_case(string $name, callable $fn): void {
    global $failed;
    try {
        $fn();
        echo "PASS {$name}\n";
    } catch (Throwable $e) {
        $failed++;
        echo "FAIL {$name}: {$e->getMessage()}\n";
    }
}

sc_case('concurrent_sales_do_not_oversell_stock', function () use ($wpdb) {
    sc_rebuild($wpdb);
    sc_seed($wpdb);

    $results = sc_parallel_two();
    $successes = array_values(array_filter($results, static fn($row) => ($row['ok'] ?? false) === true));
    $failures = array_values(array_filter($results, static fn($row) => ($row['ok'] ?? false) !== true));

    if (count($successes) !== 1 || count($failures) !== 1) {
        throw new RuntimeException('expected one sale success and one controlled rejection: '.json_encode($results));
    }
    if (($failures[0]['code'] ?? '') !== 'insufficient_stock' || (int)($failures[0]['http'] ?? 0) !== 409) {
        throw new RuntimeException('losing sale did not fail with insufficient_stock/409: '.json_encode($failures[0]));
    }

    $qty = (float)$wpdb->get_var(
        'SELECT quantity FROM '.Db::table('stock_balances').' WHERE company_id=1 AND branch_id=1 AND product_id=100 AND batch_key=0 AND custodian_key=0'
    );
    $sales = (int)$wpdb->get_var('SELECT COUNT(*) FROM '.Db::table('counter_sales'));
    $saleLines = (int)$wpdb->get_var('SELECT COUNT(*) FROM '.Db::table('counter_sale_lines'));
    $ledger = (int)$wpdb->get_var("SELECT COUNT(*) FROM ".Db::table('stock_ledger')." WHERE source_type='counter_sale'");
    $journals = (int)$wpdb->get_var("SELECT COUNT(*) FROM ".Db::table('journal_entries')." WHERE source_type='counter_sale' AND status='posted'");
    $unbalanced = (int)$wpdb->get_var(
        'SELECT COUNT(*) FROM (SELECT je.id FROM '.Db::table('journal_entries').' je JOIN '.Db::table('journal_lines').
        ' jl ON jl.journal_entry_id=je.id GROUP BY je.id HAVING ABS(SUM(jl.debit)-SUM(jl.credit))>0.005) x'
    );

    if (abs($qty - 1.0) > 0.001 || $qty < -0.0001) {
        throw new RuntimeException('stock oversell invariant failed quantity='.$qty);
    }
    if ($sales !== 1 || $saleLines !== 1 || $ledger !== 1 || $journals !== 1 || $unbalanced !== 0) {
        throw new RuntimeException(
            "atomic sale invariant mismatch sales={$sales} lines={$saleLines} ledger={$ledger} journals={$journals} unbalanced={$unbalanced}"
        );
    }
});

sc_case('concurrent_receipts_do_not_overcollect_sale', function () use ($wpdb) {
    sc_rebuild($wpdb);
    sc_seed($wpdb);

    $sale = SalesService::counter(
        sc_actor(),
        1,
        201,
        0.0,
        null,
        [['product_id' => 100, 'quantity' => 1]]
    );
    $saleId = (int)$sale['id'];

    $results = sc_parallel_receipts($saleId);
    $successes = array_values(array_filter($results, static fn($row) => ($row['ok'] ?? false) === true));
    $failures = array_values(array_filter($results, static fn($row) => ($row['ok'] ?? false) !== true));

    if (count($successes) !== 1 || count($failures) !== 1) {
        throw new RuntimeException('expected one receipt success and one controlled rejection: '.json_encode($results));
    }
    if (($failures[0]['code'] ?? '') !== 'customer_advance_disabled' || (int)($failures[0]['http'] ?? 0) !== 409) {
        throw new RuntimeException('losing receipt did not fail with customer_advance_disabled/409: '.json_encode($failures[0]));
    }

    $row = $wpdb->get_row(
        $wpdb->prepare('SELECT paid_amount,outstanding_amount FROM '.Db::table('counter_sales').' WHERE id=%d', $saleId),
        ARRAY_A
    );
    $paid = (float)($row['paid_amount'] ?? -1);
    $outstanding = (float)($row['outstanding_amount'] ?? -1);
    $receipts = (int)$wpdb->get_var(
        $wpdb->prepare('SELECT COUNT(*) FROM '.Db::table('customer_receipts').' WHERE sale_id=%d AND status=\'posted\'', $saleId)
    );
    $receiptAmount = (float)$wpdb->get_var(
        $wpdb->prepare('SELECT COALESCE(SUM(amount),0) FROM '.Db::table('customer_receipts').' WHERE sale_id=%d AND status=\'posted\'', $saleId)
    );
    $receiptJournals = (int)$wpdb->get_var(
        "SELECT COUNT(*) FROM ".Db::table('journal_entries')." WHERE source_type='customer_receipt' AND status='posted'"
    );
    $unbalanced = (int)$wpdb->get_var(
        'SELECT COUNT(*) FROM (SELECT je.id FROM '.Db::table('journal_entries').' je JOIN '.Db::table('journal_lines').
        ' jl ON jl.journal_entry_id=je.id GROUP BY je.id HAVING ABS(SUM(jl.debit)-SUM(jl.credit))>0.005) x'
    );

    if (abs($paid - 70.0) > 0.001 || abs($outstanding - 30.0) > 0.001) {
        throw new RuntimeException("sale collection invariant failed paid={$paid} outstanding={$outstanding}");
    }
    if ($receipts !== 1 || abs($receiptAmount - 70.0) > 0.001 || $receiptJournals !== 1 || $unbalanced !== 0) {
        throw new RuntimeException(
            "receipt atomicity mismatch receipts={$receipts} amount={$receiptAmount} journals={$receiptJournals} unbalanced={$unbalanced}"
        );
    }
});

echo ($failed ? 'FAILED' : 'PASSED')." sales concurrency suite\n";
exit($failed ? 1 : 0);
