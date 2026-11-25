<?php
define('EH7_INTEGRATION_LIBRARY_ONLY', true);
require __DIR__.'/integration_mariadb.php';

use ExcelHerbal\ERP7\Database\Db;
use ExcelHerbal\ERP7\Database\Schema;
use ExcelHerbal\ERP7\Domain\DomainException;
use ExcelHerbal\ERP7\Http\ApiDispatch;
use ExcelHerbal\ERP7\Security\Actor;
use ExcelHerbal\ERP7\Security\Capabilities;

// Standalone CI is not bootstrapped by WordPress; fixture clock is UTC.
if (!function_exists('get_gmt_from_date')) {
    function get_gmt_from_date(string $datetime, string $format = 'Y-m-d H:i:s'): string {
        return (new DateTimeImmutable($datetime, new DateTimeZone('UTC')))->format($format);
    }
}

// Match WordPress GMT conversion in this UTC-only disposable fixture.
if (!function_exists('get_date_from_gmt')) {
    function get_date_from_gmt(string $datetime, string $format = 'Y-m-d H:i:s'): string {
        return (new DateTimeImmutable($datetime, new DateTimeZone('UTC')))->format($format);
    }
}

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
    // WordPress owns wp_users in production. The disposable integration DB
    // needs its minimal read-only identity table for the employee LEFT JOIN.
    if ($db->query('DROP TABLE IF EXISTS '.$db->users) === false) {
        throw new RuntimeException('Synthetic WP users reset failed');
    }
    if ($db->query('CREATE TABLE '.$db->users.' ('.
        'ID BIGINT UNSIGNED NOT NULL,PRIMARY KEY(ID)'.
        ') ENGINE=InnoDB DEFAULT CHARSET=utf8mb4') === false) {
        throw new RuntimeException('Synthetic WP users table missing: '.$db->last_error);
    }
}
function uat_seed(Eh7IntegrationWpdb $db): void {
    uat_insert($db, 'companies', ['id'=>1,'name'=>'UAT Disposable Company','status'=>'active','created_at'=>'2026-01-01 00:00:00']);
    foreach ([[1,'B1','UAT Branch One',1],[2,'B2','UAT Branch Two',0]] as [$id,$code,$name,$ho]) {
        uat_insert($db, 'branches', ['id'=>$id,'company_id'=>1,'code'=>$code,'name'=>$name,'is_head_office'=>$ho,'status'=>'active','created_at'=>'2026-01-01 00:00:00']);
    }
    uat_insert($db, 'designations', [
        'company_id'=>1,'code'=>'FE','name'=>'Field Executive',
        'sequence_no'=>1,'field_role'=>1,'status'=>'active',
    ]);
    uat_insert($db, 'designations', [
        'company_id'=>1,'code'=>'SYSADMIN','name'=>'System Administrator',
        'sequence_no'=>2,'field_role'=>0,'status'=>'active',
    ]);
    uat_insert($db, 'designations', [
        'company_id'=>2,'code'=>'FE','name'=>'Other Company Role',
        'sequence_no'=>1,'field_role'=>0,'status'=>'active',
    ]);
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
        'ho_amount'=>20,'bm_profit'=>10,'salary_fund'=>5,'office_expense'=>5,'points'=>2,'purchase_cost'=>50,
        'reason'=>'UAT pricing','status'=>'active','approved_by'=>20,'created_at'=>'2026-01-01 00:00:00',
    ]);
    uat_insert($db, 'stock_balances', [
        'id'=>1,'company_id'=>1,'branch_id'=>1,'product_id'=>100,'batch_key'=>0,'custodian_key'=>0,
        'quantity'=>100,'average_unit_cost'=>50,'updated_at'=>'2026-01-01 00:00:00',
    ]);
    // Scheduled attendance + an actual matching GPS row are both required
    // for synthetic Morning Product Issue. Manual check-in is deliberately disabled.
    $scheduledAt = gmdate('Y-m-d H:i:s', time() - 3600);
    $gpsAt = gmdate('Y-m-d H:i:s', time() - 120);
    uat_insert($db, 'attendance', [
        'id'=>1,'company_id'=>1,'branch_id'=>1,'employee_id'=>10,
        'business_date'=>uat_date(),'status'=>'present',
        'check_in_at'=>$scheduledAt,'created_at'=>$scheduledAt,
    ]);
    uat_insert($db, 'gps_points', [
        'id'=>1,'company_id'=>1,'branch_id'=>1,'employee_id'=>10,
        'attendance_id'=>1,'latitude'=>31.701,'longitude'=>76.93,
        'source'=>'duty','recorded_at'=>$gpsAt,'created_at'=>$gpsAt,
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
    Capabilities::DAILY_APPROVE,Capabilities::DAILY_ISSUE,Capabilities::DAILY_REVIEW,Capabilities::BANK_RECONCILE,
    Capabilities::EMP_VIEW,Capabilities::EMP_MANAGE,Capabilities::HR_VIEW,Capabilities::EMP_DOCUMENT_DOWNLOAD,
    Capabilities::INVENTORY_VIEW,Capabilities::TRANSFER_RECEIVE,Capabilities::EXPENSE_APPROVE,
    Capabilities::PAYROLL_APPROVE,Capabilities::PAYROLL_PAY,
], 'SYSADMIN');
$maker = uat_actor(30, [1,2], [
    Capabilities::TRANSFER_CREATE,Capabilities::INVENTORY_VIEW,Capabilities::EXPENSE_CREATE,Capabilities::PAYROLL_GENERATE,Capabilities::DAILY_OTHERS,
], 'SYSADMIN');

// Synthetic role projections: the capability list AND branch set, never
// the job title alone, determine server-side access.
$branchManager = uat_actor(20, [2], [
    Capabilities::DAILY_APPROVE, Capabilities::EXPENSE_APPROVE,
    Capabilities::SALES_CREATE, Capabilities::INVENTORY_VIEW,
], 'BM');
$financeReviewer = uat_actor(30, [1,2], [
    Capabilities::BANK_RECONCILE, Capabilities::EXPENSE_APPROVE,
], 'FINANCE');
$headOffice = uat_actor(20, [1,2], [
    Capabilities::SALES_DISCOUNT_HO_APPROVE, Capabilities::SALES_VIEW,
], 'MD');

$failed = 0;
function uat_case(string $name, callable $fn): void {
    global $failed;
    try { $fn(); echo "PASS {$name}\n"; }
    catch (Throwable $e) { $failed++; echo "FAIL {$name}: ".get_class($e).' '.$e->getMessage()."\n"; }
}

function uat_expect_denial(callable $action, string $expected, string $label): void {
    try {
        $action();
    } catch (DomainException $e) {
        if ($e->codeKey !== $expected || $e->httpStatus < 400) {
            throw new RuntimeException(
                $label.': expected '.$expected.', got '.$e->codeKey.' / '.$e->httpStatus
            );
        }
        return;
    }
    throw new RuntimeException($label.': forbidden action was accepted');
}

