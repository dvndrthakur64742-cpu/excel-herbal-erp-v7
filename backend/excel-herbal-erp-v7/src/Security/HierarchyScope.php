<?php
namespace ExcelHerbal\ERP7\Security;

use ExcelHerbal\ERP7\Database\Db;
use ExcelHerbal\ERP7\Domain\DomainException;

/**
 * Central employee visibility engine.
 * Reporting designation is a grouping label only; authority comes from the
 * actor's primary designation + reporting tree + branch authority.
 */
final class HierarchyScope {
    public const FIELD_EXECUTIVE='FIELD_EXECUTIVE';
    public const ASM='ASM';
    public const SM='SM';
    public const BRANCH_MANAGER='BRANCH_MANAGER';
    public const REGIONAL='REGIONAL';
    public const SENIOR_MANAGEMENT='SENIOR_MANAGEMENT';
    public const SYSTEM_ADMIN='SYSTEM_ADMIN';

    public static function allowedReportingCategories():array {
        return [self::FIELD_EXECUTIVE,self::ASM,self::SM,self::BRANCH_MANAGER,self::REGIONAL,self::SENIOR_MANAGEMENT,self::SYSTEM_ADMIN];
    }

    public static function normaliseCode(string $code):string {
        $code=strtoupper(trim($code));
        $code=preg_replace('/[^A-Z0-9]+/','_',$code)?:'';
        return trim($code,'_');
    }

    public static function reportingCategoryForCode(string $primary,?string $explicit=null):string {
        $explicit=self::normaliseCode((string)$explicit);
        if($explicit!==''&&in_array($explicit,self::allowedReportingCategories(),true))return $explicit;
        $code=self::normaliseCode($primary);
        return match($code){
            'ASM','ASSISTANT_SALES_MANAGER'=>self::ASM,
            'SM','SALES_MANAGER'=>self::SM,
            'BM','BRANCH_MANAGER'=>self::BRANCH_MANAGER,
            'RM','REGIONAL_MANAGER','RC','REGIONAL_COORDINATOR','AGM','ASSISTANT_GENERAL_MANAGER'=>self::REGIONAL,
            'ZI','ZONAL_INSPECTOR','CM','CHAIRMAN','CHAIRMAN_MANAGING_DIRECTOR','MD','MANAGING_DIRECTOR'=>self::SENIOR_MANAGEMENT,
            'SYSADMIN','SYSTEM_ADMIN','ADMIN','ADMINISTRATOR'=>self::SYSTEM_ADMIN,
            default=>self::FIELD_EXECUTIVE,
        };
    }

    public static function categoryForEmployee(int $companyId,int $employeeId):string {
        $db=Db::wpdb();
        $row=$db->get_row($db->prepare("SELECT designation_code,reporting_designation_code FROM ".Db::table('employees')." WHERE company_id=%d AND id=%d",$companyId,$employeeId),ARRAY_A);
        if(!$row)throw new DomainException('Employee not found.','employee_not_found',404);
        return self::reportingCategoryForCode((string)$row['designation_code'],(string)($row['reporting_designation_code']??''));
    }

    public static function hasCompanyWideSystemAuthority(Actor $a):bool {
        return BranchAuthority::isCompanyWideAdmin($a->employeeId,$a->companyId,$a->designationCode);
    }

