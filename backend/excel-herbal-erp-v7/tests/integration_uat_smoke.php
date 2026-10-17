<?php
define('EH7_INTEGRATION_LIBRARY_ONLY', true);
require __DIR__.'/integration_mariadb.php';

use ExcelHerbal\ERP7\Database\Db;
use ExcelHerbal\ERP7\Database\Schema;
use ExcelHerbal\ERP7\Domain\DomainException;
use ExcelHerbal\ERP7\Http\ApiDispatch;
use ExcelHerbal\ERP7\Security\Actor;
use ExcelHerbal\ERP7\Security\Capabilities;
use ExcelHerbal\ERP7\Inventory\StockService;
use ExcelHerbal\ERP7\Inventory\InventoryService;
use ExcelHerbal\ERP7\Finance\AccountingService;
use ExcelHerbal\ERP7\Finance\FinanceClosingService;
use ExcelHerbal\ERP7\Finance\FinancePeriodService;

if (!function_exists('get_option')) {
    function get_option($name, $default = false) {
        global $wpdb;
        if (!isset($wpdb)) return $default;
        $value = $wpdb->get_var($wpdb->prepare(
            'SELECT option_value FROM '.$wpdb->prefix.'options WHERE option_name=%s LIMIT 1',
            (string)$name
        ));
        return $value === null ? $default : $value;
    }
}

// The disposable integration database runs outside WordPress. Mirror its
// configured business timezone as UTC because uat_date() deliberately uses UTC.
if (!function_exists('wp_timezone')) {
    function wp_timezone(): DateTimeZone {
        return new DateTimeZone('UTC');
    }
}
if (!function_exists('get_date_from_gmt')) {
    function get_date_from_gmt($gmt_string, $format = 'Y-m-d H:i:s'): string {
        $instant = new DateTimeImmutable((string)$gmt_string, new DateTimeZone('UTC'));
        return $instant->setTimezone(wp_timezone())->format((string)$format);
    }
}

final class Eh7UatRequest implements ArrayAccess {
    public function __construct(private array $params = [], private array $json = []) {}
    public function get_param(string $key): mixed { return $this->params[$key] ?? null; }
    public function get_params(): array { return $this->params + $this->json; }
    public function get_json_params(): array { return $this->json; }
    public function offsetExists(mixed $offset): bool { return array_key_exists((string)$offset, $this->params); }
    public function offsetGet(mixed $offset): mixed { return $this->params[(string)$offset] ?? null; }
    public function offsetSet(mixed $offset, mixed $value): void { $this->params[(string)$offset] = $value; }
    public function offsetUnset(mixed $offset): void { unset($this->params[(string)$offset]); }
}

function uat_date(): string { return gmdate('Y-m-d'); }
function uat_actor(int $employeeId, array $branches, array $caps, string $designation = 'SYSADMIN'): Actor {
    return new Actor(5000 + $employeeId, $employeeId, 1, $branches[0] ?? 1, $branches, $caps, $designation);
}
function uat_dispatch(string $handler, Actor $actor, array $params = [], array $json = []): mixed {
    return ApiDispatch::dispatch($handler, new Eh7UatRequest($params, $json), $actor);
}
function uat_insert(Eh7IntegrationWpdb $db, string $table, array $row): void {
    if ($db->insert(Db::table($table), $row) === false) throw new RuntimeException('Insert '.$table.' failed: '.$db->last_error);
}
function uat_create_options(Eh7IntegrationWpdb $db): void {
    if ($db->query('DROP TABLE IF EXISTS '.$db->prefix.'options') === false) throw new RuntimeException($db->last_error);
    $sql = 'CREATE TABLE '.$db->prefix.'options ('.
        'option_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,'.
        'option_name VARCHAR(191) NOT NULL,'.
        'option_value LONGTEXT NOT NULL,'.
        'autoload VARCHAR(20) NOT NULL DEFAULT \'no\','.
        'PRIMARY KEY(option_id),UNIQUE KEY option_name(option_name)'.
        ') ENGINE=InnoDB DEFAULT CHARSET=utf8mb4';
    if ($db->query($sql) === false) throw new RuntimeException($db->last_error);
}
function uat_rebuild_schema(Eh7IntegrationWpdb $db): void {
    $defs = Schema::definitions();
    $db->query('SET FOREIGN_KEY_CHECKS=0');
    foreach (array_keys($defs) as $name) {
        if ($db->query('DROP TABLE IF EXISTS '.Db::table($name)) === false) throw new RuntimeException('Drop '.$name.' failed: '.$db->last_error);
    }
    foreach ($defs as $name => $definition) {
        if ($db->query('CREATE TABLE '.Db::table($name).' ('.$definition.') ENGINE=InnoDB DEFAULT CHARSET=utf8mb4') === false) {
            throw new RuntimeException('Create '.$name.' failed: '.$db->last_error);
        }
    }
    $db->query('SET FOREIGN_KEY_CHECKS=1');
    uat_create_options($db);
}
function uat_seed(Eh7IntegrationWpdb $db): void {
    uat_insert($db, 'companies', ['id'=>1,'name'=>'UAT Disposable Company','status'=>'active','created_at'=>'2026-01-01 00:00:00']);
    foreach ([[1,'B1','UAT Branch One',1],[2,'B2','UAT Branch Two',0]] as [$id,$code,$name,$ho]) {
        uat_insert($db, 'branches', ['id'=>$id,'company_id'=>1,'code'=>$code,'name'=>$name,'is_head_office'=>$ho,'status'=>'active','created_at'=>'2026-01-01 00:00:00']);
    }
    foreach ([[10,'E10','Field Employee',1,'FE',501],[20,'E20','UAT Manager',2,'SYSADMIN',502],[30,'E30','UAT Maker',2,'SYSADMIN',503]] as [$id,$code,$name,$branch,$designation,$wp]) {
        uat_insert($db, 'employees', [
            'id'=>$id,'company_id'=>1,'employee_code'=>$code,'wp_user_id'=>$wp,'designation_code'=>$designation,
            'assigned_branch_id'=>$branch,'full_name'=>$name,'mobile'=>'90000000'.$id,'monthly_salary'=>$id===10?30000:0,
            'joining_date'=>'2026-01-01','status'=>'active','created_at'=>'2026-01-01 00:00:00',
        ]);
    }
    uat_insert($db, 'employee_branch_history', [
        'id'=>1,'company_id'=>1,'employee_id'=>10,'branch_id'=>1,'effective_from'=>'2026-01-01','effective_to'=>null,
        'reason'=>'UAT baseline','changed_by'=>20,'created_at'=>'2026-01-01 00:00:00',
    ]);
    uat_insert($db, 'salary_revisions', [
        'id'=>1,'company_id'=>1,'employee_id'=>10,'effective_from'=>'2026-01-01','monthly_salary'=>30000,
        'status'=>'baseline','reason'=>'UAT salary baseline','created_by'=>20,'created_at'=>'2026-01-01 00:00:00',
    ]);
    uat_insert($db, 'products', [
        'id'=>100,'company_id'=>1,'sku'=>'UAT-P100','name'=>'UAT Herbal Product','uom'=>'PCS',
        'batch_tracking'=>'off','expiry_tracking'=>0,'status'=>'active','created_at'=>'2026-01-01 00:00:00',
    ]);
    uat_insert($db, 'product_commercial_revisions', [
        'id'=>1,'company_id'=>1,'product_id'=>100,'effective_from'=>'2026-01-01 00:00:00','mrp'=>120,'sale_price'=>100,
        'ho_amount'=>60,'bm_profit'=>20,'salary_fund'=>10,'office_expense'=>10,'points'=>2,'purchase_cost'=>50,
        'reason'=>'UAT pricing','status'=>'active','approved_by'=>20,'created_at'=>'2026-01-01 00:00:00',
    ]);
    uat_insert($db, 'stock_balances', [
        'id'=>1,'company_id'=>1,'branch_id'=>1,'product_id'=>100,'batch_key'=>0,'custodian_key'=>0,
        'quantity'=>100,'average_unit_cost'=>50,'updated_at'=>'2026-01-01 00:00:00',
    ]);
    foreach ([
        [1,'CASH','Cash','asset','cash'],[2,'UPI','UPI','asset','upi'],[3,'SALES','Sales','revenue',null],
        [4,'COGS','Cost of Goods Sold','expense',null],[5,'INVENTORY','Inventory','asset',null],
        [6,'INTER_BRANCH_CLEARING','Inter Branch Clearing','asset',null],[7,'STOCK_VARIANCE','Stock Variance','expense',null],
        [8,'OFFICE_EXPENSE','Office Expense','expense',null],[9,'PAYROLL_EXPENSE','Payroll Expense','expense',null],
        [10,'PAYROLL_PAYABLE','Payroll Payable','liability',null],
    ] as [$id,$code,$name,$type,$subtype]) {
        uat_insert($db, 'accounts', ['id'=>$id,'company_id'=>1,'code'=>$code,'name'=>$name,'type'=>$type,'subtype'=>$subtype,'active'=>1]);
    }
    uat_insert($db, 'expense_heads', ['id'=>1,'company_id'=>1,'code'=>'TRAVEL','name'=>'Travel Expense','expense_account_id'=>8,'active'=>1]);
    foreach ([['daily_cash_account_id','1'],['daily_upi_account_id','2'],['weekly_off_iso_days','[7]'],['payroll_leave_types','{}']] as [$key,$value]) {
        uat_insert($db, 'settings', ['company_id'=>1,'setting_key'=>$key,'setting_value'=>$value,'updated_at'=>'2026-01-01 00:00:00']);
    }

    $key = random_bytes(32);
    if ($db->insert($db->prefix.'options', ['option_name'=>'eh7_document_key','option_value'=>base64_encode($key),'autoload'=>'no']) === false) {
        throw new RuntimeException('Document key seed failed: '.$db->last_error);
    }
    $plain = "UAT employee document fixture\n"; $iv = random_bytes(12); $tag = '';
    $cipher = openssl_encrypt($plain, 'aes-256-gcm', $key, OPENSSL_RAW_DATA, $iv, $tag, 'eh7-document-v1');
    if ($cipher === false) throw new RuntimeException('UAT document encryption failed');
    uat_insert($db, 'private_documents', [
        'id'=>71,'filename'=>'uat-employee.pdf','mime_type'=>'application/pdf','payload'=>base64_encode($cipher),
        'iv'=>base64_encode($iv),'tag'=>base64_encode($tag),'sha256'=>hash('sha256',$plain),'created_at'=>'2026-01-01 00:00:00',
    ]);
    uat_insert($db, 'employee_documents', [
        'id'=>72,'company_id'=>1,'employee_id'=>10,'attachment_id'=>0,'private_file_id'=>71,'document_type'=>'uat_fixture',
        'title'=>'UAT employee document','status'=>'active','uploaded_by'=>20,'created_at'=>'2026-01-01 00:00:00',
    ]);
}

