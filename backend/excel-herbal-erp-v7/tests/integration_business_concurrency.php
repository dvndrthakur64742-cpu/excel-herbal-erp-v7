<?php
define('EH7_INTEGRATION_LIBRARY_ONLY', true);
require __DIR__.'/integration_mariadb.php';

use ExcelHerbal\ERP7\Database\Db;
use ExcelHerbal\ERP7\Database\Schema;
use ExcelHerbal\ERP7\Domain\DomainException;
use ExcelHerbal\ERP7\Inventory\InventoryService;
use ExcelHerbal\ERP7\Organization\OrganizationEmployeeService;
use ExcelHerbal\ERP7\Organization\OrganizationBranchService;
use ExcelHerbal\ERP7\Payroll\PayrollPerformanceService;
use ExcelHerbal\ERP7\Payroll\SalaryService;
use ExcelHerbal\ERP7\Security\Actor;
use ExcelHerbal\ERP7\Security\Capabilities;
use ExcelHerbal\ERP7\Database\Transaction;
use ExcelHerbal\ERP7\Finance\AccountingService;
use ExcelHerbal\ERP7\Finance\FinancePeriodService;

const EH7_BC_DATE = '2026-09-01';

function bc_actor(array $caps): Actor {
    return new Actor(9001, 101, 1, 1, [1, 2], $caps, 'SYSADMIN');
}

function bc_rebuild_schema(Eh7IntegrationWpdb $db): void {
    $names = [
        'stock_transfer_lines', 'stock_transfers', 'branch_closings', 'hr_separations',
        'audit_log', 'performance_entries', 'leave_requests', 'attendance', 'holidays',
        'accounts', 'journal_entries', 'journal_lines', 'number_series',
        'expenses', 'daily_cycles', 'stock_adjustments', 'reversals', 'accounting_periods',
        'settings', 'payroll_items', 'payroll_runs', 'salary_revisions',
        'employee_branch_authorities', 'employee_branch_history', 'employees', 'branches', 'companies',
    ];
    $definitions = Schema::definitions();
    $db->query('SET FOREIGN_KEY_CHECKS=0');
    foreach ($names as $name) {
        $db->query('DROP TABLE IF EXISTS '.Db::table($name));
    }
    foreach (array_reverse($names) as $name) {
        if (!isset($definitions[$name])) throw new RuntimeException('Schema definition missing for '.$name);
        $sql = 'CREATE TABLE '.Db::table($name).' ('.$definitions[$name].') ENGINE=InnoDB DEFAULT CHARSET=utf8mb4';
        if ($db->query($sql) === false) throw new RuntimeException('Create '.$name.' failed: '.$db->last_error);
    }
    $db->query('SET FOREIGN_KEY_CHECKS=1');
}

function bc_insert(Eh7IntegrationWpdb $db, string $table, array $row): void {
    if ($db->insert(Db::table($table), $row) === false) {
        throw new RuntimeException('Insert '.$table.' failed: '.$db->last_error);
    }
}

function bc_seed_head_office(Eh7IntegrationWpdb $db): void {
    bc_insert($db, 'companies', [
        'id' => 1, 'name' => 'Concurrency Test Co', 'status' => 'active', 'created_at' => '2026-01-01 00:00:00',
    ]);
}

