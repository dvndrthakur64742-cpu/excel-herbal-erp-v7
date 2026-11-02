<?php
/** Standalone new-user identity tests. Synthetic data only; no WordPress connection. */
require_once __DIR__.'/../src/Core/Autoloader.php';
\ExcelHerbal\ERP7\Core\Autoloader::register(__DIR__.'/../src');

use ExcelHerbal\ERP7\Domain\DomainException;
use ExcelHerbal\ERP7\Organization\OrganizationEmployeeService;

$GLOBALS['fake_usernames'] = [];
$GLOBALS['fake_emails'] = [];
$GLOBALS['inserted_wp_users'] = [];

function username_exists($login) {return isset($GLOBALS['fake_usernames'][$login]) ? $GLOBALS['fake_usernames'][$login] : false;}
function email_exists($email) {return isset($GLOBALS['fake_emails'][$email]) ? $GLOBALS['fake_emails'][$email] : false;}
function wp_insert_user($data) {
    $GLOBALS['inserted_wp_users'][]=$data;
    return 317 + count($GLOBALS['inserted_wp_users']);
}
function is_wp_error($value) {return false;}

$method=(new ReflectionClass(OrganizationEmployeeService::class))->getMethod('createWordPressUser');
$checks=0;
function verifyUsername(bool $truth,string $label):void {
    global $checks;
    if(!$truth)throw new RuntimeException('FAIL '.$label);
    $checks++;
    echo 'PASS '.$label.PHP_EOL;
}
function blockedUsername(callable $operation,string $expected):void {
    try {$operation();}
    catch(DomainException $e){verifyUsername($e->codeKey===$expected,'denied '.$expected);return;}
    throw new RuntimeException('Expected error '.$expected);
}

$first=$method->invoke(null,1,'SYN-101','Synthetic Person','','synthetic-test-password','9000000011');
verifyUsername($first===318,'synthetic WP identity was created');
verifyUsername($GLOBALS['inserted_wp_users'][0]['user_login']==='9000000011','new username equals mobile');
verifyUsername($GLOBALS['inserted_wp_users'][0]['role']==='subscriber','new user is a subscriber');

$second=$method->invoke(null,1,'SYN-102','Synthetic Person Two','','synthetic-test-password','+91 90000 00012');
verifyUsername($second===319,'second synthetic WP identity created');
verifyUsername($GLOBALS['inserted_wp_users'][1]['user_login']==='919000000012','phone is normalized consistently');
verifyUsername(!str_starts_with($GLOBALS['inserted_wp_users'][1]['user_login'],'eh7_'),'legacy username prefix is not used');

$before=count($GLOBALS['inserted_wp_users']);
$GLOBALS['fake_usernames']['9000000011']=24; // Existing WordPress owner must never be silently adopted.
blockedUsername(fn()=>$method->invoke(null,1,'SYN-103','Synthetic Person Three','','synthetic-test-password','9000000011'),'wp_mobile_username_in_use');
blockedUsername(fn()=>$method->invoke(null,1,'SYN-104','Synthetic Person Four','','synthetic-test-password','1234567'),'mobile_invalid');
verifyUsername(count($GLOBALS['inserted_wp_users'])===$before,'collision and invalid inputs have no WP account side effects');
echo 'PASSED '.$checks.' synthetic mobile-username assertions'.PHP_EOL;
