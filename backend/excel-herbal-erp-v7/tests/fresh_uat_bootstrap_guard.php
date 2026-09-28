<?php
define('EH7_SOURCE_HEAD','0123456789abcdef0123456789abcdef01234567');
$testEnv='staging';$testHost='uat.example.test';
$options=[];
function wp_get_environment_type(){global $testEnv;return $testEnv;}
function home_url($path=''){global $testHost;return 'https://'.$testHost.$path;}
function get_option($key,$default=''){global $options;return array_key_exists($key,$options)?$options[$key]:$default;}
final class FreshUatGuardDb{
 public string $prefix='wp_';
 public function prepare($q,...$args){return $q.'|'.implode('|',$args);}
 public function get_var($q){global $options;$id=str_contains($q,'eh7_uat_admin_employee_id')?0:0;return str_contains($q,'|active')?1:0;}
}
$wpdb=new FreshUatGuardDb();
require_once __DIR__.'/../src/Core/Autoloader.php';
\ExcelHerbal\ERP7\Core\Autoloader::register(__DIR__.'/../src');

try{\ExcelHerbal\ERP7\Administration\FreshUatBootstrap::assertSafeTarget();echo "PASS fresh_uat_safe_target\n";}
catch(Throwable $e){fwrite(STDERR,"FAIL fresh_uat_safe_target ".$e->getMessage()."\n");exit(1);}

$status=\ExcelHerbal\ERP7\Administration\FreshUatBootstrap::status();
if(($status['seeded']??true)!==false){fwrite(STDERR,"FAIL fresh_uat_unseeded_status\n");exit(1);}
$options=[
 'eh7_uat_seed_source_head'=>EH7_SOURCE_HEAD,
 'eh7_uat_seeded_at'=>'2026-09-18 12:00:00',
 'eh7_uat_seed_mode'=>'fresh_synthetic',
 'eh7_uat_admin_employee_id'=>1,
 'eh7_uat_limited_employee_id'=>2,
];
$status=\ExcelHerbal\ERP7\Administration\FreshUatBootstrap::status();
if(($status['seeded']??false)!==true||($status['synthetic_only']??false)!==true){fwrite(STDERR,"FAIL fresh_uat_seed_marker\n");exit(1);}
echo "PASS fresh_uat_seed_marker\n";

$testHost='office.excelherbal.in';
try{\ExcelHerbal\ERP7\Administration\FreshUatBootstrap::assertSafeTarget();fwrite(STDERR,"FAIL fresh_uat_office_refusal\n");exit(1);}
catch(RuntimeException $e){if(!str_contains($e->getMessage(),'explicit BUILD/UAT package marker')){fwrite(STDERR,"FAIL fresh_uat_office_message\n");exit(1);}}
echo "PASS fresh_uat_refuses_office_host\n";

$testHost='uat.example.test';$testEnv='production';
try{\ExcelHerbal\ERP7\Administration\FreshUatBootstrap::assertSafeTarget();fwrite(STDERR,"FAIL fresh_uat_production_refusal\n");exit(1);}
catch(RuntimeException $e){if(!str_contains($e->getMessage(),'non-staging')){fwrite(STDERR,"FAIL fresh_uat_production_message\n");exit(1);}}
echo "PASS fresh_uat_refuses_non_staging\n";
