<?php
namespace ExcelHerbal\ERP7\Administration;
use ExcelHerbal\ERP7\Database\Db;
use ExcelHerbal\ERP7\Database\Transaction;
use ExcelHerbal\ERP7\Inventory\StockService;
use ExcelHerbal\ERP7\Domain\DomainException;
use ExcelHerbal\ERP7\Security\Actor;
use ExcelHerbal\ERP7\Security\Audit;
use ExcelHerbal\ERP7\Security\Capabilities;
use ExcelHerbal\ERP7\Security\Guard;

final class MaintenanceService{
 private const HOOK='eh7_daily_maintenance';
 public static function boot():void{
  add_action(self::HOOK,[self::class,'runCron']);
  if(!wp_next_scheduled(self::HOOK))wp_schedule_event(time()+3600,'daily',self::HOOK);
 }
 public static function runCron():void{try{self::cleanupInternal();}catch(\Throwable $e){error_log('EH7 maintenance cleanup failed: '.$e->getMessage());}}
 public static function cleanup(Actor $a,array $input=[]):array{
  Guard::cap($a,Capabilities::ACCESS_MANAGE);
  $operation=trim((string)($input['operation']??''));
  if($operation===''){
   $r=self::cleanupInternal();Audit::add($a,'maintenance.cleanup','system',0,$r);return$r;
  }
  if($operation!=='resolve_uat_anomalies')throw new DomainException('Unknown maintenance operation.','maintenance_operation_invalid',422);
  $confirmation=trim((string)($input['confirmation']??''));$reason=trim((string)($input['reason']??''));
  if($confirmation!=='RESOLVE_UAT_ANOMALIES')throw new DomainException('Explicit UAT cleanup confirmation is required.','maintenance_confirmation_required',422);
  if(strlen($reason)<10)throw new DomainException('UAT cleanup reason must contain at least 10 characters.','reason_required',422);
  $r=self::resolveOperational($a,$reason);$r['routine_cleanup']=self::cleanupInternal();Audit::add($a,'maintenance.resolve_uat_anomalies','system',0,$r);return$r;
 }
 private static function cleanupInternal():array{
  $db=Db::wpdb();$now=Db::now();
  $idemCut=gmdate('Y-m-d H:i:s',time()-45*DAY_IN_SECONDS);$sessionCut=gmdate('Y-m-d H:i:s',time()-45*DAY_IN_SECONDS);
  $idem=Db::mustQuery($db,$db->prepare("DELETE FROM ".Db::table('idempotency_keys')." WHERE status='complete' AND completed_at IS NOT NULL AND completed_at<%s",$idemCut));
  $sessions=Db::mustQuery($db,$db->prepare("DELETE FROM ".Db::table('mobile_sessions')." WHERE (revoked_at IS NOT NULL AND revoked_at<%s) OR (refresh_expires_at<%s AND created_at<%s)",$sessionCut,$now,$sessionCut));
  return['idempotency_deleted'=>$idem,'sessions_deleted'=>$sessions,'completed_at'=>$now];
 }
 private static function resolveOperational(Actor $a,string $reason):array{
  return Transaction::run(function()use($a,$reason){
   $db=Db::wpdb();$company=$a->companyId;$today=Db::today();$now=Db::now();
   $result=['attendance_acknowledged'=>0,'daily_cycles_cancelled'=>0,'daily_cycles_skipped'=>0,'payroll_drafts_discarded'=>0,'roles_deactivated'=>0,'designations_deactivated'=>0];

   $attendance=Db::table('attendance');
   $open=(array)$db->get_results($db->prepare("SELECT * FROM {$attendance} WHERE company_id=%d AND check_in_at IS NOT NULL AND check_out_at IS NULL AND checkout_exception=0 AND business_date<%s ORDER BY id",$company,$today),ARRAY_A);
   foreach($open as$row){
    Db::mustUpdate($db,$attendance,['checkout_exception'=>1,'checkout_exception_reason'=>$reason,'checkout_exception_by'=>$a->employeeId,'checkout_exception_at'=>$now],['id'=>(int)$row['id']]);
    Audit::add($a,'attendance.checkout_missing_acknowledged','attendance',(int)$row['id'],['branch_id'=>(int)$row['branch_id'],'business_date'=>(string)$row['business_date'],'check_in_at'=>$row['check_in_at'],'reason'=>$reason]);
    $result['attendance_acknowledged']++;
   }

   $cycles=Db::table('daily_cycles');$requests=Db::table('daily_requests');$issues=Db::table('daily_issue_lines');$evenings=Db::table('evening_settlements');$journals=Db::table('journal_entries');$performance=Db::table('performance_entries');$balances=Db::table('stock_balances');
   $stale=(array)$db->get_results($db->prepare("SELECT * FROM {$cycles} WHERE company_id=%d AND status NOT IN ('completed','cancelled') AND business_date<%s ORDER BY id",$company,$today),ARRAY_A);
   foreach($stale as$cycle){
    $cycleId=(int)$cycle['id'];$branch=(int)$cycle['branch_id'];$employee=(int)$cycle['employee_id'];$status=(string)$cycle['status'];
    $posted=(int)$db->get_var($db->prepare("SELECT COUNT(*) FROM {$journals} WHERE company_id=%d AND source_type='daily_cycle' AND source_id=%d",$company,$cycleId));
    $perf=(int)$db->get_var($db->prepare("SELECT COUNT(*) FROM {$performance} WHERE company_id=%d AND source_type='daily_cycle' AND source_id=%d",$company,$cycleId));
    if($posted||$perf){$result['daily_cycles_skipped']++;continue;}
    $issueRows=(array)$db->get_results($db->prepare("SELECT il.* FROM {$issues} il JOIN {$requests} r ON r.id=il.daily_request_id WHERE r.daily_cycle_id=%d ORDER BY il.id",$cycleId),ARRAY_A);
    if(!$issueRows&&in_array($status,['morning_draft','stock_requested','approved'],true)){
     Db::mustQuery($db,$db->prepare("UPDATE {$requests} SET status='cancelled' WHERE daily_cycle_id=%d AND status IN ('draft','submitted','approved')",$cycleId));
     Db::mustUpdate($db,$cycles,['status'=>'cancelled','completed_at'=>$now],['id'=>$cycleId]);
     Audit::add($a,'daily_order.cancel_stale','daily_cycle',$cycleId,['branch_id'=>$branch,'mode'=>'pre_issue','reason'=>$reason]);
     $result['daily_cycles_cancelled']++;continue;
    }
    if(!$issueRows||!in_array($status,['issued','evening_draft'],true)){$result['daily_cycles_skipped']++;continue;}
    $evening=$db->get_row($db->prepare("SELECT * FROM {$evenings} WHERE daily_cycle_id=%d FOR UPDATE",$cycleId),ARRAY_A);
    if($evening&&!in_array((string)$evening['status'],['draft'],true)){$result['daily_cycles_skipped']++;continue;}
    $needed=[];
    foreach($issueRows as$line){
     $key=(int)$line['product_id'].':'.(int)($line['batch_id']??0);
     $needed[$key]=($needed[$key]??0)+(float)$line['quantity'];
    }
    $safe=true;
    foreach($needed as$key=>$qty){
     [$product,$batchKey]=array_map('intval',explode(':',$key,2));
     $available=(float)$db->get_var($db->prepare("SELECT quantity FROM {$balances} WHERE company_id=%d AND branch_id=%d AND product_id=%d AND batch_key=%d AND custodian_key=%d",$company,$branch,$product,$batchKey,$employee));
     if($available+0.0001<$qty){$safe=false;break;}
    }
    if(!$safe){$result['daily_cycles_skipped']++;continue;}
    foreach($issueRows as$line){
     $product=(int)$line['product_id'];$batch=$line['batch_id']!==null?(int)$line['batch_id']:null;$qty=(float)$line['quantity'];$cost=(float)$line['purchase_cost_snapshot'];
     StockService::move($a,$branch,$product,$batch,$employee,'OUT',$qty,$cost,'daily_cancel_return',$cycleId);
     StockService::move($a,$branch,$product,$batch,null,'IN',$qty,$cost,'daily_cancel_return',$cycleId);
    }
    if($evening)Db::mustUpdate($db,$evenings,['status'=>'cancelled','reviewed_by'=>$a->employeeId,'reviewed_at'=>$now,'notes'=>trim(((string)($evening['notes']??''))."\nUAT cancellation: ".$reason)],['id'=>(int)$evening['id']]);
    Db::mustQuery($db,$db->prepare("UPDATE {$requests} SET status='cancelled' WHERE daily_cycle_id=%d AND status IN ('draft','submitted','approved')",$cycleId));
    Db::mustUpdate($db,$cycles,['status'=>'cancelled','completed_at'=>$now],['id'=>$cycleId]);
    Audit::add($a,'daily_order.cancel_stale','daily_cycle',$cycleId,['branch_id'=>$branch,'mode'=>'issued_full_return','reason'=>$reason,'issue_lines'=>count($issueRows)]);
    $result['daily_cycles_cancelled']++;
   }

   $payroll=Db::table('payroll_runs');$items=Db::table('payroll_items');$editors=Db::table('payroll_editors');
   $legacy=(array)$db->get_results($db->prepare("SELECT r.*,COALESCE(SUM(i.net_salary),0) net_total FROM {$payroll} r LEFT JOIN {$items} i ON i.payroll_run_id=r.id WHERE r.company_id=%d AND r.status='draft' AND (r.calculation_version IS NULL OR r.calculation_version='') AND r.journal_entry_id IS NULL AND r.payment_journal_entry_id IS NULL GROUP BY r.id HAVING ABS(net_total)<=0.005 ORDER BY r.id",$company),ARRAY_A);
   foreach($legacy as$run){
    $id=(int)$run['id'];$snapshot=(array)$db->get_results($db->prepare("SELECT * FROM {$items} WHERE payroll_run_id=%d ORDER BY id",$id),ARRAY_A);
    Audit::add($a,'payroll.discard','payroll_run',$id,['branch_id'=>(int)$run['branch_id'],'reason'=>$reason,'run'=>$run,'items'=>$snapshot,'source'=>'uat_safe_cleanup']);
    Db::mustQuery($db,$db->prepare("DELETE FROM {$editors} WHERE payroll_run_id=%d",$id));Db::mustQuery($db,$db->prepare("DELETE FROM {$items} WHERE payroll_run_id=%d",$id));Db::mustQuery($db,$db->prepare("DELETE FROM {$payroll} WHERE id=%d",$id));
    $result['payroll_drafts_discarded']++;
   }

   $roles=Db::table('roles');$employeeRoles=Db::table('employee_roles');
   $roleRows=(array)$db->get_results($db->prepare("SELECT r.*, (SELECT COUNT(*) FROM {$employeeRoles} er WHERE er.company_id=r.company_id AND er.role_id=r.id AND er.active=1) usage_count FROM {$roles} r WHERE r.company_id=%d AND r.active=1 ORDER BY r.id",$company),ARRAY_A);
   $roleGroups=[];foreach($roleRows as$row){$n=self::normalizedName((string)$row['name']);if($n!=='')$roleGroups[$n][]=$row;}
   foreach($roleGroups as$group){if(count($group)<2)continue;usort($group,static fn($x,$y)=>((int)$y['usage_count']<=>(int)$x['usage_count'])?:((int)$x['id']<=>(int)$y['id']));array_shift($group);foreach($group as$row){if((int)$row['usage_count']!==0)continue;Db::mustUpdate($db,$roles,['active'=>0],['id'=>(int)$row['id']]);Audit::add($a,'access.role_deactivate_duplicate','role',(int)$row['id'],['code'=>$row['code'],'name'=>$row['name'],'reason'=>$reason]);$result['roles_deactivated']++;}}

   $designations=Db::table('designations');$employees=Db::table('employees');$assignments=Db::table('employee_designation_assignments');
   $designationRows=(array)$db->get_results($db->prepare("SELECT d.*, (SELECT COUNT(*) FROM {$employees} e WHERE e.company_id=d.company_id AND e.designation_code=d.code AND e.status='active')+(SELECT COUNT(*) FROM {$assignments} a2 WHERE a2.company_id=d.company_id AND a2.designation_code=d.code AND a2.active=1) usage_count FROM {$designations} d WHERE d.company_id=%d AND d.status='active' ORDER BY d.id",$company),ARRAY_A);
   $designationGroups=[];foreach($designationRows as$row){$n=self::normalizedName((string)$row['name']);if($n!=='')$designationGroups[$n][]=$row;}
   foreach($designationGroups as$group){if(count($group)<2)continue;usort($group,static fn($x,$y)=>((int)$y['usage_count']<=>(int)$x['usage_count'])?:((int)$x['id']<=>(int)$y['id']));array_shift($group);foreach($group as$row){if((int)$row['usage_count']!==0)continue;Db::mustUpdate($db,$designations,['status'=>'inactive'],['id'=>(int)$row['id']]);Audit::add($a,'organization.designation_deactivate_duplicate','designation',(int)$row['id'],['code'=>$row['code'],'name'=>$row['name'],'reason'=>$reason]);$result['designations_deactivated']++;}}
   return$result+['completed_at'=>$now];
  });
 }
 private static function normalizedName(string $name):string{return strtolower(trim(preg_replace('/\s+/',' ',$name)??''));}
 public static function diagnostics(Actor $a):array{
  Guard::any($a,[Capabilities::AUDIT_VIEW,Capabilities::ACCESS_MANAGE]);$db=Db::wpdb();$c=$a->companyId;
  $employees=Db::table('employees');$journal=Db::table('journal_entries');$jl=Db::table('journal_lines');$stock=Db::table('stock_balances');$ledger=Db::table('stock_ledger');$hist=Db::table('employee_branch_history');$sessions=Db::table('mobile_sessions');$idem=Db::table('idempotency_keys');$attendance=Db::table('attendance');$cycles=Db::table('daily_cycles');$payroll=Db::table('payroll_runs');$roles=Db::table('roles');$designations=Db::table('designations');
  $emp=$db->get_row($db->prepare("SELECT COUNT(*) total,SUM(status='active') active,SUM(status='active' AND wp_user_id IS NULL) without_login FROM {$employees} WHERE company_id=%d",$c),ARRAY_A)?:[];
  $mobiles=(array)$db->get_results($db->prepare("SELECT id,mobile FROM {$employees} WHERE company_id=%d AND status='active' AND mobile IS NOT NULL AND mobile<>''",$c),ARRAY_A);$seen=[];$dups=0;foreach($mobiles as$m){$n=preg_replace('/\\D+/','',(string)$m['mobile'])?:'';if($n==='')continue;if(isset($seen[$n])){$dups++;}else$seen[$n]=1;}
  $unbalanced=(int)$db->get_var($db->prepare("SELECT COUNT(*) FROM (SELECT je.id FROM {$journal} je JOIN {$jl} l ON l.journal_entry_id=je.id WHERE je.company_id=%d GROUP BY je.id HAVING ABS(SUM(l.debit)-SUM(l.credit))>0.005) x",$c));
  $orphanJournal=(int)$db->get_var($db->prepare("SELECT COUNT(*) FROM {$jl} l LEFT JOIN {$journal} je ON je.id=l.journal_entry_id WHERE je.id IS NULL"));
  $negativeStock=(int)$db->get_var($db->prepare("SELECT COUNT(*) FROM {$stock} WHERE company_id=%d AND quantity<0",$c));
  $missingHistory=(int)$db->get_var($db->prepare("SELECT COUNT(*) FROM {$employees} e WHERE e.company_id=%d AND e.status='active' AND NOT EXISTS(SELECT 1 FROM {$hist} h WHERE h.company_id=e.company_id AND h.employee_id=e.id AND h.effective_to IS NULL)",$c));
  $orphanSessions=(int)$db->get_var("SELECT COUNT(*) FROM {$sessions} s LEFT JOIN {$employees} e ON e.id=s.employee_id WHERE e.id IS NULL");
  $staleIdem=(int)$db->get_var($db->prepare("SELECT COUNT(*) FROM {$idem} WHERE status='complete' AND completed_at<%s",gmdate('Y-m-d H:i:s',time()-45*DAY_IN_SECONDS)));
  $openPastAttendance=(int)$db->get_var($db->prepare("SELECT COUNT(*) FROM {$attendance} WHERE company_id=%d AND check_in_at IS NOT NULL AND check_out_at IS NULL AND checkout_exception=0 AND business_date<%s",$c,Db::today()));$acknowledgedMissingCheckout=(int)$db->get_var($db->prepare("SELECT COUNT(*) FROM {$attendance} WHERE company_id=%d AND check_out_at IS NULL AND checkout_exception=1",$c));
  $staleCycles=(int)$db->get_var($db->prepare("SELECT COUNT(*) FROM {$cycles} WHERE company_id=%d AND status NOT IN ('completed','cancelled') AND business_date<%s",$c,Db::today()));
  $legacyDraftPayroll=(int)$db->get_var($db->prepare("SELECT COUNT(*) FROM {$payroll} WHERE company_id=%d AND status='draft' AND (calculation_version IS NULL OR calculation_version='')",$c));
  $roleRows=(array)$db->get_results($db->prepare("SELECT name FROM {$roles} WHERE company_id=%d AND active=1",$c),ARRAY_A);$roleNames=[];$duplicateRoleNames=0;foreach($roleRows as$r){$n=strtolower(trim(preg_replace('/\\s+/',' ',(string)($r['name']??''))));if($n==='')continue;if(isset($roleNames[$n]))$duplicateRoleNames++;else$roleNames[$n]=1;}
  $designationRows=(array)$db->get_results($db->prepare("SELECT name FROM {$designations} WHERE company_id=%d AND status='active'",$c),ARRAY_A);$designationNames=[];$duplicateDesignationNames=0;foreach($designationRows as$r){$n=strtolower(trim(preg_replace('/\\s+/',' ',(string)($r['name']??''))));if($n==='')continue;if(isset($designationNames[$n]))$duplicateDesignationNames++;else$designationNames[$n]=1;}
  $critical=$unbalanced+$orphanJournal+$negativeStock+$missingHistory+$orphanSessions+$dups;
  $operational=$openPastAttendance+$staleCycles+$legacyDraftPayroll+$duplicateRoleNames+$duplicateDesignationNames;
  return['status'=>($critical+$operational)===0?'healthy':'attention','company_id'=>$c,'employees'=>['total'=>(int)($emp['total']??0),'active'=>(int)($emp['active']??0),'without_login'=>(int)($emp['without_login']??0),'duplicate_normalized_mobiles'=>$dups],'accounting'=>['unbalanced_journals'=>$unbalanced,'orphan_journal_lines'=>$orphanJournal],'stock'=>['negative_balances'=>$negativeStock],'organization'=>['active_without_open_branch_history'=>$missingHistory,'duplicate_active_designation_names'=>$duplicateDesignationNames],'attendance'=>['open_past_without_checkout'=>$openPastAttendance,'acknowledged_missing_checkout'=>$acknowledgedMissingCheckout],'daily_order'=>['stale_non_completed_cycles'=>$staleCycles],'payroll'=>['legacy_draft_runs'=>$legacyDraftPayroll],'access'=>['duplicate_active_role_names'=>$duplicateRoleNames],'sessions'=>['orphan_sessions'=>$orphanSessions],'maintenance'=>['stale_completed_idempotency'=>$staleIdem],'checked_at'=>Db::now()];
 }
}