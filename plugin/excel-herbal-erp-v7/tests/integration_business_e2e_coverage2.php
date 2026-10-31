<?php
define('EH7_INTEGRATION_LIBRARY_ONLY', true);
require __DIR__.'/integration_mariadb.php';

use ExcelHerbal\ERP7\Database\Db;
use ExcelHerbal\ERP7\Database\Schema;
use ExcelHerbal\ERP7\Domain\DomainException;
use ExcelHerbal\ERP7\Http\ApiDispatch;
use ExcelHerbal\ERP7\Security\Actor;
use ExcelHerbal\ERP7\Security\Capabilities;

if (!function_exists('wp_timezone')) {
    function wp_timezone(): DateTimeZone { return new DateTimeZone('UTC'); }
}
if (!function_exists('get_date_from_gmt')) {
    function get_date_from_gmt($date, $format = 'Y-m-d H:i:s') {
        try { return (new DateTimeImmutable((string)$date, new DateTimeZone('UTC')))->format((string)$format); }
        catch (Throwable $e) { return ''; }
    }
}

final class Eh7E2e2Request implements ArrayAccess {
    public function __construct(private array $params = [], private array $json = []) {}
    public function get_param(string $key): mixed { return $this->params[$key] ?? null; }
    public function get_params(): array { return $this->params + $this->json; }
    public function get_json_params(): array { return $this->json; }
    public function offsetExists(mixed $offset): bool { return array_key_exists((string)$offset, $this->params); }
    public function offsetGet(mixed $offset): mixed { return $this->params[(string)$offset] ?? null; }
    public function offsetSet(mixed $offset, mixed $value): void { $this->params[(string)$offset] = $value; }
    public function offsetUnset(mixed $offset): void { unset($this->params[(string)$offset]); }
}

function e2_date(): string { return gmdate('Y-m-d'); }
function e2_actor(int $employeeId, array $caps): Actor {
    return new Actor(7000 + $employeeId, $employeeId, 1, 1, [1], $caps, 'SYSADMIN');
}
function e2_dispatch(string $handler, Actor $actor, array $params = [], array $json = []): mixed {
    return ApiDispatch::dispatch($handler, new Eh7E2e2Request($params, $json), $actor);
}
function e2_insert(Eh7IntegrationWpdb $db, string $table, array $row): void {
    if ($db->insert(Db::table($table), $row) === false) throw new RuntimeException('Insert '.$table.' failed: '.$db->last_error);
}
function e2_rebuild(Eh7IntegrationWpdb $db): void {
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
}
function e2_seed(Eh7IntegrationWpdb $db): void {
    e2_insert($db,'companies',['id'=>1,'name'=>'Coverage II Disposable Co','status'=>'active','created_at'=>'2026-01-01 00:00:00']);
    e2_insert($db,'branches',['id'=>1,'company_id'=>1,'code'=>'B1','name'=>'Coverage Branch','is_head_office'=>1,'status'=>'active','created_at'=>'2026-01-01 00:00:00']);
    foreach ([[20,'E20','Coverage Approver'],[30,'E30','Coverage Maker']] as [$id,$code,$name]) {
        e2_insert($db,'employees',[
            'id'=>$id,'company_id'=>1,'employee_code'=>$code,'wp_user_id'=>8000+$id,'designation_code'=>'SYSADMIN',
            'assigned_branch_id'=>1,'full_name'=>$name,'mobile'=>'98888000'.$id,'monthly_salary'=>0,
            'joining_date'=>'2026-01-01','status'=>'active','created_at'=>'2026-01-01 00:00:00',
        ]);
    }
    e2_insert($db,'products',[
        'id'=>100,'company_id'=>1,'sku'=>'E2-P100','name'=>'Coverage Herbal Product','uom'=>'PCS',
        'batch_tracking'=>'off','expiry_tracking'=>0,'status'=>'active','created_at'=>'2026-01-01 00:00:00',
    ]);
    e2_insert($db,'product_commercial_revisions',[
        'id'=>1,'company_id'=>1,'product_id'=>100,'effective_from'=>'2026-01-01 00:00:00',
        'mrp'=>120,'sale_price'=>100,'ho_amount'=>20,'bm_profit'=>10,'salary_fund'=>5,
        'office_expense'=>5,'points'=>2,'purchase_cost'=>50,'reason'=>'Coverage pricing',
        'status'=>'active','approved_by'=>20,'created_at'=>'2026-01-01 00:00:00',
    ]);
    e2_insert($db,'stock_balances',[
        'id'=>1,'company_id'=>1,'branch_id'=>1,'product_id'=>100,'batch_key'=>0,'custodian_key'=>0,
        'quantity'=>0,'average_unit_cost'=>0,'updated_at'=>'2026-01-01 00:00:00',
    ]);

    $accounts=[
        [1,'CASH','Cash','asset','cash'],
        [2,'UPI','UPI','asset','upi'],
        [3,'SALES','Sales','income','sales'],
        [4,'COGS','Cost of Goods Sold','expense','cogs'],
        [5,'INVENTORY','Inventory','asset','inventory'],
        [6,'INTER_BRANCH_CLEARING','Inter-branch Clearing','asset','inter_branch_clearing'],
        [7,'STOCK_VARIANCE','Stock Variance','expense','stock_variance'],
        [8,'OFFICE_EXPENSE','Office Expense','expense','office_expense'],
        [9,'PAYROLL_EXPENSE','Payroll Expense','expense','payroll'],
        [10,'PAYROLL_PAYABLE','Payroll Payable','liability','payroll_payable'],
        [11,'AR','Accounts Receivable','asset','receivable'],
        [12,'AP','Accounts Payable','liability','payable'],
    ];
    foreach($accounts as[$id,$code,$name,$type,$subtype]){
        e2_insert($db,'accounts',['id'=>$id,'company_id'=>1,'code'=>$code,'name'=>$name,'type'=>$type,'subtype'=>$subtype,'active'=>1]);
    }
    e2_insert($db,'expense_heads',['id'=>1,'company_id'=>1,'code'=>'TRAVEL','name'=>'Travel Expense','expense_account_id'=>8,'active'=>1]);


}

