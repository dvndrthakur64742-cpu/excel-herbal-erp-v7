<?php
namespace ExcelHerbal\ERP7\Finance;
use ExcelHerbal\ERP7\Database\Db;
use ExcelHerbal\ERP7\Domain\DomainException;
use ExcelHerbal\ERP7\Security\Actor;
final class BranchDayGuard{
 public static function assertOpen(Actor $a,int $branchId,string $date):void{$status=(string)Db::wpdb()->get_var(Db::wpdb()->prepare("SELECT status FROM ".Db::table('branch_closings')." WHERE company_id=%d AND branch_id=%d AND business_date=%s LIMIT 1",$a->companyId,$branchId,substr($date,0,10)));if($status==='closed')throw new DomainException('Branch business day is closed. Reopen it before posting.','branch_day_closed',409);}
}
