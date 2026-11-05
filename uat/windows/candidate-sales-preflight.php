<?php
declare(strict_types=1);
if (PHP_SAPI !== 'cli') { exit(2); }
$expected = getenv('EH7_CANDIDATE_SOURCE_SHA') ?: '';
if (!preg_match('/^[a-f0-9]{40}$/', $expected)) {
    throw new RuntimeException('Candidate Git SHA required');
}
$site = 'http://127.0.0.1:18880/erp-uat-candidate';
$plugin = 'D:/ERP7-UAT-Candidate/plugin/excel-herbal-erp-v7';
$mount = 'D:/xampp/htdocs/erp-uat-candidate/wp-content/plugins/excel-herbal-erp-v7';
if (realpath($mount) !== realpath($plugin)) { throw new RuntimeException('Unsafe plugin mount'); }
define('WP_USE_THEMES',false);
$_SERVER['HTTP_HOST']='127.0.0.1:18880';
$_SERVER['REQUEST_URI']='/erp-uat-candidate/';
require 'D:/xampp/htdocs/erp-uat-candidate/wp-load.php';
use ExcelHerbal\ERP7\Database\Db;
use ExcelHerbal\ERP7\Administration\FreshUatBootstrap;
use ExcelHerbal\ERP7\Administration\StagingSafety;
$db=Db::wpdb();
if (home_url('/') !== $site.'/' || $db->dbname !== 'eh7_restore_5ec7b1894f7a'
    || wp_get_environment_type() !== 'staging' || EH7_SOURCE_HEAD !== $expected
    || !FreshUatBootstrap::status()['seeded'] || !StagingSafety::status()['sanitized']
    || !StagingSafety::status()['active_mobile_sessions_zero']) {
    throw new RuntimeException('Unsafe candidate source, database, or UAT status');
}
$balance=$db->get_results("SELECT product_id,branch_id,batch_key,custodian_key,quantity FROM ".Db::table('stock_balances')." ORDER BY product_id,branch_id,custodian_key LIMIT 20",ARRAY_A);
$accounts=$db->get_results("SELECT id,subtype,active FROM ".Db::table('accounts')." WHERE subtype IN ('cash','upi') ORDER BY subtype",ARRAY_A);
$products=$db->get_results("SELECT id,sku,status FROM ".Db::table('products')." ORDER BY id LIMIT 8",ARRAY_A);
$orders=$db->get_results("SELECT id,channel,status,net_amount FROM ".Db::table('prepaid_sales_orders')." ORDER BY id DESC LIMIT 8",ARRAY_A);
$days=$db->get_results("SELECT branch_id,business_date,status FROM ".Db::table('branch_closings')." ORDER BY id DESC LIMIT 8",ARRAY_A);
$cycles=$db->get_results("SELECT id,business_date,status FROM ".Db::table('daily_cycles')." ORDER BY id DESC LIMIT 8",ARRAY_A);
$count=function($name)use($db){return (int)$db->get_var("SELECT COUNT(*) FROM ".Db::table($name));};
echo json_encode([
    'candidate_source'=>substr($expected,0,8),'today'=>Db::today(),'timezone'=>wp_timezone_string(),
    'balances'=>$balance,'accounts'=>$accounts,'products'=>$products,'orders'=>$orders,
    'branch_days'=>$days,'cycles'=>$cycles,'sale_count'=>$count('counter_sales'),
    'journal_count'=>$count('journal_entries'),'order_count'=>$count('prepaid_sales_orders')
],JSON_PRETTY_PRINT|JSON_UNESCAPED_SLASHES),PHP_EOL;
