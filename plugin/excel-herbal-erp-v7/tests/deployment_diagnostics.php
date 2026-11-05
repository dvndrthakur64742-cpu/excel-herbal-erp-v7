<?php
/** Read-only runtime environment diagnostic contract. No real WordPress/DB. */
declare(strict_types=1);
define('EH7_SOURCE_HEAD','6c201cde385645ad3748f495d4e8a190544b549c');
$environment='staging';
$siteHost='office.excelherbal.in';
function wp_get_environment_type():string {return $GLOBALS['environment'];}
function home_url($path=''):string {return 'https://'.$GLOBALS['siteHost'].$path;}
require_once __DIR__.'/../src/Core/Autoloader.php';
\ExcelHerbal\ERP7\Core\Autoloader::register(__DIR__.'/../src');
function requireDiagnostic(bool $valid,string $reason):void {
    if(!$valid){fwrite(STDERR,'FAIL: '.$reason."\n");exit(1);}
}
$cls=\ExcelHerbal\ERP7\Administration\DeploymentDiagnostics::class;
$office=$cls::status();
requireDiagnostic($office['office_production_host']===true,'production host must be recognized');
requireDiagnostic($office['office_environment_mismatch']===true,'office host with staging config must warn');
requireDiagnostic($office['configuration_review_required']===true,'office config review flag missing');
requireDiagnostic($office['embedded_source_sha_format_valid']===true,'embedded git SHA misread');
requireDiagnostic($office['staging_source_marker_purpose']==='sanitized_uat_only','marker meaning ambiguous');
$environment='production';
$correct=$cls::status();
requireDiagnostic($correct['office_production_host']===true&&!$correct['office_environment_mismatch'],'real production environment incorrectly flagged');
$environment='staging';
$siteHost='uat.excelherbal.in';
$uat=$cls::status();
requireDiagnostic($uat['office_production_host']===false&&!$uat['configuration_review_required'],'isolated UAT incorrectly flagged');
$source=file_get_contents(__DIR__.'/../src/Administration/DeploymentDiagnostics.php');
$dispatcher=file_get_contents(__DIR__.'/../src/Http/ApiDispatch.php');
requireDiagnostic(str_contains($dispatcher,"'deployment_diagnostics'=>\\ExcelHerbal\\ERP7\\Administration\\DeploymentDiagnostics::status()"),'diagnostics not wired to health');
requireDiagnostic(!preg_match('/\\b(update_option|delete_option|wp_set_password|mustQuery|wpdb|dbDelta|file_put_contents)\\s*\\(/',$source),'diagnostic may write to site');
echo "PASS Office staging-vs-production configuration mismatch diagnosed read-only\n";
echo "PASS source marker distinguished from synthetic staging sanitization\n";
echo "PASS production Office and separate UAT treated correctly\n";