$wpdb = eh7_setup_global_db();
uat_rebuild_schema($wpdb);
uat_seed($wpdb);

$self = uat_actor(10, [1], [Capabilities::ATT_SELF, Capabilities::DAILY_SELF], 'FE');
$manager = uat_actor(20, [1,2], [
    Capabilities::DAILY_APPROVE,Capabilities::DAILY_ISSUE,Capabilities::DAILY_REVIEW,
    Capabilities::EMP_VIEW,Capabilities::EMP_MANAGE,Capabilities::EMP_DOCUMENT_DOWNLOAD,Capabilities::EMP_DOCUMENT_MANAGE,Capabilities::HR_VIEW,
    Capabilities::TRANSFER_RECEIVE,Capabilities::EXPENSE_APPROVE,
    Capabilities::PAYROLL_APPROVE,Capabilities::PAYROLL_PAY,
], 'SYSADMIN');
$maker = uat_actor(30, [1,2], [
    Capabilities::TRANSFER_CREATE,Capabilities::INVENTORY_VIEW,Capabilities::EXPENSE_CREATE,Capabilities::PAYROLL_GENERATE,
], 'SYSADMIN');

$failed = 0;
function uat_case(string $name, callable $fn): void {
    global $failed;
    try { $fn(); echo "PASS {$name}\n"; }
    catch (Throwable $e) { $failed++; echo "FAIL {$name}: ".get_class($e).' '.$e->getMessage()."\n"; }
}
function uat_expect_forbidden(callable $fn,string $message): void {
    try { $fn(); }
    catch (DomainException $e) {
        if (($e->codeKey === 'permission_denied' && $e->httpStatus === 403)
            || ($e->codeKey === 'maker_checker_required' && $e->httpStatus === 409)) return;
        throw $e;
    }
    throw new RuntimeException($message);
}

uat_case('uat_bootstrap_contract_metadata', function () use ($self) {
    $bootstrap = uat_dispatch('bootstrap', $self);
    $date = (string)($bootstrap['business_date'] ?? '');
    if (!preg_match('/^\\d{4}-\\d{2}-\\d{2}$/', $date) || $date !== Db::today()) {
        throw new RuntimeException('bootstrap business_date is missing or not authoritative');
    }
    if (trim((string)($bootstrap['business_timezone'] ?? '')) === '') {
        throw new RuntimeException('bootstrap business_timezone is missing');
    }
    $timestamp = (string)($bootstrap['server_timestamp'] ?? '');
    if ($timestamp === '' || strtotime($timestamp) === false) {
        throw new RuntimeException('bootstrap server_timestamp is missing or invalid');
    }
    $contract = trim((string)($bootstrap['api_contract'] ?? ''));
    $featureContract = trim((string)(($bootstrap['features']['api_contract'] ?? '')));
    if ($contract === '' || $featureContract === '' || $contract !== $featureContract) {
        throw new RuntimeException('bootstrap api_contract metadata is missing or inconsistent');
    }
});

uat_case('uat_branch_scope_fail_closed', function () use ($self) {
    try { uat_dispatch('work.check_in', $self, ['branch_id'=>2,'lat'=>31.9579,'lng'=>77.1095]); }
    catch (DomainException $e) { if ($e->codeKey === 'branch_forbidden' && $e->httpStatus === 403) return; throw $e; }
    throw new RuntimeException('cross-branch attendance check-in was accepted');
});

uat_case('uat_attendance_checkin_requires_gps', function () use ($self) {
    try {
        uat_dispatch('work.check_in', $self, ['branch_id'=>1]);
    } catch (DomainException $e) {
        if ($e->codeKey !== 'gps_location_required' || $e->httpStatus !== 422) throw $e;
        $today = uat_dispatch('work.attendance_today', $self);
        if ($today && !empty($today['check_in_at'])) {
            throw new RuntimeException('check-in without GPS created attendance');
        }
        return;
    }
    throw new RuntimeException('check-in without GPS was accepted');
});

uat_case('uat_sales_capability_fail_closed', function () use ($self) {
    try {
        uat_dispatch('sales.counter', $self, [
            'branch_id'=>1,
            'customer_id'=>null,
            'paid_amount'=>100,
            'payment_account_id'=>1,
            'lines'=>[['product_id'=>100,'quantity'=>1]],
        ]);
    }
    catch (DomainException $e) {
        if ($e->codeKey === 'permission_denied' && $e->httpStatus === 403) return;
        throw $e;
    }
    throw new RuntimeException('actor without SALES_CREATE capability posted a sale');
});

uat_case('uat_attendance_checkin_today_checkout', function () use ($self) {
    $in = uat_dispatch('work.check_in', $self, ['branch_id'=>1,'lat'=>31.9579,'lng'=>77.1095]);
    if (($in['status'] ?? '') !== 'present') throw new RuntimeException('check-in status mismatch');
    $today = uat_dispatch('work.attendance_today', $self);
    if (!$today || empty($today['check_in_at']) || (int)$today['branch_id'] !== 1) throw new RuntimeException('attendance today did not reflect check-in');
    $out = uat_dispatch('work.check_out', $self);
    if (($out['status'] ?? '') !== 'present') throw new RuntimeException('check-out status mismatch');
    if (empty(uat_dispatch('work.attendance_today', $self)['check_out_at'])) throw new RuntimeException('check-out was not persisted');
});