$wpdb=eh7_setup_global_db();
e2_rebuild($wpdb);
e2_seed($wpdb);

$maker=e2_actor(30,[
    Capabilities::SALES_CREATE,Capabilities::PURCHASE_CREATE,Capabilities::ADJ_CREATE,Capabilities::ADJ_APPROVE,
    Capabilities::EXPENSE_CREATE,Capabilities::REVERSAL_CREATE,Capabilities::REVERSAL_APPROVE,Capabilities::BRANCH_CLOSE,
]);
$approver=e2_actor(20,[
    Capabilities::RECEIPT_CREATE,Capabilities::SUPPLIER_PAYMENT,Capabilities::ADJ_APPROVE,
    Capabilities::EXPENSE_APPROVE,Capabilities::REVERSAL_APPROVE,
    Capabilities::BRANCH_CLOSE,Capabilities::BRANCH_REOPEN,
    Capabilities::REPORTS_VIEW,Capabilities::ACCOUNTING_VIEW,
]);

$state=[];
$failed=0;
function e2_case(string $name, callable $fn):void{
    global $failed;
    try{$fn();echo "PASS {$name}\n";}
    catch(Throwable $e){$failed++;echo "FAIL {$name}: ".get_class($e).' '.$e->getMessage()."\n";}
}

