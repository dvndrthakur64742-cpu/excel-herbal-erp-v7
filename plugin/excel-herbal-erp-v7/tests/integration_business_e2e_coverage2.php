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


e2_case('e2_purchase_batch_preparation_rollback',function()use($maker,$wpdb,&$state){
    $pid=9100;
    $supplier=(int)$state['supplier_id'];
    $date=e2_date();
    $batches=Db::table('batches');
    e2_insert($wpdb,'products',['id'=>$pid,'company_id'=>1,'sku'=>'PUR-ROLLBACK-9100','name'=>'Synthetic batch rollback','uom'=>'PCS','batch_tracking'=>'required','expiry_tracking'=>1,'status'=>'active','created_at'=>Db::now()]);
    $before=[];
    foreach(['purchase_bills','purchase_bill_lines','stock_balances','stock_ledger','journal_entries','journal_lines','audit_log'] as $table){
        $before[$table]=(int)$wpdb->get_var('SELECT COUNT(*) FROM '.Db::table($table));
    }
    $base=['product_id'=>$pid,'quantity'=>2,'unit_cost'=>50,'batch_no'=>'PUR-ROLLBACK-NEW','manufactured_on'=>'2026-01-01','expires_on'=>'2098-12-31'];
    $attempt=fn($bill,$lines)=>\ExcelHerbal\ERP7\Purchase\PurchaseService::bill($maker,1,$supplier,$bill,$date,$lines);
    $reject=function($bill,$lines,$code)use($attempt){
        try{$attempt($bill,$lines);}catch(DomainException $e){if($e->codeKey===$code)return;throw $e;}
        throw new RuntimeException('Unexpected purchase success: '.$bill);
    };
    $reject('PUR-MISSING-EXPIRY',[array_diff_key($base,['expires_on'=>true])],'batch_expiry_required');
    $reject('PUR-MISSING-BATCH',[array_diff_key($base,['batch_no'=>true])],'batch_required');
    $reject('PUR-BAD-LINE',[$base,array_replace($base,['quantity'=>0])],'domain_error');
    $reject('PUR-DUP-LINE',[$base,$base],'duplicate_purchase_line');
    $reject('E2E-BILL-001',[$base],'purchase_duplicate');
    if((int)$wpdb->get_var("SELECT COUNT(*) FROM {$batches} WHERE product_id={$pid}")!==0)throw new RuntimeException('Failed purchase left a new batch');
    e2_insert($wpdb,'batches',['company_id'=>1,'product_id'=>$pid,'batch_no'=>'PUR-ROLLBACK-EXISTING','manufactured_on'=>null,'expires_on'=>null,'status'=>'active','created_at'=>Db::now()]);
    $existing=array_replace($base,['batch_no'=>'PUR-ROLLBACK-EXISTING']);
    $reject('PUR-METADATA',[$existing,array_replace($existing,['quantity'=>0])],'domain_error');
    $row=$wpdb->get_row("SELECT manufactured_on,expires_on FROM {$batches} WHERE product_id={$pid}",ARRAY_A);
    if(!$row||$row['manufactured_on']!==null||$row['expires_on']!==null)throw new RuntimeException('Failed purchase changed existing batch dates');
    foreach($before as $table=>$count){
        if((int)$wpdb->get_var('SELECT COUNT(*) FROM '.Db::table($table))!==$count)throw new RuntimeException('Failed purchase changed '.$table);
    }
    $wpdb->query("DELETE FROM {$batches} WHERE product_id={$pid}");
    $wpdb->query('DELETE FROM '.Db::table('products')." WHERE id={$pid}");
});

