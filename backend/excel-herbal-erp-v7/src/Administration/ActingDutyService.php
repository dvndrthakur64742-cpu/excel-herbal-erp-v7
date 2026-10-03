<?php
namespace ExcelHerbal\ERP7\Administration;

use ExcelHerbal\ERP7\Database\Db;
use ExcelHerbal\ERP7\Database\Transaction;
use ExcelHerbal\ERP7\Domain\DomainException;
use ExcelHerbal\ERP7\Security\Actor;
use ExcelHerbal\ERP7\Security\Audit;
use ExcelHerbal\ERP7\Security\BranchAuthority;
use ExcelHerbal\ERP7\Security\Capabilities;
use ExcelHerbal\ERP7\Security\DesignationDefaults;
use ExcelHerbal\ERP7\Security\Guard;
use ExcelHerbal\ERP7\Security\HierarchyScope;

/**
 * Exact-action, exact-branch acting duty. It never mutates permanent identity,
 * designation, role, branch-authority or reporting-manager state.
 */
final class ActingDutyService
{
    /** @return array<string,string> action => permanent capability */
    public static function actionCapabilities(): array
    {
        return [
            'daily.approve' => Capabilities::DAILY_APPROVE,
            'daily.issue' => Capabilities::DAILY_ISSUE,
            'daily.final_post' => Capabilities::DAILY_REVIEW,
            'workforce.leave.decision' => Capabilities::LEAVE_MANAGE,
        ];
    }

    public static function employeeChoices(Actor $a,int $branchId):array
    {
        Guard::branch($a,$branchId,Capabilities::DELEGATION_MANAGE);
        $ids=HierarchyScope::visibleEmployeeIds($a,$branchId);
        if(!$ids)return[];
        $db=Db::wpdb();$sql="SELECT id,employee_code,full_name,designation_code FROM ".Db::table('employees')." WHERE company_id=%d AND assigned_branch_id=%d AND status='active' AND id IN (".implode(',',array_map('intval',$ids)).") ORDER BY full_name,id";
        return(array)$db->get_results($db->prepare($sql,$a->companyId,$branchId),ARRAY_A);
    }

    public static function list(Actor $a, ?int $branchId = null): array
    {
        $db=Db::wpdb();$t=Db::table('acting_delegations');$e=Db::table('employees');
        if($branchId!==null&&$branchId>0&&!$a->hasBranch($branchId)&&!self::hasIncomingDelegationInBranch($a,$branchId))throw new DomainException('Branch is outside effective authority.','branch_forbidden',403);
        $where='d.company_id=%d';$args=[$a->companyId];
        if($a->can(Capabilities::DELEGATION_MANAGE)){
            $branches=array_values(array_unique(array_map('intval',$a->branchIds)));$visible=HierarchyScope::visibleEmployeeIds($a);
            if($branches&&$visible){$bp=implode(',',array_fill(0,count($branches),'%d'));$ep=implode(',',array_fill(0,count($visible),'%d'));$where.=' AND ((d.branch_id IN ('.$bp.') AND (d.delegator_employee_id IN ('.$ep.') OR d.delegate_employee_id IN ('.$ep.'))) OR d.delegator_employee_id=%d OR d.delegate_employee_id=%d)';$args=array_merge($args,$branches,$visible,$visible,[$a->employeeId,$a->employeeId]);}
            else{$where.=' AND (d.delegator_employee_id=%d OR d.delegate_employee_id=%d)';$args[]=$a->employeeId;$args[]=$a->employeeId;}
        } else {
            $where.=' AND (d.delegator_employee_id=%d OR d.delegate_employee_id=%d)';$args[]=$a->employeeId;$args[]=$a->employeeId;
        }
        if($branchId!==null&&$branchId>0){$where.=' AND d.branch_id=%d';$args[]=$branchId;}
        $sql="SELECT d.*,dr.full_name delegator_name,de.full_name delegate_name FROM {$t} d JOIN {$e} dr ON dr.id=d.delegator_employee_id AND dr.company_id=d.company_id JOIN {$e} de ON de.id=d.delegate_employee_id AND de.company_id=d.company_id WHERE {$where} ORDER BY d.starts_at DESC,d.id DESC LIMIT 250";
        $rows=(array)$db->get_results($db->prepare($sql,...$args),ARRAY_A);$now=Db::now();
        foreach($rows as&$r){$r['effective_status']=self::effectiveStatus($r,$now);$r['can_revoke']=self::canRevokeRow($a,$r);}unset($r);
        return['actions'=>array_keys(self::actionCapabilities()),'delegations'=>$rows];
    }