function bc_seed_payroll(Eh7IntegrationWpdb $db, bool $pendingSalary = false): void {
    bc_insert($db, 'companies', [
        'id' => 1, 'name' => 'Concurrency Test Co', 'status' => 'active', 'created_at' => '2026-01-01 00:00:00',
    ]);
    bc_insert($db, 'branches', [
        'id' => 1, 'company_id' => 1, 'code' => 'B1', 'name' => 'Branch One',
        'is_head_office' => 1, 'status' => 'active', 'created_at' => '2026-01-01 00:00:00',
    ]);
    bc_insert($db, 'branches', [
        'id' => 2, 'company_id' => 1, 'code' => 'B2', 'name' => 'Branch Two',
        'is_head_office' => 0, 'status' => 'active', 'created_at' => '2026-01-01 00:00:00',
    ]);
    bc_insert($db, 'employees', [
        'id' => 10, 'company_id' => 1, 'employee_code' => 'E10', 'designation_code' => 'BM',
        'assigned_branch_id' => 1, 'full_name' => 'Concurrency Employee', 'monthly_salary' => 1000,
        'joining_date' => '2026-01-01', 'status' => 'active', 'created_at' => '2026-01-01 00:00:00',
    ]);
    // The synthetic actor must exist in the hierarchy engine. Its future joining
    // date keeps it outside the September payroll snapshot under test.
    bc_insert($db, 'employees', [
        'id' => 101, 'company_id' => 1, 'employee_code' => 'ADMIN101', 'designation_code' => 'SYSADMIN',
        'assigned_branch_id' => 1, 'full_name' => 'Concurrency Admin', 'monthly_salary' => 0,
        'joining_date' => '2026-10-01', 'status' => 'active', 'created_at' => '2026-01-01 00:00:00',
    ]);
    bc_insert($db, 'employee_branch_history', [
        'id' => 1, 'company_id' => 1, 'employee_id' => 10, 'branch_id' => 1,
        'effective_from' => '2026-01-01', 'effective_to' => null, 'reason' => 'Initial assignment',
        'changed_by' => 101, 'created_at' => '2026-01-01 00:00:00',
    ]);
    bc_insert($db, 'salary_revisions', [
        'id' => 1, 'company_id' => 1, 'employee_id' => 10, 'effective_from' => '2026-01-01',
        'monthly_salary' => 1000, 'status' => 'baseline', 'reason' => 'Baseline salary',
        'created_by' => 201, 'created_at' => '2026-01-01 00:00:00',
    ]);
    if ($pendingSalary) {
        bc_insert($db, 'salary_revisions', [
            'id' => 2, 'company_id' => 1, 'employee_id' => 10, 'effective_from' => EH7_BC_DATE,
            'monthly_salary' => 2000, 'status' => 'pending', 'reason' => 'Reviewed salary increase',
            'created_by' => 201, 'created_at' => '2026-08-31 00:00:00',
        ]);
    }
    bc_insert($db, 'settings', [
        'company_id' => 1, 'setting_key' => 'weekly_off_iso_days', 'setting_value' => '[7]',
        'updated_at' => '2026-01-01 00:00:00',
    ]);
    bc_insert($db, 'settings', [
        'company_id' => 1, 'setting_key' => 'payroll_leave_types', 'setting_value' => '{}',
        'updated_at' => '2026-01-01 00:00:00',
    ]);
    bc_insert($db, 'attendance', [
        'company_id' => 1, 'branch_id' => 1, 'employee_id' => 10, 'business_date' => EH7_BC_DATE,
        'status' => 'present', 'created_at' => '2026-09-01 09:00:00',
    ]);
}

function bc_seed_reporting(Eh7IntegrationWpdb $db): void {
    bc_insert($db, 'companies', [
        'id' => 1, 'name' => 'Concurrency Test Co', 'status' => 'active', 'created_at' => '2026-01-01 00:00:00',
    ]);
    bc_insert($db, 'branches', [
        'id' => 1, 'company_id' => 1, 'code' => 'B1', 'name' => 'Branch One',
        'is_head_office' => 1, 'status' => 'active', 'created_at' => '2026-01-01 00:00:00',
    ]);
    foreach ([[10,'E10','Employee A'],[11,'E11','Employee B']] as [$id,$code,$name]) {
        bc_insert($db, 'employees', [
            'id' => $id, 'company_id' => 1, 'employee_code' => $code, 'designation_code' => 'BM',
            'assigned_branch_id' => 1, 'full_name' => $name, 'monthly_salary' => 1000,
            'joining_date' => '2026-01-01', 'status' => 'active', 'created_at' => '2026-01-01 00:00:00',
        ]);
    }
    // Reporting mutations run as synthetic SYSADMIN 101. Production actors are
    // always backed by an active employee row, so keep the concurrency fixture
    // subject to the same hierarchy-scope precondition.
    bc_insert($db, 'employees', [
        'id' => 101, 'company_id' => 1, 'employee_code' => 'ADMIN101', 'designation_code' => 'SYSADMIN',
        'assigned_branch_id' => 1, 'full_name' => 'Concurrency Admin', 'monthly_salary' => 0,
        'joining_date' => '2026-10-01', 'status' => 'active', 'created_at' => '2026-01-01 00:00:00',
    ]);
}

