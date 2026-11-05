<?php
/** One-time current-date synthetic evening settlement on the source-pinned candidate. */
declare(strict_types=1);
if(PHP_SAPI!=='cli')exit(2);
$sha=(string)(getenv('EH7_CANDIDATE_SOURCE_SHA')?:'');
$candidatePluginDir='D:/ERP7-UAT-Candidate/plugin/excel-herbal-erp-v7';
if(!preg_match('/^[a-f0-9]{40}$/i',$sha)||
 realpath('D:/xampp/htdocs/erp-uat-candidate/wp-content/plugins/excel-herbal-erp-v7')!==realpath($candidatePluginDir))
 throw new RuntimeException('Candidate source not recognized');
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
function goodEvening(bool $ok,string $why):void{if(!$ok)throw new RuntimeException($why);}
function refuseEvening(callable $fn,string $code):void{
 try{$fn();throw new RuntimeException('Rejected operation unexpectedly accepted: '.$code);}
 catch(DomainException $e){goodEvening($e->codeKey===$code,'Expected '.$code.', got '.$e->codeKey);}
}
$db=Db::wpdb();$today=Db::today();
goodEvening(home_url('/')==='http://127.0.0.1:18880/erp-uat-candidate/'&&
 (string)$db->dbname==='eh7_restore_5ec7b1894f7a'&&
 wp_get_environment_type()==='staging'&&
 wp_timezone_string()==='Asia/Kolkata'&&$today==='2026-11-04'&&
 hash_equals($sha,(string)EH7_SOURCE_HEAD)&&
 realpath((string)EH7_DIR)===realpath($candidatePluginDir)&&
 FreshUatBootstrap::status()['seeded']===true&&
 StagingSafety::status()['sanitized']===true&&
 StagingSafety::status()['active_mobile_sessions_zero']===true,
 'Not the correct isolated, idle, synthetic current-date UAT');
$cycles=Db::table('daily_cycles');$stock=Db::table('stock_balances');
$journal=Db::table('journal_entries');$settlements=Db::table('evening_settlements');
$warehouse=static fn()=>(float)$db->get_var(
 "SELECT quantity FROM {$stock} WHERE company_id=1 AND branch_id=1 AND product_id=1 AND batch_key=0 AND custodian_key=0");
$employee=static fn()=>(float)$db->get_var(
 "SELECT quantity FROM {$stock} WHERE company_id=1 AND branch_id=1 AND product_id=1 AND batch_key=0 AND custodian_key=2");
$cycle=$db->get_row("SELECT id,status,business_date,employee_id FROM {$cycles} WHERE id=2",ARRAY_A);
goodEvening((bool)$cycle&&$cycle['status']==='issued'&&
 $cycle['business_date']===$today&&(int)$cycle['employee_id']===2&&
 abs($warehouse())<.00001&&abs($employee()-1)<.00001&&
 (int)$db->get_var("SELECT COUNT(*) FROM {$settlements}")===1&&
 (int)$db->get_var("SELECT COUNT(*) FROM {$journal}")===9&&
 (int)$db->get_var('SELECT COUNT(*) FROM '.Db::table('counter_sales'))===7&&
 (int)$db->get_var("SELECT COUNT(*) FROM ".Db::table('settings').
 " WHERE company_id=1 AND setting_key IN ('daily_cash_account_id','daily_upi_account_id')")===2,
 'Wrong candidate pre-settlement baseline; do not repeat this script');
$f=$db->get_row("SELECT id,wp_user_id,company_id,assigned_branch_id FROM ".Db::table('employees').
 " WHERE employee_code='UAT-FIELD'",ARRAY_A);
$m=$db->get_row("SELECT id,company_id,assigned_branch_id FROM ".Db::table('employees').
 " WHERE employee_code='UAT-BM'",ARRAY_A);
goodEvening($f&&$m&&(int)$f['id']===2&&(int)$m['id']===3,
 'Missing independent synthetic BM and field employees');
