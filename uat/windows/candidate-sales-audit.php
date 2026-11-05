<?php
/** Read-only independent verification of the one-time candidate B2C payment UAT. */
declare(strict_types=1);
if(PHP_SAPI!=='cli')exit(2);
$candidateSha=(string)(getenv('EH7_CANDIDATE_SOURCE_SHA')?:'');
if(!preg_match('/^[0-9a-f]{40}$/i',$candidateSha))throw new RuntimeException('Exact candidate SHA required');
$candidatePluginDir='D:/ERP7-UAT-Candidate/plugin/excel-herbal-erp-v7';
$candidateMount='D:/xampp/htdocs/erp-uat-candidate/wp-content/plugins/excel-herbal-erp-v7';
if(realpath($candidateMount)!==realpath($candidatePluginDir))throw new RuntimeException('Candidate mount mismatch');
define('WP_USE_THEMES',false);
$_SERVER['HTTP_HOST']='127.0.0.1:18880';
$_SERVER['REQUEST_URI']='/erp-uat-candidate/';
require 'D:/xampp/htdocs/erp-uat-candidate/wp-load.php';
use ExcelHerbal\ERP7\Administration\FreshUatBootstrap;
use ExcelHerbal\ERP7\Administration\StagingSafety;
use ExcelHerbal\ERP7\Database\Db;
function assertAudit(bool $condition,string $message):void{if(!$condition)throw new RuntimeException($message);}
$db=Db::wpdb();
assertAudit(home_url('/')==='http://127.0.0.1:18880/erp-uat-candidate/' &&
 (string)$db->dbname==='eh7_restore_5ec7b1894f7a' &&
 wp_get_environment_type()==='staging' && EH7_SOURCE_HEAD===$candidateSha &&
 realpath((string)EH7_DIR)===realpath($candidatePluginDir) &&
 FreshUatBootstrap::status()['seeded']===true &&
 StagingSafety::status()['sanitized']===true &&
 StagingSafety::status()['active_mobile_sessions_zero']===true,
 'Unsafe environment/source/sessions');
$orders=Db::table('prepaid_sales_orders');
$payments=Db::table('prepaid_sales_order_payments');
$sales=Db::table('counter_sales');
$journals=Db::table('journal_entries');
$journalLines=Db::table('journal_lines');
$balances=Db::table('stock_balances');
assertAudit((int)$db->get_var("SELECT COUNT(*) FROM {$orders}")===7 &&
 (int)$db->get_var("SELECT COUNT(*) FROM {$sales}")===7 &&
 (int)$db->get_var("SELECT COUNT(*) FROM {$journals}")===9,
 'Candidate expected posted transaction row counts changed');
$rows=(array)$db->get_results("SELECT id,status,net_amount,sale_id FROM {$orders} WHERE id IN (6,7) ORDER BY id",ARRAY_A);
assertAudit(count($rows)===2,'Expected two new B2C orders');
$saleIds=[];
foreach($rows as $o){
 assertAudit($o['status']==='posted' && (string)$o['net_amount']==='100.00' &&
  (int)$o['sale_id']>0,'One candidate prepaid order not fully posted');
 $saleIds[]=(int)$o['sale_id'];
}
assertAudit(count(array_unique($saleIds))===2,'Two orders refer to the same invoice');
$cash=(array)$db->get_results("SELECT method,status,amount,received_by,verified_by FROM {$payments} WHERE order_id=6 ORDER BY id",ARRAY_A);
$upi=(array)$db->get_results("SELECT method,status,amount,received_by,verified_by,bank_evidence_ref FROM {$payments} WHERE order_id=7 ORDER BY id",ARRAY_A);
assertAudit(count($cash)===2 && $cash[0]['method']==='cash' &&
 $cash[1]['method']==='cash' && $cash[0]['status']==='confirmed' &&
 $cash[1]['status']==='confirmed' && (float)$cash[0]['amount']===40.0 &&
 (float)$cash[1]['amount']===60.0,'Cash partial collection totals/status mismatch');
assertAudit(count($upi)===1 && $upi[0]['method']==='upi' &&
 $upi[0]['status']==='confirmed' && (float)$upi[0]['amount']===100.0 &&
 (int)$upi[0]['received_by']!== (int)$upi[0]['verified_by'] &&
 (int)$upi[0]['verified_by']===3 &&
 strlen((string)$upi[0]['bank_evidence_ref'])>=6,
 'UPI maker/checker or bank evidence missing');
foreach($saleIds as $saleId){
 $sale=$db->get_row($db->prepare("SELECT paid_amount,outstanding_amount,status FROM {$sales} WHERE id=%d",$saleId),ARRAY_A);
 assertAudit((bool)$sale && $sale['status']==='posted' &&
  (string)$sale['paid_amount']==='100.00' &&
  (string)$sale['outstanding_amount']==='0.00','Invoice not fully prepaid');
 $entry=$db->get_row($db->prepare(
 "SELECT j.id,COALESCE(SUM(l.debit),0) debit,COALESCE(SUM(l.credit),0) credit FROM {$journals} j ".
 "JOIN {$journalLines} l ON l.journal_entry_id=j.id WHERE j.source_type='counter_sale' ".
 "AND j.source_id=%d GROUP BY j.id",$saleId),ARRAY_A);
 assertAudit((bool)$entry && abs((float)$entry['debit']-(float)$entry['credit'])<0.005,
  'Unbalanced or missing candidate invoice journal');
}
$warehouse=(float)$db->get_var("SELECT quantity FROM {$balances} WHERE company_id=1 AND branch_id=1 ".
 "AND product_id=1 AND batch_key=0 AND custodian_key=0");
assertAudit(abs($warehouse-1.0)<0.00001,'Warehouse balance did not decrease by 2 units');
$cycle=(string)$db->get_var('SELECT status FROM '.Db::table('daily_cycles').' WHERE id=1');
assertAudit($cycle==='completed','Existing synthetic field cycle was disturbed');
echo "PASS independent candidate payment audit: 7 orders, 7 invoices, 9 journals\n";
echo "PASS Cash split 40+60, UPI maker-checker with bank evidence, 0 outstanding\n";
echo "PASS two balanced journals, warehouse 1, old evening cycle remains completed\n";
echo "CANDIDATE B2C POSTING READ-ONLY AUDIT PASSED (NO PRODUCTION/BANK ACTION)\n";
