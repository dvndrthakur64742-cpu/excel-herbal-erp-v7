<?php
namespace ExcelHerbal\ERP7\Security;
use ExcelHerbal\ERP7\Database\Db;
final class BranchAuthority {
    public static function isCompanyWideAdmin(int $employeeId,int $companyId,string $designationCode=''):bool{
        $designation=strtoupper(trim($designationCode));
        if(in_array($designation,['SYSADMIN','SYSTEM_ADMIN','ADMIN','ADMINISTRATOR'],true))return true;
        $db=Db::wpdb();
        return (bool)$db->get_var($db->prepare(
            "SELECT 1 FROM ".Db::table('employee_roles')." er JOIN ".Db::table('roles')." r ON r.id=er.role_id AND r.company_id=er.company_id AND r.active=1 JOIN ".Db::table('role_capabilities')." rc ON rc.role_id=r.id AND rc.active=1 AND rc.capability=%s WHERE er.company_id=%d AND er.employee_id=%d AND er.active=1 AND UPPER(r.code) IN ('SYSTEM_ADMIN','SYSADMIN','ADMIN','ADMINISTRATOR') LIMIT 1",
            Capabilities::ACCESS_MANAGE,$companyId,$employeeId
        ));
    }

    /** @return int[] */
    public static function ids(int $employeeId,int $companyId):array{
        $db=Db::wpdb();$emp=Db::table('employees');$auth=Db::table('employee_branch_authorities');$branches=Db::table('branches');
        $employee=$db->get_row($db->prepare("SELECT id,assigned_branch_id,designation_code FROM {$emp} WHERE id=%d AND company_id=%d AND status='active'",$employeeId,$companyId),ARRAY_A);
        if(!$employee)return[];
        $isSystemAdmin=self::isCompanyWideAdmin($employeeId,$companyId,(string)($employee['designation_code']??''));
        if($isSystemAdmin){
            return array_map('intval',(array)$db->get_col($db->prepare("SELECT id FROM {$branches} WHERE company_id=%d AND status='active' ORDER BY id",$companyId)));
        }
        $home=(int)$db->get_var($db->prepare("SELECT b.id FROM {$branches} b WHERE b.id=%d AND b.company_id=%d AND b.status='active'",(int)$employee['assigned_branch_id'],$companyId));
        $ids=$home?[$home]:[];
        $rows=$db->get_col($db->prepare("SELECT a.branch_id FROM {$auth} a JOIN {$branches} b ON b.id=a.branch_id AND b.company_id=a.company_id AND b.status='active' WHERE a.company_id=%d AND a.employee_id=%d AND a.active=1 AND a.valid_from<=%s AND (a.valid_until IS NULL OR a.valid_until>%s)",$companyId,$employeeId,Db::now(),Db::now()));
        foreach((array)$rows as$id)$ids[]=(int)$id;
        $ids=array_values(array_unique(array_filter($ids)));sort($ids);return$ids;
    }
}