    public static function create(Actor $a,array $data): array
    {
        Guard::cap($a,Capabilities::DELEGATION_MANAGE);
        $branch=(int)($data['branch_id']??0);if($branch<1||!$a->hasBranch($branch))throw new DomainException('Branch is outside effective authority.','branch_forbidden',403);
        $delegator=(int)($data['delegator_employee_id']??$a->employeeId);$delegate=(int)($data['delegate_employee_id']??0);$action=trim((string)($data['action_code']??''));$reason=trim((string)($data['reason']??''));
        if($delegate<1)throw new DomainException('Delegate employee is required.','delegate_required',422);if($delegator===$delegate)throw new DomainException('Self-delegation is forbidden.','delegation_self_forbidden',422);
        if(strlen($reason)<5)throw new DomainException('Delegation reason is required.','delegation_reason_required',422);
        if(!isset(self::actionCapabilities()[$action]))throw new DomainException('Unsupported delegation action.','delegation_action_invalid',422);
        if($delegator!==$a->employeeId){if(!$a->can(Capabilities::ACCESS_MANAGE))throw new DomainException('Only access administrators may create delegation for another delegator.','delegator_forbidden',403);HierarchyScope::assertCanViewEmployee($a,$delegator);}
        [$starts,$ends]=self::window((string)($data['starts_at']??''),(string)($data['ends_at']??''));
        if(!self::employeeHasPermanentAuthority($a->companyId,$delegator,$branch,$action))throw new DomainException('Delegator does not own this exact action in this branch.','delegator_authority_missing',403);
        $db=Db::wpdb();$emp=$db->get_row($db->prepare("SELECT id,status FROM ".Db::table('employees')." WHERE id=%d AND company_id=%d",$delegate,$a->companyId),ARRAY_A);if(!$emp||$emp['status']!=='active')throw new DomainException('Delegate must be an active employee.','delegate_invalid',422);HierarchyScope::assertCanViewEmployee($a,$delegate);
        return Transaction::run(function()use($a,$delegator,$delegate,$branch,$action,$starts,$ends,$reason){
            $db=Db::wpdb();$t=Db::table('acting_delegations');
            $overlap=$db->get_row($db->prepare("SELECT id FROM {$t} WHERE company_id=%d AND delegator_employee_id=%d AND branch_id=%d AND action_code=%s AND status='active' AND NOT(ends_at<=%s OR starts_at>=%s) ORDER BY id LIMIT 1 FOR UPDATE",$a->companyId,$delegator,$branch,$action,$starts,$ends),ARRAY_A);
            if($overlap)throw new DomainException('An overlapping active delegation already exists.','delegation_overlap',409);
            Db::mustInsert($db,$t,['company_id'=>$a->companyId,'delegator_employee_id'=>$delegator,'delegate_employee_id'=>$delegate,'branch_id'=>$branch,'action_code'=>$action,'starts_at'=>$starts,'ends_at'=>$ends,'reason'=>$reason,'status'=>'active','created_by'=>$a->employeeId,'created_at'=>Db::now()]);$id=(int)$db->insert_id;
            Audit::add($a,'acting.delegation_create','acting_delegation',$id,['branch_id'=>$branch,'delegator_employee_id'=>$delegator,'delegate_employee_id'=>$delegate,'action_code'=>$action,'starts_at'=>$starts,'ends_at'=>$ends,'reason'=>$reason]);
            return['id'=>$id,'status'=>'active','delegator_employee_id'=>$delegator,'delegate_employee_id'=>$delegate,'branch_id'=>$branch,'action_code'=>$action,'starts_at'=>$starts,'ends_at'=>$ends];
        });
    }