uat_case('uat_daily_order_full_cycle', function () use ($self, $manager, $wpdb) {
    $date = uat_date();
    $created = uat_dispatch('daily.create', $self, [
        'branch_id'=>1,'employee_id'=>10,'business_date'=>$date,'lines'=>[['product_id'=>100,'quantity'=>2]],
    ]);
    $cycle=(int)$created['id']; $request=(int)$created['request_id'];
    if (($created['status'] ?? '') !== 'morning_draft') throw new RuntimeException('daily create status mismatch');
    // F03: having branch + DAILY_OTHERS is not sufficient without reporting scope.
    $outsideTeam = uat_actor(30, [1,2], [Capabilities::DAILY_OTHERS], 'ASM');
    foreach (['daily.submit','daily.additional','daily.evening_start','daily.evening_save','daily.evening_submit'] as $action) {
        try { uat_dispatch($action,$outsideTeam,['id'=>$cycle,'lines'=>[]]); }
        catch (DomainException $e) {
            if ($e->codeKey==='employee_scope_forbidden' && $e->httpStatus===403) continue;
            throw $e;
        }
        throw new RuntimeException('out-of-hierarchy Daily Order write accepted: '.$action);
    }
    $state=(string)$wpdb->get_var($wpdb->prepare('SELECT status FROM '.Db::table('daily_cycles').' WHERE id=%d',$cycle));
    if ($state!=='morning_draft') throw new RuntimeException('denied hierarchy write changed Daily Order state');
    if ((uat_dispatch('daily.submit',$self,['id'=>$cycle])['status'] ?? '') !== 'stock_requested') throw new RuntimeException('daily submit failed');
    uat_expect_forbidden(
        fn()=>uat_dispatch('daily.approve',$self,['id'=>$request]),
        'self-service actor approved own daily request'
    );
    if ((uat_dispatch('daily.approve',$manager,['id'=>$request])['status'] ?? '') !== 'approved') throw new RuntimeException('daily approve failed');
    // A corrupted approved request with no lines must never transition to
    // issued or post stock ledger entries. Restore the synthetic fixture.
    $requestLine=$wpdb->get_row($wpdb->prepare(
        'SELECT * FROM '.Db::table('daily_request_lines').' WHERE daily_request_id=%d LIMIT 1',$request
    ),ARRAY_A);
    if(!$requestLine)throw new RuntimeException('UAT approved Daily Order line fixture missing');
    $deleted=$wpdb->query($wpdb->prepare(
        'DELETE FROM '.Db::table('daily_request_lines').' WHERE id=%d',(int)$requestLine['id']
    ));
    if($deleted!==1)throw new RuntimeException('UAT failed to remove synthetic request line');
    try {
        foreach(['daily.issue_preflight','daily.issue'] as $action) {
            try { uat_dispatch($action,$manager,['id'=>$request,'allocations'=>[]]); }
            catch(DomainException $error) {
                if($error->codeKey==='daily_request_lines_missing' && $error->httpStatus===409)continue;
                throw $error;
            }
            throw new RuntimeException('Empty approved Daily Order was accepted by '.$action);
        }
        $requestStatus=(string)$wpdb->get_var($wpdb->prepare(
            'SELECT status FROM '.Db::table('daily_requests').' WHERE id=%d',$request
        ));
        if($requestStatus!=='approved')
            throw new RuntimeException('Empty request rejection changed the approved request state');
        $invalidIssueLedger=(int)$wpdb->get_var($wpdb->prepare(
            'SELECT COUNT(*) FROM '.Db::table('stock_ledger').
            ' WHERE source_type=%s AND source_id=%d','daily_issue',$request
        ));
        if($invalidIssueLedger!==0)
            throw new RuntimeException('Empty request rejection wrote a stock ledger movement');
    } finally {
        uat_insert($wpdb,'daily_request_lines',$requestLine);
    }
    $preflight=uat_dispatch('daily.issue_preflight',$manager,['id'=>$request]);
    if (empty($preflight['all_available']) || abs((float)($preflight['requested_quantity']??0)-2)>0.001 ||
        count($preflight['lines']??[])!==1 || empty($preflight['lines'][0]['issueable']))
        throw new RuntimeException('Daily issue preflight did not cover approved request quantity');
    $beforeIssueStock=(float)$wpdb->get_var(
        'SELECT quantity FROM '.Db::table('stock_balances').
        ' WHERE company_id=1 AND branch_id=1 AND product_id=100 AND batch_key=0 AND custodian_key=0'
    );
    if(abs($beforeIssueStock-100)>0.001)throw new RuntimeException('Preflight unexpectedly changed warehouse stock');

    // Supplying a valid line plus an unrelated ID must fail, not silently
    // discard the extra allocation and issue stock against a partial payload.
    try {
        uat_dispatch('daily.issue',$manager,['id'=>$request,'allocations'=>[
            ['request_line_id'=>(int)$requestLine['id'],'quantity'=>2],
            ['request_line_id'=>99999991,'quantity'=>1],
        ]]);
        throw new RuntimeException('Foreign issue allocation line was accepted');
    } catch(DomainException $error) {
        if($error->codeKey!=='issue_allocation_unknown_line'||$error->httpStatus!==422)throw $error;
    }
    $afterInvalidAllocation=(float)$wpdb->get_var(
        'SELECT quantity FROM '.Db::table('stock_balances').
        ' WHERE company_id=1 AND branch_id=1 AND product_id=100 AND batch_key=0 AND custodian_key=0'
    );
    if(abs($afterInvalidAllocation-$beforeIssueStock)>0.001)
        throw new RuntimeException('Rejected foreign issue allocation changed warehouse stock');
    $invalidAllocationLedger=(int)$wpdb->get_var($wpdb->prepare(
        'SELECT COUNT(*) FROM '.Db::table('stock_ledger').
        ' WHERE source_type=%s AND source_id=%d','daily_issue',$request
    ));
    if($invalidAllocationLedger!==0)
        throw new RuntimeException('Rejected foreign allocation wrote stock ledger entries');

    if ((uat_dispatch('daily.issue',$manager,['id'=>$request,'allocations'=>[]])['status'] ?? '') !== 'issued') throw new RuntimeException('daily issue automatic allocation failed');
    // Transfer custody must be atomic: one warehouse OUT plus one employee IN,
    // and the request cannot issue twice on a stale/replayed action.
    $warehouseAfterIssue=(float)$wpdb->get_var(
        'SELECT quantity FROM '.Db::table('stock_balances').
        ' WHERE company_id=1 AND branch_id=1 AND product_id=100 AND batch_key=0 AND custodian_key=0'
    );
    $employeeAfterIssue=(float)$wpdb->get_var(
        'SELECT quantity FROM '.Db::table('stock_balances').
        ' WHERE company_id=1 AND branch_id=1 AND product_id=100 AND batch_key=0 AND custodian_key=10'
    );
    $issueLedger=(int)$wpdb->get_var($wpdb->prepare(
        'SELECT COUNT(*) FROM '.Db::table('stock_ledger').
        ' WHERE source_type=%s AND source_id=%d', 'daily_issue', $request
    ));
    if(abs($warehouseAfterIssue-98)>0.001||abs($employeeAfterIssue-2)>0.001||$issueLedger!==2)
        throw new RuntimeException('Daily issue did not move warehouse stock into employee custody exactly once');
    $repeatWasRejected=false;
    try { uat_dispatch('daily.issue',$manager,['id'=>$request,'allocations'=>[]]); }
    catch (DomainException $error) { $repeatWasRejected=true; }
    if(!$repeatWasRejected)throw new RuntimeException('Repeat stock issue succeeded unexpectedly');
    $replayedLedger=(int)$wpdb->get_var($wpdb->prepare(
        'SELECT COUNT(*) FROM '.Db::table('stock_ledger').
        ' WHERE source_type=%s AND source_id=%d', 'daily_issue', $request
    ));
    if($replayedLedger!==$issueLedger)
        throw new RuntimeException('Repeat stock issue modified the stock ledger');

    $evening=uat_dispatch('daily.evening_start',$self,['id'=>$cycle]); $eveningId=(int)$evening['evening_id'];
    $issueLineId=(int)$wpdb->get_var($wpdb->prepare('SELECT issue_line_id FROM '.Db::table('evening_lines').' WHERE evening_settlement_id=%d LIMIT 1',$eveningId));
    // EveningStart pre-fills sales, but the header is not yet verified.
    // Direct Submit without Save Draft must fail with no business mutation.
    try {
        uat_dispatch('daily.evening_submit',$self,['id'=>$cycle]);
        throw new RuntimeException('Unverified Evening Closing was submitted without Save Draft');
    } catch (DomainException $e) {
        if ($e->codeKey !== 'evening_totals_mismatch' || $e->httpStatus !== 409) throw $e;
    }
    if ((string)$wpdb->get_var($wpdb->prepare('SELECT status FROM '.Db::table('daily_cycles').' WHERE id=%d',$cycle))!=='evening_draft') {
        throw new RuntimeException('Rejected direct submit changed Daily Order state');
    }

    $saved=uat_dispatch('daily.evening_save',$self,[
        'id'=>$cycle,'lines'=>[['issue_line_id'=>$issueLineId,'return_quantity'=>0,'wholesale_quantity'=>0,'retail_rate'=>100,'wholesale_rate'=>0]],
        'wholesale_details'=>[],'price_reason'=>'',
    ]);
    if (abs((float)$saved['expected_amount']-200.0)>0.005) throw new RuntimeException('daily expected amount mismatch');
    // Service-level validation must reject invalid PCS even for internal
    // ApiDispatch callers that do not pass through the HTTP payload guard.
    // Failed writes must roll back and retain the last verified settlement.
    foreach ([
        ['return_quantity'=>-1,'wholesale_quantity'=>0],
        ['return_quantity'=>0,'wholesale_quantity'=>-1],
        ['return_quantity'=>0.5,'wholesale_quantity'=>0],
        ['return_quantity'=>0,'wholesale_quantity'=>0.5],
    ] as $invalidQuantities) {
        $rejected=false;
        try {
            uat_dispatch('daily.evening_save',$self,[
                'id'=>$cycle,
                'lines'=>[[
                    'issue_line_id'=>$issueLineId,
                    'return_quantity'=>$invalidQuantities['return_quantity'],
                    'wholesale_quantity'=>$invalidQuantities['wholesale_quantity'],
                    'retail_rate'=>100,
                    'wholesale_rate'=>0,
                ]],
                'wholesale_details'=>[],
                'price_reason'=>'',
            ]);
        } catch (DomainException $e) {
            if ($e->codeKey!=='whole_pcs_required' || $e->httpStatus!==422) throw $e;
            $rejected=true;
        }
        if (!$rejected) throw new RuntimeException('Invalid Evening Closing PCS were accepted by service.');
        $current=$wpdb->get_row($wpdb->prepare(
            'SELECT return_quantity,wholesale_quantity,total_amount FROM '.Db::table('evening_lines').' WHERE issue_line_id=%d',
            $issueLineId
        ),ARRAY_A);
        if (abs((float)$current['return_quantity'])>.0001 ||
            abs((float)$current['wholesale_quantity'])>.0001 ||
            abs((float)$current['total_amount']-200)>.005) {
            throw new RuntimeException('Rejected PCS input modified persisted Evening Closing.');
        }
    }
    // F01: unchanged repeated saves must not compound distributions; edited returns recalculate from source snapshots.
    $saveLines = fn(int $returns) => [
        'id'=>$cycle,'lines'=>[['issue_line_id'=>$issueLineId,'return_quantity'=>$returns,'wholesale_quantity'=>0,'retail_rate'=>100,'wholesale_rate'=>0]],
        'wholesale_details'=>[],'price_reason'=>'',
    ];
    foreach ([1,1,1,0,0] as $returnQty) {
        $reSaved=uat_dispatch('daily.evening_save',$self,$saveLines($returnQty));
        $expected=($returnQty===1)?100.0:200.0;
        $line=$wpdb->get_row($wpdb->prepare('SELECT points,salary_fund,ho_amount,bm_profit,office_expense FROM '.Db::table('evening_lines').' WHERE issue_line_id=%d',$issueLineId),ARRAY_A);
        if (abs((float)$reSaved['expected_amount']-$expected)>.005 ||
            abs((float)$line['points']-(($returnQty===1)?2.0:4.0))>.005 ||
            abs((float)$line['salary_fund']-(($returnQty===1)?10.0:20.0))>.005 ||
            abs((float)$line['ho_amount']-(($returnQty===1)?60.0:120.0))>.005 ||
            abs((float)$line['bm_profit']-(($returnQty===1)?20.0:40.0))>.005 ||
            abs((float)$line['office_expense']-(($returnQty===1)?10.0:20.0))>.005)
            throw new RuntimeException('F01 evening save compounded the original distribution');
    }
    // Stale/corrupted settlement totals must fail closed even after Save.
    // The disposable MariaDB fixture is restored before the normal final post.
    if ($wpdb->update(Db::table('evening_settlements'),['expected_amount'=>99],['id'=>$eveningId])===false) {
        throw new RuntimeException('Could not stage synthetic stale-total fixture');
    }
    try {
        uat_dispatch('daily.evening_submit',$self,['id'=>$cycle]);
        throw new RuntimeException('Mismatched Evening Closing header total was submitted');
    } catch (DomainException $e) {
        if ($e->codeKey !== 'evening_totals_mismatch' || $e->httpStatus !== 409) throw $e;
    }
    if ((string)$wpdb->get_var($wpdb->prepare('SELECT status FROM '.Db::table('evening_settlements').' WHERE id=%d',$eveningId))!=='draft') {
        throw new RuntimeException('Rejected amount mismatch modified settlement status');
    }
    if ($wpdb->update(Db::table('evening_settlements'),['expected_amount'=>200],['id'=>$eveningId])===false) {
        throw new RuntimeException('Could not restore synthetic verified total');
    }
    uat_dispatch('daily.evening_submit',$self,['id'=>$cycle]);
    $posted=uat_dispatch('daily.final_post',$manager,['id'=>$cycle,'cash'=>200,'upi'=>0]);
    if (($posted['status']??'')!=='completed'||abs((float)$posted['amount']-200.0)>0.005) throw new RuntimeException('daily final post mismatch');
    $warehouse=(float)$wpdb->get_var('SELECT quantity FROM '.Db::table('stock_balances').' WHERE company_id=1 AND branch_id=1 AND product_id=100 AND batch_key=0 AND custodian_key=0');
    $custody=(float)$wpdb->get_var('SELECT quantity FROM '.Db::table('stock_balances').' WHERE company_id=1 AND branch_id=1 AND product_id=100 AND batch_key=0 AND custodian_key=10');
    $perf=(int)$wpdb->get_var('SELECT COUNT(*) FROM '.Db::table('performance_entries').' WHERE source_type=\'daily_cycle\' AND source_id='.(int)$cycle);
    if(abs($warehouse-98.0)>0.001||abs($custody)>0.001||$perf!==1) throw new RuntimeException("daily invariant mismatch warehouse={$warehouse} custody={$custody} perf={$perf}");
});