uat_case('uat_staff_bm_finance_ho_role_scopes_no_writes', function () use (
    $self, $branchManager, $financeReviewer, $headOffice, $wpdb
) {
    $tables = [
        'prepaid_sales_orders', 'stock_transfers', 'expenses', 'payroll_runs',
        'audit_log', 'journal_entries', 'stock_ledger',
    ];
    $before = [];
    foreach ($tables as $name) {
        $before[$name] = (int)$wpdb->get_var('SELECT COUNT(*) FROM '.Db::table($name));
    }
    $order = [
        'branch_id'=>1, 'channel'=>'b2c',
        'lines'=>[['product_id'=>100, 'quantity'=>'1']],
    ];
    uat_expect_denial(fn()=>uat_dispatch('sales.order_create', $self, $order),
        'permission_denied', 'Staff cannot create prepaid Sales orders');
    uat_expect_denial(fn()=>uat_dispatch('finance.expense', $self, [
        'branch_id'=>1, 'expense_head_id'=>1, 'amount'=>1,
        'payment_account_id'=>1, 'expense_date'=>uat_date(),
        'description'=>'Unauthorised fixture expense',
    ]), 'permission_denied', 'Staff cannot create Finance expenses');
    uat_expect_denial(fn()=>uat_dispatch('inventory.transfer_create', $self, [
        'source_branch_id'=>1, 'destination_branch_id'=>2,
        'lines'=>[['product_id'=>100, 'quantity'=>1]],
        'notes'=>'Unauthorised fixture transfer',
    ]), 'permission_denied', 'Staff cannot create stock transfers');
    uat_expect_denial(fn()=>uat_dispatch('payroll.generate', $self, [
        'branch_id'=>1, 'period_start'=>uat_date(), 'period_end'=>uat_date(),
    ]), 'permission_denied', 'Staff cannot generate Payroll');
    uat_expect_denial(fn()=>uat_dispatch('org.document_download', $self, [
        'id'=>10, 'document_id'=>72,
    ]), 'permission_denied', 'Staff cannot download restricted HR documents');

    uat_expect_denial(fn()=>uat_dispatch('sales.order_create', $branchManager, $order),
        'branch_forbidden', 'Branch Manager cannot create Sales orders in other branch');
    uat_expect_denial(fn()=>uat_dispatch('finance.expenses', $branchManager, [
        'branch_id'=>1,
    ]), 'branch_forbidden', 'Branch Manager cannot list other-branch expenses');
    uat_expect_denial(fn()=>uat_dispatch('sales.order_create', $financeReviewer, $order),
        'permission_denied', 'Bank verifier cannot create Sales orders');
    uat_expect_denial(fn()=>uat_dispatch('sales.order_create', $headOffice, $order),
        'permission_denied', 'HO approval capability does not grant Sales creation');
    $policy = uat_dispatch('sales.discount_policy', $headOffice);
    if (!array_key_exists('configured', $policy)) {
        throw new RuntimeException('Head Office cannot read authorised discount policy');
    }
    foreach ($tables as $name) {
        $count = (int)$wpdb->get_var('SELECT COUNT(*) FROM '.Db::table($name));
        if ($count !== $before[$name]) {
            throw new RuntimeException('Denied action mutated '.$name);
        }
    }
});

uat_case('uat_employee_directory_names_and_company_scope', function () use ($manager) {
    $rows = uat_dispatch('org.employees', $manager, ['branch_id'=>1]);
    $employee = null;
    foreach ($rows as $row) {
        if ((int)($row['id'] ?? 0)===10) { $employee=$row; break; }
    }
    if (!$employee || $employee['full_name'] !== 'Field Employee'
        || ($employee['designation_code'] ?? '') !== 'FE'
        || ($employee['designation_name'] ?? '') !== 'Field Executive') {
        throw new RuntimeException('Employee directory did not use own-company designation name');
    }
    $otherBranch = uat_actor(20,[2],[Capabilities::EMP_VIEW],'BM');
    uat_expect_denial(
        fn()=>uat_dispatch('org.employees',$otherBranch,['branch_id'=>1]),
        'branch_forbidden','Employee directory leaked another branch'
    );
});

uat_case('uat_branch_scope_fail_closed', function () use ($self) {
    try {
        uat_dispatch('daily.create', $self, [
            'branch_id'=>2,'employee_id'=>10,'business_date'=>uat_date(),
            'lines'=>[['product_id'=>100,'quantity'=>1]],
        ]);
    } catch (DomainException $e) {
        if ($e->codeKey === 'branch_forbidden' && $e->httpStatus === 403) return;
        throw $e;
    }
    throw new RuntimeException('cross-branch Daily Order was accepted');
});

uat_case('uat_automatic_attendance_and_gps_evidence', function () use ($self) {
    foreach (['work.check_in','work.check_out'] as $manualRoute) {
        try {
            uat_dispatch($manualRoute, $self, ['branch_id'=>1,'lat'=>31.701,'lng'=>76.93]);
            throw new RuntimeException($manualRoute.' unexpectedly permitted manual duty change');
        } catch (DomainException $e) {
            if ($e->codeKey !== 'attendance_manual_disabled' || $e->httpStatus !== 403) throw $e;
        }
    }
    $today = uat_dispatch('work.attendance_today', $self);
    if (!$today || empty($today['check_in_at']) || (int)$today['branch_id'] !== 1) {
        throw new RuntimeException('scheduled attendance is absent or in wrong branch');
    }
    if (!\ExcelHerbal\ERP7\Workforce\AttendanceGpsEvidence::hasVerifiedMorningPoint(
        1, 1, 10, uat_date()
    )) throw new RuntimeException('synthetic authenticated GPS point is not associated to scheduled duty');
});

uat_case('uat_daily_order_full_cycle', function () use ($self, $maker, $manager, $wpdb) {
    $date = uat_date();
    $created = uat_dispatch('daily.create', $self, [
        'branch_id'=>1,'employee_id'=>10,'business_date'=>$date,'lines'=>[['product_id'=>100,'quantity'=>2]],
    ]);
    $cycle=(int)$created['id']; $request=(int)$created['request_id'];
    if (($created['status'] ?? '') !== 'morning_draft') throw new RuntimeException('daily create status mismatch');
    if ((uat_dispatch('daily.submit',$self,['id'=>$cycle])['status'] ?? '') !== 'stock_requested') throw new RuntimeException('daily submit failed');
    if ((uat_dispatch('daily.review',$maker,['id'=>$request])['status'] ?? '') !== 'reviewed') throw new RuntimeException('independent review failed');
    // A review must not give the maker or an unrelated branch approval rights.
    $foreignBM = uat_actor(20, [2], [Capabilities::DAILY_APPROVE], 'BM');
    uat_expect_denial(fn()=>uat_dispatch('daily.approve',$self,['id'=>$request]),
        'maker_checker_required', 'Field Staff cannot approve own request');
    uat_expect_denial(fn()=>uat_dispatch('daily.approve',$foreignBM,['id'=>$request]),
        'acting_authority_denied', 'Manager of other branch cannot approve');
    $statusBefore = (string)$wpdb->get_var($wpdb->prepare(
        'SELECT status FROM '.Db::table('daily_requests').' WHERE id=%d', $request
    ));
    if ($statusBefore !== 'reviewed') throw new RuntimeException('Denied Daily approval changed request state');
    if ((uat_dispatch('daily.approve',$manager,['id'=>$request])['status'] ?? '') !== 'approved') throw new RuntimeException('daily approve failed');
    $lineId=(int)$wpdb->get_var($wpdb->prepare('SELECT id FROM '.Db::table('daily_request_lines').' WHERE daily_request_id=%d LIMIT 1',$request));
    if ((uat_dispatch('daily.issue',$manager,['id'=>$request,'allocations'=>[['request_line_id'=>$lineId,'quantity'=>2]]])['status'] ?? '') !== 'awaiting_receipt') throw new RuntimeException('staged allocation failed');
    $warehouseBefore=(float)$wpdb->get_var('SELECT quantity FROM '.Db::table('stock_balances').' WHERE company_id=1 AND branch_id=1 AND product_id=100 AND batch_key=0 AND custodian_key=0');
    if(abs($warehouseBefore-100.0)>0.001)throw new RuntimeException('stock moved before employee receipt');
    if ((uat_dispatch('daily.receive',$self,['id'=>$request])['status'] ?? '') !== 'issued') throw new RuntimeException('employee receipt confirmation failed');
    $evening=uat_dispatch('daily.evening_start',$self,['id'=>$cycle]); $eveningId=(int)$evening['evening_id'];
    $issueLineId=(int)$wpdb->get_var($wpdb->prepare('SELECT issue_line_id FROM '.Db::table('evening_lines').' WHERE evening_settlement_id=%d LIMIT 1',$eveningId));
    $saved=uat_dispatch('daily.evening_save',$self,[
        'id'=>$cycle,'lines'=>[['issue_line_id'=>$issueLineId,'return_quantity'=>0,'wholesale_quantity'=>0,'retail_rate'=>100,'wholesale_rate'=>0]],
        'wholesale_details'=>[],'price_reason'=>'',
    ]);
    if (abs((float)$saved['expected_amount']-200.0)>0.005) throw new RuntimeException('daily expected amount mismatch');
    uat_dispatch('daily.evening_submit',$self,['id'=>$cycle]);
    $upi=uat_dispatch('daily.upi_record',$self,['id'=>$cycle,'reference'=>'UATUPI0001','amount'=>100]);
    if(($upi['status']??'')!=='pending') throw new RuntimeException('UPI receipt was not pending');
    $decision=uat_dispatch('daily.upi_decision',$manager,['id'=>(int)$upi['id'],'approve'=>true,'bank_evidence_ref'=>'BANKMATCH001']);
    if(($decision['status']??'')!=='verified')throw new RuntimeException('UPI independent verification failed');
    $posted=uat_dispatch('daily.final_post',$manager,['id'=>$cycle,'cash'=>100,'upi'=>100]);
    if (($posted['status']??'')!=='completed'||abs((float)$posted['amount']-200.0)>0.005) throw new RuntimeException('daily final post mismatch');
    $warehouse=(float)$wpdb->get_var('SELECT quantity FROM '.Db::table('stock_balances').' WHERE company_id=1 AND branch_id=1 AND product_id=100 AND batch_key=0 AND custodian_key=0');
    $custody=(float)$wpdb->get_var('SELECT quantity FROM '.Db::table('stock_balances').' WHERE company_id=1 AND branch_id=1 AND product_id=100 AND batch_key=0 AND custodian_key=10');
    $perf=(int)$wpdb->get_var('SELECT COUNT(*) FROM '.Db::table('performance_entries').' WHERE source_type=\'daily_cycle\' AND source_id='.(int)$cycle);
    if(abs($warehouse-98.0)>0.001||abs($custody)>0.001||$perf!==1) throw new RuntimeException("daily invariant mismatch warehouse={$warehouse} custody={$custody} perf={$perf}");
});