    public static function revoke(Actor $a,int $id,string $reason): array
    {
        $reason=trim($reason);if(strlen($reason)<5)throw new DomainException('Revoke reason is required.','delegation_revoke_reason_required',422);
        return Transaction::run(function()use($a,$id,$reason){$db=Db::wpdb();$t=Db::table('acting_delegations');$r=$db->get_row($db->prepare("SELECT * FROM {$t} WHERE id=%d AND company_id=%d FOR UPDATE",$id,$a->companyId),ARRAY_A);if(!$r)throw new DomainException('Delegation not found.','delegation_not_found',404);if(!self::canRevokeRow($a,$r))throw new DomainException('Delegation revoke is outside authority.','delegation_revoke_forbidden',403);if($r['status']!=='active')throw new DomainException('Delegation is not active.','delegation_not_active',409);Db::mustUpdate($db,$t,['status'=>'revoked','revoked_by'=>$a->employeeId,'revoked_at'=>Db::now(),'revoke_reason'=>$reason],['id'=>$id]);Audit::add($a,'acting.delegation_revoke','acting_delegation',$id,['branch_id'=>(int)$r['branch_id'],'delegator_employee_id'=>(int)$r['delegator_employee_id'],'delegate_employee_id'=>(int)$r['delegate_employee_id'],'action_code'=>(string)$r['action_code'],'reason'=>$reason]);return['id'=>$id,'status'=>'revoked'];});
    }

    public static function unavailability(Actor $a,?int $branchId=null):array
    {
        $db=Db::wpdb();$t=Db::table('acting_unavailability');$e=Db::table('employees');$where='u.company_id=%d';$args=[$a->companyId];
        if($a->can(Capabilities::DELEGATION_MANAGE)){$branches=array_values(array_unique(array_map('intval',$a->branchIds)));$visible=HierarchyScope::visibleEmployeeIds($a);if(!$branches||!$visible)return[];$bp=implode(',',array_fill(0,count($branches),'%d'));$ep=implode(',',array_fill(0,count($visible),'%d'));$where.=' AND u.branch_id IN ('.$bp.') AND u.employee_id IN ('.$ep.')';$args=array_merge($args,$branches,$visible);}else{$where.=' AND u.employee_id=%d';$args[]=$a->employeeId;}
        if($branchId!==null&&$branchId>0){if(!$a->hasBranch($branchId))throw new DomainException('Branch is outside effective authority.','branch_forbidden',403);$where.=' AND u.branch_id=%d';$args[]=$branchId;}
        $rows=(array)$db->get_results($db->prepare("SELECT u.*,e.full_name employee_name FROM {$t} u JOIN {$e} e ON e.id=u.employee_id AND e.company_id=u.company_id WHERE {$where} ORDER BY u.starts_at DESC,u.id DESC LIMIT 250",...$args),ARRAY_A);$now=Db::now();foreach($rows as&$r)$r['effective_status']=self::effectiveStatus($r,$now);unset($r);return$rows;
    }

    public static function createUnavailability(Actor $a,array $data):array
    {
        Guard::cap($a,Capabilities::DELEGATION_MANAGE);$branch=(int)($data['branch_id']??0);if($branch<1||!$a->hasBranch($branch))throw new DomainException('Branch is outside effective authority.','branch_forbidden',403);$employee=(int)($data['employee_id']??$a->employeeId);if($employee!==$a->employeeId){if(!$a->can(Capabilities::ACCESS_MANAGE))throw new DomainException('Only access administrators may mark another employee unavailable.','unavailability_employee_forbidden',403);HierarchyScope::assertCanViewEmployee($a,$employee);}$reason=trim((string)($data['reason']??''));if(strlen($reason)<5)throw new DomainException('Unavailability reason is required.','unavailability_reason_required',422);[$starts,$ends]=self::window((string)($data['starts_at']??''),(string)($data['ends_at']??''));$db=Db::wpdb();$valid=(int)$db->get_var($db->prepare("SELECT COUNT(*) FROM ".Db::table('employees')." WHERE id=%d AND company_id=%d AND status='active'",$employee,$a->companyId));if(!$valid)throw new DomainException('Active employee not found.','employee_not_found',404);
        return Transaction::run(function()use($a,$employee,$branch,$starts,$ends,$reason){$db=Db::wpdb();$t=Db::table('acting_unavailability');$overlap=$db->get_row($db->prepare("SELECT id FROM {$t} WHERE company_id=%d AND employee_id=%d AND branch_id=%d AND status='active' AND NOT(ends_at<=%s OR starts_at>=%s) ORDER BY id LIMIT 1 FOR UPDATE",$a->companyId,$employee,$branch,$starts,$ends),ARRAY_A);if($overlap)throw new DomainException('An overlapping unavailability window already exists.','unavailability_overlap',409);Db::mustInsert($db,$t,['company_id'=>$a->companyId,'employee_id'=>$employee,'branch_id'=>$branch,'starts_at'=>$starts,'ends_at'=>$ends,'reason'=>$reason,'status'=>'active','created_by'=>$a->employeeId,'created_at'=>Db::now()]);$id=(int)$db->insert_id;Audit::add($a,'acting.unavailability_create','acting_unavailability',$id,['branch_id'=>$branch,'employee_id'=>$employee,'starts_at'=>$starts,'ends_at'=>$ends,'reason'=>$reason]);return['id'=>$id,'status'=>'active','employee_id'=>$employee,'branch_id'=>$branch,'starts_at'=>$starts,'ends_at'=>$ends];});
    }