e2_case('e2_saleable_stock_expiry_fefo',function()use($maker,$wpdb){
    $day=new DateTimeImmutable(Db::today());
    $past=$day->modify('-1 day')->format('Y-m-d');
    $today=$day->format('Y-m-d');
    $future=$day->modify('+30 days')->format('Y-m-d');
    $pid=9200;$inactive=9201;
    try{
        \ExcelHerbal\ERP7\Database\Transaction::run(function()use($maker,$wpdb,$pid,$inactive,$past,$today,$future){
            foreach([[$pid,'active'],[$inactive,'inactive']] as [$id,$status]){
                e2_insert($wpdb,'products',['id'=>$id,'company_id'=>1,'sku'=>'EXPIRY-'.$id,'name'=>'Synthetic expiry '.$id,'uom'=>'PCS','batch_tracking'=>'optional','expiry_tracking'=>1,'status'=>$status,'created_at'=>Db::now()]);
            }
            $stock=function($product,$batch,$quantity)use($wpdb){
                e2_insert($wpdb,'stock_balances',['company_id'=>1,'branch_id'=>1,'product_id'=>$product,'batch_key'=>$batch,'custodian_key'=>0,'quantity'=>$quantity,'average_unit_cost'=>10,'updated_at'=>Db::now()]);
            };
            $ids=[];
            foreach([['today',$today,'active'],['future',$future,'active'],['expired',$past,'active'],['missing',null,'active'],['inactive',$future,'inactive']] as [$name,$expiry,$status]){
                e2_insert($wpdb,'batches',['company_id'=>1,'product_id'=>$pid,'batch_no'=>'EXP-'.$name,'expires_on'=>$expiry,'status'=>$status,'created_at'=>Db::now()]);
                $ids[$name]=(int)$wpdb->insert_id;
                $stock($pid,$ids[$name],2);
            }
            $stock($pid,0,2);
            $stock($inactive,0,2);
            // A valid batch from another product cannot satisfy this product.
            e2_insert($wpdb,'batches',['company_id'=>1,'product_id'=>$inactive,'batch_no'=>'EXP-WRONG-PRODUCT','expires_on'=>$future,'status'=>'active','created_at'=>Db::now()]);
            $stock($pid,(int)$wpdb->insert_id,2);
            $visible=array_values(array_filter(\ExcelHerbal\ERP7\Sales\SalesService::availableStock($maker,1),fn($r)=>in_array((int)$r['product_id'],[$pid,$inactive],true)));
            if(array_map(fn($r)=>(int)$r['batch_key'],$visible)!==[$ids['today'],$ids['future']])throw new RuntimeException('Saleable stock includes unavailable or wrongly ordered batches');
            $alloc=\ExcelHerbal\ERP7\Inventory\StockService::automaticCustodyAllocations($maker,1,$pid,3);
            if(count($alloc)!==2||$alloc[0]['batch_id']!==$ids['today']||$alloc[1]['batch_id']!==$ids['future']||abs($alloc[0]['quantity']-2)>0.001||abs($alloc[1]['quantity']-1)>0.001)throw new RuntimeException('Expiry allocation did not follow FEFO');
            try{
                \ExcelHerbal\ERP7\Inventory\StockService::automaticCustodyAllocations($maker,1,$pid,5);
                throw new RuntimeException('Non-saleable stock was allocated');
            }catch(DomainException $e){if($e->codeKey!=='insufficient_stock')throw $e;}
            throw new RuntimeException('expiry-fixture-rollback');
        });
    }catch(RuntimeException $e){if($e->getMessage()!=='expiry-fixture-rollback')throw $e;}
});

