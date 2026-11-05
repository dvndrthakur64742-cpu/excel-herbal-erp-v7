<?php
/** Read-only guard: original localhost UAT retained its pre-candidate rows. */
declare(strict_types=1);
if(PHP_SAPI!=='cli')exit(2);
define('WP_USE_THEMES',false);
$_SERVER['HTTP_HOST']='127.0.0.1:18880';
$_SERVER['REQUEST_URI']='/erp-uat/';
require 'D:/xampp/htdocs/erp-uat/wp-load.php';
use ExcelHerbal\ERP7\Database\Db;
use ExcelHerbal\ERP7\Administration\FreshUatBootstrap;
use ExcelHerbal\ERP7\Administration\StagingSafety;
$db=Db::wpdb();
if(home_url('/')!=='http://127.0.0.1:18880/erp-uat/' ||
 (string)$db->dbname!=='eh7_local_uat' ||
 wp_get_environment_type()!=='staging' ||
 (string)EH7_SOURCE_HEAD!=='2e40eba61d97ef26b543c631682d0701af75b3bd' ||
 FreshUatBootstrap::status()['seeded']!==true ||
 StagingSafety::status()['sanitized']!==true ||
 StagingSafety::status()['active_mobile_sessions_zero']!==true){
 throw new RuntimeException('Original source/DB/idle synthetic safety changed');
}
$orders=(int)$db->get_var('SELECT COUNT(*) FROM '.Db::table('prepaid_sales_orders'));
$sales=(int)$db->get_var('SELECT COUNT(*) FROM '.Db::table('counter_sales'));
$journals=(int)$db->get_var('SELECT COUNT(*) FROM '.Db::table('journal_entries'));
$warehouse=(float)$db->get_var('SELECT quantity FROM '.Db::table('stock_balances').
 ' WHERE company_id=1 AND branch_id=1 AND product_id=1 AND batch_key=0 AND custodian_key=0');
if($orders!==5 || $sales!==5 || $journals!==7 || abs($warehouse-3.0)>0.00001){
 throw new RuntimeException('Original localhost UAT rows unexpectedly changed');
}
echo "PASS original WordPress synthetic UAT unchanged: 5 orders, 5 sales, 7 journals, warehouse 3\n";
echo "Original WordPress source marker is older; source-certified release remains blocked\n";
