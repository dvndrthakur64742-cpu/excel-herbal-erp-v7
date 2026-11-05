<?php
/** Candidate-only resume: stock requested -> independent review -> receipt. One-time. */
declare(strict_types=1);
if(PHP_SAPI!=='cli')exit(2);
$sha=(string)(getenv('EH7_CANDIDATE_SOURCE_SHA')?:'');
$candidatePluginDir='D:/ERP7-UAT-Candidate/plugin/excel-herbal-erp-v7';
if(!preg_match('/^[a-f0-9]{40}$/i',$sha)||
 realpath('D:/xampp/htdocs/erp-uat-candidate/wp-content/plugins/excel-herbal-erp-v7')!==realpath($candidatePluginDir))
 throw new RuntimeException('Candidate pinned source missing');
define('WP_USE_THEMES',false);
$_SERVER['HTTP_HOST']='127.0.0.1:18880';
$_SERVER['REQUEST_URI']='/erp-uat-candidate/';
require 'D:/xampp/htdocs/erp-uat-candidate/wp-load.php';
use ExcelHerbal\ERP7\Administration\FreshUatBootstrap;
use ExcelHerbal\ERP7\Administration\StagingSafety;
use ExcelHerbal\ERP7\Database\Db;
use ExcelHerbal\ERP7\DailyOrder\DailyOrderService;
use ExcelHerbal\ERP7\Domain\DomainException;
use ExcelHerbal\ERP7\Security\Actor;
use ExcelHerbal\ERP7\Security\Capabilities as Cap;
use ExcelHerbal\ERP7\Workforce\AttendanceGpsEvidence;
function mustStock(bool $x,string $why):void{if(!$x)throw new RuntimeException($why);}
function rejectStock(callable $fn,string $expected):void{
 try{$fn();throw new RuntimeException('Forbidden operation accepted: '.$expected);}
 catch(DomainException $e){mustStock($e->codeKey===$expected,'Expected '.$expected.', got '.$e->codeKey);}
}
$db=Db::wpdb();$today=Db::today();
mustStock((string)$db->dbname==='eh7_restore_5ec7b1894f7a'&&
 home_url('/')==='http://127.0.0.1:18880/erp-uat-candidate/'&&
 wp_get_environment_type()==='staging'&&
 wp_timezone_string()==='Asia/Kolkata'&&
 hash_equals($sha,(string)EH7_SOURCE_HEAD)&&
 realpath((string)EH7_DIR)===realpath($candidatePluginDir)&&
 FreshUatBootstrap::status()['seeded']===true&&
 StagingSafety::status()['sanitized']===true&&
 StagingSafety::status()['active_mobile_sessions_zero']===true&&
 $today==='2026-11-04'&&AttendanceGpsEvidence::hasVerifiedMorningPoint(1,1,2,$today),
 'Not verified safe current-day, source-pinned synthetic candidate');
$cycles=Db::table('daily_cycles');$requests=Db::table('daily_requests');
$stock=Db::table('stock_balances');
$cycle=$db->get_row("SELECT id,status,employee_id,business_date FROM {$cycles} WHERE id=2",ARRAY_A);
$req=$db->get_row("SELECT id,daily_cycle_id,status,requested_by,reviewed_by FROM {$requests} WHERE id=2",ARRAY_A);
$wh=static fn()=>(float)$db->get_var("SELECT quantity FROM {$stock} WHERE company_id=1 AND branch_id=1 AND product_id=1 AND batch_key=0 AND custodian_key=0");
$owned=static fn()=>(float)$db->get_var("SELECT quantity FROM {$stock} WHERE company_id=1 AND branch_id=1 AND product_id=1 AND batch_key=0 AND custodian_key=2");
mustStock($cycle&&$req&&$cycle['status']==='stock_requested'&&
 $req['status']==='submitted'&&(int)$req['daily_cycle_id']===2&&
 (int)$req['requested_by']===2&&empty($req['reviewed_by'])&&
 (int)$cycle['employee_id']===2&&$cycle['business_date']===$today&&
 abs($wh()-1)<.0001&&abs($owned())<.0001&&
 (int)$db->get_var('SELECT COUNT(*) FROM '.Db::table('daily_issue_lines'))===1&&
 (int)$db->get_var('SELECT COUNT(*) FROM '.Db::table('journal_entries'))===9,
 'Candidate not at exactly expected submitted stock request; do not repeat');
$employee=static fn($code)=>$db->get_row($db->prepare("SELECT * FROM ".Db::table('employees')." WHERE employee_code=%s",$code),ARRAY_A);
$f=$employee('UAT-FIELD');$admin=$employee('UAT-ADMIN');$bm=$employee('UAT-BM');
mustStock((int)$f['id']===2&&(int)$admin['id']===1&&(int)$bm['id']===3,
 'Expected three fixed synthetic employees');
$field=new Actor((int)$f['wp_user_id'],2,1,1,[1],[Cap::DAILY_SELF,Cap::DAILY_ISSUE],'EMPLOYEE');
$reviewer=new Actor((int)$admin['wp_user_id'],1,1,1,[1],
 [Cap::DAILY_OTHERS,Cap::DAILY_APPROVE,Cap::DAILY_SELF],'SYSADMIN');
$manager=new Actor(0,3,1,1,[1],
 [Cap::DAILY_APPROVE,Cap::DAILY_ISSUE,Cap::DAILY_REVIEW],'BM');
rejectStock(static fn()=>DailyOrderService::review($field,2),'permission_denied');
$review=DailyOrderService::review($reviewer,2);
mustStock($review['status']==='reviewed','Independent synthetic reviewer blocked');
rejectStock(static fn()=>DailyOrderService::approve($reviewer,2),'maker_checker_required');
$approved=DailyOrderService::approve($manager,2);
mustStock($approved['status']==='approved','BM final approval failed');
$line=$db->get_row("SELECT id,quantity FROM ".Db::table('daily_request_lines')." WHERE daily_request_id=2",ARRAY_A);
mustStock($line&&abs((float)$line['quantity']-1)<.0001,'Wrong requested synthetic product quantity');
rejectStock(static fn()=>DailyOrderService::issue($field,2,
 [['request_line_id'=>(int)$line['id'],'quantity'=>1]]),'maker_checker_required');
$issued=DailyOrderService::issue($manager,2,
 [['request_line_id'=>(int)$line['id'],'quantity'=>1]]);
mustStock($issued['status']==='awaiting_receipt'&&abs($wh()-1)<.0001,
 'Stock moved prematurely before beneficiary accepted issue');
rejectStock(static fn()=>DailyOrderService::receive($reviewer,2),'daily_receipt_forbidden');
$received=DailyOrderService::receive($field,2);
mustStock($received['status']==='issued'&&abs($wh())<.0001&&abs($owned()-1)<.0001,
 'Employee physical receipt did not reconcile warehouse/employee custody');
rejectStock(static fn()=>DailyOrderService::receive($field,2),'daily_request_state_invalid');
mustStock((int)$db->get_var("SELECT COUNT(*) FROM ".Db::table('stock_ledger').
 " WHERE source_type='daily_issue' AND source_id=2")===2,
 'Expected paired stock ledger transfers for new daily issue');
echo "PASS: submitted morning stock -> independent review -> separate BM approval\n";
echo "PASS: self-review, reviewer self-approval, self-issue, wrong-employee receipt and duplicate receipt rejected\n";
echo "PASS: stock changed only after synthetic employee receipt (warehouse 1->0, field 0->1), two custody entries\n";
echo "CANDIDATE SYNTHETIC CURRENT-DAY STOCK REQUEST/ISSUE/RECEIPT UAT PASSED\n";