    /** @return int[] */
    public static function visibleEmployeeIds(Actor $a,?int $branchId=null):array {
        $db=Db::wpdb();
        $rows=(array)$db->get_results($db->prepare("SELECT id,assigned_branch_id,reporting_employee_id,designation_code FROM ".Db::table('employees')." WHERE company_id=%d AND status='active' ORDER BY id",$a->companyId),ARRAY_A);
        if(!$rows)return[];
        $actorCode=self::normaliseCode($a->designationCode);
        $byId=[];$children=[];
        foreach($rows as$r){$id=(int)$r['id'];$byId[$id]=$r;$mgr=(int)($r['reporting_employee_id']??0);if($mgr>0)$children[$mgr][]=$id;}
        if(!isset($byId[$a->employeeId]))return[$a->employeeId];

        $allCompany=self::hasCompanyWideSystemAuthority($a);
        if($allCompany){$ids=array_keys($byId);}
        elseif(in_array($actorCode,['BM','BRANCH_MANAGER'],true)){
            $ownBranch=(int)$byId[$a->employeeId]['assigned_branch_id'];$ids=[];foreach($byId as$id=>$r)if((int)$r['assigned_branch_id']===$ownBranch)$ids[]=$id;
        }
        elseif(in_array($actorCode,['RM','REGIONAL_MANAGER','RC','REGIONAL_COORDINATOR','AGM','ASSISTANT_GENERAL_MANAGER','ZI','ZONAL_INSPECTOR','CM','CHAIRMAN','CHAIRMAN_MANAGING_DIRECTOR','MD','MANAGING_DIRECTOR'],true)){
            $allowed=array_flip(array_map('intval',$a->branchIds));$ids=[];foreach($byId as$id=>$r)if(isset($allowed[(int)$r['assigned_branch_id']]))$ids[]=$id;
        }
        elseif(in_array($actorCode,['ASM','ASSISTANT_SALES_MANAGER','SM','SALES_MANAGER'],true)){
            $ids=[$a->employeeId];$queue=$children[$a->employeeId]??[];$seen=[];$allowed=array_flip(array_map('intval',$a->branchIds));
            while($queue){$id=(int)array_shift($queue);if(isset($seen[$id]))continue;$seen[$id]=1;if(isset($byId[$id])&&isset($allowed[(int)$byId[$id]['assigned_branch_id']]))$ids[]=$id;foreach(($children[$id]??[]) as$child)$queue[]=(int)$child;}
        } else {$ids=[$a->employeeId];}

        $ids=array_values(array_unique(array_map('intval',$ids)));
        if($branchId!==null&&$branchId>0){$ids=array_values(array_filter($ids,fn($id)=>isset($byId[$id])&&(int)$byId[$id]['assigned_branch_id']===$branchId));}
        sort($ids);return$ids;
    }


    /** @return int[] */
    public static function manageableEmployeeIds(Actor $a):array {
        $db=Db::wpdb();
        $rows=(array)$db->get_results($db->prepare("SELECT id,assigned_branch_id,reporting_employee_id FROM ".Db::table('employees')." WHERE company_id=%d AND status IN ('active','inactive') ORDER BY id",$a->companyId),ARRAY_A);
        if(!$rows)return[$a->employeeId];
        $byId=[];$children=[];
        foreach($rows as$r){$id=(int)$r['id'];$byId[$id]=$r;$mgr=(int)($r['reporting_employee_id']??0);if($mgr>0)$children[$mgr][]=$id;}
        $actorCode=self::normaliseCode($a->designationCode);
        if(self::hasCompanyWideSystemAuthority($a)){ $ids=array_keys($byId);sort($ids);return$ids; }
        $ids=[$a->employeeId];$queue=$children[$a->employeeId]??[];$seen=[];$allowed=array_flip(array_values(array_unique(array_merge([(int)$a->branchId],array_map('intval',$a->branchIds)))));
        while($queue){$id=(int)array_shift($queue);if(isset($seen[$id]))continue;$seen[$id]=1;if(!isset($byId[$id]))continue;$branch=(int)$byId[$id]['assigned_branch_id'];if(!isset($allowed[$branch]))continue;$ids[]=$id;foreach(($children[$id]??[]) as$child)$queue[]=(int)$child;}
        $ids=array_values(array_unique(array_map('intval',$ids)));sort($ids);return$ids;
    }

    public static function canManageEmployeeAccess(Actor $a,int $employeeId):bool {
        return in_array($employeeId,self::manageableEmployeeIds($a),true);
    }

    public static function assertCanManageEmployeeAccess(Actor $a,int $employeeId):void {
        if(!self::canManageEmployeeAccess($a,$employeeId))throw new DomainException('Employee access is outside delegated reporting authority.','employee_access_scope_forbidden',403);
    }

    public static function canViewEmployee(Actor $a,int $employeeId):bool {
        return in_array($employeeId,self::visibleEmployeeIds($a),true);
    }

    public static function assertCanViewEmployee(Actor $a,int $employeeId):void {
        if(!self::canViewEmployee($a,$employeeId))throw new DomainException('Employee is outside reporting hierarchy scope.','employee_scope_forbidden',403);
    }
}