uat_case('uat_inventory_transfer_create_dispatch_receive', function () use ($maker,$manager,$wpdb) {
    $created=uat_dispatch('inventory.transfer_create',$maker,[
        'source_branch_id'=>1,'destination_branch_id'=>2,'lines'=>[['product_id'=>100,'quantity'=>5]],'notes'=>'UAT transfer',
    ]);
    $id=(int)$created['id']; uat_dispatch('inventory.transfer_pack',$maker,['id'=>$id]);
    if((uat_dispatch('inventory.transfer_dispatch',$maker,['id'=>$id])['status']??'')!=='in_transit') throw new RuntimeException('transfer dispatch failed');
    $lineId=(int)$wpdb->get_var($wpdb->prepare('SELECT id FROM '.Db::table('stock_transfer_lines').' WHERE transfer_id=%d LIMIT 1',$id));
    if((uat_dispatch('inventory.transfer_receive',$manager,['id'=>$id,'lines'=>[['transfer_line_id'=>$lineId,'received_quantity'=>5]]])['status']??'')!=='received') throw new RuntimeException('transfer receive failed');
    $source=(float)$wpdb->get_var('SELECT quantity FROM '.Db::table('stock_balances').' WHERE company_id=1 AND branch_id=1 AND product_id=100 AND batch_key=0 AND custodian_key=0');
    $dest=(float)$wpdb->get_var('SELECT quantity FROM '.Db::table('stock_balances').' WHERE company_id=1 AND branch_id=2 AND product_id=100 AND batch_key=0 AND custodian_key=0');
    if(abs($source-93.0)>0.001||abs($dest-5.0)>0.001) throw new RuntimeException("transfer invariant mismatch source={$source} dest={$dest}");
});

uat_case('uat_inventory_transfer_list_branches_units_and_scope', function () use ($manager,$branchManager,$wpdb) {
    // This suite recreates a disposable MariaDB schema: no production data is touched.
    $rows = uat_dispatch('inventory.transfers', $manager, ['branch_id'=>1]);
    $received = null;
    foreach ($rows as $row) {
        if (($row['status'] ?? '') === 'received') { $received = $row; break; }
    }
    if (!$received) throw new RuntimeException('Expected received transfer missing from source branch');
    if (($received['source_branch_name'] ?? '') !== 'UAT Branch One'
        || ($received['destination_branch_name'] ?? '') !== 'UAT Branch Two'
        || (int)($received['line_count'] ?? 0) !== 1
        || abs((float)($received['single_quantity'] ?? 0)-5.0)>0.001
        || ($received['single_uom'] ?? '') !== 'PCS') {
        throw new RuntimeException('Transfer list lost human-readable branches, one-line quantity or UOM');
    }
    $destinationRows = uat_dispatch('inventory.transfers', $branchManager, ['branch_id'=>2]);
    if (!array_filter($destinationRows, fn($r)=>(int)$r['id']===(int)$received['id'])) {
        throw new RuntimeException('Authorised destination branch cannot see its transfer');
    }
    uat_expect_denial(
        fn()=>uat_dispatch('inventory.transfers', $branchManager, ['branch_id'=>1]),
        'branch_forbidden', 'Destination-only manager cannot list source branch'
    );

    uat_insert($wpdb,'products', [
        'id'=>101,'company_id'=>1,'sku'=>'UAT-KG-101','name'=>'UAT Bulk Product',
        'uom'=>'KG','batch_tracking'=>'off','expiry_tracking'=>0,
        'status'=>'active','created_at'=>'2026-01-01 00:00:00',
    ]);
    uat_insert($wpdb,'stock_transfers', [
        'id'=>900,'company_id'=>1,'source_branch_id'=>1,
        'destination_branch_id'=>2,'status'=>'draft','created_by'=>30,
        'created_at'=>'2026-01-01 00:00:00',
    ]);
    uat_insert($wpdb,'stock_transfer_lines', [
        'transfer_id'=>900,'product_id'=>100,'batch_id'=>null,'quantity'=>3,
    ]);
    uat_insert($wpdb,'stock_transfer_lines', [
        'transfer_id'=>900,'product_id'=>101,'batch_id'=>null,'quantity'=>7,
    ]);
    $rows = uat_dispatch('inventory.transfers', $manager, ['branch_id'=>1]);
    $multi = null;
    foreach ($rows as $row) {
        if ((int)$row['id']===900) { $multi=$row; break; }
    }
    if (!$multi || (int)($multi['line_count'] ?? 0)!==2) {
        throw new RuntimeException('Mixed-unit transfer line count is wrong');
    }
    // Multi-product transfers must be presented as counts, not a sum across KG and PCS.
    if (($multi['source_branch_name'] ?? '') !== 'UAT Branch One'
        || ($multi['destination_branch_name'] ?? '') !== 'UAT Branch Two') {
        throw new RuntimeException('Mixed-unit transfer branch labels are wrong');
    }
});

