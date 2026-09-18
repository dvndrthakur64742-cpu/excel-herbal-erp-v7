<?php
if(!defined('WP_CLI')||!WP_CLI){if(function_exists('http_response_code'))http_response_code(403);exit;}
$required=['EH7_UAT_WP_ADMIN_LOGIN','EH7_UAT_ADMIN_PASSWORD','EH7_UAT_ADMIN_MOBILE','EH7_UAT_LIMITED_PASSWORD','EH7_UAT_LIMITED_MOBILE'];
$cfg=[];
foreach($required as$name){$value=(string)getenv($name);if($value==='')throw new RuntimeException('Missing environment variable: '.$name);$cfg[$name]=$value;}
$result=\ExcelHerbal\ERP7\Administration\FreshUatBootstrap::bootstrap([
 'wp_admin_login'=>$cfg['EH7_UAT_WP_ADMIN_LOGIN'],
 'admin_password'=>$cfg['EH7_UAT_ADMIN_PASSWORD'],
 'admin_mobile'=>$cfg['EH7_UAT_ADMIN_MOBILE'],
 'limited_password'=>$cfg['EH7_UAT_LIMITED_PASSWORD'],
 'limited_mobile'=>$cfg['EH7_UAT_LIMITED_MOBILE'],
 'company_name'=>(string)(getenv('EH7_UAT_COMPANY_NAME')?:'EH7 Fresh UAT'),
 'branch_name'=>(string)(getenv('EH7_UAT_BRANCH_NAME')?:'UAT Branch'),
]);
echo wp_json_encode($result,JSON_PRETTY_PRINT|JSON_UNESCAPED_SLASHES).PHP_EOL;
