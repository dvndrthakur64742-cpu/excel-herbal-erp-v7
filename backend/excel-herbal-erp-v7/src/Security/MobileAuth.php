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
 private const ACCESS_COOKIE='eh7_access_v1';
 private const REFRESH_COOKIE='eh7_refresh_v1';
 private const COOKIE_PATH='/wp-json/excel-herbal-erp/v7/';

 public static function boot():void{
  add_filter('determine_current_user',[self::class,'user'],20);
  // WordPress REST exposes request headers reliably here even on hosts where
  // Apache/FastCGI does not populate HTTP_AUTHORIZATION consistently.
  add_filter('rest_pre_dispatch',[self::class,'restUser'],5,3);
 }

 public static function user($current){
  if($current)return$current;
  $uid=self::resolveAccessUser(self::accessTokens());
  return$uid>0?$uid:$current;
 }

 public static function restUser($result,$server,$request){
  $route=method_exists($request,'get_route')?(string)$request->get_route():'';
  if(!str_starts_with($route,'/excel-herbal-erp/v7/'))return$result;
  if(get_current_user_id()>0)return$result;

  $tokens=[];
  foreach(['authorization','x-eh7-authorization'] as$name){
   $header=method_exists($request,'get_header')?trim((string)$request->get_header($name)):'';
   if(preg_match('/^Bearer\s+(.+)$/i',$header,$m)){
    $token=trim((string)$m[1]);
    if($token!==''&&!in_array($token,$tokens,true))$tokens[]=$token;
   }
  }
  $cookie=trim((string)($_COOKIE[self::ACCESS_COOKIE]??''));
  if($cookie!==''&&!in_array($cookie,$tokens,true))$tokens[]=$cookie;

  $uid=self::resolveAccessUser($tokens);
  if($uid>0)wp_set_current_user($uid);
  return$result;
 }

 private static function resolveAccessUser(array $tokens):int{
  if(!$tokens)return 0;
  $db=Db::wpdb();$t=Db::table('mobile_sessions');$e=Db::table('employees');$now=gmdate('Y-m-d H:i:s');
  foreach($tokens as$token){
   $hash=hash('sha256',trim((string)$token));
   $row=$db->get_row($db->prepare("SELECT s.id,s.wp_user_id FROM {$t} s JOIN {$e} e ON e.id=s.employee_id AND e.wp_user_id=s.wp_user_id AND e.status='active' WHERE s.access_hash=%s AND s.revoked_at IS NULL AND s.access_expires_at>%s LIMIT 1",$hash,$now),ARRAY_A);
   if(!$row)continue;
   $updated=$db->update($t,['last_used_at'=>$now],['id'=>(int)$row['id']]);
   if($updated===false)error_log('EH7 mobile session last_used_at update failed for session '.(int)$row['id']);
   return(int)$row['wp_user_id'];
  }
  return 0;
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
  $candidates=[];$provided=trim($refresh);if($provided!=='')$candidates[]=$provided;
  $cookie=self::refreshCookie();if($cookie!==''&&!in_array($cookie,$candidates,true))$candidates[]=$cookie;
  if(!$candidates)throw new DomainException('Refresh token required.','refresh_required',422);
  return Transaction::run(function()use($candidates,$device,$deviceId){
   $db=Db::wpdb();$t=Db::table('mobile_sessions');$e=Db::table('employees');$now=gmdate('Y-m-d H:i:s');$r=null;
   foreach($candidates as$token){
    $hash=hash('sha256',$token);
    $r=$db->get_row($db->prepare("SELECT s.* FROM {$t} s JOIN {$e} e ON e.id=s.employee_id AND e.wp_user_id=s.wp_user_id AND e.status='active' WHERE s.refresh_hash=%s AND s.revoked_at IS NULL AND s.refresh_expires_at>%s LIMIT 1 FOR UPDATE",$hash,$now),ARRAY_A);
    if($r)break;
   }
   if(!$r)throw new DomainException('Refresh token invalid or expired.','refresh_invalid',401);
   $updated=$db->update($t,['revoked_at'=>$now],['id'=>(int)$r['id']]);if($updated===false)throw new DomainException('Refresh rotation failed.','refresh_revoke_failed',500);
   $key=self::deviceKey($deviceId);if($key===null&&isset($r['device_key'])&&trim((string)$r['device_key'])!=='')$key=(string)$r['device_key'];
   return self::issue((int)$r['wp_user_id'],(int)$r['employee_id'],$device?:($r['device_name']??''),$key);
  });
 }

 public static function logout():array{
  $db=Db::wpdb();$table=Db::table('mobile_sessions');$now=gmdate('Y-m-d H:i:s');
  foreach(self::accessTokens() as$token){
   $updated=$db->update($table,['revoked_at'=>$now],['access_hash'=>hash('sha256',$token)]);
   if($updated===false)throw new DomainException('Logout could not revoke the mobile session.','logout_revoke_failed',500);
  }
  self::clearAuthCookies();
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
  self::setAuthCookies($access,$refresh,$now);
  return['access_token'=>$access,'refresh_token'=>$refresh,'token_type'=>'Bearer','expires_in'=>self::ACCESS_TTL];
 }

 private static function authorizationHeader():string{
  foreach(['HTTP_AUTHORIZATION','REDIRECT_HTTP_AUTHORIZATION','Authorization','HTTP_X_EH7_AUTHORIZATION'] as$key){$value=trim((string)($_SERVER[$key]??''));if($value!=='')return$value;}
  if(function_exists('getallheaders')){foreach((array)getallheaders() as$name=>$value)if(in_array(strtolower((string)$name),['authorization','x-eh7-authorization'],true)&&trim((string)$value)!=='')return trim((string)$value);}
  return'';
 }
 private static function accessTokens():array{
  $tokens=[];$h=self::authorizationHeader();
  if(preg_match('/^Bearer\s+(.+)$/i',$h,$m)){$token=trim((string)$m[1]);if($token!=='')$tokens[]=$token;}
  if(self::isErpRestRequest()){
   $cookie=trim((string)($_COOKIE[self::ACCESS_COOKIE]??''));
   if($cookie!==''&&!in_array($cookie,$tokens,true))$tokens[]=$cookie;
  }
  return$tokens;
 }
 private static function refreshCookie():string{
  if(!self::isErpRestRequest())return'';
  return trim((string)($_COOKIE[self::REFRESH_COOKIE]??''));
 }
 private static function isErpRestRequest():bool{
  $uri=(string)($_SERVER['REQUEST_URI']??'');
  if(str_contains($uri,self::COOKIE_PATH))return true;
  $route=trim((string)($_GET['rest_route']??''));
  return str_starts_with($route,'/excel-herbal-erp/v7/');
 }
 private static function setAuthCookies(string $access,string $refresh,int $issuedAt):void{
  if(headers_sent())return;
  $secure=function_exists('is_ssl')?is_ssl():true;
  setcookie(self::ACCESS_COOKIE,$access,['expires'=>$issuedAt+self::ACCESS_TTL,'path'=>self::COOKIE_PATH,'secure'=>$secure,'httponly'=>true,'samesite'=>'Strict']);
  setcookie(self::REFRESH_COOKIE,$refresh,['expires'=>$issuedAt+self::REFRESH_TTL,'path'=>self::COOKIE_PATH,'secure'=>$secure,'httponly'=>true,'samesite'=>'Strict']);
 }
 private static function clearAuthCookies():void{
  if(headers_sent())return;
  $secure=function_exists('is_ssl')?is_ssl():true;$expired=time()-3600;
  setcookie(self::ACCESS_COOKIE,'',['expires'=>$expired,'path'=>self::COOKIE_PATH,'secure'=>$secure,'httponly'=>true,'samesite'=>'Strict']);
  setcookie(self::REFRESH_COOKIE,'',['expires'=>$expired,'path'=>self::COOKIE_PATH,'secure'=>$secure,'httponly'=>true,'samesite'=>'Strict']);
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