    public static function revokeUnavailability(Actor $a,int $id,string $reason):array
    {
        $reason=trim($reason);if(strlen($reason)<5)throw new DomainException('Revoke reason is required.','unavailability_revoke_reason_required',422);return Transaction::run(function()use($a,$id,$reason){$db=Db::wpdb();$t=Db::table('acting_unavailability');$r=$db->get_row($db->prepare("SELECT * FROM {$t} WHERE id=%d AND company_id=%d FOR UPDATE",$id,$a->companyId),ARRAY_A);if(!$r)throw new DomainException('Unavailability window not found.','unavailability_not_found',404);if((int)$r['employee_id']!==$a->employeeId&&(!($a->can(Capabilities::ACCESS_MANAGE)&&$a->hasBranch((int)$r['branch_id']))||!HierarchyScope::canViewEmployee($a,(int)$r['employee_id'])))throw new DomainException('Unavailability revoke is outside authority.','unavailability_revoke_forbidden',403);if($r['status']!=='active')throw new DomainException('Unavailability window is not active.','unavailability_not_active',409);Db::mustUpdate($db,$t,['status'=>'revoked','revoked_by'=>$a->employeeId,'revoked_at'=>Db::now(),'revoke_reason'=>$reason],['id'=>$id]);Audit::add($a,'acting.unavailability_revoke','acting_unavailability',$id,['branch_id'=>(int)$r['branch_id'],'employee_id'=>(int)$r['employee_id'],'reason'=>$reason]);return['id'=>$id,'status'=>'revoked'];});
    }

    /** Runtime mutation gate. @return array{mode:string,delegation_id:?int,delegator_employee_id:?int} */
    public static function assertAction(Actor $a,int $branchId,string $actionCode,?int $makerEmployeeId=null):array
    {
        $cap=self::actionCapabilities()[$actionCode]??null;if($cap===null)throw new DomainException('Unsupported acting-duty action.','delegation_action_invalid',500);
        if($makerEmployeeId!==null&&$makerEmployeeId===$a->employeeId)throw new DomainException('Maker-checker separation is required.','maker_checker_required',409);
        if($a->can($cap)&&$a->hasBranch($branchId))return['mode'=>'permanent','delegation_id'=>null,'delegator_employee_id'=>null];
        $db=Db::wpdb();$t=Db::table('acting_delegations');$now=Db::now();$rows=(array)$db->get_results($db->prepare("SELECT * FROM {$t} WHERE company_id=%d AND delegate_employee_id=%d AND branch_id=%d AND action_code=%s AND status='active' AND starts_at<=%s AND ends_at>%s ORDER BY ends_at ASC,id ASC",$a->companyId,$a->employeeId,$branchId,$actionCode,$now,$now),ARRAY_A);
        foreach($rows as$r){$delegator=(int)$r['delegator_employee_id'];if(!self::employeeHasPermanentAuthority($a->companyId,$delegator,$branchId,$actionCode))continue;Audit::add($a,'acting.delegated_use','acting_delegation',(int)$r['id'],['branch_id'=>$branchId,'delegator_employee_id'=>$delegator,'delegate_employee_id'=>$a->employeeId,'action_code'=>$actionCode]);return['mode'=>'delegated','delegation_id'=>(int)$r['id'],'delegator_employee_id'=>$delegator];}
        throw new DomainException('Exact action authority is not available for this branch.','acting_authority_denied',403);
    }

