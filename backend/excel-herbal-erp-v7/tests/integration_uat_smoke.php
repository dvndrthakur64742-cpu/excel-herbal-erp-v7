<?php
define('EH7_INTEGRATION_LIBRARY_ONLY', true);
require __DIR__.'/integration_mariadb.php';

use ExcelHerbal\ERP7\Database\Db;
use ExcelHerbal\ERP7\Database\Schema;
use ExcelHerbal\ERP7\Domain\DomainException;
use ExcelHerbal\ERP7\Http\ApiDispatch;
use ExcelHerbal\ERP7\Security\Actor;
use ExcelHerbal\ERP7\Security\Capabilities;

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
    Capabilities::INVENTORY_VIEW,Capabilities::TRANSFER_RECEIVE,Capabilities::EXPENSE_APPROVE,
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
        if ($e->codeKey === 'permission_denied' && $e->httpStatus === 403) return;
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
    try { uat_dispatch('work.check_in', $self, ['branch_id'=>2]); }
    catch (DomainException $e) { if ($e->codeKey === 'branch_forbidden' && $e->httpStatus === 403) return; throw $e; }
    throw new RuntimeException('cross-branch attendance check-in was accepted');
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
    $in = uat_dispatch('work.check_in', $self, ['branch_id'=>1]);
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
    if ((uat_dispatch('daily.submit',$self,['id'=>$cycle])['status'] ?? '') !== 'stock_requested') throw new RuntimeException('daily submit failed');
    uat_expect_forbidden(
        fn()=>uat_dispatch('daily.approve',$self,['id'=>$request]),
        'self-service actor approved own daily request'
    );
    if ((uat_dispatch('daily.approve',$manager,['id'=>$request])['status'] ?? '') !== 'approved') throw new RuntimeException('daily approve failed');
    $lineId=(int)$wpdb->get_var($wpdb->prepare('SELECT id FROM '.Db::table('daily_request_lines').' WHERE daily_request_id=%d LIMIT 1',$request));
    if ((uat_dispatch('daily.issue',$manager,['id'=>$request,'allocations'=>[['request_line_id'=>$lineId,'quantity'=>2]]])['status'] ?? '') !== 'issued') throw new RuntimeException('daily issue failed');
    $evening=uat_dispatch('daily.evening_start',$self,['id'=>$cycle]); $eveningId=(int)$evening['evening_id'];
    $issueLineId=(int)$wpdb->get_var($wpdb->prepare('SELECT issue_line_id FROM '.Db::table('evening_lines').' WHERE evening_settlement_id=%d LIMIT 1',$eveningId));
    $saved=uat_dispatch('daily.evening_save',$self,[
        'id'=>$cycle,'lines'=>[['issue_line_id'=>$issueLineId,'return_quantity'=>0,'wholesale_quantity'=>0,'retail_rate'=>100,'wholesale_rate'=>0]],
        'wholesale_details'=>[],'price_reason'=>'',
    ]);
    if (abs((float)$saved['expected_amount']-200.0)>0.005) throw new RuntimeException('daily expected amount mismatch');
    uat_dispatch('daily.evening_submit',$self,['id'=>$cycle]);
    $posted=uat_dispatch('daily.final_post',$manager,['id'=>$cycle,'cash'=>200,'upi'=>0]);
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
    uat_expect_forbidden(
        fn()=>uat_dispatch('inventory.transfer_receive',$maker,['id'=>$id,'lines'=>[['transfer_line_id'=>$lineId,'received_quantity'=>5]]]),
        'transfer creator received own transfer without TRANSFER_RECEIVE'
    );
    if((uat_dispatch('inventory.transfer_receive',$manager,['id'=>$id,'lines'=>[['transfer_line_id'=>$lineId,'received_quantity'=>5]]])['status']??'')!=='received') throw new RuntimeException('transfer receive failed');
    $source=(float)$wpdb->get_var('SELECT quantity FROM '.Db::table('stock_balances').' WHERE company_id=1 AND branch_id=1 AND product_id=100 AND batch_key=0 AND custodian_key=0');
    $dest=(float)$wpdb->get_var('SELECT quantity FROM '.Db::table('stock_balances').' WHERE company_id=1 AND branch_id=2 AND product_id=100 AND batch_key=0 AND custodian_key=0');
    if(abs($source-93.0)>0.001||abs($dest-5.0)>0.001) throw new RuntimeException("transfer invariant mismatch source={$source} dest={$dest}");
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