uat_case('uat_daily_mixed_returns_wholesale_cash_upi_maker_checker', function () use ($self,$manager,$wpdb) {
    // Disposable, seeded MariaDB only. Exercise the full transaction with
    // returns, wholesale, mixed settlement and immutable financial/stock writes.
    // Use a unique synthetic business day outside the history-pagination range.
    $day=(new DateTimeImmutable(uat_date()))->modify('-203 days')->format('Y-m-d');
    $created=uat_dispatch('daily.create',$self,[
        'branch_id'=>1,'employee_id'=>10,'business_date'=>$day,
        'lines'=>[['product_id'=>100,'quantity'=>5]],
    ]);
    $cycle=(int)$created['id'];$request=(int)$created['request_id'];
    uat_dispatch('daily.submit',$self,['id'=>$cycle]);
    uat_dispatch('daily.approve',$manager,['id'=>$request]);
    uat_dispatch('daily.issue',$manager,['id'=>$request,'allocations'=>[]]);
    $evening=uat_dispatch('daily.evening_start',$self,['id'=>$cycle]);
    $eveningId=(int)$evening['evening_id'];
    $issuedLineId=(int)$wpdb->get_var($wpdb->prepare(
        'SELECT issue_line_id FROM '.Db::table('evening_lines').' WHERE evening_settlement_id=%d',$eveningId
    ));
    // Wholesale discount must not consume retail units' BM/Salary allocations.
    // Fixture: wholesale 2*100, BM 20/unit and Salary Fund 10/unit.
    // Rate 60 would split discount 40/40, exhausting more than the
    // wholesale Salary Fund's available 20 and must fail without writes.
    try {
        uat_dispatch('daily.evening_save',$self,[
            'id'=>$cycle,
            'lines'=>[[
                'issue_line_id'=>$issuedLineId,'return_quantity'=>1,'wholesale_quantity'=>2,
                'retail_rate'=>100,'wholesale_rate'=>60,
            ]],
            'wholesale_details'=>['wholesale_customer_name'=>'Synthetic Wholesale Buyer'],
            'price_reason'=>'Negative allocation rejection test',
        ]);
        throw new RuntimeException('Wholesale discount exceeded salary allocation but was saved');
    } catch(DomainException $err) {
        if($err->codeKey!=='wholesale_discount_exceeds_allocation')throw $err;
    }
    $saved=uat_dispatch('daily.evening_save',$self,[
        'id'=>$cycle,
        'lines'=>[[
            'issue_line_id'=>$issuedLineId,'return_quantity'=>1,'wholesale_quantity'=>2,
            'retail_rate'=>100,'wholesale_rate'=>80,
        ]],
        'wholesale_details'=>['wholesale_customer_name'=>'Synthetic Wholesale Buyer'],
        'price_reason'=>'UAT fixture — prices taken from issue snapshots',
    ]);
    if (abs((float)$saved['expected_amount']-360)>.005) throw new RuntimeException('Mixed closing amount must be 2*100 + 2*80 = 360');
    $line=$wpdb->get_row($wpdb->prepare(
        'SELECT issued_quantity,return_quantity,retail_quantity,wholesale_quantity,total_amount,ho_amount,bm_profit,office_expense,points,salary_fund FROM '.Db::table('evening_lines').' WHERE evening_settlement_id=%d',$eveningId
    ),ARRAY_A);
    if (abs((float)$line['issued_quantity']-5)>.001 ||
        abs((float)$line['return_quantity']-1)>.001 ||
        abs((float)$line['retail_quantity']-2)>.001 ||
        abs((float)$line['wholesale_quantity']-2)>.001 ||
        abs((float)$line['total_amount']-360)>.005) {
        throw new RuntimeException('Mixed wholesale/retail/return quantities failed to reconcile');
    }
    // 4 sold PCS * [HO 60 + BM 20 + Office 10 + Salary Fund 10]
    // less 40 wholesale discount => BM -20 and Salary Fund -20.
    if(abs((float)$line['ho_amount']-240)>.005||
       abs((float)$line['bm_profit']-60)>.005||
       abs((float)$line['office_expense']-40)>.005||
       abs((float)$line['salary_fund']-20)>.005||
       abs((float)$line['points']-8)>.005||
       abs((float)$line['ho_amount']+(float)$line['bm_profit']+
           (float)$line['office_expense']+(float)$line['salary_fund']-360)>.005) {
        throw new RuntimeException('Wholesale BM/Salary 50-50 distribution did not reconcile');
    }
    // Simulate a stale/misallocated closing on disposable data. Submission
    // must refuse a distribution that differs from the actual sale.
    Db::mustUpdate($wpdb,Db::table('evening_lines'),['bm_profit'=>61],['id'=>(int)$wpdb->get_var($wpdb->prepare(
        'SELECT id FROM '.Db::table('evening_lines').' WHERE evening_settlement_id=%d',$eveningId
    ))]);
    try {
        uat_dispatch('daily.evening_submit',$self,['id'=>$cycle]);
        throw new RuntimeException('Stale distribution incorrectly submitted');
    } catch(DomainException $err) {
        if($err->codeKey!=='evening_distribution_mismatch')throw $err;
    }
    Db::mustUpdate($wpdb,Db::table('evening_lines'),['bm_profit'=>60],['id'=>(int)$wpdb->get_var($wpdb->prepare(
        'SELECT id FROM '.Db::table('evening_lines').' WHERE evening_settlement_id=%d',$eveningId
    ))]);
    uat_dispatch('daily.evening_submit',$self,['id'=>$cycle]);

    // A dual-capability maker must not approve their own settlement.
    $dual=uat_actor(10,[1,2],[
        Capabilities::DAILY_SELF,Capabilities::DAILY_APPROVE,
        Capabilities::DAILY_ISSUE,Capabilities::DAILY_REVIEW,
    ],'SYSADMIN');
    uat_expect_forbidden(
        fn()=>uat_dispatch('daily.final_post',$dual,['id'=>$cycle,'cash'=>200,'upi'=>160]),
        'Evening maker final-posted their own submitted settlement'
    );
    $failureCases=[
        ['cash'=>201,'upi'=>160],
        ['cash'=>200,'upi'=>-1],
    ];
    foreach($failureCases as$bad) {
        $rejected=false;
        try {
            uat_dispatch('daily.final_post',$manager,['id'=>$cycle,'cash'=>$bad['cash'],'upi'=>$bad['upi']]);
        } catch(DomainException $e) {
            if($e->httpStatus!==409 && $e->httpStatus!==422) throw $e;
            $rejected=true;
        }
        if(!$rejected) throw new RuntimeException('Non-reconciled cash/UPI payment was accepted');
        $status=(string)$wpdb->get_var($wpdb->prepare('SELECT status FROM '.Db::table('daily_cycles').' WHERE id=%d',$cycle));
        $movements=(int)$wpdb->get_var($wpdb->prepare(
            "SELECT COUNT(*) FROM ".Db::table('stock_ledger')." WHERE source_id=%d AND source_type IN ('daily_return','daily_sale')",$cycle
        ));
        if($status!=='evening_submitted'||$movements!==0) {
            throw new RuntimeException('Rejected Final Post mutated order or stock');
        }
    }
    $posted=uat_dispatch('daily.final_post',$manager,['id'=>$cycle,'cash'=>200,'upi'=>160]);
    if(($posted['status']??'')!=='completed'||abs((float)($posted['amount']??0)-360)>.005) {
        throw new RuntimeException('Mixed settlement Final Post failed');
    }
    $settlement=$wpdb->get_row($wpdb->prepare(
        'SELECT status,cash_amount,upi_amount,submitted_by,reviewed_by FROM '.Db::table('evening_settlements').' WHERE id=%d',$eveningId
    ),ARRAY_A);
    if($settlement['status']!=='posted'||abs((float)$settlement['cash_amount']-200)>.005||
        abs((float)$settlement['upi_amount']-160)>.005||
        (int)$settlement['submitted_by']!==(int)$self->employeeId||
        (int)$settlement['reviewed_by']!==(int)$manager->employeeId) {
        throw new RuntimeException('Maker-checker and split-payment settlement was not persisted');
    }
    $warehouse=(float)$wpdb->get_var(
        'SELECT quantity FROM '.Db::table('stock_balances').' WHERE company_id=1 AND branch_id=1 AND product_id=100 AND batch_key=0 AND custodian_key=0'
    );
    $custody=(float)$wpdb->get_var(
        'SELECT quantity FROM '.Db::table('stock_balances').' WHERE company_id=1 AND branch_id=1 AND product_id=100 AND batch_key=0 AND custodian_key=10'
    );
    if(abs($warehouse-94)>.001||abs($custody)>.001) {
        throw new RuntimeException("Mixed settlement stock custody wrong warehouse={$warehouse} employee={$custody}");
    }
    $returned=(float)$wpdb->get_var($wpdb->prepare(
        "SELECT COALESCE(SUM(quantity),0) FROM ".Db::table('stock_ledger')." WHERE source_type='daily_return' AND source_id=%d AND direction='IN'",$cycle
    ));
    $sold=(float)$wpdb->get_var($wpdb->prepare(
        "SELECT COALESCE(SUM(quantity),0) FROM ".Db::table('stock_ledger')." WHERE source_type='daily_sale' AND source_id=%d AND direction='OUT'",$cycle
    ));
    if(abs($returned-1)>.001||abs($sold-4)>.001)throw new RuntimeException('Mixed settlement stock ledger mismatch');
    $journal=$wpdb->get_row($wpdb->prepare(
        "SELECT id FROM ".Db::table('journal_entries')." WHERE source_type='daily_cycle' AND source_id=%d",$cycle
    ),ARRAY_A);
    if(!$journal) throw new RuntimeException('Daily sale/COGS journal absent after Final Post');
    $totals=$wpdb->get_row($wpdb->prepare(
        'SELECT SUM(debit) d,SUM(credit) c FROM '.Db::table('journal_lines').' WHERE journal_entry_id=%d',(int)$journal['id']
    ),ARRAY_A);
    if(abs((float)$totals['d']-560)>.005||abs((float)$totals['c']-560)>.005) {
        throw new RuntimeException('Mixed settlement journal must balance 360 sales + 200 COGS');
    }
    $performance=$wpdb->get_row($wpdb->prepare(
        "SELECT points,salary_fund FROM ".Db::table('performance_entries')." WHERE source_type='daily_cycle' AND source_id=%d",$cycle
    ),ARRAY_A);
    if(!$performance||abs((float)$performance['points']-8)>.005||
       abs((float)$performance['salary_fund']-20)>.005)throw new RuntimeException('Performance distribution mismatch after 50/50 wholesale discount');
    try {
        uat_dispatch('daily.final_post',$manager,['id'=>$cycle,'cash'=>200,'upi'=>160]);
        throw new RuntimeException('Final Post was replayed and could duplicate stock/journal');
    } catch(DomainException $e) {
        if($e->httpStatus<400||$e->httpStatus>=500)throw $e;
    }
    $journalCount=(int)$wpdb->get_var($wpdb->prepare(
        "SELECT COUNT(*) FROM ".Db::table('journal_entries')." WHERE source_type='daily_cycle' AND source_id=%d",$cycle
    ));
    if($journalCount!==1)throw new RuntimeException('Final Post replay duplicated journal');
});