    /** Exact-action work queue for the current delegate; never exposes generic branch data. */
    public static function inbox(Actor $a):array
    {
        $db=Db::wpdb();$now=Db::now();$delegations=(array)$db->get_results($db->prepare("SELECT * FROM ".Db::table('acting_delegations')." WHERE company_id=%d AND delegate_employee_id=%d AND status='active' AND starts_at<=%s AND ends_at>%s ORDER BY ends_at ASC,id ASC",$a->companyId,$a->employeeId,$now,$now),ARRAY_A);$items=[];$seen=[];
        foreach($delegations as$d){$branch=(int)$d['branch_id'];$action=(string)$d['action_code'];if(!self::employeeHasPermanentAuthority($a->companyId,(int)$d['delegator_employee_id'],$branch,$action))continue;$rows=[];
            if($action==='daily.approve'){$rows=(array)$db->get_results($db->prepare("SELECT r.id source_id,r.status,c.id daily_cycle_id,c.business_date,c.employee_id,e.employee_code,e.full_name employee_name FROM ".Db::table('daily_requests')." r JOIN ".Db::table('daily_cycles')." c ON c.id=r.daily_cycle_id JOIN ".Db::table('employees')." e ON e.id=c.employee_id AND e.company_id=c.company_id WHERE c.company_id=%d AND c.branch_id=%d AND r.status='submitted' AND r.requested_by<>%d ORDER BY c.business_date,r.id",$a->companyId,$branch,$a->employeeId),ARRAY_A);}
            elseif($action==='daily.issue'){$rows=(array)$db->get_results($db->prepare("SELECT r.id source_id,r.status,c.id daily_cycle_id,c.business_date,c.employee_id,e.employee_code,e.full_name employee_name FROM ".Db::table('daily_requests')." r JOIN ".Db::table('daily_cycles')." c ON c.id=r.daily_cycle_id JOIN ".Db::table('employees')." e ON e.id=c.employee_id AND e.company_id=c.company_id WHERE c.company_id=%d AND c.branch_id=%d AND r.status='approved' AND r.requested_by<>%d ORDER BY c.business_date,r.id",$a->companyId,$branch,$a->employeeId),ARRAY_A);}
            elseif($action==='daily.final_post'){$rows=(array)$db->get_results($db->prepare("SELECT c.id source_id,c.status,c.business_date,c.employee_id,e.employee_code,e.full_name employee_name,s.id settlement_id FROM ".Db::table('daily_cycles')." c JOIN ".Db::table('evening_settlements')." s ON s.daily_cycle_id=c.id JOIN ".Db::table('employees')." e ON e.id=c.employee_id AND e.company_id=c.company_id WHERE c.company_id=%d AND c.branch_id=%d AND c.status='evening_submitted' AND s.status='submitted' AND s.submitted_by<>%d ORDER BY c.business_date,c.id",$a->companyId,$branch,$a->employeeId),ARRAY_A);}
            elseif($action==='workforce.leave.decision'){$rows=(array)$db->get_results($db->prepare("SELECT l.id source_id,l.status,l.date_from,l.date_to,l.leave_type,l.employee_id,e.employee_code,e.full_name employee_name FROM ".Db::table('leave_requests')." l JOIN ".Db::table('employees')." e ON e.id=l.employee_id AND e.company_id=l.company_id WHERE l.company_id=%d AND l.branch_id=%d AND l.status='submitted' AND l.employee_id<>%d ORDER BY l.requested_at,l.id",$a->companyId,$branch,$a->employeeId),ARRAY_A);}
            foreach($rows as$r){$key=$action.':'.(int)$r['source_id'];if(isset($seen[$key]))continue;$seen[$key]=1;$items[]=['delegation_id'=>(int)$d['id'],'delegator_employee_id'=>(int)$d['delegator_employee_id'],'branch_id'=>$branch,'action_code'=>$action,'expires_at'=>(string)$d['ends_at'],'reason'=>(string)$d['reason'],'work'=>$r];}
        }
        return['items'=>$items,'count'=>count($items)];
    }

