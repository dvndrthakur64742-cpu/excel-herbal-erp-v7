<?php
/** Read-only candidate current-day partial workflow forensic status. */
declare(strict_types=1);
if(PHP_SAPI!=='cli')exit(2);
$sha=(string)(getenv('EH7_CANDIDATE_SOURCE_SHA')?:'');
if(!preg_match('/^[a-f0-9]{40}$/i',$sha))throw new RuntimeException('SHA missing');
$candidatePluginDir='D:/ERP7-UAT-Candidate/plugin/excel-herbal-erp-v7';
if(realpath('D:/xampp/htdocs/erp-uat-candidate/wp-content/plugins/excel-herbal-erp-v7')!==realpath($candidatePluginDir))throw new RuntimeException('Wrong mount');
define('WP_USE_THEMES',false);
$_SERVER['HTTP_HOST']='127.0.0.1:18880';
$_SERVER['REQUEST_URI']='/erp-uat-candidate/';
require 'D:/xampp/htdocs/erp-uat-candidate/wp-load.php';
use ExcelHerbal\ERP7\Database\Db;
use ExcelHerbal\ERP7\Administration\StagingSafety;
use ExcelHerbal\ERP7\Administration\FreshUatBootstrap;
$db=Db::wpdb();
if((string)$db->dbname!=='eh7_restore_5ec7b1894f7a' || home_url('/')!=='http://127.0.0.1:18880/erp-uat-candidate/' ||
 EH7_SOURCE_HEAD!==$sha||!StagingSafety::status()['sanitized']||!FreshUatBootstrap::status()['seeded']||
 !StagingSafety::status()['active_mobile_sessions_zero'])throw new RuntimeException('Not the isolated idle candidate');
$cycles=$db->get_results('SELECT id,business_date,employee_id,status FROM '.Db::table('daily_cycles').' ORDER BY id',ARRAY_A);
$requests=$db->get_results('SELECT id,daily_cycle_id,status,reviewed_by,approved_by,issued_by FROM '.Db::table('daily_requests').' ORDER BY id',ARRAY_A);
$att=$db->get_results('SELECT id,employee_id,business_date,check_in_at FROM '.Db::table('attendance').' ORDER BY id DESC LIMIT 4',ARRAY_A);
$gps=$db->get_results('SELECT id,employee_id,attendance_id,recorded_at FROM '.Db::table('gps_points').' ORDER BY id DESC LIMIT 4',ARRAY_A);
$balances=$db->get_results('SELECT product_id,custodian_key,quantity FROM '.Db::table('stock_balances').' ORDER BY custodian_key',ARRAY_A);
echo json_encode(['today'=>Db::today(),'local_now'=>current_time('mysql'),'cycles'=>$cycles,
 'requests'=>$requests,'attendance'=>$att,'gps'=>$gps,'stock'=>$balances,
 'journals'=>(int)$db->get_var('SELECT COUNT(*) FROM '.Db::table('journal_entries'))],JSON_PRETTY_PRINT),PHP_EOL;
