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

echo ($failed ? 'FAILED' : 'PASSED')." staging UAT end-to-end smoke suite\n";
exit($failed ? 1 : 0);
