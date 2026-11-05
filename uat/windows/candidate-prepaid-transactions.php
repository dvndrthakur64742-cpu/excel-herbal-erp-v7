<?php
/**
 * One-time, disposable, synthetic-only WordPress candidate transaction UAT.
 * Tests Cash+UPI 100% prepayment, maker-checker, replay and stock/GL posting.
 * Never point at original localhost or production: hard-coded candidate-only DB.
 */
declare(strict_types=1);
if (PHP_SAPI !== 'cli') { fwrite(STDERR,"CLI-only test\n"); exit(2); }
$sha=(string)(getenv('EH7_CANDIDATE_SOURCE_SHA') ?: '');
if (!preg_match('/^[0-9a-f]{40}$/i',$sha)) { throw new RuntimeException('Candidate source SHA required'); }
$candidatePluginDir='D:/ERP7-UAT-Candidate/plugin/excel-herbal-erp-v7';
$mount='D:/xampp/htdocs/erp-uat-candidate/wp-content/plugins/excel-herbal-erp-v7';
if (!is_dir($candidatePluginDir) || realpath($mount)!==realpath($candidatePluginDir)) {
    throw new RuntimeException('Candidate plugin junction/source mismatch');
}
define('WP_USE_THEMES',false);
$_SERVER['HTTP_HOST']='127.0.0.1:18880';
$_SERVER['REQUEST_URI']='/erp-uat-candidate/';
require 'D:/xampp/htdocs/erp-uat-candidate/wp-load.php';

use ExcelHerbal\ERP7\Administration\FreshUatBootstrap;
use ExcelHerbal\ERP7\Administration\StagingSafety;
use ExcelHerbal\ERP7\Database\Db;
use ExcelHerbal\ERP7\Domain\DomainException;
use ExcelHerbal\ERP7\Sales\PrepaidOrderService;
use ExcelHerbal\ERP7\Security\Actor;
use ExcelHerbal\ERP7\Security\Capabilities as Cap;

function check(bool $ok,string $why):void { if(!$ok)throw new RuntimeException($why); }
function reject(callable $fn,string $key):void {
    try {$fn();throw new RuntimeException('Unexpectedly accepted prohibited operation: '.$key);}
    catch(DomainException $e){check($e->codeKey===$key,'Expected '.$key.', got '.$e->codeKey);}
}
$db=Db::wpdb();
check(home_url('/')==='http://127.0.0.1:18880/erp-uat-candidate/' &&
  (string)$db->dbname==='eh7_restore_5ec7b1894f7a' &&
  wp_get_environment_type()==='staging' &&
  hash_equals(strtolower($sha),strtolower((string)EH7_SOURCE_HEAD)) &&
  realpath((string)EH7_DIR)===realpath($candidatePluginDir) &&
  FreshUatBootstrap::status()['seeded']===true &&
  StagingSafety::status()['sanitized']===true &&
  StagingSafety::status()['active_mobile_sessions_zero']===true,
  'Unsafe WordPress synthetic candidate/source/identity');
$admin=$db->get_row("SELECT * FROM ".Db::table('employees')." WHERE employee_code='UAT-ADMIN'",ARRAY_A);
$bm=$db->get_row("SELECT * FROM ".Db::table('employees')." WHERE employee_code='UAT-BM'",ARRAY_A);
check((bool)$admin && (bool)$bm && $admin['id']!==$bm['id'] &&
  (int)$admin['company_id']===(int)$bm['company_id'] &&
  (int)$admin['assigned_branch_id']===(int)$bm['assigned_branch_id'],
  'Distinct synthetic sales/bank verifier identities are unavailable');
$cid=(int)$admin['company_id'];$branch=(int)$admin['assigned_branch_id'];
check($cid===1 && $branch===1 && (int)$bm['id']===3,
  'Unexpected synthetic-only branch/company/employee identities');
$seller=new Actor((int)$admin['wp_user_id'],(int)$admin['id'],$cid,$branch,[$branch],
  [Cap::SALES_CREATE,Cap::RECEIPT_CREATE,Cap::BANK_RECONCILE],'SYSADMIN');
$verifier=new Actor(0,(int)$bm['id'],$cid,$branch,[$branch],[Cap::BANK_RECONCILE],'BM');
$ordersTable=Db::table('prepaid_sales_orders');
$salesTable=Db::table('counter_sales');
$journalTable=Db::table('journal_entries');
$balanceTable=Db::table('stock_balances');
$getCount=static fn(string $table):int=>(int)$db->get_var("SELECT COUNT(*) FROM {$table}");
$getWarehouse=static fn():float=>(float)$db->get_var($db->prepare(
 "SELECT quantity FROM {$balanceTable} WHERE company_id=%d AND branch_id=%d AND product_id=1 AND batch_key=0 AND custodian_key=0",$cid,$branch
));
$oldOrders=$getCount($ordersTable);$oldSales=$getCount($salesTable);$oldJournals=$getCount($journalTable);
$oldWarehouse=$getWarehouse();
// This suite is intentionally ONE-TIME only, since the candidate was cloned after earlier UAT.
check($oldOrders===5 && $oldSales===5 && $oldJournals===7 &&
  abs($oldWarehouse-3.0)<0.00001,'Candidate baseline altered or this UAT has already run');
check((int)$db->get_var("SELECT COUNT(*) FROM ".Db::table('branch_closings').
 " WHERE company_id=1 AND branch_id=1 AND business_date='".esc_sql(Db::today())."' AND status='closed'")===0,
 'Local synthetic business day closed; do not bypass guard');
