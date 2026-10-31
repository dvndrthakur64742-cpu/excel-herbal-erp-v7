<?php
/**
 * Real MariaDB transaction tests using synthetic data only.
 * NEVER run on an actual production database.
 */
define('EH7_INTEGRATION_LIBRARY_ONLY',true);
require __DIR__.'/integration_mariadb.php';
require_once __DIR__.'/../src/Core/Autoloader.php';
\ExcelHerbal\ERP7\Core\Autoloader::register(__DIR__.'/../src');

use ExcelHerbal\ERP7\Database\Db;
use ExcelHerbal\ERP7\Database\Schema;
use ExcelHerbal\ERP7\Domain\DomainException;
use ExcelHerbal\ERP7\Sales\PrepaidOrderService;
use ExcelHerbal\ERP7\Security\Actor;
use ExcelHerbal\ERP7\Security\Capabilities as C;

$database=(string)(getenv('EH7_MARIADB_DATABASE')?:'');
if(getenv('EH7_INTEGRATION_MODE')!=='synthetic' || !str_starts_with($database,'eh7_test_')){
    fwrite(STDERR,"REFUSED: synthetic-only test requires EH7_INTEGRATION_MODE=synthetic and eh7_test_* database\n");
    exit(2);
}
$db=eh7_setup_global_db();
$tables=[
    'audit_log','journal_lines','journal_entries','counter_sale_lines','counter_sales','stock_ledger','stock_balances',
    'prepaid_sales_order_payments','prepaid_sales_order_lines','prepaid_sales_orders','distributor_price_slabs',
    'product_commercial_revisions','products','parties','accounts','number_series','settings','accounting_periods',
    'branch_closings','employees','branches','companies',
];
$definitions=Schema::definitions();
foreach($tables as $name){
    $table=Db::table($name);
    if($db->query("DROP TABLE IF EXISTS {$table}")===false)throw new RuntimeException($db->last_error);
}
foreach(array_reverse($tables) as $name){
    if(!isset($definitions[$name]))throw new RuntimeException('Missing schema definition '.$name);
    $table=Db::table($name);
    if($db->query("CREATE TABLE {$table} (".$definitions[$name].") ENGINE=InnoDB DEFAULT CHARSET=utf8mb4")===false)
        throw new RuntimeException('Create '.$name.' failed: '.$db->last_error);
}
function seed(string $table,array $data):int {
    $db=Db::wpdb();
    Db::mustInsert($db,Db::table($table),$data);
    return $db->insert_id;
}
function checkSales(bool $yes,string $label):void{
    if(!$yes)throw new RuntimeException('FAILED: '.$label);
    echo "PASS $label\n";
}
function denySales(callable $fn,string $error):void{
    try{$fn();}catch(DomainException $e){checkSales($e->codeKey===$error,'denied '.$error);return;}
    throw new RuntimeException('Expected error: '.$error);
}
$now=Db::now();
seed('companies',['id'=>1,'name'=>'Synthetic ERP UAT','status'=>'active','created_at'=>$now]);
seed('branches',['id'=>1,'company_id'=>1,'code'=>'HO','name'=>'Synthetic HO','is_head_office'=>1,'status'=>'active','created_at'=>$now]);
foreach([101,102,103,104] as $eid)seed('employees',[
    'id'=>$eid,'company_id'=>1,'employee_code'=>'TEST'.$eid,'designation_code'=>$eid===104?'SYSADMIN':($eid===102?'BM':'SALES'),
    'assigned_branch_id'=>1,'full_name'=>'Synthetic '.$eid,'status'=>'active','created_at'=>$now
]);
seed('parties',['id'=>5,'company_id'=>1,'branch_id'=>1,'type'=>'customer','name'=>'Synthetic Customer','status'=>'active','created_at'=>$now]);
seed('products',['id'=>1,'company_id'=>1,'sku'=>'SYN001','name'=>'Synthetic Product','uom'=>'PCS','batch_tracking'=>'off','status'=>'active','created_at'=>$now]);
seed('product_commercial_revisions',[
    'company_id'=>1,'product_id'=>1,'effective_from'=>'2020-01-01 00:00:00','mrp'=>'110.00','sale_price'=>'100.00',
    'ho_amount'=>'50.00','bm_profit'=>'10.00','salary_fund'=>'5.00','office_expense'=>'5.00',
    'points'=>'1.00','purchase_cost'=>'40.0000','status'=>'active','created_at'=>$now
]);
seed('stock_balances',['company_id'=>1,'branch_id'=>1,'product_id'=>1,'batch_key'=>0,'custodian_key'=>0,'quantity'=>'10.000','average_unit_cost'=>'40.0000','updated_at'=>$now]);
foreach([
    [10,'CASH','Cash Account','asset','cash'],
    [11,'UPI','UPI Bank','asset','upi'],
    [12,'SALES','Sales Revenue','income',null],
    [13,'COGS','COGS','expense',null],
    [14,'INVENTORY','Stock Inventory','asset',null]
] as [$id,$code,$name,$type,$subtype]){
    seed('accounts',['id'=>$id,'company_id'=>1,'code'=>$code,'name'=>$name,'type'=>$type,'subtype'=>$subtype,'active'=>1]);
}
$seller=new Actor(101,101,1,1,[1],[C::SALES_CREATE,C::SALES_VIEW],'SALES');
$cashier=new Actor(102,102,1,1,[1],[C::RECEIPT_CREATE,C::SALES_DISCOUNT_APPROVE],'BM');
$finance=new Actor(103,103,1,1,[1],[C::BANK_RECONCILE],'FINANCE');
$admin=new Actor(104,104,1,1,[1],[C::SALES_DISCOUNT_HO_APPROVE,C::PRODUCT_MANAGE,C::ACCESS_MANAGE],'SYSADMIN');

