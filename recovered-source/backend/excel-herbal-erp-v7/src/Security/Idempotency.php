<?php
namespace ExcelHerbal\ERP7\Security;
use ExcelHerbal\ERP7\Database\Db;
use ExcelHerbal\ERP7\Database\Transaction;
use ExcelHerbal\ERP7\Domain\DomainException;
final class Idempotency{
 public static function run(Actor $a,string $key,string $op,callable $fn):mixed{
  if(trim($key)==='')throw new DomainException('X-Idempotency-Key required.','idempotency_required',400);
  $hash=hash('sha256',$a->companyId.'|'.$a->employeeId.'|'.$op.'|'.$key);
  return Transaction::run(function()use($a,$hash,$op,$fn){
   $db=Db::wpdb();$t=Db::table('idempotency_keys');
   $existing=$db->get_row($db->prepare("SELECT * FROM {$t} WHERE request_hash=%s FOR UPDATE",$hash),ARRAY_A);
   if($existing){
    if($existing['status']==='complete')return json_decode((string)$existing['response_json'],true);
    throw new DomainException('Identical request in progress.','idempotency_in_progress',409);
   }
   $inserted=$db->insert($t,['request_hash'=>$hash,'company_id'=>$a->companyId,'employee_id'=>$a->employeeId,'operation'=>$op,'status'=>'in_progress','created_at'=>Db::now()]);
   if($inserted===false){
    $race=$db->get_row($db->prepare("SELECT * FROM {$t} WHERE request_hash=%s FOR UPDATE",$hash),ARRAY_A);
    if($race){
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
}
