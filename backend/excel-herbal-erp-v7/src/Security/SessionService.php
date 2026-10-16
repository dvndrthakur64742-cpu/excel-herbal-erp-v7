<?php
namespace ExcelHerbal\ERP7\Security;

use ExcelHerbal\ERP7\Database\Db;
use ExcelHerbal\ERP7\Domain\DomainException;

final class SessionService {
    public static function mine(Actor $a):array {
        Guard::cap($a,Capabilities::ACCESS);
        $db=Db::wpdb();$t=Db::table('mobile_sessions');$now=Db::now();
        $currentHash=self::currentAccessHash();
        $rows=(array)$db->get_results($db->prepare(
            "SELECT id,device_name,device_key,access_expires_at,refresh_expires_at,revoked_at,created_at,last_used_at,access_hash FROM {$t} WHERE employee_id=%d AND wp_user_id=%d ORDER BY id DESC LIMIT 100",
            $a->employeeId,$a->userId
        ),ARRAY_A);
        foreach($rows as &$r){$r['id']=(int)$r['id'];$r['current']=$currentHash!==''&&hash_equals((string)$r['access_hash'],$currentHash);$r['active']=$r['revoked_at']===null&&(string)$r['refresh_expires_at']>$now;$key=trim((string)($r['device_key']??''));$r['device_ref']=$key!==''?substr($key,0,10):'legacy';unset($r['access_hash'],$r['device_key']);}
        unset($r);return $rows;
    }
    public static function revokeMine(Actor $a,int $sessionId):array {
        Guard::cap($a,Capabilities::ACCESS);$db=Db::wpdb();$t=Db::table('mobile_sessions');
        $r=$db->get_row($db->prepare("SELECT id,revoked_at FROM {$t} WHERE id=%d AND employee_id=%d AND wp_user_id=%d",$sessionId,$a->employeeId,$a->userId),ARRAY_A);
        if(!$r)throw new DomainException('Mobile session not found.','session_not_found',404);
        if(!$r['revoked_at'])Db::mustUpdate($db,$t,['revoked_at'=>Db::now()],['id'=>$sessionId]);
        return ['id'=>$sessionId,'revoked'=>true];
    }
    public static function logoutAll(Actor $a):array {
        Guard::cap($a,Capabilities::ACCESS);$db=Db::wpdb();$t=Db::table('mobile_sessions');$now=Db::now();
        $sql=$db->prepare("UPDATE {$t} SET revoked_at=%s WHERE employee_id=%d AND wp_user_id=%d AND revoked_at IS NULL",$now,$a->employeeId,$a->userId);
        return ['revoked'=>Db::mustQuery($db,$sql)];
    }
    private static function currentAccessHash():string {
        $h=(string)($_SERVER['HTTP_AUTHORIZATION']??'');
        return preg_match('/^Bearer\s+(.+)$/i',$h,$m)?hash('sha256',trim((string)$m[1])):'';
    }
}
