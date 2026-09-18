<?php
namespace ExcelHerbal\ERP7\Security;
use ExcelHerbal\ERP7\Database\Db;
use ExcelHerbal\ERP7\Database\Transaction;
use ExcelHerbal\ERP7\Domain\DomainException;

final class MobileAuth{
 private const ACCESS_TTL=3600;
 private const REFRESH_TTL=2592000;
 private const LOGIN_WINDOW=900;
 private const LOGIN_MAX_MOBILE_IP=8;
 private const LOGIN_MAX_MOBILE=20;

 public static function boot():void{add_filter('determine_current_user',[self::class,'user'],20);}

 public static function user($current){
  if($current)return$current;
  $h=self::authorizationHeader();
  if(!preg_match('/^Bearer\s+(.+)$/i',$h,$m))return$current;
  $hash=hash('sha256',trim($m[1]));$db=Db::wpdb();$t=Db::table('mobile_sessions');$e=Db::table('employees');$now=gmdate('Y-m-d H:i:s');
  $row=$db->get_row($db->prepare("SELECT s.id,s.wp_user_id FROM {$t} s JOIN {$e} e ON e.id=s.employee_id AND e.wp_user_id=s.wp_user_id AND e.status='active' WHERE s.access_hash=%s AND s.revoked_at IS NULL AND s.access_expires_at>%s LIMIT 1",$hash,$now),ARRAY_A);
  if(!$row)return$current;
  $updated=$db->update($t,['last_used_at'=>$now],['id'=>(int)$row['id']]);
  if($updated===false)error_log('EH7 mobile session last_used_at update failed for session '.(int)$row['id']);
  return(int)$row['wp_user_id'];
 }

 public static function login(string $mobile,string $password,string $device='',string $deviceId=''):array{
  $mobile=self::normaliseMobile($mobile);
  if($mobile===''||$password==='')throw new DomainException('Mobile number and password are required.','credentials_required',422);
  self::assertLoginAllowed($mobile);
  $db=Db::wpdb();$e=Db::table('employees');
  $candidates=(array)$db->get_results("SELECT id,wp_user_id,mobile FROM {$e} WHERE status='active' AND wp_user_id IS NOT NULL AND mobile IS NOT NULL",ARRAY_A);
  $rows=[];foreach($candidates as$c){if(self::normaliseMobile((string)$c['mobile'])===$mobile)$rows[]=$c;}
  if(count($rows)!==1){self::recordLoginFailure($mobile);throw new DomainException('Invalid login credentials.','invalid_credentials',401);}
  $emp=$rows[0];$uid=(int)$emp['wp_user_id'];
  if($uid<1){self::recordLoginFailure($mobile);throw new DomainException('Invalid login credentials.','invalid_credentials',401);}
  $u=get_user_by('id',$uid);
  if(!$u||!wp_check_password($password,$u->user_pass,(int)$u->ID)){self::recordLoginFailure($mobile);throw new DomainException('Invalid login credentials.','invalid_credentials',401);}
  self::clearLoginFailures($mobile);
  return self::issue((int)$u->ID,(int)$emp['id'],$device,self::deviceKey($deviceId));
 }

 public static function refresh(string $refresh,string $device='',string $deviceId=''):array{
  if(trim($refresh)==='')throw new DomainException('Refresh token required.','refresh_required',422);
  return Transaction::run(function()use($refresh,$device,$deviceId){
   $db=Db::wpdb();$t=Db::table('mobile_sessions');$e=Db::table('employees');$hash=hash('sha256',$refresh);$now=gmdate('Y-m-d H:i:s');
   $r=$db->get_row($db->prepare("SELECT s.* FROM {$t} s JOIN {$e} e ON e.id=s.employee_id AND e.wp_user_id=s.wp_user_id AND e.status='active' WHERE s.refresh_hash=%s AND s.revoked_at IS NULL AND s.refresh_expires_at>%s LIMIT 1 FOR UPDATE",$hash,$now),ARRAY_A);
   if(!$r)throw new DomainException('Refresh token invalid or expired.','refresh_invalid',401);
   $updated=$db->update($t,['revoked_at'=>$now],['id'=>(int)$r['id']]);if($updated===false)throw new DomainException('Refresh rotation failed.','refresh_revoke_failed',500);
   $key=self::deviceKey($deviceId);if($key===null&&isset($r['device_key'])&&trim((string)$r['device_key'])!=='')$key=(string)$r['device_key'];
   return self::issue((int)$r['wp_user_id'],(int)$r['employee_id'],$device?:($r['device_name']??''),$key);
  });
 }

