<?php
namespace ExcelHerbal\ERP7\Security;
use ExcelHerbal\ERP7\Database\Db;
use ExcelHerbal\ERP7\Domain\DomainException;
final class Guard {
    public static function cap(Actor $a,string $cap):void{if(!$a->can($cap))throw new DomainException('Permission denied.','permission_denied',403);}
    public static function any(Actor $a,array $caps):void{foreach($caps as$cap)if($a->can((string)$cap))return;throw new DomainException('Permission denied.','permission_denied',403);}
    public static function branch(Actor $a,int $branchId,string $cap):void{self::cap($a,$cap);if($branchId<1||!$a->hasBranch($branchId))throw new DomainException('Branch is outside effective authority.','branch_forbidden',403);}
    public static function branchAny(Actor $a,int $branchId,array $caps):void{self::any($a,$caps);if($branchId<1||!$a->hasBranch($branchId))throw new DomainException('Branch is outside effective authority.','branch_forbidden',403);}
    public static function allActiveBranches(Actor $a,string $cap):void{self::cap($a,$cap);$db=Db::wpdb();$ids=array_map('intval',(array)$db->get_col($db->prepare("SELECT id FROM ".Db::table('branches')." WHERE company_id=%d AND status='active' ORDER BY id",$a->companyId)));$missing=array_values(array_diff($ids,$a->branchIds));if($missing)throw new DomainException('Company-wide operation requires authority over every active branch.','all_branch_authority_required',403);}
}
