<?php
namespace ExcelHerbal\ERP7\Finance;
use ExcelHerbal\ERP7\Core\Input;use ExcelHerbal\ERP7\Database\Db;use ExcelHerbal\ERP7\Database\Transaction;use ExcelHerbal\ERP7\Domain\DomainException;use ExcelHerbal\ERP7\Inventory\StockService;use ExcelHerbal\ERP7\Security\Actor;use ExcelHerbal\ERP7\Security\Audit;use ExcelHerbal\ERP7\Security\Capabilities;use ExcelHerbal\ERP7\Security\Guard;
final class FinancePeriodService{
 public static function periods(Actor $a):array{Guard::allActiveBranches($a,Capabilities::PERIOD_MANAGE);$db=Db::wpdb();return(array)$db->get_results($db->prepare("SELECT * FROM ".Db::table('accounting_periods')." WHERE company_id=%d ORDER BY period_end DESC,id DESC LIMIT 100",$a->companyId),ARRAY_A);}
 public static function closePeriod(Actor $a,string $from,string $to):array{
  Guard::allActiveBranches($a,Capabilities::PERIOD_MANAGE);
  [$from,$to]=Input::dateRange($from,$to,'Accounting period');
  return Transaction::run(function()use($a,$from,$to){
   $db=Db::wpdb();$periods=Db::table('accounting_periods');
   $existing=$db->get_row($db->prepare("SELECT * FROM {$periods} WHERE company_id=%d AND period_start=%s AND period_end=%s FOR UPDATE",$a->companyId,$from,$to),ARRAY_A);
   $overlap=(int)$db->get_var($db->prepare("SELECT COUNT(*) FROM {$periods} WHERE company_id=%d AND status='closed' AND NOT(period_start=%s AND period_end=%s) AND NOT(period_end<%s OR period_start>%s)",$a->companyId,$from,$to,$from,$to));
   if($overlap)throw new DomainException('Period overlaps existing close.','period_overlap',409);
   $openDaily=(int)$db->get_var($db->prepare("SELECT COUNT(*) FROM ".Db::table('daily_cycles')." WHERE company_id=%d AND business_date BETWEEN %s AND %s AND status NOT IN ('completed','cancelled')",$a->companyId,$from,$to));
   $pendingExpenses=(int)$db->get_var($db->prepare("SELECT COUNT(*) FROM ".Db::table('expenses')." WHERE company_id=%d AND expense_date BETWEEN %s AND %s AND status='pending'",$a->companyId,$from,$to));
   $pendingAdjustments=(int)$db->get_var($db->prepare("SELECT COUNT(*) FROM ".Db::table('stock_adjustments')." WHERE company_id=%d AND status='pending' AND DATE(created_at)<=%s",$a->companyId,$to));
   $pendingReversals=(int)$db->get_var($db->prepare("SELECT COUNT(*) FROM ".Db::table('reversals')." WHERE company_id=%d AND status IN ('pending','approved') AND DATE(requested_at)<=%s",$a->companyId,$to));
   $draftPayroll=(int)$db->get_var($db->prepare("SELECT COUNT(*) FROM ".Db::table('payroll_runs')." WHERE company_id=%d AND status='draft' AND period_end<=%s",$a->companyId,$to));
   $branches=Db::table('branches');$closings=Db::table('branch_closings');$daily=Db::table('daily_cycles');$journals=Db::table('journal_entries');
   $missingClosings=(array)$db->get_results($db->prepare(
    "SELECT x.branch_id,b.name branch_name,x.business_date
     FROM (
       SELECT branch_id,business_date FROM {$daily} WHERE company_id=%d AND business_date BETWEEN %s AND %s
       UNION
       SELECT branch_id,DATE(entry_date) business_date FROM {$journals} WHERE company_id=%d AND branch_id IS NOT NULL AND status='posted' AND DATE(entry_date) BETWEEN %s AND %s
       UNION
       SELECT id branch_id,%s business_date FROM {$branches} WHERE company_id=%d AND status='active'
     ) x
     JOIN {$branches} b ON b.id=x.branch_id AND b.company_id=%d AND b.status='active'
     LEFT JOIN {$closings} c ON c.company_id=%d AND c.branch_id=x.branch_id AND c.business_date=x.business_date AND c.status='closed'
     WHERE c.id IS NULL
     ORDER BY x.business_date,b.name",
    $a->companyId,$from,$to,$a->companyId,$from,$to,$to,$a->companyId,$a->companyId,$a->companyId
   ),ARRAY_A);
   $blocking=[];
   if($openDaily)$blocking[]='open_daily_cycles';
   if($pendingExpenses)$blocking[]='pending_expenses';
   if($pendingAdjustments)$blocking[]='pending_stock_adjustments';
   if($pendingReversals)$blocking[]='pending_reversals';
   if($draftPayroll)$blocking[]='draft_payroll';
   if($missingClosings){$refs=[];foreach(array_slice($missingClosings,0,20) as $m)$refs[]=$m['business_date'].' '.$m['branch_name'];$suffix=count($missingClosings)>20?' ...':'';$blocking[]='missing_branch_closings('.count($missingClosings).'): '.implode(', ',$refs).$suffix;}
   if($blocking)throw new DomainException('Accounting Period close blocked: '.implode('; ',$blocking),'period_close_blocked',409);
   $data=['status'=>'closed','closed_by'=>$a->employeeId,'closed_at'=>Db::now(),'reopened_by'=>null,'reopened_at'=>null];
   if($existing){if($existing['status']==='closed')return['id'=>(int)$existing['id'],'status'=>'closed'];Db::mustUpdate($db,$periods,$data,['id'=>(int)$existing['id']]);$id=(int)$existing['id'];}
   else{Db::mustInsert($db,$periods,['company_id'=>$a->companyId,'period_start'=>$from,'period_end'=>$to]+$data);if(!$db->insert_id)throw new DomainException('Accounting period could not be created.','period_create_failed',500);$id=(int)$db->insert_id;}
   Audit::add($a,'accounting_period.close','accounting_period',$id,['from'=>$from,'to'=>$to,'required_closings_verified'=>true]);
   return['id'=>$id,'status'=>'closed'];
  });
 }
 public static function reopenPeriod(Actor $a,int $id,string $reason):array{Guard::allActiveBranches($a,Capabilities::PERIOD_MANAGE);$reason=trim($reason);if(strlen($reason)<5)throw new DomainException('Reason required.');return Transaction::run(function()use($a,$id,$reason){$db=Db::wpdb();$t=Db::table('accounting_periods');$r=$db->get_row($db->prepare("SELECT * FROM {$t} WHERE id=%d AND company_id=%d FOR UPDATE",$id,$a->companyId),ARRAY_A);if(!$r)throw new DomainException('Accounting period not found.','period_not_found',404);if($r['status']!=='closed')throw new DomainException('Only a closed accounting period can be reopened.','period_state_invalid',409);Db::mustUpdate($db,$t,['status'=>'open','reopened_by'=>$a->employeeId,'reopened_at'=>Db::now()],['id'=>$id]);Audit::add($a,'accounting_period.reopen','accounting_period',$id,['reason'=>$reason,'from'=>$r['period_start'],'to'=>$r['period_end']]);return['id'=>$id,'status'=>'open'];});}
}