e2_case('e2_purchase_bill_and_supplier_payment',function()use($maker,$approver,$wpdb,&$state){
    $supplier=e2_dispatch('purchase.supplier_create',$maker,['name'=>'Coverage Supplier','mobile'=>'9000000002','gstin'=>'22AAAAA0000A1Z5']);
    $bill=e2_dispatch('purchase.bill',$maker,[
        'branch_id'=>1,'supplier_id'=>(int)$supplier['id'],'bill_no'=>'E2E-BILL-001','bill_date'=>e2_date(),
        'lines'=>[['product_id'=>100,'quantity'=>10,'unit_cost'=>40]],
    ]);
    if(abs((float)$bill['total_amount']-400)>0.005||abs((float)$bill['outstanding_amount']-400)>0.005)throw new RuntimeException('purchase bill amounts mismatch');
    $payment=e2_dispatch('purchase.payment',$approver,[
        'purchase_bill_id'=>(int)$bill['id'],'amount'=>150,'payment_account_id'=>1,
    ]);
    if(($payment['status']??'')!=='posted')throw new RuntimeException('supplier payment did not post');
    $out=(float)$wpdb->get_var('SELECT outstanding_amount FROM '.Db::table('purchase_bills').' WHERE id='.(int)$bill['id']);
    $qty=(float)$wpdb->get_var('SELECT quantity FROM '.Db::table('stock_balances').' WHERE branch_id=1 AND product_id=100 AND batch_key=0 AND custodian_key=0');
    if(abs($out-250)>0.005||abs($qty-10)>0.001)throw new RuntimeException("purchase controls mismatch outstanding={$out} stock={$qty}");
    $state['bill_id']=(int)$bill['id'];$state['supplier_id']=(int)$supplier['id'];
});


e2_case('e2_sales_credit_and_customer_receipt',function()use($maker,$approver,$wpdb,&$state){
    $customer=e2_dispatch('sales.customer_create',$maker,[
        'branch_id'=>1,'name'=>'Coverage Customer','mobile'=>'9000000001','email'=>'customer@example.test','address'=>'Disposable fixture',
    ]);
    $sale=e2_dispatch('sales.counter',$maker,[
        'branch_id'=>1,'customer_id'=>(int)$customer['id'],'paid_amount'=>100,'payment_account_id'=>1,
        'lines'=>[['product_id'=>100,'quantity'=>4]],
    ]);
    if(abs((float)$sale['gross_amount']-400)>0.005||abs((float)$sale['outstanding_amount']-300)>0.005)throw new RuntimeException('credit sale amounts mismatch');
    $receipt=e2_dispatch('sales.receipt',$approver,[
        'branch_id'=>1,'sale_id'=>(int)$sale['id'],'amount'=>150,'payment_account_id'=>1,'reference'=>'E2E-CUST-REC',
    ]);
    if(abs((float)$receipt['remaining_outstanding']-150)>0.005)throw new RuntimeException('receipt outstanding mismatch');
    $open=e2_dispatch('sales.open_sales',$approver,['branch_id'=>1,'customer_id'=>(int)$customer['id']]);
    if(count($open)!==1||abs((float)$open[0]['outstanding_amount']-150)>0.005)throw new RuntimeException('open sales control mismatch');
    $qty=(float)$wpdb->get_var('SELECT quantity FROM '.Db::table('stock_balances').' WHERE branch_id=1 AND product_id=100 AND batch_key=0 AND custodian_key=0');
    if(abs($qty-6)>0.001)throw new RuntimeException('sale stock movement mismatch');
    $state['sale_id']=(int)$sale['id'];$state['receipt_id']=(int)$receipt['id'];$state['customer_id']=(int)$customer['id'];
});

e2_case('e2_inventory_adjustment_maker_checker',function()use($maker,$approver,$wpdb,&$state){
    $adj=e2_dispatch('inventory.adjustment',$maker,[
        'branch_id'=>1,'reason'=>'Coverage positive stock correction',
        'lines'=>[['product_id'=>100,'quantity_delta'=>2,'unit_cost'=>40]],
    ]);
    try{e2_dispatch('inventory.adjustment_decision',$maker,['id'=>(int)$adj['id'],'approve'=>true]);}
    catch(DomainException $e){
        if($e->codeKey!=='maker_checker_required')throw $e;
        $approved=e2_dispatch('inventory.adjustment_decision',$approver,['id'=>(int)$adj['id'],'approve'=>true]);
        if(($approved['status']??'')!=='approved'||(int)($approved['journal_entry_id']??0)<1)throw new RuntimeException('adjustment approval/journal mismatch');
        $qty=(float)$wpdb->get_var('SELECT quantity FROM '.Db::table('stock_balances').' WHERE branch_id=1 AND product_id=100 AND batch_key=0 AND custodian_key=0');
        if(abs($qty-8)>0.001)throw new RuntimeException('adjustment stock movement mismatch');
        $state['adjustment_id']=(int)$adj['id'];
        return;
    }
    throw new RuntimeException('adjustment maker approved own request');
});