    public static function authorityStatus(Actor $a,int $branchId,string $actionCode,?int $primaryEmployeeId=null,?int $makerEmployeeId=null):array
    {
        if($branchId<1)throw new DomainException('Branch is required.','branch_required',422);if(!isset(self::actionCapabilities()[$actionCode]))throw new DomainException('Unsupported acting-duty action.','delegation_action_invalid',422);
        $incoming=self::incomingDelegation($a,$branchId,$actionCode);if(!$a->hasBranch($branchId)&&$incoming===null)throw new DomainException('Branch is outside effective authority.','branch_forbidden',403);
        $branchManaged=$a->hasBranch($branchId)&&$a->can(Capabilities::DELEGATION_MANAGE);
        if(!$branchManaged)return['branch_id'=>$branchId,'action_code'=>$actionCode,'actor_mode'=>$incoming!==null?'delegated':'none','incoming_delegation'=>$incoming,'primary_authority'=>null,'fallback_authority'=>null,'fallback_active'=>false,'permanent_holders'=>[]];
        $db=Db::wpdb();$employees=(array)$db->get_results($db->prepare("SELECT e.id,e.employee_code,e.full_name,e.designation_code,COALESCE(d.sequence_no,999999) sequence_no FROM ".Db::table('employees')." e LEFT JOIN ".Db::table('designations')." d ON d.company_id=e.company_id AND d.code=e.designation_code AND d.status='active' WHERE e.company_id=%d AND e.status='active' ORDER BY sequence_no,e.id",$a->companyId),ARRAY_A);
        $holders=[];foreach($employees as$e){$eid=(int)$e['id'];if(self::employeeHasPermanentAuthority($a->companyId,$eid,$branchId,$actionCode)){$e['unavailable']=self::employeeUnavailable($a->companyId,$eid,$branchId);$holders[]=$e;}}
        if($primaryEmployeeId===null&&$holders)$primaryEmployeeId=(int)$holders[0]['id'];$primary=null;foreach($holders as$h)if((int)$h['id']===$primaryEmployeeId){$primary=$h;break;}
        $fallback=null;if($primary&&$primary['unavailable']){foreach($holders as$h){if((int)$h['id']===$primaryEmployeeId)continue;if($makerEmployeeId!==null&&(int)$h['id']===$makerEmployeeId)continue;if(!$h['unavailable']){$fallback=$h;break;}}}
        $actorMode='none';if($a->can(self::actionCapabilities()[$actionCode])&&$a->hasBranch($branchId))$actorMode='permanent';elseif($incoming!==null)$actorMode='delegated';
        return['branch_id'=>$branchId,'action_code'=>$actionCode,'actor_mode'=>$actorMode,'incoming_delegation'=>$incoming,'primary_authority'=>$primary,'fallback_authority'=>$fallback,'fallback_active'=>$fallback!==null&&$primary!==null&&$primary['unavailable']===true,'permanent_holders'=>$holders];
    }

    private static function incomingDelegation(Actor $a,int $branchId,string $actionCode):?array
    {
        $db=Db::wpdb();$now=Db::now();$rows=(array)$db->get_results($db->prepare("SELECT * FROM ".Db::table('acting_delegations')." WHERE company_id=%d AND delegate_employee_id=%d AND branch_id=%d AND action_code=%s AND status='active' AND starts_at<=%s AND ends_at>%s ORDER BY ends_at ASC,id ASC",$a->companyId,$a->employeeId,$branchId,$actionCode,$now,$now),ARRAY_A);foreach($rows as$r)if(self::employeeHasPermanentAuthority($a->companyId,(int)$r['delegator_employee_id'],$branchId,$actionCode))return$r;return null;
    }

    private static function hasIncomingDelegationInBranch(Actor $a,int $branchId):bool
    {
        $db=Db::wpdb();$now=Db::now();return (bool)$db->get_var($db->prepare("SELECT 1 FROM ".Db::table('acting_delegations')." WHERE company_id=%d AND delegate_employee_id=%d AND branch_id=%d AND status='active' AND starts_at<=%s AND ends_at>%s LIMIT 1",$a->companyId,$a->employeeId,$branchId,$now,$now));
    }

    private static function canRevokeRow(Actor $a,array $row):bool
    {
        if((int)$row['delegator_employee_id']===$a->employeeId)return true;if(!$a->can(Capabilities::ACCESS_MANAGE)||!$a->hasBranch((int)$row['branch_id']))return false;return HierarchyScope::canViewEmployee($a,(int)$row['delegator_employee_id'])||HierarchyScope::canViewEmployee($a,(int)$row['delegate_employee_id']);
    }

    private static function effectiveStatus(array $row,string $now):string
    {
        if((string)$row['status']!=='active')return(string)$row['status'];if((string)$row['ends_at']<=$now)return'expired';if((string)$row['starts_at']>$now)return'scheduled';return'active';
    }

