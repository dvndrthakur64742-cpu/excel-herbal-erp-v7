<?php
namespace ExcelHerbal\ERP7\Administration;
use ExcelHerbal\ERP7\Database\Db;
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
 public static function cleanup(Actor $a):array{Guard::cap($a,Capabilities::ACCESS_MANAGE);$r=self::cleanupInternal();Audit::add($a,'maintenance.cleanup','system',0,$r);return$r;}
 private static function cleanupInternal():array{
  $db=Db::wpdb();$now=Db::now();
  $idemCut=gmdate('Y-m-d H:i:s',time()-45*DAY_IN_SECONDS);$sessionCut=gmdate('Y-m-d H:i:s',time()-45*DAY_IN_SECONDS);
  $idem=Db::mustQuery($db,$db->prepare("DELETE FROM ".Db::table('idempotency_keys')." WHERE status='complete' AND completed_at IS NOT NULL AND completed_at<%s",$idemCut));
  $sessions=Db::mustQuery($db,$db->prepare("DELETE FROM ".Db::table('mobile_sessions')." WHERE (revoked_at IS NOT NULL AND revoked_at<%s) OR (refresh_expires_at<%s AND created_at<%s)",$sessionCut,$now,$sessionCut));
  return['idempotency_deleted'=>$idem,'sessions_deleted'=>$sessions,'completed_at'=>$now];
 }
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
  $openPastAttendance=(int)$db->get_var($db->prepare("SELECT COUNT(*) FROM {$attendance} WHERE company_id=%d AND check_in_at IS NOT NULL AND check_out_at IS NULL AND business_date<%s",$c,Db::today()));
  $staleCycles=(int)$db->get_var($db->prepare("SELECT COUNT(*) FROM {$cycles} WHERE company_id=%d AND status<>'completed' AND business_date<%s",$c,Db::today()));
  $legacyDraftPayroll=(int)$db->get_var($db->prepare("SELECT COUNT(*) FROM {$payroll} WHERE company_id=%d AND status='draft' AND (calculation_version IS NULL OR calculation_version='')",$c));
  $roleRows=(array)$db->get_results($db->prepare("SELECT name FROM {$roles} WHERE company_id=%d AND active=1",$c),ARRAY_A);$roleNames=[];$duplicateRoleNames=0;foreach($roleRows as$r){$n=strtolower(trim(preg_replace('/\\s+/',' ',(string)($r['name']??''))));if($n==='')continue;if(isset($roleNames[$n]))$duplicateRoleNames++;else$roleNames[$n]=1;}
  $designationRows=(array)$db->get_results($db->prepare("SELECT name FROM {$designations} WHERE company_id=%d AND status='active'",$c),ARRAY_A);$designationNames=[];$duplicateDesignationNames=0;foreach($designationRows as$r){$n=strtolower(trim(preg_replace('/\\s+/',' ',(string)($r['name']??''))));if($n==='')continue;if(isset($designationNames[$n]))$duplicateDesignationNames++;else$designationNames[$n]=1;}
  $critical=$unbalanced+$orphanJournal+$negativeStock+$missingHistory+$orphanSessions+$dups;
  $operational=$openPastAttendance+$staleCycles+$legacyDraftPayroll+$duplicateRoleNames+$duplicateDesignationNames;
  return['status'=>($critical+$operational)===0?'healthy':'attention','company_id'=>$c,'employees'=>['total'=>(int)($emp['total']??0),'active'=>(int)($emp['active']??0),'without_login'=>(int)($emp['without_login']??0),'duplicate_normalized_mobiles'=>$dups],'accounting'=>['unbalanced_journals'=>$unbalanced,'orphan_journal_lines'=>$orphanJournal],'stock'=>['negative_balances'=>$negativeStock],'organization'=>['active_without_open_branch_history'=>$missingHistory,'duplicate_active_designation_names'=>$duplicateDesignationNames],'attendance'=>['open_past_without_checkout'=>$openPastAttendance],'daily_order'=>['stale_non_completed_cycles'=>$staleCycles],'payroll'=>['legacy_draft_runs'=>$legacyDraftPayroll],'access'=>['duplicate_active_role_names'=>$duplicateRoleNames],'sessions'=>['orphan_sessions'=>$orphanSessions],'maintenance'=>['stale_completed_idempotency'=>$staleIdem],'checked_at'=>Db::now()];
 }
}