uat_case('uat_sales_report_consolidates_posted_daily_orders', function () use ($wpdb) {
    $reporter=uat_actor(20,[1,2],[Capabilities::REPORTS_VIEW],'SYSADMIN');
    $today=uat_date();
    $rows=uat_dispatch('reports.sales',$reporter,[
        'branch_id'=>1,'from'=>$today,'to'=>$today,
    ]);
    $daily=array_values(array_filter($rows,static fn($row)=>($row['source_type']??'')==='daily_order'));
    $dbCount=(int)$wpdb->get_var($wpdb->prepare(
        "SELECT COUNT(*) FROM ".Db::table('daily_cycles')." c ".
        "JOIN ".Db::table('evening_settlements')." es ON es.daily_cycle_id=c.id AND es.status='posted' ".
        "WHERE c.company_id=%d AND c.branch_id=%d AND c.status='completed' AND c.business_date=%s",
        1,1,$today
    ));
    if($dbCount===0||count($daily)!==$dbCount) {
        throw new RuntimeException('Sales report omitted or duplicated a posted Daily Order');
    }
    foreach($daily as$row) {
        if(($row['status']??'')!=='posted'||
           ($row['reference']??'')!=='DO-'.(int)$row['source_id']||
           ($row['id']??'')!=='daily_order:'.(int)$row['source_id']||
           abs((float)$row['gross_amount']-(float)$row['paid_amount'])>.005||
           abs((float)$row['outstanding_amount'])>.005) {
            throw new RuntimeException('Posted Daily Order sales report fields or source identity mismatch');
        }
    }
    $pastDay=(new DateTimeImmutable($today))->modify('-203 days')->format('Y-m-d');
    $pastRows=uat_dispatch('reports.sales',$reporter,[
        'branch_id'=>1,'from'=>$pastDay,'to'=>$pastDay,
    ]);
    $pastDaily=array_values(array_filter($pastRows,static fn($row)=>($row['source_type']??'')==='daily_order'));
    if(count($pastDaily)!==1||abs((float)$pastDaily[0]['gross_amount']-360)>.005||
       abs((float)$pastDaily[0]['paid_amount']-360)>.005) {
        throw new RuntimeException('Mixed Cash/UPI wholesale Daily Order absent from branch sales report');
    }
    $otherBranch=uat_dispatch('reports.sales',$reporter,[
        'branch_id'=>2,'from'=>$pastDay,'to'=>$today,
    ]);
    foreach($otherBranch as$row) {
        if(($row['source_type']??'')==='daily_order') {
            throw new RuntimeException('Daily Order of branch 1 leaked to branch 2 sales report');
        }
    }
    uat_expect_forbidden(fn()=>uat_dispatch('reports.sales',
        uat_actor(10,[1],[Capabilities::DAILY_SELF],'FE'),
        ['branch_id'=>1,'from'=>$today,'to'=>$today]
    ),'Daily Order sales report ignored REPORTS_VIEW capability');
});

uat_case('uat_audit_batch_without_expiry_and_expired_quarantine', function () use ($manager,$wpdb) {
    // F02: batch-required without expiry tracking must remain issueable when expires_on is NULL.
    uat_insert($wpdb,'products',[
        'id'=>101,'company_id'=>1,'sku'=>'UAT-BATCH-101','name'=>'Batch tracked no expiry',
        'uom'=>'PCS','batch_tracking'=>'required','expiry_tracking'=>0,'status'=>'active','created_at'=>'2026-01-01 00:00:00',
    ]);
    $yesterday=(new DateTimeImmutable(Db::today()))->modify('-1 day')->format('Y-m-d');
    uat_insert($wpdb,'batches',[
        'id'=>1011,'company_id'=>1,'product_id'=>101,'batch_no'=>'NO-EXPIRY',
        'expires_on'=>null,'status'=>'active','created_at'=>'2026-01-01 00:00:00',
    ]);
    uat_insert($wpdb,'batches',[
        'id'=>1012,'company_id'=>1,'product_id'=>101,'batch_no'=>'EXPIRED',
        'expires_on'=>$yesterday,'status'=>'active','created_at'=>'2026-01-01 00:00:00',
    ]);
    foreach ([[1011,5],[1012,5]] as [$batchId,$quantity]) {
        uat_insert($wpdb,'stock_balances',[
            'company_id'=>1,'branch_id'=>1,'product_id'=>101,'batch_key'=>$batchId,'custodian_key'=>0,
            'quantity'=>$quantity,'average_unit_cost'=>50,'updated_at'=>'2026-01-01 00:00:00',
        ]);
    }
    $available=StockService::warehouseAvailable($manager,1,101);
    $alloc=StockService::automaticCustodyAllocations($manager,1,101,3);
    if (abs($available-5)>0.001 || count($alloc)!==1 ||
        (int)$alloc[0]['batch_id']!==1011 || abs((float)$alloc[0]['quantity']-3)>0.001)
        throw new RuntimeException('F02 no-expiry batch was rejected or expired batch allocated');
    // F07: controlled hold removes expired stock from warehouse, without allowing sale/dispatch.
    $keeper=uat_actor(20,[1,2],[Capabilities::ADJ_CREATE],'SYSADMIN');
    $hold=InventoryService::quarantineHold($keeper,1,101,1012,2,'Expired batch quarantine UAT');
    if (($hold['status']??'')!=='open') throw new RuntimeException('F07 quarantine hold was not created');
    $remaining=(float)$wpdb->get_var($wpdb->prepare(
        'SELECT quantity FROM '.Db::table('stock_balances').' WHERE company_id=1 AND branch_id=1 AND product_id=101 AND batch_key=%d AND custodian_key=0',1012));
    if (abs($remaining-3)>0.001) throw new RuntimeException('F07 expired quarantine did not deduct source stock');
    try { StockService::move($keeper,1,101,1012,null,'OUT',1,50,'daily_sale',999999); }
    catch (DomainException $e) {
        if ($e->codeKey==='batch_expired') return;
        throw $e;
    }
    throw new RuntimeException('F07 expired batch became sale-eligible');
});

