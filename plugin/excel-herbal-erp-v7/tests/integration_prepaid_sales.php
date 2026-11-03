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
if(($argv[1]??'')==='post-worker'){
    try {
        $workerDb=eh7_setup_global_db();
        $workerActor=new Actor(101,101,1,1,[1],[C::SALES_CREATE,C::SALES_VIEW],'SALES');
        $result=PrepaidOrderService::post($workerActor,(int)($argv[2]??0));
        echo json_encode($result,JSON_THROW_ON_ERROR)."\n";
        exit(0);
    }catch(Throwable $e){
        fwrite(STDERR,get_class($e).': '.$e->getMessage()."\n");
        exit(3);
    }
}
$db=eh7_setup_global_db();
$tables=[
    'audit_log','journal_lines','journal_entries','reversals','counter_sale_lines','counter_sales','stock_ledger','stock_balances',
    'prepaid_refund_evidence','prepaid_return_requests','prepaid_sales_order_payments','prepaid_sales_order_lines','prepaid_sales_orders','distributor_price_slabs',
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
denySales(fn()=>PrepaidOrderService::verifyUpi($finance,$upi['id'],'BANK-UTR-0002'),'upi_payment_state_invalid');
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
// 20% discount exceeds configured 10% HO cutoff. Branch manager cannot approve it.
$hoOrder=PrepaidOrderService::create($seller,1,'b2b',5,[['product_id'=>1,'quantity'=>'1']],'20.00','Head Office special campaign');
denySales(fn()=>PrepaidOrderService::approveDiscount($cashier,$hoOrder['id']),'permission_denied');
$hoDecision=PrepaidOrderService::approveDiscount($admin,$hoOrder['id']);
checkSales($hoDecision['approval_scope']==='head_office','larger discount requires separate Head Office authority');
PrepaidOrderService::collect($cashier,$hoOrder['id'],10,'80.00','cash');
PrepaidOrderService::post($seller,$hoOrder['id']);

// Two independent PHP processes race to post the same fully paid order.
// Row-level locking must serialize both posts; exactly one stock and journal posting.
$race=PrepaidOrderService::create($seller,1,'b2c',null,[['product_id'=>1,'quantity'=>'1']]);
PrepaidOrderService::collect($cashier,$race['id'],10,'100.00','cash');
$cmd=[PHP_BINARY,__FILE__,'post-worker',(string)$race['id']];
$processes=[];
foreach([1,2] as $worker){
    $pipes=[];$proc=proc_open($cmd,[1=>['pipe','w'],2=>['pipe','w']],$pipes,__DIR__);
    if(!is_resource($proc))throw new RuntimeException('Cannot start concurrent posting worker.');
    $processes[]=[$proc,$pipes];
}
$workerResults=[];
foreach($processes as [$proc,$pipes]){
    $stdout=stream_get_contents($pipes[1]);$stderr=stream_get_contents($pipes[2]);
    fclose($pipes[1]);fclose($pipes[2]);
    $code=proc_close($proc);
    if($code!==0)throw new RuntimeException('Concurrent posting failed: '.$stderr);
    $workerResults[]=json_decode($stdout,true,512,JSON_THROW_ON_ERROR);
}
checkSales(count($workerResults)===2 && $workerResults[0]['sale_id']===$workerResults[1]['sale_id'],'concurrent invoice calls share one sale ID');
checkSales((int)$db->get_var('SELECT COUNT(*) FROM '.Db::table('counter_sales'))===5,'concurrent posting created one additional invoice only');
checkSales((int)$db->get_var('SELECT COUNT(*) FROM '.Db::table('journal_entries'))===5,'concurrent posting created one additional journal only');
checkSales(abs((float)$db->get_var('SELECT quantity FROM '.Db::table('stock_balances').' WHERE product_id=1')-2.)<0.0001,'concurrent posting deducts stock exactly once');


 // Phase 1 Return Intake: no payment, stock or accounting writes until a
 // verified, separate refund+credit-note posting flow is released.
$returnMaker=new Actor(101,101,1,1,[1],[C::REVERSAL_CREATE,C::REVERSAL_APPROVE,C::SALES_VIEW],'SALES');
$returnInspector=new Actor(102,102,1,1,[1],[C::REVERSAL_APPROVE,C::SALES_VIEW],'BM');
$returnApprover=new Actor(103,103,1,1,[1],[C::REVERSAL_APPROVE,C::SALES_VIEW],'FINANCE');
$returnForeign=new Actor(104,104,1,99,[99],[C::REVERSAL_APPROVE,C::SALES_VIEW],'SYSADMIN');
$returnStock=(float)$db->get_var('SELECT quantity FROM '.Db::table('stock_balances').' WHERE product_id=1');
$returnLedger=(int)$db->get_var('SELECT COUNT(*) FROM '.Db::table('stock_ledger'));
$returnJournal=(int)$db->get_var('SELECT COUNT(*) FROM '.Db::table('journal_entries'));
$returnPayment=(int)$db->get_var("SELECT COUNT(*) FROM ".Db::table('prepaid_sales_order_payments')." WHERE order_id=".(int)$post['id']." AND status='confirmed'");
denySales(fn()=>\ExcelHerbal\ERP7\Sales\PrepaidReturnService::request(
 $returnMaker,(int)$post['id'],'bad'
),'prepaid_return_reason_required');
denySales(fn()=>\ExcelHerbal\ERP7\Sales\PrepaidReturnService::request(
 $returnMaker,(int)$failed['id'],'Full refund for an unposted order'
),'prepaid_return_invoice_not_posted');
$return=\ExcelHerbal\ERP7\Sales\PrepaidReturnService::request(
 $returnMaker,(int)$post['id'],'Synthetic full return of prepaid B2C goods'
);
checkSales($return['status']==='requested' && $return['financial_posted']===false,
 'return request recorded without money or stock posting');
$returnId=(int)$return['id'];
denySales(fn()=>\ExcelHerbal\ERP7\Sales\PrepaidReturnService::request(
 $returnMaker,(int)$post['id'],'Repeat synthetic return request'
),'prepaid_return_already_requested');
denySales(fn()=>\ExcelHerbal\ERP7\Sales\PrepaidReturnService::inspect(
 $returnMaker,$returnId,'UAT-PHYSICAL-001'
),'maker_checker_required');
denySales(fn()=>\ExcelHerbal\ERP7\Sales\PrepaidReturnService::inspect(
 $returnInspector,$returnId,'bad'
),'prepaid_return_inspection_required');
denySales(fn()=>\ExcelHerbal\ERP7\Sales\PrepaidReturnService::inspect(
 $returnForeign,$returnId,'UAT-PHYSICAL-001'
),'branch_forbidden');
$returnPhysical=\ExcelHerbal\ERP7\Sales\PrepaidReturnService::inspect(
 $returnInspector,$returnId,'UAT-PHYSICAL-001','Fixture goods physically checked'
);
checkSales($returnPhysical['status']==='received' && $returnPhysical['stock_posted']===false,
 'independent physical inspection stored without stock posting');
denySales(fn()=>\ExcelHerbal\ERP7\Sales\PrepaidReturnService::decide(
 $returnInspector,$returnId,true
),'maker_checker_required');
denySales(fn()=>\ExcelHerbal\ERP7\Sales\PrepaidReturnService::decide(
 $returnMaker,$returnId,true
),'maker_checker_required');
$returnDecision=\ExcelHerbal\ERP7\Sales\PrepaidReturnService::decide(
 $returnApprover,$returnId,true
);
checkSales($returnDecision['status']==='refund_pending' && $returnDecision['refund_posted']===false &&
 $returnDecision['credit_note_posted']===false,'third independent approver keeps refund pending');
denySales(fn()=>\ExcelHerbal\ERP7\Sales\PrepaidReturnService::decide(
 $returnApprover,$returnId,true
),'prepaid_return_state_invalid');
checkSales(count(\ExcelHerbal\ERP7\Sales\PrepaidReturnService::list($returnApprover,1))===1,
 'scoped return queue readable');

 // Record the two ORIGINAL tender portions (Cash and confirmed UPI).
 // Both are evidence only: even verified documents cannot post a refund.
$evidenceMaker=new Actor(104,104,1,1,[1],[C::REVERSAL_CREATE,C::REVERSAL_APPROVE,C::SALES_VIEW],'SYSADMIN');
$evidenceCashChecker=new Actor(102,102,1,1,[1],[C::REVERSAL_APPROVE,C::SALES_VIEW],'BM');
$evidenceUpiChecker=new Actor(103,103,1,1,[1],[C::BANK_RECONCILE,C::SALES_VIEW],'FINANCE');
$evidenceForeign=new Actor(104,104,1,99,[99],[C::REVERSAL_CREATE,C::SALES_VIEW],'SYSADMIN');
$originals=(array)$db->get_results($db->prepare(
  'SELECT id,method,amount FROM '.Db::table('prepaid_sales_order_payments').
  ' WHERE company_id=1 AND order_id=%d ORDER BY id',(int)$post['id']
),ARRAY_A);
checkSales(count($originals)===2 && $originals[0]['method']==='cash' &&
 $originals[1]['method']==='upi','return source has original Cash and UPI tender lines');
denySales(fn()=>\ExcelHerbal\ERP7\Sales\PrepaidRefundEvidenceService::submit(
 $evidenceMaker,$returnId,(int)$originals[0]['id'],'101.00','UAT-CASH-REF-001'
),'refund_amount_mismatch');
denySales(fn()=>\ExcelHerbal\ERP7\Sales\PrepaidRefundEvidenceService::submit(
 $evidenceForeign,$returnId,(int)$originals[0]['id'],'100.00','UAT-CASH-REF-001'
),'branch_forbidden');
denySales(fn()=>\ExcelHerbal\ERP7\Sales\PrepaidRefundEvidenceService::submit(
 $evidenceMaker,$returnId,999999,'100.00','UAT-UNKNOWN-001'
),'refund_original_payment_invalid');
$cashEvidence=\ExcelHerbal\ERP7\Sales\PrepaidRefundEvidenceService::submit(
 $evidenceMaker,$returnId,(int)$originals[0]['id'],'100.00','UAT-CASH-REF-001'
);
checkSales($cashEvidence['status']==='evidence_submitted' &&
 $cashEvidence['refund_disbursed']===false,'cash proof intake does not imply payout');
denySales(fn()=>\ExcelHerbal\ERP7\Sales\PrepaidRefundEvidenceService::submit(
 $evidenceMaker,$returnId,(int)$originals[0]['id'],'100.00','UAT-CASH-REF-002'
),'refund_evidence_duplicate');
denySales(fn()=>\ExcelHerbal\ERP7\Sales\PrepaidRefundEvidenceService::verify(
 $evidenceMaker,(int)$cashEvidence['id'],'UAT-CASH-CHECK-001'
),'maker_checker_required');
$verifiedCash=\ExcelHerbal\ERP7\Sales\PrepaidRefundEvidenceService::verify(
 $evidenceCashChecker,(int)$cashEvidence['id'],'UAT-CASH-CHECK-001'
);
checkSales($verifiedCash['status']==='evidence_verified' &&
 $verifiedCash['refund_disbursed']===false,'independent manual cash proof check is NOT disbursement');
$partialPreflight=\ExcelHerbal\ERP7\Sales\PrepaidReturnService::detail($returnApprover,$returnId);
checkSales($partialPreflight['refund_evidence_check']['evidence_complete']===false &&
 in_array('refund_evidence_missing',$partialPreflight['refund_evidence_check']['blockers'],true),
 'real MariaDB return detail reports missing split-tender verification');
denySales(fn()=>\ExcelHerbal\ERP7\Sales\PrepaidReturnService::detail($returnForeign,$returnId),
 'branch_forbidden');
$upiEvidence=\ExcelHerbal\ERP7\Sales\PrepaidRefundEvidenceService::submit(
 $evidenceMaker,$returnId,(int)$originals[1]['id'],'100.00','UAT-UPI-REF-001'
);
denySales(fn()=>\ExcelHerbal\ERP7\Sales\PrepaidRefundEvidenceService::verify(
 $evidenceCashChecker,(int)$upiEvidence['id'],'UAT-UPI-BANK-CHECK'
),'permission_denied');
denySales(fn()=>\ExcelHerbal\ERP7\Sales\PrepaidRefundEvidenceService::verify(
 $evidenceUpiChecker,(int)$upiEvidence['id'],'bad'
),'refund_verification_reference_required');
$verifiedUpi=\ExcelHerbal\ERP7\Sales\PrepaidRefundEvidenceService::verify(
 $evidenceUpiChecker,(int)$upiEvidence['id'],'UAT-UPI-BANK-CHECK'
);
checkSales($verifiedUpi['status']==='evidence_verified' &&
 $verifiedUpi['manual_evidence_only']===true,'independent manual UPI check NOT bank API proof');
denySales(fn()=>\ExcelHerbal\ERP7\Sales\PrepaidRefundEvidenceService::verify(
 $evidenceUpiChecker,(int)$upiEvidence['id'],'UAT-UPI-CHECK-REPEAT'
),'refund_evidence_state_invalid');
$completePreflight=\ExcelHerbal\ERP7\Sales\PrepaidReturnService::detail($returnApprover,$returnId);
checkSales($completePreflight['refund_evidence_check']['evidence_complete']===true &&
 $completePreflight['refund_evidence_check']['expected_amount']==='200.00' &&
 $completePreflight['refund_evidence_check']['verified_evidence_count']===2 &&
 $completePreflight['refund_evidence_check']['refund_disbursed']===false &&
 $completePreflight['refund_evidence_check']['credit_note_posted']===false,
 'real MariaDB reconciles both verified tenders without disbursement or credit note');
$evidenceList=\ExcelHerbal\ERP7\Sales\PrepaidRefundEvidenceService::list($evidenceCashChecker,$returnId);
checkSales(count($evidenceList)===2 && $evidenceList[0]['status']==='evidence_verified' &&
 $evidenceList[1]['status']==='evidence_verified','split-tender refund evidence independently verified');
checkSales((string)$db->get_var('SELECT status FROM '.Db::table('prepaid_return_requests').
 ' WHERE id='.(int)$returnId)==='refund_pending','verified documents do not mark refund paid');
checkSales((int)$db->get_var('SELECT COUNT(*) FROM '.Db::table('prepaid_refund_evidence'))===2,
 'one evidence row per original confirmed payment');
echo "PASS synthetic cash/UPI evidence traceability; NO refund or credit note posting\n";

checkSales((int)$db->get_var('SELECT COUNT(*) FROM '.Db::table('prepaid_return_requests'))===1,
 'full-return uniqueness enforced');
checkSales((float)$db->get_var('SELECT quantity FROM '.Db::table('stock_balances').' WHERE product_id=1')===$returnStock,
 'return intake did not inflate warehouse stock');
checkSales((int)$db->get_var('SELECT COUNT(*) FROM '.Db::table('stock_ledger'))===$returnLedger,
 'return intake did not change custody or stock ledger');
checkSales((int)$db->get_var('SELECT COUNT(*) FROM '.Db::table('journal_entries'))===$returnJournal,
 'return intake did not reverse sales or disburse money');
checkSales((int)$db->get_var("SELECT COUNT(*) FROM ".Db::table('prepaid_sales_order_payments')." WHERE order_id=".(int)$post['id']." AND status='confirmed'")===$returnPayment,
 'confirmed original payment evidence remains immutable');
echo "PASS prepaid return physical receipt and independent approval remain refund_pending until verified refund posting exists\n";

 // A paid prepaid invoice cannot be reversed by the generic finance route:
 // there is no verified refund record / prepaid order state transition yet.
 // A plain counter-sale reversal would restore stock and reverse the journal
 // while leaving an already-paid, still-posted order and confirmed payments.
$reversalMaker=new Actor(101,101,1,1,[1],[C::REVERSAL_CREATE],'SALES');
$reversalApprover=new Actor(102,102,1,1,[1],[C::REVERSAL_APPROVE],'BM');
$protectedSale=(int)$post['sale_id'];
checkSales($protectedSale>0,'fully paid synthetic counter sale exists');
$reversalStartStock=(float)$db->get_var('SELECT quantity FROM '.Db::table('stock_balances').' WHERE product_id=1');
$reversalStartJournal=(int)$db->get_var('SELECT COUNT(*) FROM '.Db::table('journal_entries'));
$reversalStartLedger=(int)$db->get_var('SELECT COUNT(*) FROM '.Db::table('stock_ledger'));
denySales(fn()=>\ExcelHerbal\ERP7\Finance\FinanceReversalService::requestReversal(
 $reversalMaker,'counter_sale',$protectedSale,'Synthetic prepaid refund must be reconciled'
),'prepaid_refund_workflow_required');
checkSales((int)$db->get_var('SELECT COUNT(*) FROM '.Db::table('reversals'))===0,
    'prepaid reversal request did not leave a pending reversal row');
// Mimic an approved legacy reversal request created before the new guard.
// The execute path independently blocks it: approval cannot bypass protection.
$legacyRequest=seed('reversals',[
 'company_id'=>1,'branch_id'=>1,'source_type'=>'counter_sale',
 'source_id'=>$protectedSale,'reason'=>'Legacy test-only refund reversal',
 'status'=>'approved','requested_by'=>101,'requested_at'=>Db::now(),
 'decided_by'=>102,'decided_at'=>Db::now()
]);
denySales(fn()=>\ExcelHerbal\ERP7\Finance\FinanceReversalService::executeReversal(
 $reversalApprover,$legacyRequest
),'prepaid_refund_workflow_required');
checkSales((string)$db->get_var('SELECT status FROM '.Db::table('reversals').
    ' WHERE id='.(int)$legacyRequest)==='approved','legacy reversal remains unexecuted');
checkSales((string)$db->get_var('SELECT status FROM '.Db::table('counter_sales').
    ' WHERE id='.$protectedSale)==='posted','paid prepaid invoice remains posted');
checkSales((string)$db->get_var('SELECT status FROM '.Db::table('prepaid_sales_orders').
    ' WHERE sale_id='.$protectedSale)==='posted','prepaid order status preserved');
checkSales(abs((float)$db->get_var('SELECT quantity FROM '.Db::table('stock_balances').
    ' WHERE product_id=1')-$reversalStartStock)<.0001,'paid reversal did not change stock');
checkSales((int)$db->get_var('SELECT COUNT(*) FROM '.Db::table('journal_entries'))===$reversalStartJournal,
    'paid reversal did not create or reverse a journal');
checkSales((int)$db->get_var('SELECT COUNT(*) FROM '.Db::table('stock_ledger'))===$reversalStartLedger,
    'paid reversal did not change stock ledger');
echo "PASS generic reversal refused fully paid prepaid invoice until verified refund workflow exists\n";

echo "PASSED full prepaid B2C/B2B/distributor MariaDB transaction and concurrent posting integration (synthetic only)\n";