e2_case('e2_finance_expense_reversal_workflow',function()use($maker,$approver,$wpdb,&$state){
    $expense=e2_dispatch('finance.expense',$maker,[
        'branch_id'=>1,'expense_head_id'=>1,'amount'=>75,'payment_account_id'=>1,
        'expense_date'=>e2_date(),'description'=>'Coverage reversible expense',
    ]);
    $decision=e2_dispatch('finance.expense_decision',$approver,['id'=>(int)$expense['id'],'approve'=>true]);
    if(($decision['status']??'')!=='approved'||(int)($decision['journal_entry_id']??0)<1)throw new RuntimeException('expense approval failed');
    $request=e2_dispatch('finance.reversal_request',$maker,[
        'source_type'=>'expense','source_id'=>(int)$expense['id'],'reason'=>'Coverage reversal verification',
    ]);
    try{e2_dispatch('finance.reversal_decision',$maker,['id'=>(int)$request['id'],'approve'=>true]);}
    catch(DomainException $e){
        if($e->codeKey!=='maker_checker_required')throw $e;
        $approved=e2_dispatch('finance.reversal_decision',$approver,['id'=>(int)$request['id'],'approve'=>true]);
        if(($approved['status']??'')!=='approved')throw new RuntimeException('reversal approval failed');
        $executed=e2_dispatch('finance.reversal_execute',$approver,['id'=>(int)$request['id']]);
        if(($executed['status']??'')!=='executed'||(int)($executed['reversal_journal_id']??0)<1)throw new RuntimeException('reversal execution failed');
        $expenseStatus=(string)$wpdb->get_var('SELECT status FROM '.Db::table('expenses').' WHERE id='.(int)$expense['id']);
        $reversalStatus=(string)$wpdb->get_var('SELECT status FROM '.Db::table('reversals').' WHERE id='.(int)$request['id']);
        if($expenseStatus!=='reversed'||$reversalStatus!=='executed')throw new RuntimeException('reversal source state mismatch');
        $state['reversal_id']=(int)$request['id'];
        return;
    }
    throw new RuntimeException('reversal maker approved own request');
});