function bc_seed_transfer(Eh7IntegrationWpdb $db): void {
    bc_insert($db, 'companies', [
        'id' => 1, 'name' => 'Concurrency Test Co', 'status' => 'active', 'created_at' => '2026-01-01 00:00:00',
    ]);
    bc_insert($db, 'stock_transfers', [
        'id' => 1, 'company_id' => 1, 'source_branch_id' => 1, 'destination_branch_id' => 2,
        'status' => 'draft', 'created_by' => 101, 'created_at' => '2026-09-01 08:00:00',
        'notes' => 'Concurrency fixture',
    ]);
    bc_insert($db, 'stock_transfer_lines', [
        'id' => 1, 'transfer_id' => 1, 'product_id' => 500, 'batch_id' => null,
        'quantity' => 5, 'received_quantity' => 0, 'unit_cost_snapshot' => 0,
    ]);
}


function bc_seed_finance_close_race(Eh7IntegrationWpdb $db): void {
    bc_insert($db,'companies',['id'=>1,'name'=>'Finance Concurrency Co','status'=>'active','created_at'=>'2026-01-01 00:00:00']);
    foreach ([1,2] as $branch) {
        bc_insert($db,'branches',[
            'id'=>$branch,'company_id'=>1,'code'=>'B'.$branch,'name'=>'Branch '.$branch,
            'is_head_office'=>$branch===1?1:0,'status'=>'active','created_at'=>'2026-01-01 00:00:00',
        ]);
        bc_insert($db,'branch_closings',[
            'company_id'=>1,'branch_id'=>$branch,'business_date'=>'2019-01-15',
            'status'=>'closed','created_by'=>101,'closed_by'=>101,
            'created_at'=>'2019-01-15 22:00:00','closed_at'=>'2019-01-15 22:30:00',
        ]);
    }
    foreach ([[1,'TEST_CASH','asset'],[2,'TEST_EXPENSE','expense']] as [$id,$code,$type]) {
        bc_insert($db,'accounts',[
            'id'=>$id,'company_id'=>1,'code'=>$code,'name'=>$code,'type'=>$type,'active'=>1,
        ]);
    }
    bc_insert($db,'expenses',[
        'id'=>1,'company_id'=>1,'branch_id'=>1,'expense_head_id'=>1,
        'amount'=>50,'payment_account_id'=>1,'status'=>'approved',
        'expense_date'=>'2019-01-15','description'=>'Race source',
        'created_by'=>101,'approved_by'=>101,'created_at'=>'2019-01-15 10:00:00',
    ]);
}

/** Named-lock notification forces journal posting to start after closer owns the company-row lock. */
function bc_close_period_with_signal(): array {
    $actor=bc_actor([Capabilities::PERIOD_MANAGE]);
    return Transaction::run(function()use($actor) {
        AccountingService::lockCompanyForPeriod($actor);
        $db=Db::wpdb();
        $held=$db->get_var("SELECT GET_LOCK('eh7_bc_period_close_ready',5)");
        if((int)$held!==1)throw new RuntimeException('Finance close signal lock unavailable');
        try {
            usleep(450000);
            return FinancePeriodService::closePeriod($actor,'2019-01-15','2019-01-15');
        } finally {
            $db->get_var("SELECT RELEASE_LOCK('eh7_bc_period_close_ready')");
        }
    });
}
function bc_post_during_period_close(): int {
    $db=Db::wpdb();$deadline=microtime(true)+5;$seen=false;
    do {
        $held=$db->get_var("SELECT IS_USED_LOCK('eh7_bc_period_close_ready')");
        if($held!==null){$seen=true;break;}
        usleep(10000);
    } while(microtime(true)<$deadline);
    if(!$seen)throw new RuntimeException('Never observed pending finance close');
    $actor=bc_actor([Capabilities::PERIOD_MANAGE]);
    return AccountingService::post($actor,1,'expense',1,'2019-01-15 12:00:00',[
        ['account_id'=>2,'debit'=>50,'credit'=>0],
        ['account_id'=>1,'debit'=>0,'credit'=>50],
    ],'Reject if period close committed first');
}

function bc_wait(float $startAt): void {
    while (($remaining = $startAt - microtime(true)) > 0) {
        usleep((int)min(50000, max(1000, $remaining * 1000000)));
    }
}

