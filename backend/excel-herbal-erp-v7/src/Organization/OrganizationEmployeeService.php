<?php
namespace ExcelHerbal\ERP7\Organization;
use ExcelHerbal\ERP7\Security\DesignationDefaults;use ExcelHerbal\ERP7\Core\Input;use ExcelHerbal\ERP7\Database\Db;use ExcelHerbal\ERP7\Database\Transaction;use ExcelHerbal\ERP7\Domain\DomainException;use ExcelHerbal\ERP7\Security\Actor;use ExcelHerbal\ERP7\Security\Audit;use ExcelHerbal\ERP7\Security\BranchAuthority;use ExcelHerbal\ERP7\Security\Capabilities;use ExcelHerbal\ERP7\Security\Guard;use ExcelHerbal\ERP7\Security\HierarchyScope;
final class OrganizationEmployeeService{
 public static function employees(Actor $a,int $branch,string $status='active'):array{
  Guard::branch($a,$branch,Capabilities::EMP_VIEW);$status=strtolower(trim($status))?:'active';if(!in_array($status,['active','inactive','all'],true))throw new DomainException('Employee status filter is invalid.','employee_status_invalid',422);
  $where=$status==='all'?"status IN ('active','inactive')":"status='".$status."'";
  $rows=(array)Db::wpdb()->get_results(Db::wpdb()->prepare(
   "SELECT id,employee_code,full_name,mobile,email,designation_code,reporting_designation_code,assigned_branch_id,reporting_employee_id,monthly_salary,joining_date,separation_date,status,CASE WHEN wp_user_id IS NULL THEN 0 ELSE 1 END login_enabled FROM ".Db::table('employees')." WHERE company_id=%d AND assigned_branch_id=%d AND {$where} ORDER BY CASE WHEN status='active' THEN 0 ELSE 1 END,full_name",
   $a->companyId,$branch
  ),ARRAY_A);
  $visible=array_flip(HierarchyScope::visibleEmployeeIds($a,$branch));
  $rows=array_values(array_filter($rows,fn($r)=>isset($visible[(int)$r['id']])));
  foreach($rows as&$r)$r['reporting_category']=HierarchyScope::reportingCategoryForCode((string)$r['designation_code'],(string)($r['reporting_designation_code']??''));unset($r);return $rows;
 }
 public static function createEmployee(Actor $a,array $data,string $requiredCapability=Capabilities::EMP_MANAGE):array{
  $branch=(int)($data['assigned_branch_id']??0);Guard::branch($a,$branch,$requiredCapability);
  $code=strtoupper(trim((string)($data['employee_code']??'')));$name=trim((string)($data['full_name']??''));$designation=strtoupper(trim((string)($data['designation_code']??'')));$reportingDesignation=HierarchyScope::normaliseCode((string)($data['reporting_designation_code']??''));if($reportingDesignation!==''&&!in_array($reportingDesignation,HierarchyScope::allowedReportingCategories(),true))throw new DomainException('Invalid reporting designation category.','reporting_designation_invalid',422);
  if($code===''||$name===''||$designation==='')throw new DomainException('Employee code, name and designation are required.');
  $mobile=self::normaliseMobile((string)($data['mobile']??''));$email=trim((string)($data['email']??''));$joiningRaw=trim((string)($data['joining_date']??''));$joining=$joiningRaw===''?Db::today():Input::date($joiningRaw,'Joining date');
  if($mobile!==''&&(strlen($mobile)<8||strlen($mobile)>15))throw new DomainException('Mobile number must contain 8 to 15 digits.','mobile_invalid',422);
  if($email!==''&&!is_email($email))throw new DomainException('Valid employee email is required.','email_invalid',422);
  self::assertMobileAvailable($mobile);
  $db=Db::wpdb();$validDes=(int)$db->get_var($db->prepare("SELECT COUNT(*) FROM ".Db::table('designations')." WHERE company_id=%d AND code=%s AND status='active'",$a->companyId,$designation));
  if(!$validDes)throw new DomainException('Active designation not found.','designation_invalid',422);
  if(DesignationDefaults::requiresAccessManagement($designation))Guard::cap($a,Capabilities::ACCESS_MANAGE);
  $reporting=isset($data['reporting_employee_id'])?(int)$data['reporting_employee_id']:null;
  if($reporting){$manager=$db->get_row($db->prepare("SELECT id,assigned_branch_id FROM ".Db::table('employees')." WHERE company_id=%d AND id=%d AND status='active'",$a->companyId,$reporting),ARRAY_A);if(!$manager)throw new DomainException('Reporting employee not found.','reporting_employee_invalid',422);Guard::branch($a,(int)$manager['assigned_branch_id'],$requiredCapability);}
  $roleIds=[];foreach((array)($data['role_ids']??[]) as $roleId){$rid=(int)$roleId;if($rid<1||in_array($rid,$roleIds,true))throw new DomainException('Invalid or duplicate role assignment.','role_invalid',422);$ok=(int)$db->get_var($db->prepare("SELECT COUNT(*) FROM ".Db::table('roles')." WHERE id=%d AND company_id=%d AND active=1",$rid,$a->companyId));if(!$ok)throw new DomainException('Invalid role assignment.','role_invalid',422);$roleIds[]=$rid;}if($roleIds)Guard::cap($a,Capabilities::ACCESS_MANAGE);
  $result=Transaction::run(function()use($a,$data,$branch,$code,$name,$designation,$reportingDesignation,$reporting,$mobile,$email,$roleIds,$joining){
   \ExcelHerbal\ERP7\Payroll\SalaryService::lockCompany($a->companyId);$db=Db::wpdb();$payrollConflict=(int)$db->get_var($db->prepare("SELECT COUNT(*) FROM ".Db::table('payroll_runs')." WHERE company_id=%d AND branch_id=%d AND period_end>=%s",$a->companyId,$branch,$joining));if($payrollConflict)throw new DomainException('Employee joining date conflicts with an existing payroll period. Regenerate or review payroll first.','employee_create_payroll_conflict',409);$requestedUid=(int)($data['wp_user_id']??0);$password=(string)($data['password']??'');$provisionLogin=!array_key_exists('provision_login',$data)||!empty($data['provision_login']);$provisioned=false;$generatedPassword=false;$notify=false;$uid=null;
   if($requestedUid>0){
    if(!get_user_by('id',$requestedUid))throw new DomainException('WordPress user not found.','wp_user_invalid',422);
    $linked=(int)$db->get_var($db->prepare("SELECT COUNT(*) FROM ".Db::table('employees')." WHERE wp_user_id=%d",$requestedUid));
    if($linked)throw new DomainException('WordPress user is already linked to an employee.','wp_user_linked',409);
    $uid=$requestedUid;
   }elseif($mobile!==''&&$provisionLogin){
    $generatedPassword=$password==='';if(!$generatedPassword&&strlen($password)<10)throw new DomainException('Mobile login password must be at least 10 characters.','password_too_short',422);
    $password=$generatedPassword?wp_generate_password(24,true,true):$password;
    $uid=self::createWordPressUser($a->companyId,$code,$name,$email,$password);$provisioned=true;$notify=$generatedPassword&&$email!=='';
   }
   Db::mustInsert($db,Db::table('employees'),[
    'company_id'=>$a->companyId,'employee_code'=>$code,'wp_user_id'=>$uid,'designation_code'=>$designation,'reporting_designation_code'=>$reportingDesignation?:null,'assigned_branch_id'=>$branch,'reporting_employee_id'=>$reporting,
    'full_name'=>$name,'mobile'=>$mobile?:null,'email'=>$email?:null,'monthly_salary'=>max(0,(float)($data['monthly_salary']??0)),'joining_date'=>$joining,'status'=>'active','created_at'=>Db::now()
   ],'Employee code or WordPress user is already linked.','employee_duplicate');
   $id=(int)$db->insert_id;
   Db::mustInsert($db,Db::table('salary_revisions'),['company_id'=>$a->companyId,'employee_id'=>$id,'effective_from'=>$joining,'monthly_salary'=>max(0,(float)($data['monthly_salary']??0)),'status'=>'baseline','reason'=>'Employee onboarding salary','created_by'=>$a->employeeId,'created_at'=>Db::now()]);
   Db::mustInsert($db,Db::table('employee_branch_history'),['company_id'=>$a->companyId,'employee_id'=>$id,'branch_id'=>$branch,'effective_from'=>$joining,'effective_to'=>null,'reason'=>'Employee onboarding','changed_by'=>$a->employeeId,'created_at'=>Db::now()]);
   foreach($roleIds as $rid)Db::mustInsert($db,Db::table('employee_roles'),['company_id'=>$a->companyId,'employee_id'=>$id,'role_id'=>$rid,'active'=>1,'assigned_by'=>$a->employeeId,'assigned_at'=>Db::now()]);
   Audit::add($a,'employee.create','employee',$id,['branch_id'=>$branch,'designation'=>$designation,'login_provisioned'=>$uid!==null]);
   return ['id'=>$id,'employee_code'=>$code,'status'=>'active','login_enabled'=>$uid!==null,'login_setup'=>$uid===null?'not_provisioned':($notify?'password_email_pending':($provisioned&&$generatedPassword?'admin_password_reset_required':'ready')),'_notify_uid'=>$notify?(int)$uid:0];
  });
  $notifyUid=(int)($result['_notify_uid']??0);unset($result['_notify_uid']);
  if($notifyUid>0){try{wp_new_user_notification($notifyUid,null,'user');$result['login_setup']='password_email_sent';}catch(\Throwable $e){$result['login_setup']='password_email_failed';error_log('EH7 employee password email failed for WP user '.$notifyUid.': '.$e->getMessage());}}
  return $result;
 }
 public static function setEmployeeCredentials(Actor $a,int $employeeId,array $data,string $requiredCapability=Capabilities::EMP_MANAGE):array{
  $db=Db::wpdb();$table=Db::table('employees');$e=$db->get_row($db->prepare("SELECT * FROM {$table} WHERE id=%d AND company_id=%d AND status='active'",$employeeId,$a->companyId),ARRAY_A);
  if(!$e)throw new DomainException('Employee not found.','employee_not_found',404);Guard::branch($a,(int)$e['assigned_branch_id'],$requiredCapability);
  $mobile=self::normaliseMobile((string)($e['mobile']??''));if($mobile==='')throw new DomainException('Employee mobile is required before enabling mobile login.','mobile_required',422);self::assertMobileAvailable($mobile,$employeeId);
  $password=(string)($data['password']??'');if(trim($password)==='')throw new DomainException('Password is required to enable or reset mobile login.','password_required',422);if(strlen($password)<10)throw new DomainException('Mobile login password must be at least 10 characters.','password_too_short',422);
  $uid=(int)($e['wp_user_id']??0);if($uid<1){$uid=self::createWordPressUser($a->companyId,(string)$e['employee_code'],(string)$e['full_name'],(string)($e['email']??''),$password);Db::mustUpdate($db,$table,['wp_user_id'=>$uid,'mobile'=>$mobile,'updated_at'=>Db::now()],['id'=>$employeeId,'company_id'=>$a->companyId]);}else{if(!get_user_by('id',$uid))throw new DomainException('Linked WordPress user no longer exists.','wp_user_missing',409);wp_set_password($password,$uid);}
  $revoked=$db->update(Db::table('mobile_sessions'),['revoked_at'=>Db::now()],['employee_id'=>$employeeId]);if($revoked===false)throw new DomainException('Existing mobile sessions could not be revoked.','session_revoke_failed',500);
  Audit::add($a,'employee.login_credentials_reset','employee',$employeeId,['branch_id'=>(int)$e['assigned_branch_id'],'wp_user_id'=>$uid]);
  return['id'=>$employeeId,'login_enabled'=>true,'sessions_revoked'=>true,'password_updated'=>true];
 }
 public static function employeeLoginStatus(Actor $a,int $employeeId):array{
  $db=Db::wpdb();$t=Db::table('employees');$e=$db->get_row($db->prepare("SELECT id,employee_code,full_name,mobile,email,assigned_branch_id,status,wp_user_id FROM {$t} WHERE id=%d AND company_id=%d",$employeeId,$a->companyId),ARRAY_A);
  if(!$e)throw new DomainException('Employee not found.','employee_not_found',404);Guard::branch($a,(int)$e['assigned_branch_id'],Capabilities::EMP_MANAGE);$uid=(int)($e['wp_user_id']??0);$activeSessions=(int)$db->get_var($db->prepare("SELECT COUNT(*) FROM ".Db::table('mobile_sessions')." WHERE employee_id=%d AND revoked_at IS NULL AND refresh_expires_at>%s",$employeeId,Db::now()));
  return['id'=>$employeeId,'employee_code'=>(string)$e['employee_code'],'full_name'=>(string)$e['full_name'],'status'=>(string)$e['status'],'mobile'=>(string)($e['mobile']??''),'email'=>(string)($e['email']??''),'login_enabled'=>$uid>0&&get_user_by('id',$uid)!==false,'wp_user_id'=>$uid?:null,'active_sessions'=>$activeSessions];
 }
 public static function revokeEmployeeSessions(Actor $a,int $employeeId):array{
  $db=Db::wpdb();$t=Db::table('employees');$e=$db->get_row($db->prepare("SELECT id,assigned_branch_id FROM {$t} WHERE id=%d AND company_id=%d",$employeeId,$a->companyId),ARRAY_A);if(!$e)throw new DomainException('Employee not found.','employee_not_found',404);Guard::branch($a,(int)$e['assigned_branch_id'],Capabilities::EMP_MANAGE);$sql=$db->prepare("UPDATE ".Db::table('mobile_sessions')." SET revoked_at=%s WHERE employee_id=%d AND revoked_at IS NULL",Db::now(),$employeeId);$count=Db::mustQuery($db,$sql);Audit::add($a,'employee.sessions.revoke','employee',$employeeId,['revoked'=>$count]);return['id'=>$employeeId,'sessions_revoked'=>$count];
 }
 public static function reactivateEmployee(Actor $a,int $employeeId,?int $branchId,string $reactivationDate,string $reason):array{
  $date=Input::date(trim($reactivationDate),'Reactivation date');$reason=trim($reason);if(strlen($reason)<5)throw new DomainException('Reactivation reason must be at least 5 characters.','reactivation_reason_required',422);if($date>Db::today())throw new DomainException('Future employee reactivation is not supported.','future_reactivation_not_supported',422);
  return Transaction::run(function()use($a,$employeeId,$branchId,$date,$reason){
   \ExcelHerbal\ERP7\Payroll\SalaryService::lockCompany($a->companyId);$db=Db::wpdb();$t=Db::table('employees');$e=$db->get_row($db->prepare("SELECT * FROM {$t} WHERE id=%d AND company_id=%d AND status='inactive' FOR UPDATE",$employeeId,$a->companyId),ARRAY_A);if(!$e)throw new DomainException('Inactive employee not found.','inactive_employee_not_found',404);
   $branch=$branchId?:((int)$e['assigned_branch_id']);Guard::branch($a,$branch,Capabilities::EMP_MANAGE);$payrollConflict=(int)$db->get_var($db->prepare("SELECT COUNT(*) FROM ".Db::table('payroll_runs')." WHERE company_id=%d AND branch_id=%d AND period_end>=%s",$a->companyId,$branch,$date));if($payrollConflict)throw new DomainException('Employee reactivation date conflicts with an existing payroll period. Regenerate or review payroll first.','employee_reactivate_payroll_conflict',409);$validBranch=(int)$db->get_var($db->prepare("SELECT COUNT(*) FROM ".Db::table('branches')." WHERE id=%d AND company_id=%d AND status='active'",$branch,$a->companyId));if(!$validBranch)throw new DomainException('Active reactivation branch not found.','branch_not_found',404);
   if(!empty($e['separation_date'])&&$date<=(string)$e['separation_date'])throw new DomainException('Reactivation date must be after separation date.','reactivation_date_invalid',422);
   $mobile=self::normaliseMobile((string)($e['mobile']??''));if($mobile!=='')self::assertMobileAvailable($mobile,$employeeId);
   $open=(int)$db->get_var($db->prepare("SELECT COUNT(*) FROM ".Db::table('employee_branch_history')." WHERE company_id=%d AND employee_id=%d AND effective_to IS NULL",$a->companyId,$employeeId));if($open)throw new DomainException('Employee has an open branch-history assignment.','branch_history_conflict',409);
   Db::mustUpdate($db,$t,['status'=>'active','assigned_branch_id'=>$branch,'separation_date'=>null,'updated_at'=>Db::now()],['id'=>$employeeId,'company_id'=>$a->companyId]);
   Db::mustInsert($db,Db::table('employee_branch_history'),['company_id'=>$a->companyId,'employee_id'=>$employeeId,'branch_id'=>$branch,'effective_from'=>$date,'effective_to'=>null,'reason'=>'Employee reactivation: '.$reason,'changed_by'=>$a->employeeId,'created_at'=>Db::now()]);
   Audit::add($a,'employee.reactivate','employee',$employeeId,['branch_id'=>$branch,'reactivation_date'=>$date,'reason'=>$reason,'roles_restored'=>false,'extra_branch_authorities_restored'=>false]);
   return['id'=>$employeeId,'employee_code'=>(string)$e['employee_code'],'status'=>'active','assigned_branch_id'=>$branch,'reactivation_date'=>$date,'login_enabled'=>(int)($e['wp_user_id']??0)>0,'roles_restored'=>false,'extra_branch_authorities_restored'=>false];
  });
 }
 public static function setReportingManager(Actor $a,int $employeeId,?int $managerId,string $reason):array{
  $reason=trim($reason);if(strlen($reason)<5)throw new DomainException('Reporting-manager change reason must be at least 5 characters.','reporting_reason_required',422);
  if($managerId!==null&&$managerId<1)$managerId=null;
  if($managerId===$employeeId)throw new DomainException('Employee cannot report to self.','reporting_employee_invalid',422);
  return Transaction::run(function()use($a,$employeeId,$managerId,$reason){
   \ExcelHerbal\ERP7\Payroll\SalaryService::lockCompany($a->companyId);$db=Db::wpdb();$t=Db::table('employees');$e=$db->get_row($db->prepare("SELECT id,assigned_branch_id,reporting_employee_id FROM {$t} WHERE id=%d AND company_id=%d AND status='active' FOR UPDATE",$employeeId,$a->companyId),ARRAY_A);
   if(!$e)throw new DomainException('Active employee not found.','employee_not_found',404);Guard::branch($a,(int)$e['assigned_branch_id'],Capabilities::EMP_MANAGE);
   $old=$e['reporting_employee_id']!==null?(int)$e['reporting_employee_id']:null;
   if($old===$managerId)return['id'=>$employeeId,'reporting_employee_id'=>$managerId,'unchanged'=>true];
   if($managerId!==null){
    $m=$db->get_row($db->prepare("SELECT id,assigned_branch_id,reporting_employee_id FROM {$t} WHERE id=%d AND company_id=%d AND status='active'",$managerId,$a->companyId),ARRAY_A);
    if(!$m)throw new DomainException('Reporting employee not found.','reporting_employee_invalid',422);Guard::branch($a,(int)$m['assigned_branch_id'],Capabilities::EMP_MANAGE);
    $seen=[];$cursor=$managerId;$depth=0;
    while($cursor&&$depth<100){if($cursor===$employeeId)throw new DomainException('Reporting-manager change would create a reporting cycle.','reporting_cycle',409);if(isset($seen[$cursor]))throw new DomainException('Existing reporting hierarchy contains a cycle.','reporting_cycle',409);$seen[$cursor]=1;$cursor=(int)$db->get_var($db->prepare("SELECT COALESCE(reporting_employee_id,0) FROM {$t} WHERE id=%d AND company_id=%d AND status='active'",$cursor,$a->companyId));$depth++;}
    if($depth>=100)throw new DomainException('Reporting hierarchy is too deep.','reporting_hierarchy_invalid',409);
   }
   Db::mustUpdate($db,$t,['reporting_employee_id'=>$managerId,'updated_at'=>Db::now()],['id'=>$employeeId,'company_id'=>$a->companyId]);
   Audit::add($a,'employee.reporting_manager','employee',$employeeId,['branch_id'=>(int)$e['assigned_branch_id'],'before'=>$old,'after'=>$managerId,'reason'=>$reason]);
   return['id'=>$employeeId,'reporting_employee_id'=>$managerId,'unchanged'=>false];
  });
 }
 public static function offboardingPreflight(Actor $a,int $employeeId,string $separationDate='',string $requiredCapability=Capabilities::EMP_MANAGE):array{
  $db=Db::wpdb();$t=Db::table('employees');$e=$db->get_row($db->prepare("SELECT * FROM {$t} WHERE id=%d AND company_id=%d AND status='active'",$employeeId,$a->companyId),ARRAY_A);
  if(!$e)throw new DomainException('Active employee not found.','employee_not_found',404);
  Guard::branch($a,(int)$e['assigned_branch_id'],$requiredCapability);
  $date=trim($separationDate);$date=$date===''?Db::today():Input::date($date,'Separation date');
  if($date>Db::today())throw new DomainException('Future employee offboarding is not supported.','future_offboarding_not_supported',422);
  if(!empty($e['joining_date'])&&$date<(string)$e['joining_date'])throw new DomainException('Separation date cannot be before joining date.','separation_date_invalid',422);
  $blockers=self::offboardingBlockers($a,$e,$date);
  return['employee_id'=>$employeeId,'employee_code'=>(string)$e['employee_code'],'full_name'=>(string)$e['full_name'],'branch_id'=>(int)$e['assigned_branch_id'],'separation_date'=>$date,'can_offboard'=>!$blockers,'blockers'=>$blockers];
 }
 public static function offboardEmployee(Actor $a,int $employeeId,string $separationDate,string $reason,string $requiredCapability=Capabilities::EMP_MANAGE):array{
  $date=Input::date(trim($separationDate),'Separation date');$reason=trim($reason);
  if(strlen($reason)<5)throw new DomainException('Offboarding reason must be at least 5 characters.','offboarding_reason_required',422);
  if($date>Db::today())throw new DomainException('Future employee offboarding is not supported.','future_offboarding_not_supported',422);
  if($employeeId===$a->employeeId)throw new DomainException('You cannot offboard your own active ERP identity.','self_offboarding_not_allowed',409);
  return Transaction::run(function()use($a,$employeeId,$date,$reason,$requiredCapability){
   \ExcelHerbal\ERP7\Payroll\SalaryService::lockCompany($a->companyId);$db=Db::wpdb();$t=Db::table('employees');$e=$db->get_row($db->prepare("SELECT * FROM {$t} WHERE id=%d AND company_id=%d AND status='active' FOR UPDATE",$employeeId,$a->companyId),ARRAY_A);
   if(!$e)throw new DomainException('Active employee not found.','employee_not_found',404);
   Guard::branch($a,(int)$e['assigned_branch_id'],$requiredCapability);
   if(!empty($e['joining_date'])&&$date<(string)$e['joining_date'])throw new DomainException('Separation date cannot be before joining date.','separation_date_invalid',422);
   $blockers=self::offboardingBlockers($a,$e,$date);if($blockers)throw new DomainException('Employee offboarding has unresolved blockers. Run offboarding preflight.','employee_offboarding_blocked',409);
   $now=Db::now();
   Db::mustUpdate($db,$t,['status'=>'inactive','separation_date'=>$date,'updated_at'=>$now],['id'=>$employeeId,'company_id'=>$a->companyId]);
   Db::mustQuery($db,$db->prepare("UPDATE ".Db::table('employee_branch_history')." SET effective_to=%s WHERE company_id=%d AND employee_id=%d AND effective_to IS NULL",$date,$a->companyId,$employeeId));
   Db::mustQuery($db,$db->prepare("UPDATE ".Db::table('employee_branch_authorities')." SET active=0,valid_until=%s WHERE company_id=%d AND employee_id=%d AND active=1",$now,$a->companyId,$employeeId));
   Db::mustQuery($db,$db->prepare("UPDATE ".Db::table('employee_roles')." SET active=0,revoked_at=%s WHERE company_id=%d AND employee_id=%d AND active=1",$now,$a->companyId,$employeeId));
   Db::mustQuery($db,$db->prepare("UPDATE ".Db::table('employee_capability_overrides')." SET active=0 WHERE company_id=%d AND employee_id=%d AND active=1",$a->companyId,$employeeId));
   Db::mustQuery($db,$db->prepare("UPDATE ".Db::table('mobile_sessions')." SET revoked_at=%s WHERE employee_id=%d AND revoked_at IS NULL",$now,$employeeId));
   Audit::add($a,'employee.offboard','employee',$employeeId,['branch_id'=>(int)$e['assigned_branch_id'],'separation_date'=>$date,'reason'=>$reason,'wp_user_id'=>(int)($e['wp_user_id']??0)]);
   return['id'=>$employeeId,'employee_code'=>(string)$e['employee_code'],'status'=>'inactive','separation_date'=>$date,'sessions_revoked'=>true];
  });
 }
 private static function offboardingBlockers(Actor $a,array $e,string $date):array{
  $db=Db::wpdb();$eid=(int)$e['id'];$company=$a->companyId;$out=[];
  if($eid===$a->employeeId)$out[]=['code'=>'self_offboarding_not_allowed','message'=>'Current ERP actor cannot offboard self.'];
  $custody=(float)$db->get_var($db->prepare("SELECT COALESCE(SUM(quantity),0) FROM ".Db::table('stock_balances')." WHERE company_id=%d AND custodian_key=%d AND quantity>0",$company,$eid));
  if($custody>.0001)$out[]=['code'=>'stock_custody_open','message'=>'Employee still holds stock custody.','quantity'=>round($custody,3)];
  $daily=(int)$db->get_var($db->prepare("SELECT COUNT(*) FROM ".Db::table('daily_cycles')." WHERE company_id=%d AND employee_id=%d AND status NOT IN ('completed','cancelled')",$company,$eid));
  if($daily)$out[]=['code'=>'daily_orders_open','message'=>'Employee has incomplete Daily Orders.','count'=>$daily];
  $visits=(int)$db->get_var($db->prepare("SELECT COUNT(*) FROM ".Db::table('field_visits')." WHERE company_id=%d AND employee_id=%d AND status='in_progress'",$company,$eid));
  if($visits)$out[]=['code'=>'field_visit_open','message'=>'Employee has an active field visit.','count'=>$visits];
  $attendance=(int)$db->get_var($db->prepare("SELECT COUNT(*) FROM ".Db::table('attendance')." WHERE company_id=%d AND employee_id=%d AND check_in_at IS NOT NULL AND check_out_at IS NULL",$company,$eid));
  if($attendance)$out[]=['code'=>'attendance_open','message'=>'Employee has attendance without check-out.','count'=>$attendance];
  $reports=(int)$db->get_var($db->prepare("SELECT COUNT(*) FROM ".Db::table('employees')." WHERE company_id=%d AND reporting_employee_id=%d AND status='active'",$company,$eid));
  if($reports)$out[]=['code'=>'direct_reports_open','message'=>'Active employees still report to this employee.','count'=>$reports];
  $tasks=(int)$db->get_var($db->prepare("SELECT COUNT(*) FROM ".Db::table('tasks')." WHERE company_id=%d AND assigned_employee_id=%d AND status<>'completed'",$company,$eid));
  if($tasks)$out[]=['code'=>'tasks_open','message'=>'Employee has incomplete tasks.','count'=>$tasks];
  $leave=(int)$db->get_var($db->prepare("SELECT COUNT(*) FROM ".Db::table('leave_requests')." WHERE company_id=%d AND employee_id=%d AND status IN ('submitted','approved') AND date_to>=%s",$company,$eid,$date));
  if($leave)$out[]=['code'=>'leave_requests_open','message'=>'Employee has submitted leave requests on/after separation date.','count'=>$leave];
  $payroll=(int)$db->get_var($db->prepare("SELECT COUNT(*) FROM ".Db::table('payroll_runs')." r JOIN ".Db::table('payroll_items')." i ON i.payroll_run_id=r.id WHERE r.company_id=%d AND i.employee_id=%d AND r.period_end>=%s",$company,$eid,$date));
  if($payroll)$out[]=['code'=>'payroll_period_conflict','message'=>'Employee is included in a payroll period ending on/after separation date.','count'=>$payroll];
  return$out;
 }
 private static function createWordPressUser(int $companyId,string $employeeCode,string $name,string $email,string $password):int{
  if($email!==''&&email_exists($email))throw new DomainException('Employee email is already used by another WordPress account.','wp_email_in_use',409);
  $base=sanitize_user(strtolower('eh7_'.$companyId.'_'.$employeeCode),true);if($base==='')$base='eh7_'.$companyId.'_employee';$login=$base;$n=1;while(username_exists($login)){$login=$base.'_'.(++$n);if($n>1000)throw new DomainException('Unable to allocate WordPress login.','wp_user_create_failed',500);}
  $uid=wp_insert_user(['user_login'=>$login,'user_pass'=>$password,'user_email'=>$email,'display_name'=>$name,'role'=>'subscriber']);
  if(is_wp_error($uid))throw new DomainException('Unable to create employee login: '.$uid->get_error_message(),'wp_user_create_failed',500);return (int)$uid;
 }
 private static function normaliseMobile(string $mobile):string{return preg_replace('/\D+/','',$mobile)?:'';}
 private static function assertMobileAvailable(string $mobile,?int $exceptEmployeeId=null):void{
  if($mobile==='')return;$db=Db::wpdb();$rows=(array)$db->get_results("SELECT id,mobile FROM ".Db::table('employees')." WHERE status='active' AND mobile IS NOT NULL",ARRAY_A);
  foreach($rows as $row){if($exceptEmployeeId!==null&&(int)$row['id']===$exceptEmployeeId)continue;if(self::normaliseMobile((string)$row['mobile'])===$mobile)throw new DomainException('Mobile number is already assigned to another active employee.','mobile_duplicate',409);}
 }
 public static function transferEmployee(Actor $a,int $employeeId,int $newBranch,string $effectiveDate,string $reason):array{
  if(strlen(trim($reason))<5)throw new DomainException('Transfer reason is required.');
  $db=Db::wpdb();
  $e=$db->get_row($db->prepare("SELECT * FROM ".Db::table('employees')." WHERE id=%d AND company_id=%d AND status='active'",$employeeId,$a->companyId),ARRAY_A);
  if(!$e)throw new DomainException('Employee not found.','employee_not_found',404);
  $old=(int)$e['assigned_branch_id'];
  Guard::branch($a,$old,Capabilities::EMP_MANAGE);
  Guard::branch($a,$newBranch,Capabilities::EMP_MANAGE);
  $openSeparation=(int)$db->get_var($db->prepare("SELECT COUNT(*) FROM ".Db::table('hr_separations')." WHERE company_id=%d AND employee_id=%d AND status IN ('submitted','approved')",$a->companyId,$employeeId));
  if($openSeparation)throw new DomainException('Employee has an open separation workflow and cannot be transferred.','employee_transfer_blocked',409);
  if($old===$newBranch)throw new DomainException('Employee is already assigned to this branch.');
  $date=trim($effectiveDate)?:Db::today();$date=Input::date($date,'Transfer effective date');
  if($date>Db::today())throw new DomainException('Future-dated primary branch transfer is not supported until a scheduled-transfer executor is enabled.','future_transfer_not_supported',422);
  $history=Db::table('employee_branch_history');
  $open=$db->get_row($db->prepare("SELECT id,effective_from FROM {$history} WHERE company_id=%d AND employee_id=%d AND effective_to IS NULL ORDER BY effective_from DESC,id DESC LIMIT 1",$a->companyId,$employeeId),ARRAY_A);
  if($open&&$date<=(string)$open['effective_from'])throw new DomainException('Transfer date must be after the current branch assignment start date.','transfer_date_conflict',409);
  return Transaction::run(function()use($a,$employeeId,$old,$newBranch,$date,$reason,$history){
   $db=Db::wpdb();
   \ExcelHerbal\ERP7\Payroll\SalaryService::lockCompany($a->companyId);
   $current=$db->get_row($db->prepare("SELECT assigned_branch_id,status FROM ".Db::table('employees')." WHERE company_id=%d AND id=%d FOR UPDATE",$a->companyId,$employeeId),ARRAY_A);
   if(!$current||$current['status']!=='active'||(int)$current['assigned_branch_id']!==$old)throw new DomainException('Employee changed during transfer; reload and retry.','employee_transfer_conflict',409);
   $openNow=$db->get_row($db->prepare("SELECT effective_from FROM {$history} WHERE company_id=%d AND employee_id=%d AND effective_to IS NULL ORDER BY effective_from DESC,id DESC LIMIT 1 FOR UPDATE",$a->companyId,$employeeId),ARRAY_A);
   if($openNow&&$date<=$openNow['effective_from'])throw new DomainException('Transfer conflicts with current branch history.','transfer_date_conflict',409);
   $payroll=$db->get_var($db->prepare("SELECT r.id FROM ".Db::table('payroll_runs')." r JOIN ".Db::table('payroll_items')." i ON i.payroll_run_id=r.id WHERE r.company_id=%d AND i.employee_id=%d AND r.period_end>=%s LIMIT 1",$a->companyId,$employeeId,$date));
   if($payroll)throw new DomainException('Transfer would change an existing payroll period. Resolve draft payroll or review posted payroll first.','employee_transfer_payroll_conflict',409);

   Db::mustQuery($db,$db->prepare("UPDATE {$history} SET effective_to=DATE_SUB(%s,INTERVAL 1 DAY) WHERE company_id=%d AND employee_id=%d AND effective_to IS NULL",$date,$a->companyId,$employeeId));
   Db::mustInsert($db,$history,['company_id'=>$a->companyId,'employee_id'=>$employeeId,'branch_id'=>$newBranch,'effective_from'=>$date,'effective_to'=>null,'reason'=>$reason,'changed_by'=>$a->employeeId,'created_at'=>Db::now()]);
   if(!$db->insert_id)throw new DomainException('Employee branch history could not be recorded.','employee_transfer_history_failed',500);
   $updated=$db->update(Db::table('employees'),['assigned_branch_id'=>$newBranch,'updated_at'=>Db::now()],['id'=>$employeeId,'company_id'=>$a->companyId]);
   if($updated===false)throw new DomainException('Employee primary branch could not be updated.','employee_transfer_update_failed',500);
   Audit::add($a,'employee.transfer_branch','employee',$employeeId,['branch_id'=>$newBranch,'from_branch_id'=>$old,'effective_date'=>$date,'reason'=>$reason]);
   return['id'=>$employeeId,'assigned_branch_id'=>$newBranch,'effective_date'=>$date];
  });
 }
 public static function employeeHistory(Actor $a,int $employeeId):array{$db=Db::wpdb();$e=$db->get_row($db->prepare("SELECT assigned_branch_id FROM ".Db::table('employees')." WHERE id=%d AND company_id=%d",$employeeId,$a->companyId),ARRAY_A);if(!$e)throw new DomainException('Employee not found.','employee_not_found',404);Guard::branch($a,(int)$e['assigned_branch_id'],Capabilities::EMP_VIEW);return(array)$db->get_results($db->prepare("SELECT h.*,b.code branch_code,b.name branch_name FROM ".Db::table('employee_branch_history')." h JOIN ".Db::table('branches')." b ON b.id=h.branch_id WHERE h.company_id=%d AND h.employee_id=%d ORDER BY h.effective_from DESC,h.id DESC",$a->companyId,$employeeId),ARRAY_A);}
 public static function updateEmployee(Actor $a,int $employeeId,array $data):array{
  return Transaction::run(function()use($a,$employeeId,$data){
  \ExcelHerbal\ERP7\Payroll\SalaryService::lockCompany($a->companyId);
  $db=Db::wpdb();$t=Db::table('employees');$e=$db->get_row($db->prepare("SELECT * FROM {$t} WHERE id=%d AND company_id=%d",$employeeId,$a->companyId),ARRAY_A);if(!$e)throw new DomainException('Employee not found.','employee_not_found',404);Guard::branch($a,(int)$e['assigned_branch_id'],Capabilities::EMP_MANAGE);$chg=[];
  if(array_key_exists('full_name',$data)){$v=trim((string)$data['full_name']);if($v===''||strlen($v)>190)throw new DomainException('Valid employee name is required.','employee_fields_invalid',422);$chg['full_name']=$v;}
  if(array_key_exists('mobile',$data)){$v=self::normaliseMobile((string)$data['mobile']);if($v!==''&&(strlen($v)<8||strlen($v)>15))throw new DomainException('Mobile number must contain 8 to 15 digits.','mobile_invalid',422);self::assertMobileAvailable($v,$employeeId);$chg['mobile']=$v?:null;}
  if(array_key_exists('email',$data)){$v=trim((string)$data['email']);if($v!==''&&!is_email($v))throw new DomainException('Valid employee email is required.','email_invalid',422);$chg['email']=$v?:null;}
  if(array_key_exists('monthly_salary',$data)&&round((float)$data['monthly_salary'],2)!==round((float)$e['monthly_salary'],2))throw new DomainException('Use the salary revision request and independent approval workflow.','salary_revision_required',409);
  if(array_key_exists('designation_code',$data)){$v=strtoupper(trim((string)$data['designation_code']));$ok=(int)$db->get_var($db->prepare("SELECT COUNT(*) FROM ".Db::table('designations')." WHERE company_id=%d AND code=%s AND status='active'",$a->companyId,$v));if(!$ok)throw new DomainException('Active designation not found.','designation_invalid',422);if(DesignationDefaults::requiresAccessManagement($v))Guard::cap($a,Capabilities::ACCESS_MANAGE);$chg['designation_code']=$v;}
  if(array_key_exists('reporting_designation_code',$data)){$v=HierarchyScope::normaliseCode((string)$data['reporting_designation_code']);if($v!==''&&!in_array($v,HierarchyScope::allowedReportingCategories(),true))throw new DomainException('Invalid reporting designation category.','reporting_designation_invalid',422);$chg['reporting_designation_code']=$v?:null;}
  if(array_key_exists('joining_date',$data)){if((string)$data['joining_date']!==(string)$e['joining_date']){$pr=$db->get_var($db->prepare('SELECT r.id FROM '.Db::table('payroll_runs').' r JOIN '.Db::table('payroll_items').' i ON i.payroll_run_id=r.id WHERE r.company_id=%d AND i.employee_id=%d LIMIT 1',$a->companyId,$employeeId));if($pr)throw new DomainException('Joining date is locked after payroll generation.','joining_date_payroll_locked',409);}$v=Input::date((string)$data['joining_date'],'Joining date');if(!empty($e['separation_date'])&&$v>(string)$e['separation_date'])throw new DomainException('Joining date cannot be after separation date.','joining_date_invalid',422);$chg['joining_date']=$v;}
  if(!$chg)throw new DomainException('No editable employee fields supplied.','parameter_required',422);$chg['updated_at']=Db::now();Db::mustUpdate($db,$t,$chg,['id'=>$employeeId,'company_id'=>$a->companyId]);if(array_key_exists('mobile',$chg)&&self::normaliseMobile((string)($e['mobile']??''))!==self::normaliseMobile((string)($chg['mobile']??'')))Db::mustQuery($db,$db->prepare("UPDATE ".Db::table('mobile_sessions')." SET revoked_at=%s WHERE employee_id=%d AND revoked_at IS NULL",Db::now(),$employeeId));Audit::add($a,'employee.update','employee',$employeeId,['branch_id'=>(int)$e['assigned_branch_id'],'fields'=>array_keys($chg),'old'=>array_intersect_key($e,$chg),'new'=>$chg]);unset($chg['updated_at']);return['id'=>$employeeId]+$chg;
 });
 }
 public static function employeeDesignations(Actor $a,int $employeeId):array{
  $db=Db::wpdb();$e=$db->get_row($db->prepare("SELECT id,assigned_branch_id,designation_code,reporting_designation_code FROM ".Db::table('employees')." WHERE id=%d AND company_id=%d",$employeeId,$a->companyId),ARRAY_A);if(!$e)throw new DomainException('Employee not found.','employee_not_found',404);HierarchyScope::assertCanViewEmployee($a,$employeeId);Guard::cap($a,Capabilities::EMP_VIEW);
  $rows=(array)$db->get_results($db->prepare("SELECT id,designation_code,assignment_type,effective_from,effective_to,active,created_by,created_at,deactivated_by,deactivated_at FROM ".Db::table('employee_designation_assignments')." WHERE company_id=%d AND employee_id=%d ORDER BY active DESC,effective_from DESC,id DESC",$a->companyId,$employeeId),ARRAY_A);
  return ['primary_designation_code'=>(string)$e['designation_code'],'reporting_designation_code'=>(string)($e['reporting_designation_code']??''),'reporting_category'=>HierarchyScope::reportingCategoryForCode((string)$e['designation_code'],(string)($e['reporting_designation_code']??'')),'additional_designations'=>$rows];
 }
 public static function assignEmployeeDesignation(Actor $a,int $employeeId,array $data):array{
  $code=HierarchyScope::normaliseCode((string)($data['designation_code']??''));$type=strtolower(trim((string)($data['assignment_type']??'additional')));$from=Input::date((string)($data['effective_from']??Db::today()),'Effective from');$to=Input::optionalDate((string)($data['effective_to']??''),'Effective to');
  if($code==='')throw new DomainException('Designation code is required.','designation_invalid',422);if(!in_array($type,['additional','temporary'],true))throw new DomainException('Assignment type must be additional or temporary.','designation_assignment_invalid',422);if($to!==null&&$to<$from)throw new DomainException('Effective to cannot be before effective from.','designation_assignment_invalid',422);
  return Transaction::run(function()use($a,$employeeId,$code,$type,$from,$to){
   $db=Db::wpdb();$e=$db->get_row($db->prepare("SELECT id,assigned_branch_id,designation_code FROM ".Db::table('employees')." WHERE id=%d AND company_id=%d AND status='active' FOR UPDATE",$employeeId,$a->companyId),ARRAY_A);if(!$e)throw new DomainException('Employee not found.','employee_not_found',404);Guard::branch($a,(int)$e['assigned_branch_id'],Capabilities::EMP_MANAGE);
   $ok=(int)$db->get_var($db->prepare("SELECT COUNT(*) FROM ".Db::table('designations')." WHERE company_id=%d AND code=%s AND status='active'",$a->companyId,$code));if(!$ok)throw new DomainException('Active designation not found.','designation_invalid',422);if($code===HierarchyScope::normaliseCode((string)$e['designation_code']))throw new DomainException('Additional designation duplicates the employee primary designation.','designation_assignment_redundant',409);
   $rangeEnd=$to?:'9999-12-31';$assignments=Db::table('employee_designation_assignments');$overlap=(int)$db->get_var($db->prepare("SELECT COUNT(*) FROM {$assignments} WHERE company_id=%d AND employee_id=%d AND designation_code=%s AND active=1 AND NOT(COALESCE(effective_to,'9999-12-31')<%s OR effective_from>%s)",$a->companyId,$employeeId,$code,$from,$rangeEnd));if($overlap)throw new DomainException('An overlapping active designation assignment already exists.','designation_assignment_overlap',409);
   Db::mustInsert($db,$assignments,['company_id'=>$a->companyId,'employee_id'=>$employeeId,'designation_code'=>$code,'assignment_type'=>$type,'effective_from'=>$from,'effective_to'=>$to,'active'=>1,'created_by'=>$a->employeeId,'created_at'=>Db::now()]);$id=(int)$db->insert_id;Audit::add($a,'employee.designation_assignment','employee',$employeeId,['assignment_id'=>$id,'designation_code'=>$code,'assignment_type'=>$type,'effective_from'=>$from,'effective_to'=>$to]);return['id'=>$id,'employee_id'=>$employeeId,'designation_code'=>$code,'assignment_type'=>$type,'effective_from'=>$from,'effective_to'=>$to,'active'=>true,'authority_inherited'=>false];
  });
 }
 public static function deactivateEmployeeDesignation(Actor $a,int $employeeId,int $assignmentId):array{
  $db=Db::wpdb();$t=Db::table('employee_designation_assignments');$r=$db->get_row($db->prepare("SELECT d.*,e.assigned_branch_id FROM {$t} d JOIN ".Db::table('employees')." e ON e.id=d.employee_id AND e.company_id=d.company_id WHERE d.id=%d AND d.employee_id=%d AND d.company_id=%d",$assignmentId,$employeeId,$a->companyId),ARRAY_A);if(!$r)throw new DomainException('Designation assignment not found.','designation_assignment_not_found',404);Guard::branch($a,(int)$r['assigned_branch_id'],Capabilities::EMP_MANAGE);if((int)$r['active']===1)Db::mustUpdate($db,$t,['active'=>0,'deactivated_by'=>$a->employeeId,'deactivated_at'=>Db::now()],['id'=>$assignmentId]);Audit::add($a,'employee.designation_assignment_deactivate','employee',$employeeId,['assignment_id'=>$assignmentId]);return['id'=>$assignmentId,'employee_id'=>$employeeId,'active'=>false];
 }
}