e2_case('e2_quarantine_resolution_atomic',function()use($approver,$wpdb){
    try{
        \ExcelHerbal\ERP7\Database\Transaction::run(function()use($approver,$wpdb){
            $pid=9300;$today=new DateTimeImmutable(Db::today());$q=Db::table('stock_quarantine');
            e2_insert($wpdb,'products',['id'=>$pid,'company_id'=>1,'sku'=>'QUARANTINE-9300','name'=>'Synthetic quarantine','uom'=>'PCS','batch_tracking'=>'required','expiry_tracking'=>1,'status'=>'active','created_at'=>Db::now()]);
            $ids=[];
            foreach(['valid'=>$today->modify('+10 days'),'expired'=>$today->modify('-1 day')] as $name=>$date){
                e2_insert($wpdb,'batches',['company_id'=>1,'product_id'=>$pid,'batch_no'=>'QUAR-'.$name,'expires_on'=>$date->format('Y-m-d'),'status'=>'active','created_at'=>Db::now()]);
                $batch=(int)$wpdb->insert_id;
                e2_insert($wpdb,'stock_quarantine',['company_id'=>1,'branch_id'=>1,'product_id'=>$pid,'batch_id'=>$batch,'quantity'=>2,'reason'=>'Synthetic hold','status'=>'open','created_by'=>30,'created_at'=>Db::now()]);
                $ids[$name]=(int)$wpdb->insert_id;
            }
            $resolve=fn($id,$action)=>\ExcelHerbal\ERP7\Inventory\InventoryService::resolveQuarantine($approver,$id,$action,'Synthetic resolution');
            $reject=function($id,$code)use($resolve){
                try{$resolve($id,'release');}catch(DomainException $e){if($e->codeKey===$code)return;throw $e;}
                throw new RuntimeException('Unexpected quarantine release');
            };
            $reject($ids['expired'],'batch_expired');
            if(($resolve($ids['valid'],'release')['status']??'')!=='released')throw new RuntimeException('Valid release failed');
            $reject($ids['valid'],'quarantine_already_resolved');
            if((int)$wpdb->get_var("SELECT COUNT(*) FROM {$q} WHERE product_id={$pid} AND status='released'")!==1)throw new RuntimeException('Quarantine status mismatch');
            if((int)$wpdb->get_var("SELECT COUNT(*) FROM ".Db::table('stock_ledger')." WHERE product_id={$pid} AND source_type='quarantine_release'")!==1)throw new RuntimeException('Duplicate quarantine ledger');
            if(abs((float)$wpdb->get_var("SELECT SUM(quantity) FROM ".Db::table('stock_balances')." WHERE product_id={$pid}")-2)>0.001)throw new RuntimeException('Released stock quantity mismatch');
            if(($resolve($ids['expired'],'write_off')['status']??'')!=='written_off')throw new RuntimeException('Existing write-off status transition failed');
            if((int)$wpdb->get_var("SELECT COUNT(*) FROM ".Db::table('audit_log')." WHERE entity_type='stock_quarantine' AND entity_id IN (".$ids['valid'].','.$ids['expired'].")")!==2)throw new RuntimeException('Missing resolution audit');
            throw new RuntimeException('quarantine-fixture-rollback');
        });
    }catch(RuntimeException $e){if($e->getMessage()!=='quarantine-fixture-rollback')throw $e;}
});

e2_case('e2_commercial_decimal_storage',function()use($wpdb){
    $actor=e2_actor(20,[Capabilities::PRODUCT_MANAGE]);
    $table=Db::table('product_commercial_revisions');
    $before=(int)$wpdb->get_var("SELECT COUNT(*) FROM {$table}");
    $base=['mrp'=>'200.00','sale_price'=>'170.00','ho_amount'=>'100.00','bm_profit'=>'20.00','salary_fund'=>'30.00','office_expense'=>'20.00','points'=>'10.00','purchase_cost'=>'55.1234'];
    foreach([['sale_price','invalid'],['purchase_cost','55.12345'],['points',true],['mrp','1000000000000.00']] as [$field,$bad]){
        try{
            \ExcelHerbal\ERP7\Organization\OrganizationProductService::commercialRevision($actor,100,array_replace($base,[$field=>$bad]));
            throw new RuntimeException('Invalid commercial input accepted');
        }catch(DomainException $e){if($e->codeKey!=='commercial_value_invalid')throw $e;}
    }
    if((int)$wpdb->get_var("SELECT COUNT(*) FROM {$table}")!==$before)throw new RuntimeException('Invalid revision persisted');
    try{
        \ExcelHerbal\ERP7\Database\Transaction::run(function()use($actor,$wpdb,$base,$table){
            $result=\ExcelHerbal\ERP7\Organization\OrganizationProductService::commercialRevision($actor,100,$base);
            $row=$wpdb->get_row("SELECT sale_price,purchase_cost FROM {$table} WHERE id=".(int)$result['id'],ARRAY_A);
            if(!$row||$row['sale_price']!=='170.00'||$row['purchase_cost']!=='55.1234')throw new RuntimeException('Commercial decimal storage mismatch');
            throw new RuntimeException('commercial-fixture-rollback');
        });
    }catch(RuntimeException $e){if($e->getMessage()!=='commercial-fixture-rollback')throw $e;}
});