function bc_worker(string $mode, float $startAt): never {
    eh7_setup_global_db();
    bc_wait($startAt);
    try {
        $result = match ($mode) {
            'payroll-generate' => PayrollPerformanceService::generate(
                bc_actor([Capabilities::PAYROLL_GENERATE]), 1, EH7_BC_DATE, EH7_BC_DATE
            ),
            'transfer-pack' => InventoryService::transferAction(
                bc_actor([Capabilities::TRANSFER_CREATE]), 1, 'pack'
            ),
            'employee-transfer' => OrganizationEmployeeService::transferEmployee(
                bc_actor([Capabilities::EMP_MANAGE]), 10, 2, EH7_BC_DATE, 'Concurrency transfer test'
            ),
            'salary-approve' => SalaryService::approve(
                bc_actor([Capabilities::SALARY_APPROVE]), 2, true
            ),
            'report-a-to-b' => OrganizationEmployeeService::setReportingManager(
                bc_actor([Capabilities::EMP_MANAGE]), 10, 11, 'Concurrent reporting assignment A to B'
            ),
            'report-b-to-a' => OrganizationEmployeeService::setReportingManager(
                bc_actor([Capabilities::EMP_MANAGE]), 11, 10, 'Concurrent reporting assignment B to A'
            ),
            'head-office-a' => OrganizationBranchService::createBranch(
                bc_actor([Capabilities::BRANCH_MANAGE]), 'HO-A', 'Head Office A', true
            ),
            'period-close-guard' => bc_close_period_with_signal(),
            'period-post-guard' => bc_post_during_period_close(),
            'head-office-b' => OrganizationBranchService::createBranch(
                bc_actor([Capabilities::BRANCH_MANAGE]), 'HO-B', 'Head Office B', true
            ),
            default => throw new RuntimeException('Unknown business worker mode: '.$mode),
        };
        echo json_encode(['ok' => true, 'mode' => $mode, 'result' => $result], JSON_THROW_ON_ERROR);
        exit(0);
    } catch (DomainException $e) {
        echo json_encode([
            'ok' => false, 'mode' => $mode, 'code' => $e->codeKey,
            'http' => $e->httpStatus, 'message' => $e->getMessage(),
        ], JSON_THROW_ON_ERROR);
        exit(0);
    } catch (Throwable $e) {
        fwrite(STDERR, get_class($e).': '.$e->getMessage());
        exit(2);
    }
}

if (($argv[1] ?? '') === 'business-worker') {
    bc_worker((string)($argv[2] ?? ''), (float)($argv[3] ?? microtime(true)));
}

function bc_parallel(array $modes): array {
    if (!function_exists('proc_open')) throw new RuntimeException('proc_open unavailable');
    $startAt = microtime(true) + 0.35;
    $spec = [0 => ['pipe', 'r'], 1 => ['pipe', 'w'], 2 => ['pipe', 'w']];
    $workers = [];
    foreach ($modes as $mode) {
        $pipes = [];
        $process = proc_open(
            [PHP_BINARY, __FILE__, 'business-worker', $mode, sprintf('%.6F', $startAt)],
            $spec,
            $pipes
        );
        if (!is_resource($process)) throw new RuntimeException('Unable to start '.$mode.' worker');
        fclose($pipes[0]);
        $workers[] = [$mode, $process, $pipes];
    }
    $out = [];
    foreach ($workers as [$mode, $process, $pipes]) {
        $stdout = stream_get_contents($pipes[1]); fclose($pipes[1]);
        $stderr = stream_get_contents($pipes[2]); fclose($pipes[2]);
        $exit = proc_close($process);
        if ($exit !== 0) throw new RuntimeException($mode.' worker failed: '.$stderr);
        $out[] = json_decode($stdout, true, 512, JSON_THROW_ON_ERROR);
    }
    return $out;
}

function bc_success_count(array $results): int {
    return count(array_filter($results, static fn($row) => ($row['ok'] ?? false) === true));
}

function bc_failure_codes(array $results): array {
    return array_values(array_map(
        static fn($row) => (string)($row['code'] ?? ''),
        array_filter($results, static fn($row) => ($row['ok'] ?? false) !== true)
    ));
}

$wpdb = eh7_setup_global_db();
$failed = 0;

function bc_case(string $name, callable $fn): void {
    global $failed;
    try {
        $fn();
        echo "PASS {$name}\n";
    } catch (Throwable $e) {
        $failed++;
        echo "FAIL {$name}: {$e->getMessage()}\n";
    }
}

