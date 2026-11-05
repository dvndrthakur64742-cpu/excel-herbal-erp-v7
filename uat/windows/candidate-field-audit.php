<?php
/** Read-only, independent proof of completed synthetic daily field cycle. */
declare(strict_types=1);
if(PHP_SAPI!=='cli')exit(2);
$sha=(string)(getenv('EH7_CANDIDATE_SOURCE_SHA')?:'');
$candidatePluginDir='D:/ERP7-UAT-Candidate/plugin/excel-herbal-erp-v7';
if(!preg_match('/^[a-f0-9]{40}$/i',$sha)||
 realpath('D:/xampp/htdocs/erp-uat-candidate/wp-content/plugins/excel-herbal-erp-v7')!==realpath($candidatePluginDir))
 throw new RuntimeException('Wrong candidate code');
define('WP_USE_THEMES',false);
$_SERVER['HTTP_HOST']='127.0.0.1:18880';
$_SERVER['REQUEST_URI']='/erp-uat-candidate/';
require 'D:/xampp/htdocs/erp-uat-candidate/wp-load.php';
use ExcelHerbal\ERP7\Administration\FreshUatBootstrap;
use ExcelHerbal\ERP7\Administration\StagingSafety;
use ExcelHerbal\ERP7\Database\Db;
use ExcelHerbal\ERP7\Workforce\AttendanceGpsEvidence;
function verifyDaily(bool $ok,string $msg):void{if(!$ok)throw new RuntimeException($msg);}
$db=Db::wpdb();$today=Db::today();
verifyDaily(home_url('/')==='http://127.0.0.1:18880/erp-uat-candidate/'&&
 (string)$db->dbname==='eh7_restore_5ec7b1894f7a'&&
 wp_get_environment_type()==='staging'&&$today==='2026-11-04'&&
 EH7_SOURCE_HEAD===$sha&&realpath((string)EH7_DIR)===realpath($candidatePluginDir)&&
 FreshUatBootstrap::status()['seeded']===true&&
 StagingSafety::status()['sanitized']===true&&
 StagingSafety::status()['active_mobile_sessions_zero']===true,
 'Candidate source, seed, staging or date not verified');
$c=Db::table('daily_cycles');$requests=Db::table('daily_requests');
$evening=Db::table('evening_settlements');$stock=Db::table('stock_balances');
$journal=Db::table('journal_entries');$gps=Db::table('gps_points');
$cycle=$db->get_row("SELECT id,status,business_date,employee_id FROM {$c} WHERE id=2",ARRAY_A);
$req=$db->get_row("SELECT id,status,reviewed_by,approved_by,issued_by FROM {$requests} WHERE id=2",ARRAY_A);
$settled=$db->get_row("SELECT id,status,submitted_by,reviewed_by,expected_amount,cash_amount,upi_amount FROM {$evening} WHERE daily_cycle_id=2",ARRAY_A);
verifyDaily($cycle&&$req&&$settled&&$cycle['status']==='completed'&&
 $cycle['business_date']===$today&&(int)$cycle['employee_id']===2&&
 $req['status']==='issued'&&(int)$req['reviewed_by']===1&&
 (int)$req['approved_by']===3&&(int)$req['issued_by']===3&&
 $settled['status']==='posted'&&(int)$settled['submitted_by']===2&&
 (int)$settled['reviewed_by']===3&&
 abs((float)$settled['expected_amount']-100)<0.005&&
 abs((float)$settled['cash_amount']-100)<0.005&&
 abs((float)$settled['upi_amount'])<0.005,
 'Current-day authority or Cash settlement provenance incorrect');
verifyDaily(AttendanceGpsEvidence::hasVerifiedMorningPoint(1,1,2,$today)&&
 (int)$db->get_var("SELECT COUNT(*) FROM {$gps} WHERE employee_id=2 AND attendance_id=62")===1,
 'New synthetic morning GPS evidence missing');
$lines=$db->get_row($db->prepare(
 "SELECT issued_quantity,return_quantity,retail_quantity,wholesale_quantity,total_amount ".
 "FROM ".Db::table('evening_lines')." WHERE evening_settlement_id=%d",(int)$settled['id']),ARRAY_A);
verifyDaily($lines&&abs((float)$lines['issued_quantity']-1)<0.0001&&
 abs((float)$lines['return_quantity'])<0.0001&&
 abs((float)$lines['retail_quantity']-1)<0.0001&&
 abs((float)$lines['wholesale_quantity'])<0.0001&&
 abs((float)$lines['total_amount']-100)<0.005,
 'Daily issued/sold/returned quantities not reconciled');
$balance=$db->get_results("SELECT custodian_key,quantity FROM {$stock} WHERE company_id=1 AND branch_id=1 AND product_id=1 ORDER BY custodian_key",ARRAY_A);
verifyDaily(count($balance)===2&&
 abs((float)$balance[0]['quantity'])<.0001&&
 abs((float)$balance[1]['quantity'])<.0001,
 'Original custody/Warehouse stock after field sale not zero');
$journalRow=$db->get_row($db->prepare(
 "SELECT j.id,COALESCE(SUM(l.debit),0) debit,COALESCE(SUM(l.credit),0) credit FROM {$journal} j ".
 "JOIN ".Db::table('journal_lines')." l ON l.journal_entry_id=j.id ".
 "WHERE j.source_type='daily_cycle' AND j.source_id=%d GROUP BY j.id",2),ARRAY_A);
verifyDaily($journalRow&&abs((float)$journalRow['debit']-(float)$journalRow['credit'])<.005&&
 (int)$db->get_var("SELECT COUNT(*) FROM {$journal}")===10&&
 (int)$db->get_var('SELECT COUNT(*) FROM '.Db::table('counter_sales'))===7&&
 (int)$db->get_var('SELECT COUNT(*) FROM '.Db::table('prepaid_sales_orders'))===7&&
 (int)$db->get_var("SELECT COUNT(*) FROM ".Db::table('stock_ledger').
 " WHERE source_type='daily_issue' AND source_id=2")===2&&
 (int)$db->get_var("SELECT COUNT(*) FROM ".Db::table('stock_ledger').
 " WHERE source_type='daily_sale' AND source_id=2")===1,
 'GL, prior prepaid sales or paired custody ledgers inconsistent');
$old=$db->get_row("SELECT status,business_date FROM {$c} WHERE id=1",ARRAY_A);
verifyDaily($old&&$old['status']==='completed'&&$old['business_date']==='2026-11-02',
 'Historical synthetic cycle unexpectedly changed');
echo "PASS READ-ONLY: GPS-bound 2026-11-04 cycle 2 completed, Employee 2 -> Reviewer 1 -> BM 3\n";
echo "PASS READ-ONLY: 1 issued, 1 sold, 0 returned; Cash 100; warehouse 0, employee 0\n";
echo "PASS READ-ONLY: balanced daily GL 10 total; 7 previous prepaid invoices unchanged; old cycle completed\n";
echo "CANDIDATE INDEPENDENT CURRENT-DAY FIELD AUDIT PASSED\n";
