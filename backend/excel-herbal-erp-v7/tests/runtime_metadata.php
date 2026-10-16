<?php
define('EH7_VERSION','7.3.5-rc1');
define('EH7_SOURCE_HEAD','0123456789abcdef0123456789abcdef01234567');
define('WP_ENVIRONMENT_TYPE','staging');

require_once __DIR__.'/../src/Core/Autoloader.php';
\ExcelHerbal\ERP7\Core\Autoloader::register(__DIR__.'/../src');

$options=[
 'eh7_schema_version'=>\ExcelHerbal\ERP7\Database\Schema::VERSION,
 'eh7_staging_sanitized_source_head'=>EH7_SOURCE_HEAD,
 'eh7_staging_sanitized_at'=>'2026-09-18 12:00:00',
 'blog_public'=>'0',
 'eh7_uat_seed_source_head'=>EH7_SOURCE_HEAD,
 'eh7_uat_seeded_at'=>'2026-09-18 12:00:00',
 'eh7_uat_seed_mode'=>'fresh_synthetic',
 'eh7_uat_admin_employee_id'=>1,
 'eh7_uat_limited_employee_id'=>2,
];
function get_option($key,$default=''){global $options;return array_key_exists($key,$options)?$options[$key]:$default;}
final class RuntimeMetadataDb {public string $prefix='wp_';public function prepare($q,...$args){return $q.'|'.implode('|',$args);}public function get_var($sql){return str_contains($sql,'eh7_employees')?1:0;}}
$wpdb=new RuntimeMetadataDb();

$result=\ExcelHerbal\ERP7\Http\ApiDispatch::dispatch('health',null,null);
$expected=['version'=>EH7_VERSION,'source_head'=>EH7_SOURCE_HEAD,'environment'=>'staging','api_contract'=>\ExcelHerbal\ERP7\Http\ApiContract::VERSION,'schema'=>\ExcelHerbal\ERP7\Database\Schema::VERSION,'schema_installed'=>true];
foreach($expected as$key=>$value){if(!array_key_exists($key,$result)||$result[$key]!==$value){fwrite(STDERR,'FAIL runtime_metadata '.$key.PHP_EOL);exit(1);}}
$safety=$result['staging_safety']??[];
if(($safety['sanitized']??false)!==true||($safety['active_mobile_sessions_zero']??false)!==true||($safety['active_push_devices_zero']??false)!==true){fwrite(STDERR,'FAIL runtime_metadata staging_safety'.PHP_EOL);exit(1);}
$uat=$result['uat_bootstrap']??[];
if(($uat['seeded']??false)!==true||($uat['synthetic_only']??false)!==true){fwrite(STDERR,'FAIL runtime_metadata fresh_uat'.PHP_EOL);exit(1);}
$web=$result['web_runtime']??null;
if(!is_array($web)||($web['present']??true)!==false||($web['error']??'')!=='wp_upload_dir_unavailable'){fwrite(STDERR,'FAIL runtime_metadata web_runtime_cli_fallback'.PHP_EOL);exit(1);}
echo 'PASS runtime_metadata_health_environment_source_head_staging_safety_fresh_uat_and_web_runtime_fallback'.PHP_EOL;