bc_case('business_concurrent_payroll_single_draft', function () use ($wpdb) {
    bc_rebuild_schema($wpdb);
    bc_seed_payroll($wpdb);
    $results = bc_parallel(['payroll-generate', 'payroll-generate']);
    if (bc_success_count($results) !== 1) {
        throw new RuntimeException('expected exactly one payroll generator success: '.json_encode($results));
    }
    if (!in_array('payroll_duplicate', bc_failure_codes($results), true)) {
        throw new RuntimeException('losing payroll generator did not receive payroll_duplicate');
    }
    $runs = (int)$wpdb->get_var('SELECT COUNT(*) FROM '.Db::table('payroll_runs'));
    $items = (int)$wpdb->get_var('SELECT COUNT(*) FROM '.Db::table('payroll_items'));
    $audits = (int)$wpdb->get_var("SELECT COUNT(*) FROM ".Db::table('audit_log')." WHERE action='payroll.generate'");
    if ($runs !== 1 || $items !== 1 || $audits !== 1) {
        throw new RuntimeException("payroll invariant mismatch runs={$runs} items={$items} audits={$audits}");
    }
});

bc_case('business_concurrent_transfer_pack_single_transition', function () use ($wpdb) {
    bc_rebuild_schema($wpdb);
    bc_seed_transfer($wpdb);
    $results = bc_parallel(['transfer-pack', 'transfer-pack']);
    if (bc_success_count($results) !== 1) {
        throw new RuntimeException('expected exactly one transfer pack success: '.json_encode($results));
    }
    $status = (string)$wpdb->get_var('SELECT status FROM '.Db::table('stock_transfers').' WHERE id=1');
    $audits = (int)$wpdb->get_var("SELECT COUNT(*) FROM ".Db::table('audit_log')." WHERE action='stock_transfer.pack'");
    if ($status !== 'packed' || $audits !== 1) {
        throw new RuntimeException("transfer invariant mismatch status={$status} audits={$audits}");
    }
});

bc_case('business_transfer_vs_payroll_is_serialized', function () use ($wpdb) {
    bc_rebuild_schema($wpdb);
    bc_seed_payroll($wpdb);
    $results = bc_parallel(['employee-transfer', 'payroll-generate']);
    if (bc_success_count($results) !== 1) {
        throw new RuntimeException('transfer/payroll race must have exactly one winner: '.json_encode($results));
    }
    $codes = bc_failure_codes($results);
    if (!array_intersect($codes, ['employee_transfer_payroll_conflict', 'payroll_no_employees'])) {
        throw new RuntimeException('unexpected losing transfer/payroll result: '.json_encode($results));
    }
    $branch = (int)$wpdb->get_var('SELECT assigned_branch_id FROM '.Db::table('employees').' WHERE id=10');
    $runs = (int)$wpdb->get_var('SELECT COUNT(*) FROM '.Db::table('payroll_runs'));
    $valid = ($branch === 2 && $runs === 0) || ($branch === 1 && $runs === 1);
    if (!$valid) {
        throw new RuntimeException("inconsistent transfer/payroll state branch={$branch} payroll_runs={$runs}");
    }
});

bc_case('business_salary_approval_vs_payroll_snapshot_consistent', function () use ($wpdb) {
    bc_rebuild_schema($wpdb);
    bc_seed_payroll($wpdb, true);
    $results = bc_parallel(['salary-approve', 'payroll-generate']);
    $payrollRows = array_values(array_filter($results, static fn($row) => ($row['mode'] ?? '') === 'payroll-generate'));
    $payroll = $payrollRows[0] ?? [];
    if (($payroll['ok'] ?? false) !== true) {
        throw new RuntimeException('payroll must complete in salary/payroll race: '.json_encode($results));
    }
    $status = (string)$wpdb->get_var('SELECT status FROM '.Db::table('salary_revisions').' WHERE id=2');
    $fixed = (float)$wpdb->get_var('SELECT fixed_salary FROM '.Db::table('payroll_items').' LIMIT 1');
    if ($status === 'approved') {
        if (abs($fixed - 2000.0) > 0.005 || bc_success_count($results) !== 2) {
            throw new RuntimeException("approved salary was not reflected in payroll fixed_salary={$fixed}");
        }
    } elseif ($status === 'pending') {
        $salaryRows = array_values(array_filter($results, static fn($row) => ($row['mode'] ?? '') === 'salary-approve'));
        $salary = $salaryRows[0] ?? [];
        if (($salary['code'] ?? '') !== 'salary_payroll_conflict' || abs($fixed - 1000.0) > 0.005) {
            throw new RuntimeException("pending salary/payroll conflict invariant failed fixed_salary={$fixed}");
        }
    } else {
        throw new RuntimeException('unexpected salary revision status '.$status);
    }
});

