<?php
/** Synthetic regression: bearer headers and WordPress cookie coexistence. */
require_once __DIR__.'/../src/Core/Autoloader.php';
\ExcelHerbal\ERP7\Core\Autoloader::register(__DIR__.'/../src');
use ExcelHerbal\ERP7\Security\MobileAuth;
define('ARRAY_A','ARRAY_A');
define('REST_REQUEST',true);
class WP_Error { public function __construct(public string $code, public string $message, public array $data=[]) {} }
function is_wp_error($v){return $v instanceof WP_Error;}
function wp_set_current_user($id){$GLOBALS['test_uid']=$id;}
function add_filter($hook,$callback,$priority=10){$GLOBALS['hooks'][$hook]=[$callback,$priority];}
$GLOBALS['wp']=(object)['query_vars'=>['rest_route'=>'/excel-herbal-erp/v7/bootstrap']];
$GLOBALS['wpdb']=new class {
 public string $prefix='test_';
 public array $args=[];
 public function prepare($sql,...$args){$this->args=$args;return $sql;}
 public function get_row($sql,$format){return ($this->args[0]??'')===hash('sha256','synthetic-valid-token')?['id'=>1,'wp_user_id'=>23]:null;}
 public function update($table,$data,$where){return 1;}
};
function verify($ok,$label){if(!$ok)throw new RuntimeException('FAIL '.$label);echo "PASS $label\n";}
$_SERVER=['HTTP_X_EH7_AUTHORIZATION'=>'Bearer synthetic-valid-token'];
verify(MobileAuth::user(0)===23,'fallback header validates ERP session');
$_SERVER['HTTP_AUTHORIZATION']='Bearer invalid';
verify(MobileAuth::user(0)===0,'explicit invalid standard header cannot fall back');
MobileAuth::boot();
verify(($GLOBALS['hooks']['rest_authentication_errors'][1]??0)===90,'REST hook runs before cookie nonce check');
$check=$GLOBALS['hooks']['rest_authentication_errors'][0];
$_SERVER=['HTTP_AUTHORIZATION'=>'Bearer synthetic-valid-token'];
$GLOBALS['test_uid']=99;
verify($check(null)===true && $GLOBALS['test_uid']===23,'valid bearer selects its employee despite another WordPress cookie');
$_SERVER=['HTTP_AUTHORIZATION'=>'Bearer expired-or-revoked'];
$GLOBALS['test_uid']=99;
$result=$check(null);
verify($result instanceof WP_Error && $result->data['status']===401 && $GLOBALS['test_uid']===0,'invalid bearer cannot inherit cookie identity');
$_SERVER=[];
$GLOBALS['test_uid']=99;
verify($check(null)===null && $GLOBALS['test_uid']===99,'cookie-only authentication remains with WordPress nonce checks');
$_SERVER=['HTTP_AUTHORIZATION'=>'Basic synthetic'];
verify($check(null)===null,'application-password authentication unchanged');
$_SERVER=['HTTP_AUTHORIZATION'=>'Bearer synthetic-valid-token'];
$GLOBALS['wp']->query_vars['rest_route']='/wp/v2/users/me';
verify($check(null)===null,'unrelated WordPress REST namespaces unchanged');
$GLOBALS['wp']->query_vars['rest_route']='/excel-herbal-erp/v70/bootstrap';
verify($check(null)===null,'namespace prefix collision excluded');
$GLOBALS['wp']->query_vars['rest_route']='/excel-herbal-erp/v7/bootstrap';
$prior=new WP_Error('prior','Prior authentication failure',['status'=>403]);
verify($check($prior)===$prior,'prior authentication errors preserved');
echo "Mobile REST auth regressions passed.\n";
