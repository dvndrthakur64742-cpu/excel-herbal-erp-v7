<?php
/**
 * One-time candidate-only real WordPress+MariaDB field-stock/sales settlement UAT.
 * Requires separately verified Windows clock; never production or original UAT.
 * Uses only synthetic employees, GPS point, dummy stock and dummy Cash 100.
 */
declare(strict_types=1);
if(PHP_SAPI!=='cli')exit(2);
$sha=(string)(getenv('EH7_CANDIDATE_SOURCE_SHA')?:'');
if(!preg_match('/^[a-f0-9]{40}$/i',$sha))throw new RuntimeException('Exact candidate source required');
$mount='D:/xampp/htdocs/erp-uat-candidate/wp-content/plugins/excel-herbal-erp-v7';
$candidatePluginDir='D:/ERP7-UAT-Candidate/plugin/excel-herbal-erp-v7';
if(realpath($mount)!==realpath($candidatePluginDir))throw new RuntimeException('Candidate source mount mismatch');
define('WP_USE_THEMES',false);
$_SERVER['HTTP_HOST']='127.0.0.1:18880';
$_SERVER['REQUEST_URI']='/erp-uat-candidate/';
require 'D:/xampp/htdocs/erp-uat-candidate/wp-load.php';

use ExcelHerbal\ERP7\Administration\FreshUatBootstrap;
use ExcelHerbal\ERP7\Administration\StagingSafety;
use ExcelHerbal\ERP7\Database\Db;
use ExcelHerbal\ERP7\DailyOrder\DailyOrderService;
use ExcelHerbal\ERP7\Domain\DomainException;
use ExcelHerbal\ERP7\Recovery\RecoveryService;
use ExcelHerbal\ERP7\Security\Actor;
use ExcelHerbal\ERP7\Security\Capabilities as Cap;
use ExcelHerbal\ERP7\Workforce\AttendanceGpsEvidence;
use ExcelHerbal\ERP7\Workforce\WorkforceService;

function verify(bool $ok,string $message):void{if(!$ok)throw new RuntimeException($message);}
function denied(callable $fn,string $key):void{
 try{$fn();throw new RuntimeException('Unsafe operation unexpectedly allowed: '.$key);}
 catch(DomainException $ex){verify($ex->codeKey===$key,'Expected '.$key.', got '.$ex->codeKey);}
}
$db=Db::wpdb();$today=Db::today();$at=current_time('H:i:s');
verify(home_url('/')==='http://127.0.0.1:18880/erp-uat-candidate/' &&
 (string)$db->dbname==='eh7_restore_5ec7b1894f7a' &&
 wp_get_environment_type()==='staging' &&
 wp_timezone_string()==='Asia/Kolkata' &&
 $today===gmdate('Y-m-d',time()+19800) &&
 hash_equals(strtolower($sha),strtolower((string)EH7_SOURCE_HEAD)) &&
 realpath((string)EH7_DIR)===realpath($candidatePluginDir) &&
 FreshUatBootstrap::status()['seeded']===true &&
 StagingSafety::status()['sanitized']===true &&
 StagingSafety::status()['active_mobile_sessions_zero']===true &&
 $at>='10:30:00' && $at<'17:00:00',
 'Candidate not safe, today mismatch or duty window closed');
$e=Db::table('employees');$cycles=Db::table('daily_cycles');
$stock=Db::table('stock_balances');$requests=Db::table('daily_requests');
$journal=Db::table('journal_entries');$dailySales=Db::table('stock_ledger');
$getEmployee=static fn(string $code)=>$db->get_row($db->prepare(
 "SELECT * FROM {$e} WHERE employee_code=%s",$code),ARRAY_A);
$field=$getEmployee('UAT-FIELD');$admin=$getEmployee('UAT-ADMIN');$manager=$getEmployee('UAT-BM');
verify((bool)$field&&(bool)$admin&&(bool)$manager&&
 (int)$field['id']===2&&(int)$admin['id']===1&&(int)$manager['id']===3&&
 (int)$field['company_id']===1&&(int)$field['assigned_branch_id']===1&&
 (int)$admin['assigned_branch_id']===1&&(int)$manager['assigned_branch_id']===1,
 'Unexpected synthetic-only fixture employees');
$getWarehouse=static fn():float=>(float)$db->get_var(
 "SELECT quantity FROM {$stock} WHERE company_id=1 AND branch_id=1 AND product_id=1 AND batch_key=0 AND custodian_key=0");