uat_case('uat_finance_expense_maker_checker', function () use ($self,$maker,$manager,$financeReviewer,$branchManager,$wpdb) {
    $expense=uat_dispatch('finance.expense',$maker,[
        'branch_id'=>1,'expense_head_id'=>1,'amount'=>75,'payment_account_id'=>1,'expense_date'=>uat_date(),'description'=>'UAT controlled expense',
    ]);
    $expenseId = (int)$expense['id'];
    $journalsBefore = (int)$wpdb->get_var('SELECT COUNT(*) FROM '.Db::table('journal_entries'));
    uat_expect_denial(fn()=>uat_dispatch('finance.expense_decision',$self,['id'=>$expenseId,'approve'=>true]),
        'permission_denied', 'Staff cannot approve expense');
    uat_expect_denial(fn()=>uat_dispatch('finance.expense_decision',$financeReviewer,['id'=>$expenseId,'approve'=>true]),
        'maker_checker_required', 'Expense maker cannot approve own payment');
    uat_expect_denial(fn()=>uat_dispatch('finance.expense_decision',$branchManager,['id'=>$expenseId,'approve'=>true]),
        'branch_forbidden', 'Other-branch manager cannot approve expense');
    $pending = (string)$wpdb->get_var($wpdb->prepare(
        'SELECT status FROM '.Db::table('expenses').' WHERE id=%d', $expenseId
    ));
    $journalCount = (int)$wpdb->get_var('SELECT COUNT(*) FROM '.Db::table('journal_entries'));
    if ($pending !== 'pending' || $journalCount !== $journalsBefore) {
        throw new RuntimeException('Denied expense approval created journal or altered state');
    }
    $decision=uat_dispatch('finance.expense_decision',$manager,['id'=>$expenseId,'approve'=>true]);
    $journal=(int)($decision['journal_entry_id']??0);
    if(($decision['status']??'')!=='approved'||$journal<1) throw new RuntimeException('expense approval/journal failed');
    $dr=(float)$wpdb->get_var('SELECT COALESCE(SUM(debit),0) FROM '.Db::table('journal_lines').' WHERE journal_entry_id='.$journal);
    $cr=(float)$wpdb->get_var('SELECT COALESCE(SUM(credit),0) FROM '.Db::table('journal_lines').' WHERE journal_entry_id='.$journal);
    if(abs($dr-75.0)>0.005||abs($cr-75.0)>0.005) throw new RuntimeException('expense journal not balanced');
});