uat_case('uat_inventory_transfer_create_dispatch_receive', function () use ($maker,$manager,$wpdb) {
    // Assert this transfer's delta instead of a brittle stock total:
    // earlier disposable Daily Order tests may add completed sales.
    $sourceBefore=(float)$wpdb->get_var('SELECT quantity FROM '.Db::table('stock_balances').' WHERE company_id=1 AND branch_id=1 AND product_id=100 AND batch_key=0 AND custodian_key=0');
    $destBefore=(float)$wpdb->get_var('SELECT quantity FROM '.Db::table('stock_balances').' WHERE company_id=1 AND branch_id=2 AND product_id=100 AND batch_key=0 AND custodian_key=0');
    $created=uat_dispatch('inventory.transfer_create',$maker,[
        'source_branch_id'=>1,'destination_branch_id'=>2,'lines'=>[['product_id'=>100,'quantity'=>5]],'notes'=>'UAT transfer',
    ]);
    $id=(int)$created['id']; uat_dispatch('inventory.transfer_pack',$maker,['id'=>$id]);
    if((uat_dispatch('inventory.transfer_dispatch',$maker,['id'=>$id])['status']??'')!=='in_transit') throw new RuntimeException('transfer dispatch failed');
    $lineId=(int)$wpdb->get_var($wpdb->prepare('SELECT id FROM '.Db::table('stock_transfer_lines').' WHERE transfer_id=%d LIMIT 1',$id));
    uat_expect_forbidden(
        fn()=>uat_dispatch('inventory.transfer_receive',$maker,['id'=>$id,'lines'=>[['transfer_line_id'=>$lineId,'received_quantity'=>5]]]),
        'transfer creator received own transfer without TRANSFER_RECEIVE'
    );
    if((uat_dispatch('inventory.transfer_receive',$manager,['id'=>$id,'lines'=>[['transfer_line_id'=>$lineId,'received_quantity'=>5]]])['status']??'')!=='received') throw new RuntimeException('transfer receive failed');
    $source=(float)$wpdb->get_var('SELECT quantity FROM '.Db::table('stock_balances').' WHERE company_id=1 AND branch_id=1 AND product_id=100 AND batch_key=0 AND custodian_key=0');
    $dest=(float)$wpdb->get_var('SELECT quantity FROM '.Db::table('stock_balances').' WHERE company_id=1 AND branch_id=2 AND product_id=100 AND batch_key=0 AND custodian_key=0');
    if(abs($source-($sourceBefore-5.0))>0.001||abs($dest-($destBefore+5.0))>0.001) {
        throw new RuntimeException("transfer delta mismatch source={$sourceBefore}->{$source} destination={$destBefore}->{$dest}");
    }
});

uat_case('uat_finance_expense_maker_checker', function () use ($maker,$manager,$wpdb) {
    $expense=uat_dispatch('finance.expense',$maker,[
        'branch_id'=>1,'expense_head_id'=>1,'amount'=>75,'payment_account_id'=>1,'expense_date'=>uat_date(),'description'=>'UAT controlled expense',
    ]);
    uat_expect_forbidden(
        fn()=>uat_dispatch('finance.expense_decision',$maker,['id'=>(int)$expense['id'],'approve'=>true]),
        'expense maker approved own expense'
    );
    $decision=uat_dispatch('finance.expense_decision',$manager,['id'=>(int)$expense['id'],'approve'=>true]);
    $journal=(int)($decision['journal_entry_id']??0);
    if(($decision['status']??'')!=='approved'||$journal<1) throw new RuntimeException('expense approval/journal failed');
    $dr=(float)$wpdb->get_var('SELECT COALESCE(SUM(debit),0) FROM '.Db::table('journal_lines').' WHERE journal_entry_id='.$journal);
    $cr=(float)$wpdb->get_var('SELECT COALESCE(SUM(credit),0) FROM '.Db::table('journal_lines').' WHERE journal_entry_id='.$journal);
    if(abs($dr-75.0)>0.005||abs($cr-75.0)>0.005) throw new RuntimeException('expense journal not balanced');
});

uat_case('uat_payroll_generate_approve_pay', function () use ($maker,$manager,$wpdb) {
    $date=uat_date();
    $generated=uat_dispatch('payroll.generate',$maker,['branch_id'=>1,'period_start'=>$date,'period_end'=>$date]);
    $id=(int)$generated['id'];
    if(($generated['status']??'')!=='draft'||(float)$generated['net_total']<=0) throw new RuntimeException('payroll generation failed');
    uat_expect_forbidden(
        fn()=>uat_dispatch('payroll.approve',$maker,['id'=>$id]),
        'payroll generator approved own payroll run'
    );
    if((uat_dispatch('payroll.approve',$manager,['id'=>$id])['status']??'')!=='approved') throw new RuntimeException('payroll approval failed');
    uat_expect_forbidden(
        fn()=>uat_dispatch('payroll.pay',$maker,['id'=>$id,'payment_account_id'=>1,'payment_date'=>$date]),
        'payroll generator paid payroll without PAYROLL_PAY'
    );
    $paid=uat_dispatch('payroll.pay',$manager,['id'=>$id,'payment_account_id'=>1,'payment_date'=>$date]);
    if(($paid['status']??'')!=='paid'||(int)($paid['payment_journal_entry_id']??0)<1) throw new RuntimeException('payroll payment failed');
    $status=(string)$wpdb->get_var('SELECT status FROM '.Db::table('payroll_runs').' WHERE id='.$id);
    $journals=(int)$wpdb->get_var('SELECT COUNT(*) FROM '.Db::table('journal_entries')." WHERE source_id={$id} AND source_type IN ('payroll','payroll_payment') AND status='posted'");
    if($status!=='paid'||$journals!==2) throw new RuntimeException("payroll invariant mismatch status={$status} journals={$journals}");
});

uat_case('uat_hr_document_download_and_revoke', function () use ($manager) {
    $download=uat_dispatch('org.document_download',$manager,['id'=>10,'document_id'=>72]);
    if(($download['filename']??'')!=='uat-employee.pdf'||($download['bytes']??'')!=="UAT employee document fixture\n") throw new RuntimeException('document download mismatch');
    if((uat_dispatch('org.employee_document_deactivate',$manager,['id'=>10,'document_id'=>72])['status']??'')!=='inactive') throw new RuntimeException('document deactivate failed');
    try { uat_dispatch('org.document_download',$manager,['id'=>10,'document_id'=>72]); }
    catch(DomainException $e){ if($e->codeKey==='document_not_found'&&$e->httpStatus===404)return; throw $e; }
    throw new RuntimeException('inactive HR document remained downloadable');
});


uat_case('uat_audit_journal_negative_opposite_side_rejected', function () use ($manager) {
    // F08: balanced totals must not allow negative values on the opposite side.
    try {
        AccountingService::post($manager,1,'expense',999999,Db::businessNow(),[
            ['account_id'=>1,'debit'=>100,'credit'=>-50],
            ['account_id'=>3,'debit'=>-50,'credit'=>100],
        ],'Must reject signed opposite-side journal');
    }
    catch (DomainException $e) {
        if ($e->codeKey==='journal_amount_invalid' && $e->httpStatus===422) return;
        throw $e;
    }
    throw new RuntimeException('F08 signed journal amounts were accepted');
});

uat_case('uat_audit_repeat_branch_close_preserves_checker', function () use ($wpdb) {
    // F09: a second distinct close request must not replace the original checker/timestamp.
    $makerActor=uat_actor(30,[2],[Capabilities::BRANCH_CLOSE],'SYSADMIN');
    $checkerA=uat_actor(20,[2],[Capabilities::BRANCH_CLOSE],'SYSADMIN');
    $checkerB=uat_actor(10,[2],[Capabilities::BRANCH_CLOSE],'SYSADMIN');
    $draft=FinanceClosingService::closingDraft($makerActor,2,uat_date());
    $id=(int)$draft['id'];
    $first=FinanceClosingService::closeBranch($checkerA,$id);
    if (($first['status']??'')!=='closed') throw new RuntimeException('F09 first branch close failed');
    $before=$wpdb->get_row($wpdb->prepare('SELECT closed_by,closed_at,preflight_json FROM '.Db::table('branch_closings').' WHERE id=%d',$id),ARRAY_A);
    $second=FinanceClosingService::closeBranch($checkerB,$id);
    $after=$wpdb->get_row($wpdb->prepare('SELECT closed_by,closed_at,preflight_json FROM '.Db::table('branch_closings').' WHERE id=%d',$id),ARRAY_A);
    if (($second['status']??'')!=='closed'||(int)$after['closed_by']!==20||$before!=$after)
        throw new RuntimeException('F09 repeat close overwrote original closing metadata');
});