$getField=static fn():float=>(float)$db->get_var(
 "SELECT quantity FROM {$stock} WHERE company_id=1 AND branch_id=1 AND product_id=1 AND batch_key=0 AND custodian_key=2");
$count=static fn(string $table):int=>(int)$db->get_var("SELECT COUNT(*) FROM {$table}");
verify($count($cycles)===1&&
 (int)$db->get_var("SELECT COUNT(*) FROM {$cycles} WHERE employee_id=2 AND business_date='{$today}'")===0&&
 $count($requests)===1&&
 $count($journal)===9&&
 $count(Db::table('counter_sales'))===7&&
 abs($getWarehouse()-1.0)<0.00001&&abs($getField())<0.00001,
 'Candidate baseline changed; one-time test must not rerun');
verify((int)$db->get_var("SELECT COUNT(*) FROM ".Db::table('settings').
 " WHERE company_id=1 AND setting_key IN ('daily_cash_account_id','daily_upi_account_id')")===2,
 'Candidate daily Cash+UPI ledger configuration is not ready');
verify((int)$db->get_var($db->prepare(
 "SELECT COUNT(*) FROM ".Db::table('branch_closings').
 " WHERE company_id=1 AND branch_id=1 AND business_date=%s AND status='closed'",$today))===0,
 'Current synthetic branch business date closed');
$fieldActor=new Actor((int)$field['wp_user_id'],2,1,1,[1],[Cap::ATT_SELF,Cap::DAILY_SELF,Cap::DAILY_ISSUE,Cap::DAILY_REVIEW],'EMPLOYEE');
$reviewer=new Actor((int)$admin['wp_user_id'],1,1,1,[1],[Cap::DAILY_OTHERS,Cap::DAILY_APPROVE,Cap::DAILY_SELF],'SYSADMIN');
$approver=new Actor(0,3,1,1,[1],[Cap::DAILY_APPROVE,Cap::DAILY_ISSUE,Cap::DAILY_REVIEW],'BM');
echo 'PASS: source-pinned, idle synthetic candidate on today '.$today.' at '.$at.'; warehouse 1; no duplicate daily cycle'.PHP_EOL;
$att=WorkforceService::attendanceToday($fieldActor);
verify((bool)$att && !empty($att['check_in_at'])&&empty($att['check_out_at'])&&
 ($att['gps_status']??'')==='active'&&($att['gps_should_track']??false)===true,
 'Current duty GPS/automatic attendance not active');
verify(!AttendanceGpsEvidence::hasVerifiedMorningPoint(1,1,2,$today),
 'Morning GPS already recorded; test is one-time only');
denied(static fn()=>DailyOrderService::create($fieldActor,1,2,$today,
 [['product_id'=>1,'quantity'=>1]]),'daily_attendance_required');
verify($count($cycles)===1,'GPS rejection wrote a daily cycle');
$point=RecoveryService::gpsPoint($fieldActor,[
 'lat'=>31.701,'lng'=>76.93,'accuracy_m'=>9,'source'=>'duty']);
verify((int)$point['id']>0 && AttendanceGpsEvidence::hasVerifiedMorningPoint(1,1,2,$today),
 'Synthetic GPS proof not linked to attendance');
echo 'PASS: scheduled field attendance and GPS evidence; stock request blocked BEFORE GPS'.PHP_EOL;
$new=DailyOrderService::create($fieldActor,1,2,$today,[['product_id'=>1,'quantity'=>1]]);
$cycleId=(int)$new['id'];$requestId=(int)$new['request_id'];
verify($cycleId===2&&$requestId===2&&$new['status']==='morning_draft',
 'Wrong new daily cycle/request identity');
$submit=DailyOrderService::submit($fieldActor,$cycleId);
verify($submit['status']==='stock_requested','Stock request submission failed');
denied(static fn()=>DailyOrderService::review($fieldActor,$requestId),'permission_denied');
$review=DailyOrderService::review($reviewer,$requestId);
verify($review['status']==='reviewed','Independent reviewer failed');
denied(static fn()=>DailyOrderService::approve($reviewer,$requestId),'maker_checker_required');
$approved=DailyOrderService::approve($approver,$requestId);
verify($approved['status']==='approved','Separate BM approval failed');
$line=$db->get_row("SELECT id FROM ".Db::table('daily_request_lines')." WHERE daily_request_id={$requestId}",ARRAY_A);
verify((bool)$line,'Requested stock line missing');
denied(static fn()=>DailyOrderService::issue($fieldActor,$requestId,
 [['request_line_id'=>(int)$line['id'],'quantity'=>1]]),'maker_checker_required');
