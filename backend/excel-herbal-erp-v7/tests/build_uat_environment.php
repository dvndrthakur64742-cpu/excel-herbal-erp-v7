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
if(Environment::allowsOfficeBuildUat()!==true){fwrite(STDERR,"FAIL build_uat_office_marker\n");exit(1);}
try{Environment::assertSafeUatHost('office.excelherbal.in');}
catch(Throwable $e){fwrite(STDERR,"FAIL build_uat_office_host ".$e->getMessage()."\n");exit(1);}
try{FreshUatBootstrap::assertSafeTarget();}
catch(Throwable $e){fwrite(STDERR,"FAIL build_uat_fresh_guard ".$e->getMessage()."\n");exit(1);}

echo "PASS build_uat_environment_override\n";
echo "PASS build_uat_office_marker\n";
echo "PASS build_uat_fresh_guard\n";
