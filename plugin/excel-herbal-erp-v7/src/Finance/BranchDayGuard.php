<?php
namespace ExcelHerbal\ERP7\Finance;
use ExcelHerbal\ERP7\Core\Input;
use ExcelHerbal\ERP7\Database\Db;
use ExcelHerbal\ERP7\Domain\DomainException;
use ExcelHerbal\ERP7\Security\Actor;
final class BranchDayGuard{
 /** Use inside the posting transaction. Hold a shared branch lock so a
  * closing draft cannot be created while an absent closing row is checked.
  * Existing closing rows serialize against close/reopen via their row lock.
  */
 public static function assertOpenForPosting(Actor $a,int $branchId,string $date):void{
  $businessDate=Input::date(substr(trim($date),0,10),'Business date');
  $db=Db::wpdb();
  $branch=$db->get_var($db->prepare("SELECT id FROM ".Db::table('branches')." WHERE company_id=%d AND id=%d LOCK IN SHARE MODE",$a->companyId,$branchId));
  if(!$branch||!empty($db->last_error))throw new DomainException('Branch day lock unavailable. Retry the transaction.','branch_day_lock_failed',409);
  $status=$db->get_var($db->prepare("SELECT status FROM ".Db::table('branch_closings')." WHERE company_id=%d AND branch_id=%d AND business_date=%s LIMIT 1 LOCK IN SHARE MODE",$a->companyId,$branchId,$businessDate));
  if(!empty($db->last_error))throw new DomainException('Unable to verify branch business day.','branch_day_read_failed',500);
  if($status==='closed')throw new DomainException('Branch business day is closed. Reopen it before posting.','branch_day_closed',409);
 }

 public static function assertOpen(Actor $a,int $branchId,string $date):void{$businessDate=Input::date(substr(trim($date),0,10),'Business date');$status=(string)Db::wpdb()->get_var(Db::wpdb()->prepare("SELECT status FROM ".Db::table('branch_closings')." WHERE company_id=%d AND branch_id=%d AND business_date=%s LIMIT 1",$a->companyId,$branchId,$businessDate));if($status==='closed')throw new DomainException('Branch business day is closed. Reopen it before posting.','branch_day_closed',409);}
}