e2_case('e2_reports_and_subledger_reconciliation',function()use($approver,$wpdb){
    $date=e2_date();
    $sales=e2_dispatch('reports.sales',$approver,['branch_id'=>1,'from'=>$date,'to'=>$date]);
    $purchase=e2_dispatch('reports.purchase',$approver,['branch_id'=>1,'from'=>$date,'to'=>$date]);
    $stock=e2_dispatch('reports.stock',$approver,['branch_id'=>1]);
    $finance=e2_dispatch('reports.finance',$approver,['branch_id'=>1,'from'=>$date,'to'=>$date]);
    if(count($sales)!==1||abs((float)$sales[0]['outstanding_amount']-150)>0.005)throw new RuntimeException('sales report mismatch');
    if(count($purchase)!==1||abs((float)$purchase[0]['outstanding_amount']-250)>0.005)throw new RuntimeException('purchase report mismatch');
    $stockQty=0.0;foreach($stock as$r)if((int)$r['product_id']===100&&(int)$r['custodian_key']===0)$stockQty+=(float)$r['quantity'];
    if(abs($stockQty-8)>0.001)throw new RuntimeException('stock report mismatch');
    foreach($finance as$r)if(abs((float)$r['debit']-(float)$r['credit'])>0.005)throw new RuntimeException('finance report contains unbalanced journal');

    $receivables=e2_dispatch('reports.receivables',$approver,['branch_id'=>1]);
    $payables=e2_dispatch('reports.payables',$approver,['branch_id'=>1]);
    if(count($receivables)!==1||abs((float)$receivables[0]['outstanding_amount']-150)>0.005)throw new RuntimeException('receivables report mismatch');
    if(count($payables)!==1||abs((float)$payables[0]['outstanding_amount']-250)>0.005)throw new RuntimeException('payables report mismatch');

    $tb=e2_dispatch('reports.trial_balance',$approver,['to'=>$date,'branch_id'=>1]);
    $tbNet=0.0;foreach($tb as$r)$tbNet+=(float)$r['balance'];
    if(abs($tbNet)>0.01)throw new RuntimeException('trial balance does not net to zero: '.$tbNet);

    $pl=e2_dispatch('reports.profit_loss',$approver,['from'=>$date,'to'=>$date,'branch_id'=>1]);
    $plBy=[];foreach($pl as$r)$plBy[(string)$r['code']]=(float)$r['amount'];
    if(abs(($plBy['SALES']??0)-400)>0.01||abs(($plBy['COGS']??0)-160)>0.01||abs(($plBy['STOCK_VARIANCE']??0)+80)>0.01||abs($plBy['OFFICE_EXPENSE']??0)>0.01){
        throw new RuntimeException('profit/loss account values mismatch: '.json_encode($plBy));
    }

    $bs=e2_dispatch('reports.balance_sheet',$approver,['to'=>$date,'branch_id'=>1]);
    $assets=0.0;$claims=0.0;foreach($bs as$r){if(($r['type']??'')==='asset')$assets+=(float)$r['amount'];elseif(in_array(($r['type']??''),['liability','equity'],true))$claims+=(float)$r['amount'];}
    if(abs($assets-$claims)>0.02)throw new RuntimeException("balance sheet equation mismatch assets={$assets} claims={$claims} rows=".json_encode($bs));

    $recon=e2_dispatch('reports.finance_reconciliation',$approver,['branch_id'=>1]);
    if(count($recon)!==4)throw new RuntimeException('finance reconciliation check count mismatch');
    foreach($recon as$r)if(($r['status']??'')!=='matched')throw new RuntimeException('reconciliation mismatch: '.json_encode($r));

    $unbalanced=(int)$wpdb->get_var(
        'SELECT COUNT(*) FROM (SELECT je.id FROM '.Db::table('journal_entries').' je JOIN '.Db::table('journal_lines').
        ' jl ON jl.journal_entry_id=je.id GROUP BY je.id HAVING ABS(SUM(jl.debit)-SUM(jl.credit))>.005) x'
    );
    if($unbalanced!==0)throw new RuntimeException('raw journal balance invariant failed');
});

e2_case('e2_branch_closing_blocks_posting_and_reopens',function()use($maker,$approver,$wpdb){
    $date=e2_date();
    $pre=e2_dispatch('finance.closing_preflight',$maker,['branch_id'=>1,'business_date'=>$date]);
    if(($pre['ok']??false)!==true)throw new RuntimeException('closing preflight blocked: '.json_encode($pre['blocking']??[]));
    $draft=e2_dispatch('finance.closing_draft',$maker,['branch_id'=>1,'business_date'=>$date]);
    if(($draft['status']??'')!=='draft')throw new RuntimeException('closing draft failed');
    $closed=e2_dispatch('finance.closing_close',$approver,['id'=>(int)$draft['id']]);
    if(($closed['status']??'')!=='closed')throw new RuntimeException('branch close failed');
    $salesBefore=(int)$wpdb->get_var('SELECT COUNT(*) FROM '.Db::table('counter_sales'));
    try{
        e2_dispatch('sales.counter',$maker,[
            'branch_id'=>1,'customer_id'=>null,'paid_amount'=>100,'payment_account_id'=>1,
            'lines'=>[['product_id'=>100,'quantity'=>1]],
        ]);
    }catch(DomainException $e){
        if($e->codeKey!=='branch_day_closed')throw $e;
        $salesAfter=(int)$wpdb->get_var('SELECT COUNT(*) FROM '.Db::table('counter_sales'));
        if($salesAfter!==$salesBefore)throw new RuntimeException('closed-day mutation partially persisted');
        $reopened=e2_dispatch('finance.closing_reopen',$approver,['id'=>(int)$draft['id'],'reason'=>'Coverage controlled reopen']);
        if(($reopened['status']??'')!=='reopened')throw new RuntimeException('branch reopen failed');
        return;
    }
    throw new RuntimeException('posting succeeded on closed branch day');
});

echo ($failed?'FAILED':'PASSED')." business E2E coverage II suite\n";
exit($failed?1:0);
