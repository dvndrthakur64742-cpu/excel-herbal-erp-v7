<?php
define('EH7_SOURCE_HEAD','0123456789abcdef0123456789abcdef01234567');
define('EH7_DEPLOY_ENVIRONMENT','staging');
define('EH7_BUILD_UAT_ALLOW_OFFICE',true);
define('EH7_BUILD_UAT_HOST','office.excelherbal.in');
define('WP_ENVIRONMENT_TYPE','production');

function wp_get_environment_type(){return 'production';}
function home_url($path=''){return 'https://office.excelherbal.in'.$path;}

require_once __DIR__.'/../src/Core/Autoloader.php';
\ExcelHerbal\ERP7\Core\Autoloader::register(__DIR__.'/../src');

use ExcelHerbal\ERP7\Administration\Environment;
use ExcelHerbal\ERP7\Administration\FreshUatBootstrap;

if(Environment::type()!=='staging'){fwrite(STDERR,"FAIL build_uat_environment_override\n");exit(1);}
$hardening=Environment::hostHardeningStatus();
if(
 ($hardening['status']??'')!=='blocked'||
 ($hardening['expected_environment']??'')!=='staging'||
 ($hardening['wp_environment_type']??'')!=='production'||
 ($hardening['wp_environment_type_defined']??null)!==true||
 ($hardening['disallow_file_edit_defined']??null)!==false||
 ($hardening['disallow_file_edit']??null)!==false
){fwrite(STDERR,"FAIL host_hardening_distinguishes_package_marker_from_wp_config\n");exit(1);}
if(Environment::allowsOfficeBuildUat()!==true){fwrite(STDERR,"FAIL build_uat_office_marker\n");exit(1);}
try{Environment::assertSafeUatHost('office.excelherbal.in');}
catch(Throwable $e){fwrite(STDERR,"FAIL build_uat_office_host ".$e->getMessage()."\n");exit(1);}
try{FreshUatBootstrap::assertSafeTarget();}
catch(Throwable $e){fwrite(STDERR,"FAIL build_uat_fresh_guard ".$e->getMessage()."\n");exit(1);}

echo "PASS build_uat_environment_override\n";
echo "PASS host_hardening_distinguishes_package_marker_from_wp_config\n";
echo "PASS build_uat_office_marker\n";
echo "PASS build_uat_fresh_guard\n";

$webAdmin=file_get_contents(__DIR__.'/../src/Administration/UatWebDeployAdmin.php');
$deployScript=file_get_contents(__DIR__.'/../../../.github/scripts/deploy-uat-current-erp-workflow.ps1');
if(
 strpos($webAdmin,"ATTEST_ACTION='eh7_uat_web_attest'")===false||
 strpos($webAdmin,'Installed backend source head does not match the requested web attestation head.')===false||
 strpos($webAdmin,'self::verifyManifest($target);')===false||
 strpos($webAdmin,'hash_equals($expectedMainHash,$actualMain)')===false||
 strpos($webAdmin,'hash_equals($expectedManifestHash,$actualManifest)')===false||
 strpos($deployScript,'Attest-ExistingWebRuntime')===false||
 strpos($deployScript,'expectedManifestHash')===false
){fwrite(STDERR,"FAIL web_runtime_attestation_guard\n");exit(1);}
echo "PASS web_runtime_attestation_guard\n";