uat_case('uat_no_negative_stock_and_balanced_journals', function () use ($wpdb) {
    $negative=(int)$wpdb->get_var('SELECT COUNT(*) FROM '.Db::table('stock_balances').' WHERE quantity < -0.0001');
    $unbalanced=(int)$wpdb->get_var(
        'SELECT COUNT(*) FROM (SELECT je.id FROM '.Db::table('journal_entries').' je JOIN '.Db::table('journal_lines').
        ' jl ON jl.journal_entry_id=je.id GROUP BY je.id HAVING ABS(SUM(jl.debit)-SUM(jl.credit)) > 0.005) x'
    );
    if($negative!==0||$unbalanced!==0) throw new RuntimeException("closing invariant mismatch negative_stock={$negative} unbalanced_journals={$unbalanced}");
});


uat_case('uat_audit_daily_history_server_pagination', function () use ($self,$wpdb) {
    // F05: 150+ orders must remain visible across pages and searchable by id/date/status.
    $origin=new DateTimeImmutable(uat_date());
    for ($i=1;$i<=150;$i++) {
        $day=$origin->modify('-'.$i.' days')->format('Y-m-d');
        uat_insert($wpdb,'daily_cycles',[
            'id'=>20000+$i,'company_id'=>1,'branch_id'=>1,'employee_id'=>10,
            'business_date'=>$day,'status'=>'completed','created_by'=>10,
            'created_at'=>'2026-01-01 00:00:00',
        ]);
    }
    $first=uat_dispatch('daily.search',$self,[
        'branch_id'=>1,'page'=>1,'page_size'=>25,'status'=>'completed',
    ]);
    $last=uat_dispatch('daily.search',$self,[
        'branch_id'=>1,'page'=>7,'page_size'=>25,'status'=>'completed',
    ]);
    if ((int)($first['total']??0)<151||count($first['items']??[])!==25||
        empty($first['has_more'])||empty($last['items'])||!empty($last['has_more']))
        throw new RuntimeException('F05 page seven or total count is incorrect');
    $query=uat_dispatch('daily.search',$self,[
        'branch_id'=>1,'page'=>1,'page_size'=>25,'query'=>'20001',
    ]);
    if (count($query['items']??[])!==1||(int)$query['items'][0]['id']!==20001)
        throw new RuntimeException('F05 older record not found by order ID');
    $date=$origin->modify('-1 day')->format('Y-m-d');
    $dated=uat_dispatch('daily.search',$self,[
        'branch_id'=>1,'date_from'=>$date,'date_to'=>$date,
    ]);
    if (count($dated['items']??[])!==1||(int)$dated['items'][0]['id']!==20001)
        throw new RuntimeException('F05 business date filter failed');
    $outsideTeam=uat_actor(30,[1,2],[Capabilities::DAILY_OTHERS],'ASM');
    $denied=uat_dispatch('daily.search',$outsideTeam,[
        'branch_id'=>1,'query'=>'20001',
    ]);
    if ((int)($denied['total']??-1)!==0||!empty($denied['items']))
        throw new RuntimeException('F05 out-of-scope history visible');
});


uat_case('uat_audit_daily_draft_edit_reject_and_additional_cancel', function () use ($self,$manager,$wpdb) {
    // F04: a rejected initial order returns to editable draft; rejected/cancelled additional does not block evening.
    $date=(new DateTimeImmutable(uat_date()))->modify('-201 days')->format('Y-m-d');
    $created=uat_dispatch('daily.create',$self,[
        'branch_id'=>1,'employee_id'=>10,'business_date'=>$date,
        'lines'=>[['product_id'=>100,'quantity'=>1]],
    ]);
    $id=(int)$created['id'];$request=(int)$created['request_id'];
    $edited=uat_dispatch('daily.edit_draft',$self,[
        'id'=>$id,'lines'=>[['product_id'=>100,'quantity'=>2]],
    ]);
    if (($edited['status']??'')!=='morning_draft')throw new RuntimeException('F04 draft edit failed');
    $quantity=(float)$wpdb->get_var($wpdb->prepare(
        'SELECT quantity FROM '.Db::table('daily_request_lines').' WHERE daily_request_id=%d',$request));
    if(abs($quantity-2)>0.001)throw new RuntimeException('F04 draft quantity not updated');
    $outside=uat_actor(30,[1,2],[Capabilities::DAILY_OTHERS],'ASM');
    try { uat_dispatch('daily.edit_draft',$outside,[
        'id'=>$id,'lines'=>[['product_id'=>100,'quantity'=>5]],
    ]);throw new RuntimeException('F04 unauthorized edit succeeded'); }
    catch(DomainException $e) {
        if ($e->codeKey!=='employee_scope_forbidden'||$e->httpStatus!==403)throw $e;
    }
    uat_dispatch('daily.submit',$self,['id'=>$id]);
    uat_dispatch('daily.reject',$manager,['id'=>$request,'reason'=>'Incorrect requested quantity']);
    $cycleStatus=(string)$wpdb->get_var($wpdb->prepare('SELECT status FROM '.Db::table('daily_cycles').' WHERE id=%d',$id));
    $requestStatus=(string)$wpdb->get_var($wpdb->prepare('SELECT status FROM '.Db::table('daily_requests').' WHERE id=%d',$request));
    if($cycleStatus!=='morning_draft'||$requestStatus!=='draft')throw new RuntimeException('F04 rejected request did not return to draft');
    uat_dispatch('daily.edit_draft',$self,['id'=>$id,'lines'=>[['product_id'=>100,'quantity'=>1]]]);
    uat_dispatch('daily.submit',$self,['id'=>$id]);
    uat_dispatch('daily.approve',$manager,['id'=>$request]);
    uat_dispatch('daily.issue',$manager,['id'=>$request,'allocations'=>[]]);
    $extra=uat_dispatch('daily.additional',$self,['id'=>$id,'lines'=>[['product_id'=>100,'quantity'=>1]]]);
    uat_dispatch('daily.reject',$manager,['id'=>(int)$extra['id'],'reason'=>'Requested stock is not required']);
    $next=uat_dispatch('daily.additional',$self,['id'=>$id,'lines'=>[['product_id'=>100,'quantity'=>1]]]);
    uat_dispatch('daily.approve',$manager,['id'=>(int)$next['id']]);
    uat_dispatch('daily.cancel_additional',$self,[
        'id'=>(int)$next['id'],'reason'=>'Cancel after revised demand',
    ]);
    $remaining=(int)$wpdb->get_var($wpdb->prepare(
        "SELECT COUNT(*) FROM ".Db::table('daily_requests')." WHERE daily_cycle_id=%d AND type='additional' AND status IN ('draft','submitted','approved')",$id));
    if($remaining!==0)throw new RuntimeException('F04 additional request remained pending');
    $evening=uat_dispatch('daily.evening_start',$self,['id'=>$id]);
    if(($evening['status']??'')!=='evening_draft')throw new RuntimeException('F04 evening still blocked after additional cancellation');
});


uat_case('uat_audit_daily_cancel_reopen_unique_cycle', function () use ($self,$manager,$wpdb) {
    // F04: cancelling an unissued request does not destroy the unique employee/day record.
    $date=(new DateTimeImmutable(uat_date()))->modify('-202 days')->format('Y-m-d');
    $created=uat_dispatch('daily.create',$self,[
        'branch_id'=>1,'employee_id'=>10,'business_date'=>$date,
        'lines'=>[['product_id'=>100,'quantity'=>1]],
    ]);
    $id=(int)$created['id'];$request=(int)$created['request_id'];
    uat_dispatch('daily.submit',$self,['id'=>$id]);
    $cancel=uat_dispatch('daily.cancel_cycle',$self,[
        'id'=>$id,'reason'=>'Submitted in error, cancel it',
    ]);
    if (($cancel['status']??'')!=='cancelled') throw new RuntimeException('F04 initial order cancellation failed');
    try { uat_dispatch('daily.create',$self,[
        'branch_id'=>1,'employee_id'=>10,'business_date'=>$date,
        'lines'=>[['product_id'=>100,'quantity'=>1]],
    ]); throw new RuntimeException('F04 duplicate order created after cancel'); }
    catch(DomainException $e) {
        if($e->codeKey!=='daily_duplicate'||$e->httpStatus!==409)throw $e;
    }
    $reopened=uat_dispatch('daily.reopen_draft',$self,['id'=>$id]);
    if(($reopened['status']??'')!=='morning_draft')throw new RuntimeException('F04 reopening canceled draft failed');
    uat_dispatch('daily.edit_draft',$self,['id'=>$id,'lines'=>[['product_id'=>100,'quantity'=>2]]]);
    uat_dispatch('daily.submit',$self,['id'=>$id]);
    uat_dispatch('daily.approve',$manager,['id'=>$request]);
    try { uat_dispatch('daily.cancel_cycle',$self,['id'=>$id,'reason'=>'Too late to cancel']); }
    catch(DomainException $e) {
        if($e->codeKey==='daily_state_invalid'&&$e->httpStatus===409)return;
        throw $e;
    }
    throw new RuntimeException('F04 approved stock request could be cancelled');
});