 public static function logout():array{
  $h=self::authorizationHeader();
  if(preg_match('/^Bearer\s+(.+)$/i',$h,$m)){
   $updated=Db::wpdb()->update(Db::table('mobile_sessions'),['revoked_at'=>gmdate('Y-m-d H:i:s')],['access_hash'=>hash('sha256',trim($m[1]))]);
   if($updated===false)throw new DomainException('Logout could not revoke the mobile session.','logout_revoke_failed',500);
  }
  return['logged_out'=>true];
 }

 private static function issue(int $uid,int $eid,string $device,?string $deviceKey):array{
  $db=Db::wpdb();$sessions=Db::table('mobile_sessions');
  $valid=(int)$db->get_var($db->prepare("SELECT COUNT(*) FROM ".Db::table('employees')." WHERE id=%d AND wp_user_id=%d AND status='active'",$eid,$uid));if($valid!==1)throw new DomainException('Active employee login identity is required.','employee_login_inactive',403);
  $deviceName=substr(trim($device),0,190);$now=time();$nowSql=gmdate('Y-m-d H:i:s',$now);
  if($deviceKey!==null){
   $sql=$db->prepare("UPDATE {$sessions} SET revoked_at=%s WHERE employee_id=%d AND wp_user_id=%d AND revoked_at IS NULL AND (device_key=%s OR (device_key IS NULL AND device_name=%s))",$nowSql,$eid,$uid,$deviceKey,$deviceName);
   Db::mustQuery($db,$sql);
  }
  $access=bin2hex(random_bytes(32));$refresh=bin2hex(random_bytes(48));
  Db::mustInsert($db,$sessions,[
   'wp_user_id'=>$uid,'employee_id'=>$eid,'access_hash'=>hash('sha256',$access),'refresh_hash'=>hash('sha256',$refresh),
   'access_expires_at'=>gmdate('Y-m-d H:i:s',$now+self::ACCESS_TTL),'refresh_expires_at'=>gmdate('Y-m-d H:i:s',$now+self::REFRESH_TTL),
   'device_name'=>$deviceName,'device_key'=>$deviceKey,'created_at'=>$nowSql
  ]);
  if(!$db->insert_id)throw new DomainException('Unable to create mobile session.','session_create_failed',500);
  return['access_token'=>$access,'refresh_token'=>$refresh,'token_type'=>'Bearer','expires_in'=>self::ACCESS_TTL];
 }

 private static function authorizationHeader():string{
  foreach(['HTTP_AUTHORIZATION','REDIRECT_HTTP_AUTHORIZATION','Authorization'] as$key){$value=trim((string)($_SERVER[$key]??''));if($value!=='')return$value;}
  if(function_exists('getallheaders')){foreach((array)getallheaders() as$name=>$value)if(strcasecmp((string)$name,'Authorization')===0&&trim((string)$value)!=='')return trim((string)$value);}
  return'';
 }
 private static function deviceKey(string $deviceId):?string{$deviceId=trim($deviceId);if($deviceId==='')return null;if(strlen($deviceId)>190)throw new DomainException('Device identity is invalid.','device_identity_invalid',422);return hash('sha256',$deviceId);}
 private static function normaliseMobile(string $mobile):string{return preg_replace('/\D+/','',$mobile)?:'';}
 private static function clientIp():string{return substr((string)($_SERVER['REMOTE_ADDR']??'unknown'),0,64);}
 private static function mobileIpKey(string $mobile):string{return 'eh7_li_'.substr(hash('sha256',$mobile.'|'.self::clientIp()),0,40);}
 private static function mobileKey(string $mobile):string{return 'eh7_lm_'.substr(hash('sha256',$mobile),0,40);}
 private static function attempts(string $key):int{$v=get_transient($key);return is_numeric($v)?(int)$v:0;}
 private static function assertLoginAllowed(string $mobile):void{
  if(self::attempts(self::mobileIpKey($mobile))>=self::LOGIN_MAX_MOBILE_IP||self::attempts(self::mobileKey($mobile))>=self::LOGIN_MAX_MOBILE){
   throw new DomainException('Too many login attempts. Please try again after 15 minutes.','login_rate_limited',429);
  }
 }
 private static function recordLoginFailure(string $mobile):void{
  $ipKey=self::mobileIpKey($mobile);$mobileKey=self::mobileKey($mobile);
  set_transient($ipKey,self::attempts($ipKey)+1,self::LOGIN_WINDOW);
  set_transient($mobileKey,self::attempts($mobileKey)+1,self::LOGIN_WINDOW);
 }
 private static function clearLoginFailures(string $mobile):void{delete_transient(self::mobileIpKey($mobile));delete_transient(self::mobileKey($mobile));}
}
