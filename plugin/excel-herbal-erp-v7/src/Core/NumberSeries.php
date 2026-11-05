<?php
namespace ExcelHerbal\ERP7\Core;
use ExcelHerbal\ERP7\Database\Db;
use ExcelHerbal\ERP7\Database\Transaction;
use ExcelHerbal\ERP7\Domain\DomainException;

final class NumberSeries{
 public static function next(int $company,string $key,string $prefix):string{
  $key=trim($key);$prefix=trim($prefix);
  if($company<1||$key===''||$prefix==='')throw new DomainException('Invalid number series request.','number_series_invalid',422);
  return Transaction::run(function()use($company,$key,$prefix){
   $db=Db::wpdb();$t=Db::table('number_series');
   $seeded=$db->query($db->prepare("INSERT INTO {$t}(company_id,series_key,prefix,last_number) VALUES(%d,%s,%s,0) ON DUPLICATE KEY UPDATE id=id",$company,$key,$prefix));
   if($seeded===false)throw new DomainException('Unable to initialize number series.','number_series_store_failed',500);
   $r=$db->get_row($db->prepare("SELECT * FROM {$t} WHERE company_id=%d AND series_key=%s FOR UPDATE",$company,$key),ARRAY_A);
   if(!$r)throw new DomainException('Unable to lock number series.','number_series_lock_failed',500);
   $old=(int)$r['last_number'];$n=$old+1;$effectivePrefix=(string)$r['prefix'];
   $updated=$db->query($db->prepare("UPDATE {$t} SET last_number=%d WHERE id=%d AND last_number=%d",$n,(int)$r['id'],$old));
   if($updated!==1)throw new DomainException('Number series changed concurrently.','number_series_conflict',409);
   return $effectivePrefix.str_pad((string)$n,7,'0',STR_PAD_LEFT);
  });
 }
}
