<?php
namespace ExcelHerbal\ERP7\Security;
use ExcelHerbal\ERP7\Database\Db;
use ExcelHerbal\ERP7\Database\Transaction;
use ExcelHerbal\ERP7\Domain\DomainException;
final class Idempotency{
 public static function run(Actor $a,string $key,string $op,callable $fn,array $payload=[]):mixed{
  if(trim($key)==='')throw new DomainException('X-Idempotency-Key required.','idempotency_required',400);
  $hash=hash('sha256',$a->companyId.'|'.$a->employeeId.'|'.$op.'|'.$key);
  $payloadHash=hash('sha256',self::canonicalJson($payload));
  return Transaction::run(function()use($a,$hash,$payloadHash,$op,$fn){
   $db=Db::wpdb();$t=Db::table('idempotency_keys');
   $existing=$db->get_row($db->prepare("SELECT * FROM {$t} WHERE request_hash=%s FOR UPDATE",$hash),ARRAY_A);
   if($existing){
    if(!empty($existing['payload_hash'])&&!hash_equals((string)$existing['payload_hash'],$payloadHash))throw new DomainException('Idempotency key was already used with a different payload.','idempotency_payload_mismatch',409);
    if(empty($existing['payload_hash'])){
     if($existing['status']==='complete')throw new DomainException('This legacy idempotency key predates payload verification. Retry with a new key.','idempotency_legacy_key',409);
     Db::mustUpdate($db,$t,['payload_hash'=>$payloadHash],['id'=>(int)$existing['id']]);
    }
    if($existing['status']==='complete')return json_decode((string)$existing['response_json'],true);
    throw new DomainException('Identical request in progress.','idempotency_in_progress',409);
   }
   $inserted=$db->insert($t,['request_hash'=>$hash,'company_id'=>$a->companyId,'employee_id'=>$a->employeeId,'operation'=>$op,'payload_hash'=>$payloadHash,'status'=>'in_progress','created_at'=>Db::now()]);
   if($inserted===false){
    $race=$db->get_row($db->prepare("SELECT * FROM {$t} WHERE request_hash=%s FOR UPDATE",$hash),ARRAY_A);
    if($race){
     if(!empty($race['payload_hash'])&&!hash_equals((string)$race['payload_hash'],$payloadHash))throw new DomainException('Idempotency key was already used with a different payload.','idempotency_payload_mismatch',409);
     if(empty($race['payload_hash'])&&$race['status']==='complete')throw new DomainException('This legacy idempotency key predates payload verification. Retry with a new key.','idempotency_legacy_key',409);
     if($race['status']==='complete')return json_decode((string)$race['response_json'],true);
     throw new DomainException('Identical request in progress.','idempotency_in_progress',409);
    }
    throw new DomainException('Unable to reserve idempotency key.','idempotency_store_failed',500);
   }
   $out=$fn();
   $updated=$db->update($t,['status'=>'complete','response_json'=>wp_json_encode($out),'completed_at'=>Db::now()],['request_hash'=>$hash]);
   if($updated===false)throw new DomainException('Unable to persist idempotent response.','idempotency_store_failed',500);
   return$out;
  });
 }
 private static function canonicalJson(array $payload):string{self::sortRecursive($payload);return (string)wp_json_encode($payload,JSON_UNESCAPED_SLASHES|JSON_UNESCAPED_UNICODE);}
 private static function sortRecursive(array &$value):void{foreach($value as &$v)if(is_array($v))self::sortRecursive($v);unset($v);if(array_keys($value)!==range(0,count($value)-1))ksort($value);}
}

