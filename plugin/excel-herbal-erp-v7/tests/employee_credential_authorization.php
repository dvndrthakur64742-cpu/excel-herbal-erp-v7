<?php
/** Executable least-privilege test; synthetic WordPress users only. */
require_once __DIR__.'/../src/Core/Autoloader.php';
\ExcelHerbal\ERP7\Core\Autoloader::register(__DIR__.'/../src');
use ExcelHerbal\ERP7\Domain\DomainException;
use ExcelHerbal\ERP7\Organization\OrganizationEmployeeService;
use ExcelHerbal\ERP7\Security\Actor;
use ExcelHerbal\ERP7\Security\Capabilities;

if(!defined('ARRAY_A'))define('ARRAY_A','ARRAY_A');
$GLOBALS['test_users']=[
  1=>(object)['ID'=>1,'roles'=>['administrator']],
  2=>(object)['ID'=>2,'roles'=>['subscriber']],
  3=>(object)['ID'=>3,'roles'=>['editor']],
  4=>(object)['ID'=>4,'roles'=>['subscriber']],
  5=>(object)['ID'=>5,'roles'=>['custom_role']],
];
$GLOBALS['changed_password_for']=[];
function get_user_by($field,$value){return $GLOBALS['test_users'][(int)$value]??false;}
function user_can($user,$cap){
  $u=is_object($user)?$user:get_user_by('id',(int)$user);
  if(!$u)return false;
  return in_array($cap,['manage_options','edit_users','edit_posts','activate_plugins'],true)&&(
    in_array('administrator',$u->roles,true)||($cap==='edit_posts'&&in_array('editor',$u->roles,true))
  );
}
function wp_set_password($password,$uid){$GLOBALS['changed_password_for'][]=$uid;}
function wp_json_encode($v){return json_encode($v);}
function current_time($fmt,$gmt=false){return '2026-10-31 12:00:00';}
final class CredentialSecurityDb{
  public string $prefix='wp_';public string $last_error='';public int $target=1;public array $updates=[];
  public function prepare($q,...$args){return $q;}
  public function get_row($q,$mode){return ['id'=>8,'company_id'=>10,'assigned_branch_id'=>20,'status'=>'active','mobile'=>'9876543210','wp_user_id'=>$this->target,'employee_code'=>'TEST-8','full_name'=>'Synthetic Employee','email'=>''];}
  public function get_var($q){return 0;}
  public function get_results($q,$mode){return [['id'=>8,'mobile'=>'9876543210']];}
  public function update($table,$values,$where){$this->updates[]=$table;return 1;}
  public function insert($table,$values){return 1;}
}
$wpdb=new CredentialSecurityDb();
$manager=new Actor(2,6,10,20,[20],[Capabilities::EMP_MANAGE],'BM');
$admin=new Actor(1,1,10,20,[20],[Capabilities::EMP_MANAGE],'SYSADMIN');
$cases=[
  ['manager_cannot_reset_wp_administrator',$manager,1,'privileged_account_password_protected'],
  ['manager_cannot_reset_wp_editor',$manager,3,'privileged_account_password_protected'],
  ['manager_cannot_reset_custom_wordpress_role',$manager,5,'privileged_account_password_protected'],
  ['manager_can_reset_subscriber',$manager,4,null],
  ['wp_admin_must_reset_wp_admin_via_wordpress',$admin,1,'privileged_account_password_protected'],
];
$failed=0;
foreach($cases as [$label,$actor,$target,$expectedError]){
  $wpdb->target=$target;$wpdb->updates=[];$GLOBALS['changed_password_for']=[];
  try{
    $result=OrganizationEmployeeService::setEmployeeCredentials($actor,8,['password'=>'strong-synthetic-pass-1234']);
    if($expectedError!==null||$GLOBALS['changed_password_for']!==[$target]||!($result['password_updated']??false)||count($wpdb->updates)!==1)throw new RuntimeException('Unexpected credential mutation');
    echo "PASS $label\n";
  }catch(DomainException $e){
    if($e->codeKey!==$expectedError||$GLOBALS['changed_password_for']||$wpdb->updates){$failed++;echo "FAIL $label: {$e->codeKey} / side effect\n";}
    else echo "PASS $label\n";
  }catch(Throwable $e){$failed++;echo "FAIL $label: {$e->getMessage()}\n";}
}
if($failed)exit(1);