bc_case('business_reporting_cycle_concurrency_is_serialized', function () use ($wpdb) {
    bc_rebuild_schema($wpdb);
    bc_seed_reporting($wpdb);
    $results = bc_parallel(['report-a-to-b', 'report-b-to-a']);
    if (bc_success_count($results) !== 1) {
        throw new RuntimeException('reporting hierarchy race must have exactly one winner: '.json_encode($results));
    }
    if (!in_array('reporting_cycle', bc_failure_codes($results), true)) {
        throw new RuntimeException('losing reporting hierarchy mutation did not receive reporting_cycle: '.json_encode($results));
    }
    $aManager = (int)$wpdb->get_var('SELECT COALESCE(reporting_employee_id,0) FROM '.Db::table('employees').' WHERE id=10');
    $bManager = (int)$wpdb->get_var('SELECT COALESCE(reporting_employee_id,0) FROM '.Db::table('employees').' WHERE id=11');
    $valid = ($aManager === 11 && $bManager === 0) || ($aManager === 0 && $bManager === 10);
    if (!$valid) {
        throw new RuntimeException("reporting hierarchy cycle persisted A={$aManager} B={$bManager}");
    }
    $audits = (int)$wpdb->get_var("SELECT COUNT(*) FROM ".Db::table('audit_log')." WHERE action='employee.reporting_manager'");
    if ($audits !== 1) {
        throw new RuntimeException("reporting hierarchy audit invariant failed audits={$audits}");
    }
});

bc_case('business_single_head_office_is_concurrency_safe', function () use ($wpdb) {
    bc_rebuild_schema($wpdb);
    bc_seed_head_office($wpdb);
    $results = bc_parallel(['head-office-a', 'head-office-b']);
    if (bc_success_count($results) !== 1) {
        throw new RuntimeException('concurrent Head Office creation must have exactly one winner: '.json_encode($results));
    }
    if (!in_array('head_office_exists', bc_failure_codes($results), true)) {
        throw new RuntimeException('losing Head Office creation did not receive head_office_exists: '.json_encode($results));
    }
    $count = (int)$wpdb->get_var("SELECT COUNT(*) FROM ".Db::table('branches')." WHERE company_id=1 AND status='active' AND is_head_office=1");
    $audits = (int)$wpdb->get_var("SELECT COUNT(*) FROM ".Db::table('audit_log')." WHERE action='branch.create'");
    if ($count !== 1 || $audits !== 1) {
        throw new RuntimeException("Head Office invariant mismatch branches={$count} audits={$audits}");
    }
});


bc_case('business_period_close_vs_journal_posting_is_serialized', function()use($wpdb) {
    bc_rebuild_schema($wpdb);
    bc_seed_finance_close_race($wpdb);
    $results=bc_parallel(['period-close-guard','period-post-guard']);
    $closer=array_values(array_filter($results,static fn($row)=>$row['mode']==='period-close-guard'))[0]??[];
    $poster=array_values(array_filter($results,static fn($row)=>$row['mode']==='period-post-guard'))[0]??[];
    if(($closer['ok']??false)!==true || ($closer['result']['status']??'')!=='closed')
        throw new RuntimeException('Period close did not commit: '.json_encode($results));
    if(($poster['ok']??true)!==false || ($poster['code']??'')!=='accounting_period_closed')
        throw new RuntimeException('Concurrent journal bypassed closed period: '.json_encode($results));
    $journals=(int)$wpdb->get_var('SELECT COUNT(*) FROM '.Db::table('journal_entries'));
    $closed=(int)$wpdb->get_var("SELECT COUNT(*) FROM ".Db::table('accounting_periods')." WHERE company_id=1 AND status='closed'");
    if($journals!==0||$closed!==1)
        throw new RuntimeException('Invalid finance closing race journals='.$journals.' closed='.$closed);
});

echo ($failed ? 'FAILED' : 'PASSED')." business concurrency suite\n";
exit($failed ? 1 : 0);