$accounts=PrepaidOrderService::paymentAccounts($seller,$branch);
$cash=0;$upi=0;
foreach($accounts as $acc) {
 if($acc['subtype']==='cash')$cash=(int)$acc['id'];
 if($acc['subtype']==='upi')$upi=(int)$acc['id'];
}
check($cash>0 && $upi>0,'Candidate cash and UPI test accounts missing');
echo 'PASS: source-pinned synthetic candidate, 5 historical orders, 3 warehouse units, open local business date '.Db::today().PHP_EOL;

$cashOrder=PrepaidOrderService::create($seller,$branch,'b2c',null,[['product_id'=>1,'quantity'=>'1']]);
check($cashOrder['status']==='approved' &&
  (string)$cashOrder['net_amount']==='100.00','B2C cash order amount incorrect');
$cashId=(int)$cashOrder['id'];
check($getCount($salesTable)===$oldSales,'Cash invoice created before any prepayment');
reject(static fn()=>PrepaidOrderService::post($seller,$cashId),'full_prepayment_required');
$partial=PrepaidOrderService::collect($seller,$cashId,$cash,'40.00','cash','CANDIDATE-TEST-CASH-40');
check($partial['status']==='confirmed','Partial cash unexpectedly unconfirmed');
reject(static fn()=>PrepaidOrderService::post($seller,$cashId),'full_prepayment_required');
PrepaidOrderService::collect($seller,$cashId,$cash,'60.00','cash','CANDIDATE-TEST-CASH-60');
reject(static fn()=>PrepaidOrderService::collect($seller,$cashId,$cash,'1.00','cash','CANDIDATE-TEST-CASH-OVER'),'payment_overpaid');
$postedCash=PrepaidOrderService::post($seller,$cashId);
check($postedCash['status']==='posted' && (string)$postedCash['paid_amount']==='100.00' &&
  (string)$postedCash['outstanding_amount']==='0.00','Full Cash posting failed');
check((PrepaidOrderService::post($seller,$cashId)['idempotent']??false)===true,
 'Cash invoice retry not idempotent');
check($getCount($salesTable)===$oldSales+1 &&
  abs($getWarehouse()-($oldWarehouse-1))<0.00001 &&
  $getCount($journalTable)===$oldJournals+1,
  'Cash invoice stock/GL counters diverged');
echo 'PASS: Cash 40+60 full prepayment required, overpay blocked, one invoice, one stock deduction, one journal'.PHP_EOL;

$upiOrder=PrepaidOrderService::create($seller,$branch,'b2c',null,[['product_id'=>1,'quantity'=>'1']]);
check($upiOrder['status']==='approved' && $upiOrder['net_amount']==='100.00','UPI order incorrect');
$upiId=(int)$upiOrder['id'];
$pending=PrepaidOrderService::collect($seller,$upiId,$upi,'100.00','upi','CANDIDATE-TEST-UPI-100');
check($pending['status']==='pending','Unverified UPI receipt did not remain pending');
reject(static fn()=>PrepaidOrderService::post($seller,$upiId),'upi_verification_required');
reject(static fn()=>PrepaidOrderService::verifyUpi($seller,(int)$pending['id'],'CANDIDATE-BANK-EVIDENCE'),'maker_checker_required');
$verified=PrepaidOrderService::verifyUpi($verifier,(int)$pending['id'],'CANDIDATE-BANK-EVIDENCE');
check($verified['status']==='confirmed','Independent synthetic UPI verifier failed');
reject(static fn()=>PrepaidOrderService::verifyUpi($verifier,(int)$pending['id'],'CANDIDATE-BANK-EVIDENCE'),'upi_payment_state_invalid');
$postedUpi=PrepaidOrderService::post($seller,$upiId);
check($postedUpi['status']==='posted' && $postedUpi['outstanding_amount']==='0.00',
 'Verified UPI invoice failed');
check((PrepaidOrderService::post($seller,$upiId)['idempotent']??false)===true,
 'UPI invoice retry not idempotent');
check($getCount($ordersTable)===$oldOrders+2 &&
  $getCount($salesTable)===$oldSales+2 &&
  $getCount($journalTable)===$oldJournals+2 &&
  abs($getWarehouse()-($oldWarehouse-2))<0.00001,
  'Final Sales, stock, journals or order counts differ');
$rows=$db->get_results($db->prepare(
 "SELECT j.id,COALESCE(SUM(l.debit),0) debit,COALESCE(SUM(l.credit),0) credit FROM ".Db::table('journal_entries').
 " j JOIN ".Db::table('journal_lines')." l ON l.journal_entry_id=j.id ".
 "WHERE j.source_type='counter_sale' AND j.source_id IN (%d,%d) GROUP BY j.id",
 (int)$postedCash['sale_id'],(int)$postedUpi['sale_id']),ARRAY_A);
check(count($rows)===2,'Expected two new counter-sale journals');
foreach($rows as $row){
 check(abs((float)$row['debit']-(float)$row['credit'])<0.005,
  'Sales journal debit and credit are unbalanced');
}
echo 'PASS: UPI pending blocks invoice, maker-checker enforced, bank evidence verified, replay denied'.PHP_EOL;
echo 'PASS: 2 posted B2C invoices, stock 3->1, two balanced journals, zero outstanding'.PHP_EOL;
echo 'CANDIDATE SYNTHETIC CASH+UPI TRANSACTION UAT PASSED (NO REAL BANK TRANSFER)'.PHP_EOL;
