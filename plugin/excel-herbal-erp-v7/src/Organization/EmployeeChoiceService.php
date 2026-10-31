<?php
namespace ExcelHerbal\ERP7\Organization;

use ExcelHerbal\ERP7\Database\Db;
use ExcelHerbal\ERP7\Domain\DomainException;
use ExcelHerbal\ERP7\Security\Actor;
use ExcelHerbal\ERP7\Security\HierarchyScope;

/**
 * Privacy-minimal employee picker rows. All callers MUST check their operation
 * capability; branch and hierarchy scope are independently enforced here.
 */
final class EmployeeChoiceService {
    public static function list(
        Actor $a,
        ?int $branch=null,
        bool $selfOnly=false,
        bool $excludeSelf=false,
        ?array $restrictedIds=null
    ):array {
        if($branch!==null&&($branch<1||!$a->hasBranch($branch))){
            throw new DomainException('Branch is outside effective authority.','branch_forbidden',403);
        }
        $ids=HierarchyScope::visibleEmployeeIds($a,$branch);
        if($selfOnly)$ids=array_values(array_intersect($ids,[$a->employeeId]));
        if($excludeSelf)$ids=array_values(array_diff($ids,[$a->employeeId]));
        if($restrictedIds!==null)$ids=array_values(array_intersect($ids,array_map('intval',$restrictedIds)));
        if(!$ids)return [];
        $db=Db::wpdb();
        $marks=implode(',',array_fill(0,count($ids),'%d'));
        $rows=(array)$db->get_results($db->prepare(
            "SELECT id,employee_code,full_name,designation_code,assigned_branch_id,reporting_employee_id FROM ".Db::table('employees')." WHERE company_id=%d AND status='active' AND id IN ({$marks}) ORDER BY full_name,id",
            ...array_merge([$a->companyId],$ids)
        ),ARRAY_A);
        return array_map(static function(array $row):array{
            $row['id']=(int)$row['id'];
            $row['assigned_branch_id']=(int)$row['assigned_branch_id'];
            $row['reporting_employee_id']=$row['reporting_employee_id']!==null?(int)$row['reporting_employee_id']:null;
            return $row;
        },$rows);
    }
}