$field=new Actor((int)$f['wp_user_id'],2,1,1,[1],[Cap::DAILY_SELF,Cap::DAILY_REVIEW],'EMPLOYEE');
$bm=new Actor(0,3,1,1,[1],[Cap::DAILY_REVIEW],'BM');
$started=DailyOrderService::eveningStart($field,2);
goodEvening($started['status']==='evening_draft' && (int)$started['evening_id']>0,
 'No evening draft');
$line=$db->get_row($db->prepare("SELECT issue_line_id,issued_quantity,retail_rate ".
 "FROM ".Db::table('evening_lines')." WHERE evening_settlement_id=%d",
 (int)$started['evening_id']),ARRAY_A);
goodEvening((bool)$line&&abs((float)$line['issued_quantity']-1)<.00001,
 'Expected issued one-unit evening line');
refuseEvening(static fn()=>DailyOrderService::eveningSubmit($field,2),
 'evening_reconciliation_required');
$save=DailyOrderService::eveningSave($field,2,[[
 'issue_line_id'=>(int)$line['issue_line_id'],
 'return_quantity'=>0,'wholesale_quantity'=>0,
 'retail_rate'=>(float)$line['retail_rate']
]],[],'Synthetic one-unit Cash sale and zero return');
goodEvening(abs((float)$save['expected_amount']-100)<.005,
 'Expected field sales amount 100, not reconciled');
$submitted=DailyOrderService::eveningSubmit($field,2);
goodEvening($submitted['status']==='evening_submitted',
 'Evening settlement not submitted');
echo "PASS: evening draft -> saved reconciliation -> independent review queue\n";
foreach([0.0,50.0,101.0] as $wrong){
 refuseEvening(static fn()=>DailyOrderService::finalPost($bm,2,$wrong,0.0),
  'payment_mismatch');
}
refuseEvening(static fn()=>DailyOrderService::finalPost($field,2,100.0,0.0),
 'maker_checker_required');
goodEvening((int)$db->get_var("SELECT COUNT(*) FROM {$journal}")===9 &&
 abs($employee()-1)<.00001,
 'Failed unauthorized settlement unexpectedly posted stock/GL');
$posted=DailyOrderService::finalPost($bm,2,100.0,0.0);
goodEvening($posted['status']==='completed' &&
 abs((float)$posted['amount']-100.0)<.005,
 'BM current-day Cash 100 settlement failed');
goodEvening(abs($warehouse())<.00001&&abs($employee())<.00001&&
 (int)$db->get_var("SELECT COUNT(*) FROM {$journal}")===10&&
 (int)$db->get_var('SELECT COUNT(*) FROM '.Db::table('counter_sales'))===7&&
 (int)$db->get_var("SELECT COUNT(*) FROM ".Db::table('stock_ledger').
  " WHERE source_type='daily_sale' AND source_id=2")===1,
 'Final cycle ledger/stock did not reconcile');
$entry=$db->get_row($db->prepare(
 "SELECT j.id,COALESCE(SUM(l.debit),0) debit,COALESCE(SUM(l.credit),0) credit ".
 "FROM {$journal} j JOIN ".Db::table('journal_lines')." l ON l.journal_entry_id=j.id ".
 "WHERE j.source_type='daily_cycle' AND j.source_id=%d GROUP BY j.id",2),ARRAY_A);
goodEvening((bool)$entry&&abs((float)$entry['debit']-(float)$entry['credit'])<.005,
 'Unbalanced current-day cycle journal');
try{DailyOrderService::finalPost($bm,2,100.0,0.0);
 throw new RuntimeException('Duplicate final posting was accepted');}
catch(DomainException $e){}
goodEvening((int)$db->get_var("SELECT COUNT(*) FROM {$journal}")===10,
 'Duplicate settlement unexpectedly changed journal count');
echo "PASS: Cash 0, 50 or 101 rejected versus 100; same employee could not final-post\n";
echo "PASS: independent BM posted Cash 100; warehouse 0, employee 0, one new balanced journal\n";
echo "PASS: duplicate closing refused; previous seven counter invoices untouched\n";
echo "CANDIDATE CURRENT-DAY SYNTHETIC EVENING SETTLEMENT UAT PASSED\n";