$o=PrepaidOrderService::create($seller,1,'b2c',null,[['product_id'=>1,'quantity'=>'2']]);
checkSales($o['status']==='approved'&&$o['net_amount']==='200.00','B2C order created with price snapshot');
checkSales((int)$db->get_var('SELECT COUNT(*) FROM '.Db::table('counter_sales'))===0,'order creation does not post invoice');
PrepaidOrderService::collect($cashier,$o['id'],10,'100.00','cash');
denySales(fn()=>PrepaidOrderService::post($seller,$o['id']),'full_prepayment_required');
checkSales((int)$db->get_var('SELECT COUNT(*) FROM '.Db::table('stock_ledger'))===0,'partial payment never deducts stock');
$upi=PrepaidOrderService::collect($cashier,$o['id'],11,'100.00','upi','UTR-TEST-0001');
checkSales($upi['status']==='pending','UPI starts pending');
denySales(fn()=>PrepaidOrderService::post($seller,$o['id']),'upi_verification_required');
denySales(fn()=>PrepaidOrderService::verifyUpi($cashier,$upi['id'],'BANK-UTR-0001'),'permission_denied');
PrepaidOrderService::verifyUpi($finance,$upi['id'],'BANK-UTR-0001');
$post=PrepaidOrderService::post($seller,$o['id']);
checkSales($post['status']==='posted'&&$post['paid_amount']==='200.00','invoice after confirmed full payment');
checkSales((int)$db->get_var('SELECT COUNT(*) FROM '.Db::table('counter_sales'))===1,'one invoice created');
checkSales(abs((float)$db->get_var('SELECT quantity FROM '.Db::table('stock_balances').' WHERE product_id=1')-8.)<0.0001,'stock deducted exactly once');
checkSales((int)$db->get_var('SELECT COUNT(*) FROM '.Db::table('journal_entries'))===1,'balanced journal posted');
checkSales(abs((float)$db->get_var('SELECT SUM(debit-credit) FROM '.Db::table('journal_lines')))<0.001,'journal credits equal debits');
$again=PrepaidOrderService::post($seller,$o['id']);
checkSales(($again['idempotent']??false)===true,'duplicate post returns prior sale');
checkSales((int)$db->get_var('SELECT COUNT(*) FROM '.Db::table('stock_ledger'))===1,'duplicate post does not double-deduct stock');

$pending=PrepaidOrderService::create($seller,1,'b2b',5,[['product_id'=>1,'quantity'=>'1']],'5.00','Marketing special approval');
denySales(fn()=>PrepaidOrderService::collect($cashier,$pending['id'],10,'95.00','cash'),'sales_order_not_approved');
denySales(fn()=>PrepaidOrderService::approveDiscount($cashier,$pending['id']),'discount_policy_unconfigured');
PrepaidOrderService::discountPolicy($admin,'10.00');
$approved=PrepaidOrderService::approveDiscount($cashier,$pending['id']);
checkSales($approved['approval_scope']==='branch_manager','configured branch manager discount');
PrepaidOrderService::collect($cashier,$pending['id'],10,'95.00','cash');
PrepaidOrderService::post($seller,$pending['id']);
checkSales((int)$db->get_var('SELECT COUNT(*) FROM '.Db::table('counter_sales'))===2,'approved B2B invoice posted');

$slabs=PrepaidOrderService::setDistributorSlabs($admin,1,[
 ['min_qty'=>1,'max_qty'=>4,'unit_price'=>'90.00'],
 ['min_qty'=>5,'max_qty'=>null,'unit_price'=>'80.00']
]);
checkSales(count($slabs['slabs'])===2,'distributor price list saved in MariaDB');
$dist=PrepaidOrderService::create($seller,1,'distributor',5,[['product_id'=>1,'quantity'=>'3']]);
checkSales($dist['net_amount']==='270.00','distributor pricing applied to actual order');
PrepaidOrderService::collect($cashier,$dist['id'],10,'270.00','cash');
PrepaidOrderService::post($seller,$dist['id']);
checkSales(abs((float)$db->get_var('SELECT quantity FROM '.Db::table('stock_balances').' WHERE product_id=1')-4.)<0.0001,'B2C + B2B + distributor stock reconciled');

$failed=PrepaidOrderService::create($seller,1,'b2c',null,[['product_id'=>1,'quantity'=>'5']]);
PrepaidOrderService::collect($cashier,$failed['id'],10,'500.00','cash');
denySales(fn()=>PrepaidOrderService::post($seller,$failed['id']),'insufficient_stock');
checkSales((int)$db->get_var('SELECT COUNT(*) FROM '.Db::table('counter_sales'))===3,'failed posting rolled invoice back');
checkSales(abs((float)$db->get_var('SELECT quantity FROM '.Db::table('stock_balances').' WHERE product_id=1')-4.)<0.0001,'failed posting rolled stock back');
checkSales((int)$db->get_var('SELECT COUNT(*) FROM '.Db::table('journal_entries'))===3,'failed posting rolled journal back');
echo "PASSED full prepaid B2C/B2B/distributor MariaDB transaction integration (synthetic only)\n";
