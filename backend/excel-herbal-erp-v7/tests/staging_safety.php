<?php
define('EH7_SOURCE_HEAD','0123456789abcdef0123456789abcdef01234567');
define('WP_ENVIRONMENT_TYPE','staging');
$options=['eh7_staging_sanitized_source_head'=>'','eh7_staging_sanitized_at'=>'','blog_public'=>'1'];
$testHost='uat.excelherbal.in';
function get_option($key,$default=''){global $options;return array_key_exists($key,$options)?$options[$key]:$default;}
function update_option($key,$value,$autoload=null){global $options;$options[$key]=$value;return true;}
function home_url($path=''){global $testHost;return 'https://'.$testHost.$path;}
function current_time($format,$gmt=false){return $format==='Y-m-d'?'2026-09-18':'2026-09-18 12:00:00';}
final class StagingSafetyDb {
    public string $prefix='wp_';public string $last_error='';public int $activeSessions=3;public int $activePush=2;
    public function query($sql){if(str_contains($sql,'eh7_mobile_sessions')){$n=$this->activeSessions;$this->activeSessions=0;return$n;}if(str_contains($sql,'eh7_push_devices')){$n=$this->activePush;$this->activePush=0;return$n;}return 0;}
    public function get_var($sql){if(str_contains($sql,'eh7_mobile_sessions'))return $this->activeSessions;if(str_contains($sql,'eh7_push_devices'))return $this->activePush;return 0;}
}
$wpdb=new StagingSafetyDb();
require_once __DIR__.'/../src/Core/Autoloader.php';
\ExcelHerbal\ERP7\Core\Autoloader::register(__DIR__.'/../src');
$before=\ExcelHerbal\ERP7\Administration\StagingSafety::status();
if(($before['sanitized']??true)!==false){fwrite(STDERR,"FAIL staging_safety_before\n");exit(1);}
$result=\ExcelHerbal\ERP7\Administration\StagingSafety::sanitize();
if(($result['sanitized']??false)!==true||$wpdb->activeSessions!==0||$wpdb->activePush!==0||(string)($options['blog_public']??'1')!=='0'){fwrite(STDERR,"FAIL staging_safety_sanitize\n");exit(1);}
if(($options['eh7_staging_sanitized_source_head']??'')!==EH7_SOURCE_HEAD){fwrite(STDERR,"FAIL staging_safety_source_marker\n");exit(1);}
echo "PASS staging_safety_sanitize_clone_sessions_push_and_indexing\n";
$testHost='office.excelherbal.in';
try{\ExcelHerbal\ERP7\Administration\StagingSafety::sanitize();fwrite(STDERR,"FAIL staging_safety_office_refusal\n");exit(1);}
catch(\RuntimeException $e){if(!str_contains($e->getMessage(),'explicit BUILD/UAT package marker')){fwrite(STDERR,"FAIL staging_safety_office_refusal_message\n");exit(1);}}
echo "PASS staging_safety_refuses_office_host\n";