uat_case('uat_audit_applied_locked_stock_cost', function () use ($manager,$wpdb) {
    // R02: caller-estimated cost can go stale; the movement must report the locked ledger cost.
    uat_insert($wpdb,'products',[
        'id'=>1099,'company_id'=>1,'sku'=>'UAT-COST-1099','name'=>'Cost-lock test product',
        'uom'=>'PCS','batch_tracking'=>'off','expiry_tracking'=>0,
        'status'=>'active','created_at'=>'2026-01-01 00:00:00',
    ]);
    uat_insert($wpdb,'stock_balances',[
        'company_id'=>1,'branch_id'=>1,'product_id'=>1099,'batch_key'=>0,
        'custodian_key'=>0,'quantity'=>5,'average_unit_cost'=>60,
        'updated_at'=>'2026-01-01 00:00:00',
    ]);
    $old=StockService::cost($manager,1,1099,null,null);
    $changed=$wpdb->update(Db::table('stock_balances'),
        ['average_unit_cost'=>75],['company_id'=>1,'branch_id'=>1,'product_id'=>1099,'batch_key'=>0,'custodian_key'=>0]);
    if($changed===false)throw new RuntimeException('R02 fixture cost update failed');
    $effective=StockService::move($manager,1,1099,null,null,'OUT',2,$old,'stock_adjustment',99001);
    $ledger=(float)$wpdb->get_var($wpdb->prepare(
        "SELECT unit_cost FROM ".Db::table('stock_ledger')." WHERE source_type='stock_adjustment' AND source_id=%d AND product_id=1099 ORDER BY id DESC LIMIT 1",99001));
    if(abs($effective-75)>0.0001||abs($ledger-$effective)>0.0001) {
        throw new RuntimeException('R02 caller snapshot diverged from applied ledger cost');
    }
});

uat_case('uat_audit_period_close_posting_guard', function () use ($wpdb) {
    // R01: closing and posting now share the locked company row; a completed close blocks posting.
    $date='2019-01-15';
    foreach([1,2] as $branch) {
        uat_insert($wpdb,'branch_closings',[
            'company_id'=>1,'branch_id'=>$branch,'business_date'=>$date,
            'status'=>'closed','created_by'=>20,'closed_by'=>30,
            'created_at'=>'2019-01-01 00:00:00','closed_at'=>'2019-01-15 23:00:00',
        ]);
    }
    $actor=uat_actor(20,[1,2],[Capabilities::PERIOD_MANAGE],'SYSADMIN');
    $closed=FinancePeriodService::closePeriod($actor,$date,$date);
    if(($closed['status']??'')!=='closed')throw new RuntimeException('R01 period did not close');
    try {
        AccountingService::post($actor,1,'expense',999999,$date.' 12:00:00',[
            ['account_id'=>1,'debit'=>50,'credit'=>0],
            ['account_id'=>3,'debit'=>0,'credit'=>50],
        ],'Closed period must reject');
    } catch(DomainException $e) {
        if($e->codeKey==='accounting_period_closed'&&$e->httpStatus===409)return;
        throw $e;
    }
    throw new RuntimeException('R01 posted a journal into closed period');
});

uat_case('uat_admin_access_atomic_save_and_rollback', function () use ($wpdb) {
    // Disposable MariaDB only: access changes are not made on Office BUILD/UAT.
    $admin=uat_actor(20,[1,2],[Capabilities::ACCESS,Capabilities::ACCESS_MANAGE],'SYSADMIN');
    $role=uat_dispatch('access.role_create',$admin,[
        'code'=>'UAT_REPORT_CLERK','name'=>'UAT Report Clerk',
    ]);
    $roleId=(int)$role['id'];
    uat_dispatch('access.role_caps',$admin,[
        'id'=>$roleId,'capabilities'=>[Capabilities::REPORTS_VIEW],
        'reason'=>'UAT role permissions setup',
    ]);
    $saved=uat_dispatch('access.employee_update',$admin,[
        'id'=>10,'role_ids'=>[$roleId],
        'grants'=>[Capabilities::INVENTORY_VIEW],
        'denies'=>[Capabilities::DAILY_SELF],
        'reason'=>'UAT atomic access editing',
    ]);
    if(count($saved['roles']??[])!==1||
       !in_array(Capabilities::REPORTS_VIEW,$saved['effective_capabilities']??[],true)||
       !in_array(Capabilities::INVENTORY_VIEW,$saved['effective_capabilities']??[],true)||
       in_array(Capabilities::DAILY_SELF,$saved['effective_capabilities']??[],true)) {
        throw new RuntimeException('Atomic employee access save failed to compute role/grant/deny');
    }
    // Verify persisted state through a separate read after the write transaction committed.
    $persisted=uat_dispatch('access.employee',$admin,['id'=>10]);
    if(count($persisted['roles']??[])!==1||
       !in_array(Capabilities::REPORTS_VIEW,$persisted['effective_capabilities']??[],true)||
       !in_array(Capabilities::INVENTORY_VIEW,$persisted['effective_capabilities']??[],true)||
       in_array(Capabilities::DAILY_SELF,$persisted['effective_capabilities']??[],true)) {
        throw new RuntimeException('Successful employee access update did not persist after commit');
    }
    $auditBefore=(int)$wpdb->get_var($wpdb->prepare(
        "SELECT COUNT(*) FROM ".Db::table('audit_log')." WHERE company_id=%d AND entity_type='employee' AND entity_id=%d",1,10
    ));
    try {
        // Removing the role succeeds in the inner savepoint; the invalid
        // override must roll back that removal and all audit side effects.
        uat_dispatch('access.employee_update',$admin,[
            'id'=>10,'role_ids'=>[],
            'grants'=>['invalid.unknown_capability'],'denies'=>[],
            'reason'=>'Invalid override rollback verification',
        ]);
        throw new RuntimeException('Unknown capability was assigned to employee');
    } catch(DomainException $e) {
        if($e->codeKey!=='capability_invalid'||$e->httpStatus!==422)throw $e;
    }
    $after=uat_dispatch('access.employee',$admin,['id'=>10]);
    if(count($after['roles']??[])!==1 ||
       !in_array(Capabilities::INVENTORY_VIEW,$after['effective_capabilities']??[],true) ||
       in_array(Capabilities::DAILY_SELF,$after['effective_capabilities']??[],true)) {
        throw new RuntimeException('Failed atomic update partially changed employee access');
    }
    $auditAfter=(int)$wpdb->get_var($wpdb->prepare(
        "SELECT COUNT(*) FROM ".Db::table('audit_log')." WHERE company_id=%d AND entity_type='employee' AND entity_id=%d",1,10
    ));
    if($auditBefore!==$auditAfter)throw new RuntimeException('Rejected access change persisted an audit event');
});

uat_case('uat_finance_reversal_capability_and_branch_scope', function () use ($wpdb) {
    // These are deliberately synthetic UAT records. No source journal is
    // touched, and the test exercises denials before any reversal can post.
    foreach ([
        [81000,1,'pending'],[81001,2,'pending'],[81002,null,'approved'],
    ] as [$id,$branch,$status]) {
        uat_insert($wpdb,'reversals',[
            'id'=>$id,'company_id'=>1,'branch_id'=>$branch,
            'source_type'=>'expense','source_id'=>999900+$id,
            'reason'=>'Synthetic permission scope test',
            'status'=>$status,'requested_by'=>20,
            'requested_at'=>'2026-01-01 00:00:00',
        ]);
    }
    $limited=uat_actor(10,[1],[Capabilities::REVERSAL_CREATE],'FE');
    $visible=uat_dispatch('finance.reversals',$limited);
    $ids=array_map(static fn($r)=>(int)$r['id'],$visible);
    if(!in_array(81000,$ids,true)||
       in_array(81001,$ids,true)||
       in_array(81002,$ids,true)) {
        throw new RuntimeException('Branch-limited actor can see another branch/company-wide reversal');
    }
    $approver=uat_actor(10,[1],[Capabilities::REVERSAL_APPROVE],'FE');
    try {
        uat_dispatch('finance.reversal_decision',$approver,['id'=>81001,'approve'=>true]);
        throw new RuntimeException('Cross-branch reversal approval accepted');
    } catch (DomainException $error) {
        if($error->codeKey!=='branch_forbidden'||$error->httpStatus!==403)throw $error;
    }
    try {
        uat_dispatch('finance.reversal_execute',$approver,['id'=>81002]);
        throw new RuntimeException('Branch-limited actor executed company-wide reversal');
    } catch (DomainException $error) {
        if($error->codeKey!=='all_branch_authority_required'||$error->httpStatus!==403)throw $error;
    }
    $withoutApproval=uat_actor(10,[1,2],[],'FE');
    uat_expect_forbidden(
        fn()=>uat_dispatch('finance.reversal_execute',$withoutApproval,['id'=>81002]),
        'Reversal executed without approval capability'
    );
    $full=uat_actor(20,[1,2],[Capabilities::REVERSAL_APPROVE],'SYSADMIN');
    $all=uat_dispatch('finance.reversals',$full);
    $fullIds=array_map(static fn($row)=>(int)$row['id'],$all);
    if(!in_array(81001,$fullIds,true)||!in_array(81002,$fullIds,true))
        throw new RuntimeException('Company-authorized approver cannot list authorized reversals');
    $state=(string)$wpdb->get_var($wpdb->prepare(
        'SELECT status FROM '.Db::table('reversals').' WHERE id=%d',81002
    ));
    if($state!=='approved')throw new RuntimeException('Denied reversal modified source state');
});

echo ($failed ? 'FAILED' : 'PASSED')." staging UAT end-to-end smoke suite\n";
exit($failed ? 1 : 0);