$issued=DailyOrderService::issue($approver,$requestId,
 [['request_line_id'=>(int)$line['id'],'quantity'=>1]]);
verify($issued['status']==='awaiting_receipt'&&abs($getWarehouse()-1.0)<0.00001,
 'Stock moved before employee physical receipt');
denied(static fn()=>DailyOrderService::receive($reviewer,$requestId),'daily_receipt_forbidden');
$received=DailyOrderService::receive($fieldActor,$requestId);
verify($received['status']==='issued'&&abs($getWarehouse())<0.00001&&
 abs($getField()-1.0)<0.00001,'Employee receipt/custody movement incorrect');
denied(static fn()=>DailyOrderService::receive($fieldActor,$requestId),'daily_request_state_invalid');
echo 'PASS: request -> independent review -> BM approval -> stock allocation -> employee physical receipt (warehouse 0, field 1)'.PHP_EOL;
$evening=DailyOrderService::eveningStart($fieldActor,$cycleId);
verify($evening['status']==='evening_draft','Evening draft not created');
$eveningLine=$db->get_row($db->prepare(
 "SELECT issue_line_id,retail_rate,issued_quantity FROM ".Db::table('evening_lines').
 " WHERE evening_settlement_id=%d",(int)$evening['evening_id']),ARRAY_A);
verify((bool)$eveningLine && abs((float)$eveningLine['issued_quantity']-1)<0.00001,
 'Expected one issued evening stock unit');
denied(static fn()=>DailyOrderService::eveningSubmit($fieldActor,$cycleId),'evening_reconciliation_required');
$saved=DailyOrderService::eveningSave($fieldActor,$cycleId,[[
 'issue_line_id'=>(int)$eveningLine['issue_line_id'],
 'return_quantity'=>0,'wholesale_quantity'=>0,
 'retail_rate'=>(float)$eveningLine['retail_rate']
]],[],'Synthetic one-unit field cash retail sale');
verify(abs((float)$saved['expected_amount']-100.0)<0.005,
 'Expected one field sale Cash 100');
$submitted=DailyOrderService::eveningSubmit($fieldActor,$cycleId);
verify($submitted['status']==='evening_submitted','Evening not submitted');
foreach([0.0,50.0,101.0] as $bad){
 denied(static fn()=>DailyOrderService::finalPost($approver,$cycleId,$bad,0.0),'payment_mismatch');
}
denied(static fn()=>DailyOrderService::finalPost($fieldActor,$cycleId,100.0,0.0),'maker_checker_required');
$posted=DailyOrderService::finalPost($approver,$cycleId,100.0,0.0);
verify($posted['status']==='completed'&&abs((float)$posted['amount']-100.0)<0.005,
 'Cash 100 final settlement not posted');
verify(abs($getWarehouse())<0.00001&&abs($getField())<0.00001,
 'Stock after field sale not reconciled to zero');
verify($count($journal)===10 && $count(Db::table('counter_sales'))===7 &&
 (int)$db->get_var($db->prepare(
 "SELECT COUNT(*) FROM {$dailySales} WHERE source_type='daily_sale' AND source_id=%d",$cycleId))===1,
 'Settlement journal/stock ledger or counter invoices incorrect');
$journalRow=$db->get_row($db->prepare(
 "SELECT j.id,COALESCE(SUM(l.debit),0) debit,COALESCE(SUM(l.credit),0) credit FROM {$journal} j ".
 "JOIN ".Db::table('journal_lines')." l ON l.journal_entry_id=j.id ".
 "WHERE j.source_type='daily_cycle' AND j.source_id=%d GROUP BY j.id",$cycleId),ARRAY_A);
verify((bool)$journalRow && abs((float)$journalRow['debit']-(float)$journalRow['credit'])<0.005,
 'Field cycle accounting journal not balanced');
echo 'PASS: daily one-unit Cash 100 field sale, invalid Cash totals denied, independent BM final settlement, balanced GL'.PHP_EOL;
echo 'PASS: completed new cycle 2; warehouse 0, field 0; journal 9 -> 10; old 7 invoices untouched'.PHP_EOL;
echo 'CANDIDATE CURRENT-DAY SYNTHETIC FIELD WORKFLOW UAT PASSED (NO REAL FIELD WORK)'.PHP_EOL;