uat_case('uat_payroll_generate_approve_pay', function () use ($self,$maker,$manager,$wpdb) {
    $date=uat_date();
    $generated=uat_dispatch('payroll.generate',$maker,['branch_id'=>1,'period_start'=>$date,'period_end'=>$date]);
    $id=(int)$generated['id'];
    if(($generated['status']??'')!=='draft'||(float)$generated['net_total']<=0) throw new RuntimeException('payroll generation failed');
    uat_expect_denial(fn()=>uat_dispatch('payroll.approve',$self,['id'=>$id]),
        'permission_denied', 'Staff cannot approve Payroll');
    $selfPayrollApprover = uat_actor(30, [1,2], [Capabilities::PAYROLL_APPROVE], 'FINANCE');
    uat_expect_denial(fn()=>uat_dispatch('payroll.approve',$selfPayrollApprover,['id'=>$id]),
        'maker_checker_required', 'Payroll maker cannot approve own run');
    $foreignPayrollApprover = uat_actor(20, [2], [Capabilities::PAYROLL_APPROVE], 'BM');
    uat_expect_denial(fn()=>uat_dispatch('payroll.approve',$foreignPayrollApprover,['id'=>$id]),
        'branch_forbidden', 'Other-branch manager cannot approve Payroll');
    $statusBefore = (string)$wpdb->get_var($wpdb->prepare(
        'SELECT status FROM '.Db::table('payroll_runs').' WHERE id=%d', $id
    ));
    if ($statusBefore !== 'draft') throw new RuntimeException('Denied Payroll approval changed status');
    if((uat_dispatch('payroll.approve',$manager,['id'=>$id])['status']??'')!=='approved') throw new RuntimeException('payroll approval failed');
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

uat_case('uat_no_negative_stock_and_balanced_journals', function () use ($wpdb) {
    $negative=(int)$wpdb->get_var('SELECT COUNT(*) FROM '.Db::table('stock_balances').' WHERE quantity < -0.0001');
    $unbalanced=(int)$wpdb->get_var(
        'SELECT COUNT(*) FROM (SELECT je.id FROM '.Db::table('journal_entries').' je JOIN '.Db::table('journal_lines').
        ' jl ON jl.journal_entry_id=je.id GROUP BY je.id HAVING ABS(SUM(jl.debit)-SUM(jl.credit)) > 0.005) x'
    );
    if($negative!==0||$unbalanced!==0) throw new RuntimeException("closing invariant mismatch negative_stock={$negative} unbalanced_journals={$unbalanced}");
});

// F17: Check the FULL synthetic business chain after all prior UAT cases.
// The single disposable MariaDB schema started with 100 PCS in Branch 1;
// employee sold 2 PCS and the inter-branch transfer moved 5 PCS to Branch 2.
// Cash/UPI must have been independently reconciled into one daily journal,
// while expense/payroll journals remain separately balanced.
uat_case('f17_daily_stock_transfer_cash_upi_and_ledger_cross_reconciliation', function () use ($wpdb) {
    $db = $wpdb;
    $cycles = (array)$db->get_results(
        'SELECT id FROM '.Db::table('daily_cycles').
        " WHERE company_id=1 AND branch_id=1 AND employee_id=10 AND status='completed'",
        ARRAY_A
    );
    if (count($cycles) !== 1) throw new RuntimeException('Expected exactly one completed synthetic Daily Order');
    $cycleId = (int)$cycles[0]['id'];
    $evenings = (array)$db->get_results($db->prepare(
        'SELECT status,expected_amount,cash_amount,upi_amount FROM '.Db::table('evening_settlements').
        ' WHERE daily_cycle_id=%d', $cycleId
    ), ARRAY_A);
    if (count($evenings) !== 1 || ($evenings[0]['status'] ?? '') !== 'posted'
        || abs((float)$evenings[0]['expected_amount'] - 200.0) > 0.005
        || abs((float)$evenings[0]['cash_amount'] - 100.0) > 0.005
        || abs((float)$evenings[0]['upi_amount'] - 100.0) > 0.005) {
        throw new RuntimeException('Evening settlement is not exactly 200=100 cash +100 verified UPI');
    }
    $receipts = (array)$db->get_results($db->prepare(
        'SELECT amount,status,bank_evidence_ref FROM '.Db::table('daily_upi_receipts').
        ' WHERE company_id=1 AND branch_id=1 AND daily_cycle_id=%d', $cycleId
    ), ARRAY_A);
    if (count($receipts) !== 1 || ($receipts[0]['status'] ?? '') !== 'verified'
        || ($receipts[0]['bank_evidence_ref'] ?? '') !== 'BANKMATCH001'
        || abs((float)$receipts[0]['amount'] - 100.0) > 0.005) {
        throw new RuntimeException('Bank evidence or UPI verification missing/duplicated');
    }

    // No second Daily final-post can hide behind a balanced journal.
    $journals = (array)$db->get_results($db->prepare(
        'SELECT id FROM '.Db::table('journal_entries').
        " WHERE company_id=1 AND branch_id=1 AND source_type='daily_cycle' AND source_id=%d AND status='posted'",
        $cycleId
    ), ARRAY_A);
    if (count($journals) !== 1) throw new RuntimeException('Expected one and only one posted Daily journal');
    $journalId = (int)$journals[0]['id'];
    $lines = (array)$db->get_results($db->prepare(
        'SELECT account_id,SUM(debit) debit,SUM(credit) credit FROM '.Db::table('journal_lines').
        ' WHERE journal_entry_id=%d GROUP BY account_id', $journalId
    ), ARRAY_A);
    $actual = [];
    foreach ($lines as $line) {
        $key = (int)$line['account_id'];
        if (isset($actual[$key])) throw new RuntimeException('Daily journal repeated account row');
        $actual[$key] = [(float)$line['debit'], (float)$line['credit']];
    }
    // In this synthetic fixture: 1 Cash, 2 UPI, 3 Sales, 4 COGS, 5 Inventory.
    $expected = [
        1 => [100.0, 0.0], 2 => [100.0, 0.0], 3 => [0.0, 200.0],
        4 => [100.0, 0.0], 5 => [0.0, 100.0],
    ];
    if (count($actual) !== count($expected)) {
        throw new RuntimeException('Daily journal account count mismatch');
    }
    foreach ($expected as $accountId => $amounts) {
        if (!isset($actual[$accountId])
            || abs($actual[$accountId][0] - $amounts[0]) > 0.005
            || abs($actual[$accountId][1] - $amounts[1]) > 0.005) {
            throw new RuntimeException('Daily Cash/UPI/Sales/COGS/Inventory journal account mismatch: '.$accountId);
        }
    }
    $perf = (int)$db->get_var($db->prepare(
        'SELECT COUNT(*) FROM '.Db::table('performance_entries').
        " WHERE company_id=1 AND employee_id=10 AND source_type='daily_cycle' AND source_id=%d",
        $cycleId
    ));
    if ($perf !== 1) throw new RuntimeException('Daily settlement produced missing/duplicate performance allocation');

    $balances = (array)$db->get_results(
        'SELECT branch_id,custodian_key,quantity FROM '.Db::table('stock_balances').
        ' WHERE company_id=1 AND product_id=100', ARRAY_A
    );
    $perLocation = []; $sum = 0.0;
    foreach ($balances as $row) {
        $key = (int)$row['branch_id'].':'.(int)$row['custodian_key'];
        if (isset($perLocation[$key])) throw new RuntimeException('Duplicate synthetic warehouse/custodian balance');
        $perLocation[$key] = (float)$row['quantity'];
        $sum += (float)$row['quantity'];
    }
    // 100 opening - 2 sold = 98 remaining, irrespective of internal custody movement.
    if (abs($sum - 98.0) > 0.001
        || abs(($perLocation['1:0'] ?? 0) - 93.0) > 0.001
        || abs(($perLocation['2:0'] ?? 0) - 5.0) > 0.001
        || abs(($perLocation['1:10'] ?? 0)) > 0.001) {
        throw new RuntimeException('Cross-workflow inventory did not reconcile to 93+5 and zero employee custody');
    }
    $received = (int)$db->get_var(
        'SELECT COUNT(*) FROM '.Db::table('stock_transfers').
        " WHERE company_id=1 AND source_branch_id=1 AND destination_branch_id=2 AND status='received'"
    );
    if ($received !== 1) throw new RuntimeException('Transferred stock arrived without exactly one receipt');

    // Expense + payroll both ran in this same schema; none may leave unbalanced postings.
    $unbalanced = (int)$db->get_var(
        'SELECT COUNT(*) FROM (SELECT je.id FROM '.Db::table('journal_entries').' je JOIN '.
        Db::table('journal_lines').' jl ON jl.journal_entry_id=je.id'.
        ' GROUP BY je.id HAVING ABS(SUM(jl.debit)-SUM(jl.credit)) > 0.005) x'
    );
    if ($unbalanced !== 0) throw new RuntimeException('Combined Daily, expense, payroll and transfer journals out of balance');
});

// F17 follow-up: a replay of the same final-post must not collect money,
// deduct employee custody, create another journal or award salary points twice.
uat_case('f17_completed_daily_final_post_replay_is_read_only', function () use ($manager, $wpdb) {
    $db = $wpdb;
    $cycleId = (int)$db->get_var(
        'SELECT id FROM '.Db::table('daily_cycles').
        " WHERE company_id=1 AND branch_id=1 AND employee_id=10 AND status='completed' LIMIT 1"
    );
    if ($cycleId < 1) throw new RuntimeException('No completed synthetic Daily cycle for replay');
    $tables = ['journal_entries', 'journal_lines', 'performance_entries', 'stock_ledger', 'audit_log'];
    $before = [];
    foreach ($tables as $table) {
        $before[$table] = (int)$db->get_var('SELECT COUNT(*) FROM '.Db::table($table));
    }
    $stockBefore = (array)$db->get_results(
        'SELECT branch_id,product_id,batch_key,custodian_key,quantity,average_unit_cost FROM '.
        Db::table('stock_balances').' ORDER BY branch_id,product_id,batch_key,custodian_key', ARRAY_A
    );
    try {
        uat_dispatch('daily.final_post', $manager, [
            'id'=>$cycleId, 'cash'=>100, 'upi'=>100,
        ]);
    } catch (DomainException $e) {
        // A completed cycle is not in the evening_submitted state. The state
        // rejection is the required behavior; do not assume one error-code label.
        foreach ($tables as $table) {
            $count = (int)$db->get_var('SELECT COUNT(*) FROM '.Db::table($table));
            if ($count !== $before[$table]) {
                throw new RuntimeException('Replay changed '.$table.' rows: '.$before[$table].' -> '.$count);
            }
        }
        $stockAfter = (array)$db->get_results(
            'SELECT branch_id,product_id,batch_key,custodian_key,quantity,average_unit_cost FROM '.
            Db::table('stock_balances').' ORDER BY branch_id,product_id,batch_key,custodian_key', ARRAY_A
        );
        if ($stockBefore !== $stockAfter) {
            throw new RuntimeException('Rejected Daily replay changed warehouse or custody stock');
        }
        return;
    }
    throw new RuntimeException('Completed Daily cycle was final-posted twice');
});

// F25: reconcile the existing posted five-value report against its source
// lines, and verify historical branch scope after a synthetic employee move.
uat_case('f25_price_distribution_reconciles_and_excludes_foreign_branch_history', function () use ($wpdb) {
    $date = uat_date();
    $admin = uat_actor(20, [1,2], [Capabilities::REPORTS_VIEW], 'SYSADMIN');
    $branchTwo = uat_actor(20, [2], [Capabilities::REPORTS_VIEW], 'BM');
    $report = fn($actor, $branch, $category = '') => uat_dispatch(
        'reports.price_distribution', $actor, [
            'branch_id'=>$branch, 'from'=>$date, 'to'=>$date,
            'reporting_category'=>$category,
        ]
    );
    $fields = ['sale_price','ho_amount','bm_profit','salary_fund','expense','points'];
    $expected = $wpdb->get_row(
        'SELECT SUM(el.total_amount) sale_price,SUM(el.ho_amount) ho_amount,'.
        'SUM(el.bm_profit) bm_profit,SUM(el.salary_fund) salary_fund,'.
        'SUM(el.office_expense) expense,SUM(el.points) points FROM '.Db::table('daily_cycles').' c JOIN '.
        Db::table('evening_settlements')." es ON es.daily_cycle_id=c.id AND es.status='posted' JOIN ".
        Db::table('evening_lines')." el ON el.evening_settlement_id=es.id WHERE c.company_id=1 AND c.branch_id=1 ".
        "AND c.employee_id=10 AND c.status='completed'", ARRAY_A
    );
    $baseline = $report($admin, 1, 'FIELD_EXECUTIVE');
    if (count($baseline['rows']) !== 1 || (int)$baseline['rows'][0]['branch_id'] !== 1
        || (int)$baseline['rows'][0]['employee_id'] !== 10
        || (int)$baseline['rows'][0]['sale_days'] !== 1
        || abs((float)$baseline['totals']['sale_price'] - 200.0) > 0.005) {
        throw new RuntimeException('Expected one posted synthetic sale of 200 in Branch 1');
    }
    foreach ($fields as $field) {
        if (!isset($expected[$field], $baseline['rows'][0][$field], $baseline['totals'][$field])
            || abs((float)$baseline['rows'][0][$field] - (float)$expected[$field]) > 0.005
            || abs((float)$baseline['totals'][$field] - (float)$expected[$field]) > 0.005) {
            throw new RuntimeException('Price distribution differs from posted source: '.$field);
        }
    }
    $empty = function(array $result) use ($fields): void {
        if ($result['rows'] !== []) throw new RuntimeException('Foreign branch distribution rows leaked');
        foreach ($fields as $field) {
            if (!isset($result['totals'][$field]) || abs((float)$result['totals'][$field]) > 0.005) {
                throw new RuntimeException('Foreign branch distribution total leaked: '.$field);
            }
        }
    };
    $empty($report($admin, 1, 'BRANCH_MANAGER'));
    $empty($report($branchTwo, 2));

    // Only this disposable fixture is altered; restore even on assertion failure.
    if ($wpdb->query('UPDATE '.Db::table('employees').' SET assigned_branch_id=2 WHERE company_id=1 AND id=10') === false) {
        throw new RuntimeException('Could not move synthetic employee');
    }
    try {
        $empty($report($admin, 2));
        $empty($report($branchTwo, 2));
        $empty($report($branchTwo, null));
        $all = $report($admin, null, 'FIELD_EXECUTIVE');
        if (count($all['rows']) !== 1 || (int)$all['rows'][0]['branch_id'] !== 1) {
            throw new RuntimeException('Company-wide admin lost original transaction branch');
        }
        foreach ($fields as $field) {
            if (!isset($all['totals'][$field]) || abs((float)$all['totals'][$field] - (float)$expected[$field]) > 0.005) {
                throw new RuntimeException('Company-wide report changed after employee move: '.$field);
            }
        }
        uat_expect_denial(fn()=>$report($branchTwo, 1), 'branch_forbidden', 'Foreign branch price distribution');
    } finally {
        if ($wpdb->query('UPDATE '.Db::table('employees').' SET assigned_branch_id=1 WHERE company_id=1 AND id=10') === false) {
            throw new RuntimeException('Could not restore synthetic employee branch');
        }
    }
});

// F28: run the actual existing REST dispatcher with a disposable clock and DB.
uat_case('f28_self_attendance_cutover_manual_punch_and_recover_due_checkout', function () use ($wpdb) {
    $self = uat_actor(30,[2],[Capabilities::ATT_SELF],'FE');
    $another = uat_actor(20,[2],[Capabilities::ATT_SELF],'FE');
    $date = '2030-01-02';
    $policyKey = 'attendance_policy@'.$date;
    $admin=uat_actor(20,[1,2],[Capabilities::ACCESS_MANAGE],'SYSADMIN');
    $setTime = static function(string $stamp): void {
        $GLOBALS['eh7_test_clock_utc'] = strtotime($stamp.' UTC');
    };
    $read = static fn($actor) => uat_dispatch('work.attendance_today',$actor);
    $checkIn = static fn($actor) => uat_dispatch('work.check_in',$actor,['branch_id'=>2,'lat'=>31.7,'lng'=>76.9]);
    $checkOut = static fn($actor) => uat_dispatch('work.check_out',$actor,['lat'=>31.71,'lng'=>76.91]);
    $mustDeny = static function(callable $fn,string $code): void {
        try {$fn();} catch (DomainException $e) {
            if ($e->codeKey===$code) return;
            throw $e;
        }
        throw new RuntimeException('Expected attendance denial: '.$code);
    };
    $attendance = Db::table('attendance');
    $settings=Db::table('settings');
    $setTime('2030-01-01 12:00:00');
    try {
        $payload=['effective_from'=>$date,'times'=>\ExcelHerbal\ERP7\Workforce\SelfAttendancePolicy::DEFAULTS,'reason'=>'Approved fixture schedule'];
        $mustDeny(fn()=>uat_dispatch('admin.attendance_policy_save',$self,[],$payload),'permission_denied');
        $mustDeny(fn()=>uat_dispatch('admin.attendance_policy_save',$admin,[],array_replace($payload,['effective_from'=>'2030-01-01'])),'attendance_policy_date_invalid');
        $saved=uat_dispatch('admin.attendance_policy_save',$admin,[],$payload);
        if($saved['effective_from']!==$date) throw new RuntimeException('Policy save failed');
        $policy=uat_dispatch('admin.attendance_policy',$admin);
        if($policy['current']!==null||count($policy['upcoming'])!==1) throw new RuntimeException('Future policy applied too early');
        $setTime($date.' 08:59:59');
        $r=$read($self);
        if($r['attendance_mode']!=='self'||$r['can_check_in']!==false) throw new RuntimeException('Check-in available before 09:00');
        $mustDeny(fn()=>$checkIn($self),'attendance_window_closed');
        $setTime($date.' 09:00:00');
        if(!$read($self)['can_check_in']) throw new RuntimeException('Check-in not available at 09:00');
        $mustDeny(fn()=>uat_dispatch('work.check_in',$self,['branch_id'=>2]),'attendance_location_required');
        $mustDeny(fn()=>uat_dispatch('work.check_in',$self,['branch_id'=>1,'lat'=>31.7,'lng'=>76.9]),'branch_forbidden');
        $p=$checkIn($self);
        $row=$wpdb->get_row($wpdb->prepare("SELECT * FROM {$attendance} WHERE id=%d",(int)$p['id']),ARRAY_A);
        if(!$row||(int)$row['employee_id']!==30||$row['check_in_mode']!=='self'||$row['check_in_at']!==$date.' 09:00:00'||$row['auto_checkout_due_at']!==$date.' 19:00:00') throw new RuntimeException('Stored self check-in identity/time mismatch');
        if(abs((float)$row['check_in_lat']-31.7)>.00001||abs((float)$row['check_in_lng']-76.9)>.00001) throw new RuntimeException('Check-in location missing');
        $mustDeny(fn()=>$checkIn($self),'attendance_exists');
        $setTime($date.' 10:30:00');
        $policy=uat_dispatch('admin.attendance_policy',$admin);
        if(($policy['current']['effective_from']??null)!==$date) throw new RuntimeException('Scheduled policy not active');
        $mustDeny(fn()=>uat_dispatch('admin.attendance_policy_save',$admin,[],$payload),'attendance_policy_date_invalid');
        $r=$read($self);
        if(!$r['gps_should_track']||$r['gps_status']!=='active') throw new RuntimeException('GPS did not activate at 10:30');
        \ExcelHerbal\ERP7\Workforce\ScheduledAttendanceService::run();
        if((int)$wpdb->get_var($wpdb->prepare("SELECT COUNT(*) FROM {$attendance} WHERE company_id=1 AND business_date=%s",$date))!==1) throw new RuntimeException('Legacy scheduler created attendance in activated company');
        $setTime($date.' 17:00:00');
        $r=$read($self);
        if($r['gps_should_track']||!$r['can_check_out']||!empty($r['check_out_at'])) throw new RuntimeException('GPS stop closed attendance early');
        $setTime($date.' 18:15:00');
        $p=$checkOut($self);
        if($p['checkout_mode']!=='self'||$p['check_out_at']!==$date.' 18:15:00') throw new RuntimeException('Self checkout not recorded');
        $mustDeny(fn()=>$checkOut($self),'attendance_open_required');
        $checkIn($another);
        $nextTimes=array_replace($payload['times'],['duty_start'=>'09:15:00','gps_start'=>'11:00:00','gps_stop'=>'16:30:00','duty_end'=>'18:15:00','auto_checkout'=>'19:15:00']);
        uat_dispatch('admin.attendance_policy_save',$admin,[],['effective_from'=>'2030-01-03','times'=>$nextTimes,'reason'=>'Future fixture timing']);
        $setTime($date.' 19:00:00');
        $mustDeny(fn()=>$checkOut($another),'attendance_checkout_due');
        $setTime('2030-01-03 08:00:00');
        \ExcelHerbal\ERP7\Workforce\ScheduledAttendanceService::run();
        $row=$wpdb->get_row($wpdb->prepare("SELECT * FROM {$attendance} WHERE company_id=1 AND employee_id=20 AND business_date=%s",$date),ARRAY_A);
        if(!$row||$row['check_out_at']!==$date.' 19:00:00'||$row['checkout_mode']!=='auto'||$row['checkout_processed_at']!=='2030-01-03 08:00:00'||$row['check_out_lat']!==null||$row['check_out_lng']!==null) throw new RuntimeException('Recovered auto checkout provenance incorrect');
        \ExcelHerbal\ERP7\Workforce\ScheduledAttendanceService::run();
        $repeat=$wpdb->get_row($wpdb->prepare("SELECT * FROM {$attendance} WHERE id=%d",(int)$row['id']),ARRAY_A);
        if($repeat!==$row) throw new RuntimeException('Repeated auto checkout changed stored evidence');
        $audit=(int)$wpdb->get_var($wpdb->prepare("SELECT COUNT(*) FROM ".Db::table('audit_log')." WHERE company_id=1 AND entity_type='attendance' AND entity_id=%s AND action='attendance.auto_checkout'",(string)$row['id']));
        if($audit!==1) throw new RuntimeException('Expected exactly one automatic checkout audit record');
        $setTime('2030-01-03 09:00:00');
        if($read($self)['can_check_in']) throw new RuntimeException('Future policy start ignored');
        $setTime('2030-01-03 09:15:00');
        $p=$checkIn($self);
        if($p['auto_checkout_due_at']!=='2030-01-03 19:15:00') throw new RuntimeException('Changed cutoff not snapshotted');
        $setTime('2030-01-03 10:30:00');
        if($read($self)['gps_should_track']) throw new RuntimeException('Old GPS start still active');
        $setTime('2030-01-03 11:00:00');
        if(!$read($self)['gps_should_track']) throw new RuntimeException('Configured GPS start ignored');
        $setTime('2030-01-03 16:30:00');
        if($read($self)['gps_should_track']||!$read($self)['can_check_out']) throw new RuntimeException('Configured GPS end ignored');
    } finally {
        unset($GLOBALS['eh7_test_clock_utc']);
        $wpdb->query($wpdb->prepare("DELETE FROM {$settings} WHERE company_id=1 AND setting_key IN (%s,%s)",$policyKey,'attendance_policy@2030-01-03'));
    }
});

// F29: only a company-wide authorized reviewer may acknowledge old legacy
// omissions. No attendance time, GPS evidence or payroll input is fabricated.
uat_case('f29_head_office_legacy_checkout_acknowledgement',function()use($wpdb){
    $date='2020-01-02';
    $table=Db::table('attendance');
    $caps=[Capabilities::ATT_MANAGE,Capabilities::ACCESS_MANAGE];
    $admin=uat_actor(20,[1,2],$caps,'SYSADMIN');
    $bm=uat_actor(30,[2],$caps,'BM');
    $own=uat_actor(10,[1,2],$caps,'SYSADMIN');
    uat_insert($wpdb,'attendance',['company_id'=>1,'branch_id'=>1,'employee_id'=>10,'business_date'=>$date,
        'check_in_at'=>$date.' 05:00:00','status'=>'present','created_at'=>$date.' 05:00:00']);
    $id=(int)$wpdb->insert_id;
    $reason='Reviewed synthetic missing checkout evidence';
    $post=static fn($actor,$record,$why)=>uat_dispatch('admin.attendance_exception_ack',$actor,['attendance_id'=>$record,'reason'=>$why]);
    $before=$wpdb->get_row($wpdb->prepare("SELECT * FROM {$table} WHERE id=%d",$id),ARRAY_A);
    uat_expect_denial(fn()=>$post($bm,$id,$reason),'attendance_exception_forbidden','BM cannot acknowledge legacy attendance');
    uat_expect_denial(fn()=>$post($own,$id,$reason),'maker_checker_required','No own attendance acknowledgement');
    uat_expect_denial(fn()=>$post($admin,$id,'short'),'attendance_exception_invalid','Audit reason required');
    uat_expect_denial(fn()=>$post(new Actor(1,20,2,1,[1,2],$caps,'SYSADMIN'),$id,$reason),'attendance_exception_forbidden','No authority in an unconfigured foreign company');
    uat_insert($wpdb,'attendance',['company_id'=>2,'branch_id'=>1,'employee_id'=>10,'business_date'=>$date,
        'check_in_at'=>$date.' 05:00:00','status'=>'present','created_at'=>$date.' 05:00:00']);
    $foreignId=(int)$wpdb->insert_id;
    uat_expect_denial(fn()=>$post($admin,$foreignId,$reason),'attendance_not_found','No foreign company record acknowledgement');
    $rows=uat_dispatch('work.attendance_report',$admin,['branch_id'=>1,'from'=>$date,'to'=>$date]);
    if(count($rows)!==1||$rows[0]['can_acknowledge_missing_checkout']!==true)throw new RuntimeException('Eligible review action not projected');
    $result=$post($admin,$id,$reason);
    $after=$wpdb->get_row($wpdb->prepare("SELECT * FROM {$table} WHERE id=%d",$id),ARRAY_A);
    if($result['checkout_exception']!==1||(int)$after['checkout_exception']!==1||(int)$after['checkout_exception_by']!==20||$after['checkout_exception_reason']!==$reason)throw new RuntimeException('Acknowledgement not stored');
    foreach($before as $field=>$value){
        if(!in_array($field,['checkout_exception','checkout_exception_reason','checkout_exception_by','checkout_exception_at'],true)&&$after[$field]!==$value)throw new RuntimeException('Original attendance evidence changed: '.$field);
    }
    uat_expect_denial(fn()=>$post($admin,$id,$reason),'attendance_exception_state_invalid','Duplicate acknowledgement denied');
    $count=(int)$wpdb->get_var($wpdb->prepare("SELECT COUNT(*) FROM ".Db::table('audit_log')." WHERE company_id=1 AND entity_type='attendance' AND entity_id=%s AND action='attendance.checkout_missing_acknowledged'",(string)$id));
    if($count!==1)throw new RuntimeException('Exactly one review audit required');
    uat_insert($wpdb,'attendance',['company_id'=>1,'branch_id'=>2,'employee_id'=>30,'business_date'=>$date,
        'check_in_at'=>$date.' 05:00:00','check_in_mode'=>'self','auto_checkout_due_at'=>$date.' 13:30:00','status'=>'present','created_at'=>$date.' 05:00:00']);
    $selfId=(int)$wpdb->insert_id;
    uat_expect_denial(fn()=>$post($admin,$selfId,$reason),'attendance_exception_state_invalid','New-mode row reserved for auto recovery');
});

// F30 uses an actual dispatcher, synthetic historical business dates and an
// isolated database. No production attendance or stock rows are involved.
uat_case('f30_self_punch_gps_receipt_window_and_daily_order_evidence',function()use($wpdb){
    $date='2026-01-05';
    $actor=uat_actor(10,[1],[Capabilities::ATT_SELF,Capabilities::DAILY_SELF],'FE');
    $admin=uat_actor(20,[1,2],[Capabilities::ACCESS_MANAGE],'SYSADMIN');
    $setTime=static function(string $stamp):void{
        $GLOBALS['eh7_test_clock_utc']=strtotime($stamp.' UTC');
    };
    $point=static fn($stamp)=>uat_dispatch('work.gps_point',$actor,[],[
        'lat'=>31.71,'lng'=>76.91,'source'=>'duty','recorded_at'=>$date.'T'.$stamp.'Z',
    ]);
    $order=static fn()=>uat_dispatch('daily.create',$actor,[
        'branch_id'=>1,'employee_id'=>10,'business_date'=>$date,'lines'=>[['product_id'=>100,'quantity'=>1]],
    ]);
    $att=Db::table('attendance');$points=Db::table('gps_points');
    try {
        $setTime('2026-01-04 12:00:00');
        uat_dispatch('admin.attendance_policy_save',$admin,[],[
            'effective_from'=>$date,'times'=>\ExcelHerbal\ERP7\Workforce\SelfAttendancePolicy::DEFAULTS,
            'reason'=>'Disposable fixture policy for GPS and order crosscheck',
        ]);
        $setTime($date.' 09:00:00');
        uat_expect_denial(fn()=>$point('09:00:00'),'gps_checkin_required','No GPS without check-in');
        $p=uat_dispatch('work.check_in',$actor,['branch_id'=>1,'lat'=>31.70,'lng'=>76.90]);
        $id=(int)$p['id'];
        uat_expect_denial(fn()=>$point('09:00:00'),'gps_window_not_started','GPS cannot begin before 10:30');
        uat_expect_denial($order,'daily_attendance_required','Self punch location alone is not route evidence');
        $setTime($date.' 10:30:00');
        uat_expect_denial(fn()=>$point('10:30:01'),'gps_recorded_time_invalid','Future device timestamp denied');
        uat_expect_denial(fn()=>$point('10:29:59'),'gps_window_not_started','Pre-window GPS timestamp denied');
        $gps=$point('10:30:00');
        if((int)$gps['id']<1)throw new RuntimeException('GPS point not saved');
        $r=$wpdb->get_row($wpdb->prepare("SELECT * FROM {$att} WHERE id=%d",$id),ARRAY_A);
        if(abs((float)$r['check_in_lat']-31.70)>.000001||abs((float)$r['check_in_lng']-76.90)>.000001)throw new RuntimeException('Route point overwrote punch coordinates');
        $d=$order();
        if(($d['status']??'')!=='morning_draft')throw new RuntimeException('Verified route point did not authorize daily order');
        $setTime($date.' 17:00:00');
        uat_expect_denial(fn()=>$point('16:59:59'),'gps_window_closed','Backdated upload after GPS cutoff denied');
        $r=uat_dispatch('work.attendance_today',$actor);
        if(!$r['can_check_out']||$r['gps_should_track'])throw new RuntimeException('GPS cutoff must not close employee duty');
        $setTime($date.' 18:00:00');
        uat_dispatch('work.check_out',$actor,['lat'=>31.72,'lng'=>76.92]);
        uat_expect_denial(fn()=>$point('16:59:59'),'gps_checkin_required','No GPS after checkout');
        $count=(int)$wpdb->get_var($wpdb->prepare("SELECT COUNT(*) FROM {$points} WHERE attendance_id=%d",$id));
        if($count!==1)throw new RuntimeException('Denied GPS requests persisted unexpected points');
    }finally{
        unset($GLOBALS['eh7_test_clock_utc']);
        $wpdb->query($wpdb->prepare("DELETE FROM ".Db::table('settings')." WHERE company_id=1 AND setting_key=%s",'attendance_policy@'.$date));
    }
});

// F31: GPS exception decision is isolated from actual attendance, route
// evidence, Daily Order and salary. Test-only future date and synthetic actors.
uat_case('f31_gps_exception_request_independent_head_office_decision',function()use($wpdb){
    $date='2031-01-02';
    $employee=uat_actor(10,[1],[Capabilities::ATT_SELF,Capabilities::DAILY_SELF],'FE');
    $review=uat_actor(20,[1,2],[Capabilities::ATT_MANAGE,Capabilities::ACCESS_MANAGE],'SYSADMIN');
    $own=uat_actor(10,[1,2],[Capabilities::ATT_MANAGE,Capabilities::ACCESS_MANAGE],'SYSADMIN');
    $bm=uat_actor(30,[2],[Capabilities::ATT_MANAGE,Capabilities::ACCESS_MANAGE],'BM');
    $setTime=static function(string $stamp):void{$GLOBALS['eh7_test_clock_utc']=strtotime($stamp.' UTC');};
    $request=static fn($scope)=>uat_dispatch('work.gps_exception_request',$employee,[],['scope'=>$scope,'reason'=>'Device GPS unavailable, synthetic request']);
    $decide=static fn($actor,$id,$decision)=>uat_dispatch('admin.gps_exception_decide',$actor,['id'=>$id],['decision'=>$decision,'reason'=>'Reviewed synthetic evidence independently']);
    try{
        $setTime('2031-01-01 12:00:00');
        uat_dispatch('admin.attendance_policy_save',$review,[],['effective_from'=>$date,'times'=>\ExcelHerbal\ERP7\Workforce\SelfAttendancePolicy::DEFAULTS,'reason'=>'Synthetic GPS exception fixture']);
        $setTime($date.' 08:59:59');
        uat_expect_denial(fn()=>$request('check_in'),'gps_exception_window_closed','No request before duty');
        $setTime($date.' 09:00:00');
        uat_expect_denial(fn()=>$request('check_out'),'gps_exception_window_closed','No checkout exception without open attendance');
        $r=$request('check_in');$id=(int)$r['id'];
        if($r['status']!=='pending')throw new RuntimeException('Request not pending');
        uat_expect_denial(fn()=>$request('check_in'),'gps_exception_duplicate','No duplicate punch exception');
        uat_expect_denial(fn()=>$decide($bm,$id,'approved'),'gps_exception_forbidden','BM cannot review');
        uat_expect_denial(fn()=>$decide($own,$id,'approved'),'maker_checker_required','No self approval');
        $rows=uat_dispatch('admin.gps_exception_inbox',$review,['branch_id'=>1]);
        if(count($rows)!==1||$rows[0]['can_approve']!==true)throw new RuntimeException('Pending review not visible');
        if($decide($review,$id,'approved')['status']!=='approved')throw new RuntimeException('Decision failed');
        uat_expect_denial(fn()=>$decide($review,$id,'rejected'),'gps_exception_state_invalid','No second decision');
        $mine=uat_dispatch('work.gps_exception_mine',$employee);
        if(count($mine)!==1||$mine[0]['status']!=='approved')throw new RuntimeException('Own decision not visible');
        uat_expect_denial(fn()=>uat_dispatch('work.check_in',$employee,['branch_id'=>1]),'attendance_location_required','Approval alone does not bypass actual punch');
        $att=(int)$wpdb->get_var($wpdb->prepare("SELECT COUNT(*) FROM ".Db::table('attendance')." WHERE company_id=1 AND employee_id=10 AND business_date=%s",$date));
        if($att!==0)throw new RuntimeException('Review manufactured attendance');
        $p=uat_dispatch('work.check_in',$employee,['branch_id'=>1,'lat'=>31.7,'lng'=>76.9]);
        $r=$request('check_out');
        $setTime('2031-01-03 09:00:00');
        uat_expect_denial(fn()=>$decide($review,(int)$r['id'],'approved'),'gps_exception_expired','No backdated approval');
        if($decide($review,(int)$r['id'],'rejected')['status']!=='rejected')throw new RuntimeException('Expired request cannot be closed');
        $audit=(int)$wpdb->get_var($wpdb->prepare("SELECT COUNT(*) FROM ".Db::table('audit_log')." WHERE company_id=1 AND entity_type='attendance_gps_exception' AND entity_id=%s",(string)$id));
        if($audit!==2)throw new RuntimeException('Request and review audit missing');
    }finally{
        unset($GLOBALS['eh7_test_clock_utc']);
        $wpdb->query($wpdb->prepare("DELETE FROM ".Db::table('settings')." WHERE company_id=1 AND setting_key=%s",'attendance_policy@'.$date));
    }
});

echo ($failed ? 'FAILED' : 'PASSED')." staging UAT end-to-end smoke suite\n";
exit($failed ? 1 : 0);
