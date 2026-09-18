<?php
/** Runtime metadata probe; no WordPress or production database required. */
define('EH7_VERSION','7.3.5-rc1');
define('EH7_SOURCE_HEAD','0123456789abcdef0123456789abcdef01234567');
define('WP_ENVIRONMENT_TYPE','staging');
require_once __DIR__.'/../src/Core/Autoloader.php';
\ExcelHerbal\ERP7\Core\Autoloader::register(__DIR__.'/../src');
if(!function_exists('get_option')){
    function get_option($key,$default=''){
        return $key==='eh7_schema_version' ? \ExcelHerbal\ERP7\Database\Schema::VERSION : $default;
    }
}
$result=\ExcelHerbal\ERP7\Http\ApiDispatch::dispatch('health',null,null);
$expected=[
    'version'=>EH7_VERSION,
    'source_head'=>EH7_SOURCE_HEAD,
    'environment'=>'staging',
    'api_contract'=>\ExcelHerbal\ERP7\Http\ApiContract::VERSION,
    'schema'=>\ExcelHerbal\ERP7\Database\Schema::VERSION,
    'schema_installed'=>true,
];
foreach($expected as$key=>$value){
    if(!array_key_exists($key,$result)||$result[$key]!==$value){
        fwrite(STDERR,'FAIL runtime_metadata '.$key.PHP_EOL);
        exit(1);
    }
}
echo 'PASS runtime_metadata_health_environment_and_source_head'.PHP_EOL;
