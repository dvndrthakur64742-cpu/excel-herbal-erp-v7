<?php
namespace ExcelHerbal\ERP7\Security;
use ExcelHerbal\ERP7\Database\Db;
final class BranchAuthority {
    /** @return int[] */ public static function ids(int $employeeId,int $companyId):array{$db=Db::wpdb();$emp=Db::table('employees');$auth=Db::table('employee_branch_authorities');$branches=Db::table('branches');$home=(int)$db->get_var($db->prepare("SELECT e.assigned_branch_id FROM {$emp} e JOIN {$branches} b ON b.id=e.assigned_branch_id AND b.company_id=e.company_id AND b.status='active' WHERE e.id=%d AND e.company_id=%d AND e.status='active'",$employeeId,$companyId));$ids=$home?[$home]:[];$rows=$db->get_col($db->prepare("SELECT a.branch_id FROM {$auth} a JOIN {$branches} b ON b.id=a.branch_id AND b.company_id=a.company_id AND b.status='active' WHERE a.company_id=%d AND a.employee_id=%d AND a.active=1 AND a.valid_from<=%s AND (a.valid_until IS NULL OR a.valid_until>%s)",$companyId,$employeeId,Db::now(),Db::now()));foreach((array)$rows as$id)$ids[]=(int)$id;$ids=array_values(array_unique(array_filter($ids)));sort($ids);return$ids;}
}