    /** Permanent means designation + explicit roles/overrides + permanent branch authority only. */
    private static function employeeHasPermanentAuthority(int $companyId,int $employeeId,int $branchId,string $actionCode):bool
    {
        $cap=self::actionCapabilities()[$actionCode]??null;if($cap===null)return false;$db=Db::wpdb();$e=$db->get_row($db->prepare("SELECT id,designation_code FROM ".Db::table('employees')." WHERE id=%d AND company_id=%d AND status='active'",$employeeId,$companyId),ARRAY_A);if(!$e)return false;$caps=DesignationDefaults::forCode((string)$e['designation_code']);$roleCaps=(array)$db->get_col($db->prepare("SELECT DISTINCT rc.capability FROM ".Db::table('employee_roles')." er JOIN ".Db::table('role_capabilities')." rc ON rc.role_id=er.role_id AND rc.active=1 JOIN ".Db::table('roles')." r ON r.id=er.role_id AND r.active=1 WHERE er.company_id=%d AND er.employee_id=%d AND er.active=1",$companyId,$employeeId));$caps=array_values(array_unique(array_merge($caps,array_map('strval',$roleCaps))));$ov=(array)$db->get_results($db->prepare("SELECT capability,effect FROM ".Db::table('employee_capability_overrides')." WHERE company_id=%d AND employee_id=%d AND active=1",$companyId,$employeeId),ARRAY_A);foreach($ov as$r){$c=(string)$r['capability'];if($r['effect']==='grant')$caps[]=$c;elseif($r['effect']==='deny')$caps=array_values(array_diff($caps,[$c]));}if(!in_array($cap,array_values(array_unique($caps)),true))return false;$branches=BranchAuthority::ids($employeeId,$companyId);$designation=HierarchyScope::normaliseCode((string)$e['designation_code']);if(in_array($designation,['ZI','ZONAL_INSPECTOR','CM','CHAIRMAN','CHAIRMAN_MANAGING_DIRECTOR','MD','MANAGING_DIRECTOR'],true))$branches=array_map('intval',(array)$db->get_col($db->prepare("SELECT id FROM ".Db::table('branches')." WHERE company_id=%d AND status='active'",$companyId)));return in_array($branchId,$branches,true);
    }

    private static function employeeUnavailable(int $companyId,int $employeeId,int $branchId):bool
    {
        $db=Db::wpdb();$today=Db::today();$now=Db::now();$leave=(bool)$db->get_var($db->prepare("SELECT 1 FROM ".Db::table('leave_requests')." WHERE company_id=%d AND employee_id=%d AND status='approved' AND date_from<=%s AND date_to>=%s LIMIT 1",$companyId,$employeeId,$today,$today));if($leave)return true;$attendance=$db->get_var($db->prepare("SELECT status FROM ".Db::table('attendance')." WHERE company_id=%d AND employee_id=%d AND business_date=%s LIMIT 1",$companyId,$employeeId,$today));if(in_array(strtolower((string)$attendance),['absent','leave','unavailable'],true))return true;$manual=(bool)$db->get_var($db->prepare("SELECT 1 FROM ".Db::table('acting_unavailability')." WHERE company_id=%d AND employee_id=%d AND branch_id=%d AND status='active' AND starts_at<=%s AND ends_at>%s LIMIT 1",$companyId,$employeeId,$branchId,$now,$now));return$manual;
    }

    /** @return array{0:string,1:string} UTC mysql datetimes */
    private static function window(string $startsAt,string $endsAt):array
    {
        $starts=self::dateTime($startsAt,'starts_at');$ends=self::dateTime($endsAt,'ends_at');if($ends<=$starts)throw new DomainException('Delegation end must be after start.','delegation_window_invalid',422);$max=(new \DateTimeImmutable($starts,new \DateTimeZone('UTC')))->modify('+31 days')->format('Y-m-d H:i:s');if($ends>$max)throw new DomainException('Acting-duty window cannot exceed 31 days.','delegation_window_too_long',422);return[$starts,$ends];
    }

    private static function dateTime(string $value,string $field):string
    {
        $value=trim($value);if($value==='')throw new DomainException($field.' is required.','parameter_required',422);try{$hasZone=(bool)preg_match('/(?:Z|[+\-]\d\d:\d\d)$/i',$value);$tz=$hasZone?null:(function_exists('wp_timezone')?wp_timezone():new \DateTimeZone('UTC'));$dt=new \DateTimeImmutable($value,$tz?:null);return$dt->setTimezone(new \DateTimeZone('UTC'))->format('Y-m-d H:i:s');}catch(\Throwable $e){throw new DomainException($field.' must be a valid datetime.','parameter_invalid',422);}
    }
}