e2_case('e2_full_prepayment_and_no_customer_credit',function()use($maker,$approver,$wpdb,&$state){
    $customer=e2_dispatch('sales.customer_create',$maker,[
        'branch_id'=>1,'name'=>'Coverage Customer','mobile'=>'9000000001','email'=>'customer@example.test','address'=>'Disposable fixture',
    ]);
    // A partial-payment counter sale must not create an invoice or move stock.
    try {
        e2_dispatch('sales.counter',$maker,[
            'branch_id'=>1,'customer_id'=>(int)$customer['id'],
            'paid_amount'=>100,'payment_account_id'=>1,
            'lines'=>[['product_id'=>100,'quantity'=>4]],
        ]);
        throw new RuntimeException('credit sale unexpectedly allowed');
    } catch (DomainException $e) {
        if ($e->codeKey !== 'full_prepayment_required') throw $e;
    }
    if ((int)$wpdb->get_var('SELECT COUNT(*) FROM '.Db::table('counter_sales')) !== 0) {
        throw new RuntimeException('denied partial payment created a sale');
    }
    $sale=e2_dispatch('sales.counter',$maker,[
        'branch_id'=>1,'customer_id'=>(int)$customer['id'],
        'paid_amount'=>400,'payment_account_id'=>1,
        'lines'=>[['product_id'=>100,'quantity'=>4]],
    ]);
    if (abs((float)$sale['gross_amount']-400)>0.005
        || abs((float)$sale['outstanding_amount'])>0.005
    ) throw new RuntimeException('fully prepaid counter sale mismatch');
    // A paid invoice has no outstanding customer balance to collect twice.
    try {
        e2_dispatch('sales.receipt',$approver,[
            'branch_id'=>1,'sale_id'=>(int)$sale['id'],'amount'=>1,
            'payment_account_id'=>1,'reference'=>'E2E-DUPLICATE-REC',
        ]);
        throw new RuntimeException('receipt was accepted for a paid sale');
    } catch (DomainException $e) {
        if ($e->codeKey !== 'sale_not_outstanding') throw $e;
    }
    $open=e2_dispatch('sales.open_sales',$approver,[
        'branch_id'=>1,'customer_id'=>(int)$customer['id'],
    ]);
    if (count($open)!==0) throw new RuntimeException('fully paid sale appears as receivable');
    $qty=(float)$wpdb->get_var(
        'SELECT quantity FROM '.Db::table('stock_balances').
        ' WHERE branch_id=1 AND product_id=100 AND batch_key=0 AND custodian_key=0'
    );
    if (abs($qty-6)>0.001) throw new RuntimeException('prepaid sale stock movement mismatch');
    $state['sale_id']=(int)$sale['id'];
    $state['customer_id']=(int)$customer['id'];
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
    if(count($sales)!==1||abs((float)$sales[0]['outstanding_amount'])>0.005)throw new RuntimeException('fully paid sales report mismatch');
    if(count($purchase)!==1||abs((float)$purchase[0]['outstanding_amount']-250)>0.005)throw new RuntimeException('purchase report mismatch');
    $stockQty=0.0;foreach($stock as$r)if((int)$r['product_id']===100&&(int)$r['custodian_key']===0)$stockQty+=(float)$r['quantity'];
    if(abs($stockQty-8)>0.001)throw new RuntimeException('stock report mismatch');
    foreach($stock as $r){
        if(!array_key_exists('uom',$r)||!array_key_exists('expiry_tracking',$r)||!array_key_exists('expires_on',$r))
            throw new RuntimeException('stock insights metadata missing');
        if((int)$r['product_id']===100 && (int)$r['batch_key']===0 && $r['expires_on']!==null)
            throw new RuntimeException('unbatched stock must not inherit expiry');
    }
    foreach($finance as$r)if(abs((float)$r['debit']-(float)$r['credit'])>0.005)throw new RuntimeException('finance report contains unbalanced journal');

    $receivables=e2_dispatch('reports.receivables',$approver,['branch_id'=>1]);
    $payables=e2_dispatch('reports.payables',$approver,['branch_id'=>1]);
    if(count($receivables)!==0)throw new RuntimeException('prepaid sale incorrectly appears in receivables');
    if(count($payables)!==1||abs((float)$payables[0]['outstanding_amount']-250)>0.005)throw new RuntimeException('payables report mismatch');

    $tb=e2_dispatch('reports.trial_balance',$approver,['to'=>$date,'branch_id'=>1]);
    foreach($tb as$r)if(!array_key_exists('subtype',$r)||!array_key_exists('active',$r))throw new RuntimeException('Trial balance metadata missing');
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

    // Inactive master records must not erase posted historical movements.
    // This fixture changes only disposable UAT accounts, restoring immediately.
    $accounts=Db::table('accounts');
    Db::mustUpdate($wpdb,$accounts,['active'=>0],['id'=>3,'company_id'=>1]);
    Db::mustUpdate($wpdb,$accounts,['active'=>0],['id'=>12,'company_id'=>1]);
    try {
        $historicalPL=e2_dispatch('reports.profit_loss',$approver,['from'=>$date,'to'=>$date,'branch_id'=>1]);
        $historicalBS=e2_dispatch('reports.balance_sheet',$approver,['to'=>$date,'branch_id'=>1]);
        $historicalTB=e2_dispatch('reports.trial_balance',$approver,['to'=>$date,'branch_id'=>1]);
        $plByCode=array_column($historicalPL,null,'code');
        $bsByCode=array_column($historicalBS,null,'code');
        $tbByCode=array_column($historicalTB,null,'code');
        if(abs((float)($plByCode['SALES']['amount']??0)-400)>.005 || (int)($plByCode['SALES']['active']??1)!==0)
            throw new RuntimeException('Inactive income ledger omitted from historical profit loss');
        if(abs((float)($bsByCode['AP']['amount']??0)-250)>.005 || (int)($bsByCode['AP']['active']??1)!==0)
            throw new RuntimeException('Inactive payable ledger omitted from historical balance sheet');
        if(!isset($tbByCode['AP'],$tbByCode['SALES']))throw new RuntimeException('Historical trial balance scope mismatch');
        $asset=0.0;$claims=0.0;
        foreach($historicalBS as $row){if($row['type']==='asset')$asset+=(float)$row['amount'];else $claims+=(float)$row['amount'];}
        if(abs($asset-$claims)>.005)throw new RuntimeException('Historical balance sheet is not balanced');
        if(abs((float)($bsByCode['CURRENT_EARNINGS']['amount']??0)-(float)($plByCode['SALES']['amount']??0)+(float)($plByCode['COGS']['amount']??0)+(float)($plByCode['STOCK_VARIANCE']['amount']??0)+(float)($plByCode['OFFICE_EXPENSE']['amount']??0))>.005)
            throw new RuntimeException('Historical earnings changed after account deactivation');
    } finally {
        Db::mustUpdate($wpdb,$accounts,['active'=>1],['id'=>3,'company_id'=>1]);
        Db::mustUpdate($wpdb,$accounts,['active'=>1],['id'=>12,'company_id'=>1]);
    }
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
    $closingId=(int)$draft['id'];
    $closingTable=Db::table('branch_closings');
    $auditTable=Db::table('audit_log');
    $auditSql=$wpdb->prepare("SELECT COUNT(*) FROM {$auditTable} WHERE company_id=%d AND action=%s AND entity_type=%s AND entity_id=%s",1,'branch_closing.close','branch_closing',(string)$closingId);
    $original=$wpdb->get_row($wpdb->prepare("SELECT * FROM {$closingTable} WHERE id=%d",$closingId),ARRAY_A);
    if((int)$wpdb->get_var($auditSql)!==1)throw new RuntimeException('Branch close audit missing');
    try{
        e2_dispatch('finance.closing_close',$approver,['id'=>$closingId]);
        throw new RuntimeException('Repeated branch close accepted');
    }catch(DomainException $e){
        if($e->codeKey!=='branch_closing_invalid_state')throw $e;
    }
    $after=$wpdb->get_row($wpdb->prepare("SELECT * FROM {$closingTable} WHERE id=%d",$closingId),ARRAY_A);
    if($after!==$original||(int)$wpdb->get_var($auditSql)!==1)
        throw new RuntimeException('Repeated close altered persisted history');
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

// Independent connections reproduce the actual InnoDB lock conflict.
// The shared harness rejects non-synthetic databases before connection.
e2_case('e2_pending_expense_rejects_concurrent_closing_locks',function()use($maker,$wpdb){
    $date=e2_date();
    $lock=new Eh7IntegrationWpdb(eh7_connect());
    $companies=Db::table('companies');$closings=Db::table('branch_closings');
    $expenses=Db::table('expenses');$audit=Db::table('audit_log');
    $before=(int)$wpdb->get_var("SELECT COUNT(*) FROM {$expenses}");
    $auditBefore=(int)$wpdb->get_var("SELECT COUNT(*) FROM {$audit}");
    $originalTimeout=(int)$wpdb->get_var('SELECT @@SESSION.innodb_lock_wait_timeout');
    if($wpdb->query('SET SESSION innodb_lock_wait_timeout=1')===false)
        throw new RuntimeException('Unable to configure synthetic timeout');
    try{
        foreach([
            ["SELECT id FROM {$companies} WHERE id=1 FOR UPDATE",'period_lock_failed'],
            [$lock->prepare("SELECT id FROM {$closings} WHERE company_id=1 AND branch_id=1 AND business_date=%s FOR UPDATE",$date),'branch_day_read_failed'],
        ] as [$lockSql,$expected]){
            if($lock->query('START TRANSACTION')===false)throw new RuntimeException('Unable to start locker');
            try{
                if(!$lock->get_var($lockSql))throw new RuntimeException('Synthetic lock row missing');
                try{
                    \ExcelHerbal\ERP7\Finance\FinanceExpenseService::expense($maker,1,1,13,1,$date,'Synthetic lock conflict');
                    throw new RuntimeException('Pending expense bypassed closing lock');
                }catch(DomainException $e){if($e->codeKey!==$expected)throw $e;}
                if((int)$wpdb->get_var("SELECT COUNT(*) FROM {$expenses}")!==$before||
                   (int)$wpdb->get_var("SELECT COUNT(*) FROM {$audit}")!==$auditBefore)
                    throw new RuntimeException('Contended entry persisted a partial mutation');
            }finally{$lock->query('ROLLBACK');}
        }
        $created=\ExcelHerbal\ERP7\Finance\FinanceExpenseService::expense($maker,1,1,13,1,$date,'Synthetic lock released');
        if(($created['status']??'')!=='pending'||
           (int)$wpdb->get_var("SELECT COUNT(*) FROM {$expenses}")!==$before+1||
           (int)$wpdb->get_var("SELECT COUNT(*) FROM {$audit}")!==$auditBefore+1)
            throw new RuntimeException('Entry did not recover after release');
    }finally{$wpdb->query('SET SESSION innodb_lock_wait_timeout='.max(1,$originalTimeout));}
});

// A pending-entry transaction for any date must finish before branch close
// snapshots blockers. Use a separate, guarded disposable database connection.
e2_case('e2_branch_close_serializes_cross_date_pending_entries',function()use($maker,$approver,$wpdb){
    $date=(new DateTimeImmutable(e2_date()))->modify('-1 day')->format('Y-m-d');
    $earlier=(new DateTimeImmutable($date))->modify('-1 day')->format('Y-m-d');
    $draft=e2_dispatch('finance.closing_draft',$maker,['branch_id'=>1,'business_date'=>$date]);
    $preflight=e2_dispatch('finance.closing_preflight',$maker,['branch_id'=>1,'business_date'=>$date]);
    if(($preflight['ok']??false)!==true)throw new RuntimeException('Cross-date baseline must have no blockers');
    $closingTable=Db::table('branch_closings');
    $auditTable=Db::table('audit_log');
    $companies=Db::table('companies');
    $row=$wpdb->get_row($wpdb->prepare("SELECT * FROM {$closingTable} WHERE company_id=1 AND branch_id=1 AND business_date=%s",$date),ARRAY_A);
    if(!$row||$row['status']!=='draft'||(int)$row['id']!==(int)$draft['id'])throw new RuntimeException('Expected independent draft fixture');
    $id=(int)$row['id'];
    $auditBefore=(int)$wpdb->get_var("SELECT COUNT(*) FROM {$auditTable}");
    $lock=new Eh7IntegrationWpdb(eh7_connect());
    $timeout=(int)$wpdb->get_var('SELECT @@SESSION.innodb_lock_wait_timeout');
    if($wpdb->query('SET SESSION innodb_lock_wait_timeout=1')===false)
        throw new RuntimeException('Unable to configure synthetic timeout');
    try{
        if($lock->query('START TRANSACTION')===false)throw new RuntimeException('Unable to start pending-entry session');
        try{
            if(!$lock->get_var("SELECT id FROM {$companies} WHERE id=1 LOCK IN SHARE MODE"))
                throw new RuntimeException('Synthetic company gate missing');
            // Simulate the already-protected entry on another date, not a journal write.
            $expense=Db::table('expenses');
            if($lock->insert($expense,[
                'company_id'=>1,'branch_id'=>1,'expense_head_id'=>1,'amount'=>11,
                'payment_account_id'=>1,'status'=>'pending','expense_date'=>$earlier,
                'description'=>'Synthetic cross-date pending entry','created_by'=>$maker->employeeId,
                'created_at'=>Db::now(),
            ])===false)throw new RuntimeException('Synthetic pending entry insert failed');
            try{
                e2_dispatch('finance.closing_close',$approver,['id'=>$id]);
                throw new RuntimeException('Closing bypassed shared entry gate');
            }catch(DomainException $e){if($e->codeKey!=='period_lock_failed')throw $e;}
            if($wpdb->get_row($wpdb->prepare("SELECT * FROM {$closingTable} WHERE id=%d",$id),ARRAY_A)!==$row||
                (int)$wpdb->get_var("SELECT COUNT(*) FROM {$auditTable}")!==$auditBefore)
                throw new RuntimeException('Contended close changed committed metadata');
            if($lock->query('COMMIT')===false)throw new RuntimeException('Synthetic pending entry commit failed');
        }finally{$lock->query('ROLLBACK');}
        try{
            e2_dispatch('finance.closing_close',$approver,['id'=>$id]);
            throw new RuntimeException('Closing missed committed pending entry');
        }catch(DomainException $e){
            if($e->codeKey!=='closing_blocked'||!str_contains($e->getMessage(),'expenses_pending'))throw $e;
        }
        if($wpdb->get_row($wpdb->prepare("SELECT * FROM {$closingTable} WHERE id=%d",$id),ARRAY_A)!==$row||
            (int)$wpdb->get_var("SELECT COUNT(*) FROM {$auditTable}")!==$auditBefore)
            throw new RuntimeException('Blocked close changed committed metadata');
    }finally{$wpdb->query('SET SESSION innodb_lock_wait_timeout='.max(1,$timeout));}
});

// Product lock contention must not create a commercial revision or slab history.
e2_case('e2_commercial_writers_share_product_lock',function()use($wpdb){
    $actor=e2_actor(20,[Capabilities::PRODUCT_MANAGE,Capabilities::ACCESS_MANAGE]);
    $product=100;$products=Db::table('products');
    $revisions=Db::table('product_commercial_revisions');
    $slabs=Db::table('distributor_price_slabs');$audit=Db::table('audit_log');
    $counts=fn()=>[(int)$wpdb->get_var("SELECT COUNT(*) FROM {$revisions}"),
                   (int)$wpdb->get_var("SELECT COUNT(*) FROM {$slabs}"),
                   (int)$wpdb->get_var("SELECT COUNT(*) FROM {$audit}")];
    $before=$counts();
    $writeRevision=fn()=>\ExcelHerbal\ERP7\Organization\OrganizationProductService::commercialRevision($actor,$product,[
        'mrp'=>'200.00','sale_price'=>'170.00','ho_amount'=>'100.00','bm_profit'=>'20.00',
        'salary_fund'=>'30.00','office_expense'=>'20.00','points'=>'10.00','purchase_cost'=>'55.1234',
    ],'Synthetic lock test');
    $writeSlabs=fn()=>\ExcelHerbal\ERP7\Sales\PrepaidOrderService::setDistributorSlabs($actor,$product,[
        ['min_qty'=>1,'max_qty'=>9,'unit_price'=>'170.00'],
        ['min_qty'=>10,'max_qty'=>null,'unit_price'=>'160.00'],
    ]);
    $lock=new Eh7IntegrationWpdb(eh7_connect());
    $timeout=(int)$wpdb->get_var('SELECT @@SESSION.innodb_lock_wait_timeout');
    if($wpdb->query('SET SESSION innodb_lock_wait_timeout=1')===false)
        throw new RuntimeException('Unable to configure synthetic timeout');
    try{
        if($lock->query('START TRANSACTION')===false)throw new RuntimeException('Unable to start product locker');
        try{
            if(!$lock->get_var("SELECT id FROM {$products} WHERE company_id=1 AND id=100 FOR UPDATE"))
                throw new RuntimeException('Synthetic product missing');
            foreach([$writeRevision,$writeSlabs] as $write){
                try{$write();throw new RuntimeException('Commercial writer bypassed product lock');}
                catch(DomainException $e){if($e->codeKey!=='commercial_product_read_failed')throw $e;}
                if($counts()!==$before)throw new RuntimeException('Contended commercial writer persisted data');
            }
        }finally{$lock->query('ROLLBACK');}
        try{
            \ExcelHerbal\ERP7\Database\Transaction::run(function()use($writeRevision,$writeSlabs,$counts,$before){
                $revision=$writeRevision();$priceList=$writeSlabs();
                if((int)($revision['id']??0)<1||count($priceList['slabs']??[])!==2||
                    $counts()!==[$before[0]+1,$before[1]+2,$before[2]+2])
                    throw new RuntimeException('Commercial history or audit missing after lock release');
                throw new RuntimeException('commercial-lock-fixture-rollback');
            });
        }catch(RuntimeException $e){if($e->getMessage()!=='commercial-lock-fixture-rollback')throw $e;}
        if($counts()!==$before)throw new RuntimeException('Synthetic commercial fixture not rolled back');
    }finally{$wpdb->query('SET SESSION innodb_lock_wait_timeout='.max(1,$timeout));}
});

echo ($failed?'FAILED':'PASSED')." business E2E coverage II suite\n";
exit($failed?1:0);
