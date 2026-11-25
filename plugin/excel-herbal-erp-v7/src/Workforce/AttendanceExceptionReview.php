<?php
namespace ExcelHerbal\ERP7\Workforce;

use ExcelHerbal\ERP7\Database\Db;
use ExcelHerbal\ERP7\Database\Transaction;
use ExcelHerbal\ERP7\Domain\DomainException;
use ExcelHerbal\ERP7\Security\Actor;
use ExcelHerbal\ERP7\Security\Audit;
use ExcelHerbal\ERP7\Security\BranchAuthority;
use ExcelHerbal\ERP7\Security\Capabilities;
use ExcelHerbal\ERP7\Security\Guard;

/** Explicit, record-wise Head Office review of legacy missing checkout.
 * Acknowledgement is not a correction, location exception or salary approval.
 */
final class AttendanceExceptionReview {
    public static function canReview(Actor $actor): bool {
        if (!$actor->can(Capabilities::ATT_MANAGE) || !$actor->can(Capabilities::ACCESS_MANAGE)) return false;
        $db=Db::wpdb();
        $branches=array_map('intval',(array)$db->get_col($db->prepare(
            "SELECT id FROM ".Db::table('branches')." WHERE company_id=%d AND status='active'",$actor->companyId)));
        if (($db->last_error??'')!=='' || !$branches || array_diff($branches,$actor->branchIds)) return false;
        $admin=BranchAuthority::isCompanyWideAdmin($actor->employeeId,$actor->companyId,$actor->designationCode);
        return $admin && ($db->last_error??'')==='';
    }

    public static function eligible(array $row,Actor $actor): bool {
        return (int)($row['company_id']??0)===$actor->companyId
            && $actor->hasBranch((int)($row['branch_id']??0))
            && (int)($row['employee_id']??0)!==$actor->employeeId
            && !empty($row['check_in_at']) && empty($row['check_out_at'])
            && (int)($row['checkout_exception']??0)===0
            && empty($row['check_in_mode'])
            && !empty($row['business_date']) && $row['business_date']<Db::today();
    }

    public static function acknowledge(Actor $actor,int $id,string $reason): array {
        if (!self::canReview($actor)) throw new DomainException('Head Office system administrator attendance authority required.','attendance_exception_forbidden',403);
        $reason=trim($reason);
        if ($id<1 || strlen($reason)<10 || strlen($reason)>250) {
            throw new DomainException('Select an attendance record and enter a 10–250 character review reason.','attendance_exception_invalid',422);
        }
        return Transaction::run(function()use($actor,$id,$reason){
            $db=Db::wpdb();$table=Db::table('attendance');
            $row=$db->get_row($db->prepare("SELECT * FROM {$table} WHERE company_id=%d AND id=%d FOR UPDATE",$actor->companyId,$id),ARRAY_A);
            if (($db->last_error??'')!=='') throw new DomainException('Attendance review unavailable.','attendance_review_unavailable',503);
            if (!$row) throw new DomainException('Attendance record not found.','attendance_not_found',404);
            Guard::branch($actor,(int)$row['branch_id'],Capabilities::ATT_MANAGE);
            if ((int)$row['employee_id']===$actor->employeeId) throw new DomainException('You cannot acknowledge your own exception.','maker_checker_required',409);
            if (!self::eligible($row,$actor)) throw new DomainException('Only unresolved historical legacy missing checkouts may be acknowledged.','attendance_exception_state_invalid',409);
            $now=Db::now();
            $updated=Db::mustUpdate($db,$table,[
                'checkout_exception'=>1,'checkout_exception_reason'=>$reason,
                'checkout_exception_by'=>$actor->employeeId,'checkout_exception_at'=>$now,
            ],['id'=>$id,'company_id'=>$actor->companyId,'check_out_at'=>null,'checkout_exception'=>0]);
            if ($updated!==1) throw new DomainException('Attendance changed during review.','attendance_exception_state_invalid',409);
            Audit::add($actor,'attendance.checkout_missing_acknowledged','attendance',$id,[
                'branch_id'=>(int)$row['branch_id'],'employee_id'=>(int)$row['employee_id'],
                'business_date'=>$row['business_date'],'check_in_at'=>$row['check_in_at'],
                'reason'=>$reason,'verified_checkout'=>false,'salary_change'=>false,
            ]);
            return ['id'=>$id,'checkout_exception'=>1,'checkout_exception_at'=>$now,'check_out_at'=>null];
        });
    }
}
