<?php
// Synthetic only: checks each status without connecting to WordPress or using employee PII.
require_once __DIR__.'/../src/Core/Autoloader.php';
\ExcelHerbal\ERP7\Core\Autoloader::register(__DIR__.'/../src');

use ExcelHerbal\ERP7\Organization\EmployeeLoginPreflight;

function preflightCheck(bool $ok,string $label):void {
    if(!$ok)throw new RuntimeException('FAIL '.$label);
    echo 'PASS '.$label.PHP_EOL;
}
function preflight(string $status,int $wpId,bool $exists,bool $privileged,string $mobile,bool $userTaken=false,bool $emailTaken=false):array {
    return EmployeeLoginPreflight::assess($status,$wpId,$exists,$privileged,$mobile,$userTaken,$emailTaken);
}
$ok=preflight('active',41,true,false,'9000000011');
preflightCheck($ok['identity_state']==='linked' && $ok['can_reset_subscriber_password'] && !$ok['new_subscriber_candidate'],'valid subscriber can be offered manual credential reset');
preflightCheck($ok['identity_owner_verification_required']===true,'even valid subscriber requires owner verification');

$broken=preflight('active',86,false,false,'9000000012');
preflightCheck($broken['identity_state']==='broken' && $broken['new_subscriber_candidate'],'orphaned WP ID is a provisioning candidate, not auto-repaired');
preflightCheck($broken['identity_owner_verification_required']===true,'broken link must be verified before provisioning');

$unlinked=preflight('active',0,false,false,'9000000013');
preflightCheck($unlinked['identity_state']==='unlinked' && $unlinked['new_subscriber_candidate'],'unlinked active employee classified separately');

$collision=preflight('active',0,false,false,'9000000013',true);
preflightCheck($collision['new_subscriber_candidate']===false && in_array('mobile_username_claimed',$collision['blockers'],true),'existing WP username blocks silent linking');

$emailCollision=preflight('active',0,false,false,'9000000014',false,true);
preflightCheck(!$emailCollision['new_subscriber_candidate'] && in_array('employee_email_claimed',$emailCollision['blockers'],true),'existing WP email blocks provisioning');

$admin=preflight('active',17,true,true,'9000000015');
preflightCheck($admin['identity_state']==='linked' && !$admin['can_reset_subscriber_password'] && in_array('privileged_wordpress_identity',$admin['blockers'],true),'privileged WP account cannot be reset through ERP');

$inactive=preflight('inactive',41,true,false,'9000000016');
preflightCheck(!$inactive['can_reset_subscriber_password'] && in_array('employee_inactive',$inactive['blockers'],true),'inactive employee login maintenance disabled');

$badMobile=preflight('active',0,false,false,'7');
preflightCheck(!$badMobile['mobile_valid'] && !$badMobile['new_subscriber_candidate'],'invalid mobile is not a provisioning candidate');

$source=file_get_contents(__DIR__.'/../src/Organization/OrganizationEmployeeService.php');
preflightCheck(str_contains($source,'EmployeeLoginPreflight::assess(')&&str_contains($source,"'repair_preflight'=>"),'existing login status endpoint returns read-only preflight');
echo "PASSED employee login repair preflight\n";
