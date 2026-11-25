<?php
namespace ExcelHerbal\ERP7\Workforce;
use ExcelHerbal\ERP7\Database\Db;
use ExcelHerbal\ERP7\Database\Transaction;
use ExcelHerbal\ERP7\Domain\DomainException;
use ExcelHerbal\ERP7\Security\Actor;
use ExcelHerbal\ERP7\Security\Audit;
use ExcelHerbal\ERP7\Security\Capabilities;
use ExcelHerbal\ERP7\Security\Guard;

/** Request and independent review only. An approval is not a GPS point,
 * attendance correction, payroll decision or authorization to issue stock.
 */
final class GpsExceptionService {
    private static function reason(array $input): string {
        $reason=trim((string)($input['reason']??''));
        if(strlen($reason)<10||strlen($reason)>250)throw new DomainException('Enter a reason of 10–250 characters.','gps_exception_reason_invalid',422);
        return $reason;
    }
    private static function reviewGuard(Actor $a): void {
        if(!AttendanceExceptionReview::canReview($a))throw new DomainException('Head Office attendance review authority required.','gps_exception_forbidden',403);
    }
    public static function request(Actor $a,array $input): array {
        $branch=$a->assignedBranchId;
        Guard::branch($a,$branch,Capabilities::ATT_SELF);
        $scope=(string)($input['scope']??'');
        if(!in_array($scope,['check_in','check_out'],true))throw new DomainException('Choose check-in or checkout location exception.','gps_exception_scope_invalid',422);
        $reason=self::reason($input);
        return Transaction::run(function()use($a,$branch,$scope,$reason){
            $db=Db::wpdb();$date=Db::today();
            if(!SelfAttendancePolicy::enabled($a->companyId,$date))throw new DomainException('Self attendance is not active.','attendance_policy_inactive',409);
            // Serialize with the employee punch and scope to their assigned active branch.
            $employee=$db->get_row($db->prepare("SELECT e.id FROM ".Db::table('employees')." e JOIN ".Db::table('branches')." b ON b.id=e.assigned_branch_id AND b.company_id=e.company_id AND b.status='active' WHERE e.company_id=%d AND e.id=%d AND e.assigned_branch_id=%d AND e.status='active' FOR UPDATE",$a->companyId,$a->employeeId,$branch),ARRAY_A);
            if(!$employee||($db->last_error??'')!=='')throw new DomainException('Active assigned employee required.','attendance_branch_invalid',403);
            $state=SelfAttendanceService::today($a);
            if(!($state[$scope==='check_in'?'can_check_in':'can_check_out']??false))throw new DomainException('This punch is not currently available.','gps_exception_window_closed',409);
            $table=Db::table('attendance_gps_exceptions');$now=Db::now();
            Db::mustInsert($db,$table,[
                'company_id'=>$a->companyId,'branch_id'=>$branch,'employee_id'=>$a->employeeId,'business_date'=>$date,
                'scope'=>$scope,'reason'=>$reason,'status'=>'pending','requested_at'=>$now,
            ],'An exception already exists for this punch and date.','gps_exception_duplicate');
            $id=(int)$db->insert_id;
            Audit::add($a,'attendance.gps_exception_request','attendance_gps_exception',$id,['branch_id'=>$branch,'business_date'=>$date,'scope'=>$scope,'reason'=>$reason]);
            return ['id'=>$id,'status'=>'pending','scope'=>$scope,'business_date'=>$date];
        });
    }
    /** Called only inside the punch transaction after employee/attendance lock.
     * An exception is specific to one punch. A failed punch rolls back usage.
     */
    public static function consume(Actor $a,int $id,int $branch,string $date,string $scope,int $attendanceId):void {
        $db=Db::wpdb();$table=Db::table('attendance_gps_exceptions');
        $row=$db->get_row($db->prepare("SELECT * FROM {$table} WHERE id=%d AND company_id=%d AND employee_id=%d AND branch_id=%d AND business_date=%s AND scope=%s FOR UPDATE",$id,$a->companyId,$a->employeeId,$branch,$date,$scope),ARRAY_A);
        if(($db->last_error??'')!=='')throw new DomainException('GPS exception unavailable.','gps_exception_unavailable',503);
        if(!$row||$row['status']!=='approved'||empty($row['reviewed_by'])||(int)$row['reviewed_by']===$a->employeeId||empty($row['reviewed_at']))throw new DomainException('An unused approved exception is required for this punch.','gps_exception_not_approved',409);
        if(Db::mustUpdate($db,$table,['status'=>'used'],['id'=>$id,'company_id'=>$a->companyId,'status'=>'approved'])!==1)throw new DomainException('GPS exception already used.','gps_exception_state_invalid',409);
        Audit::add($a,'attendance.gps_exception_used','attendance_gps_exception',$id,['branch_id'=>$branch,'business_date'=>$date,'scope'=>$scope,'attendance_id'=>$attendanceId,'gps_evidence_created'=>false]);
    }
    public static function mine(Actor $a):array {
        Guard::cap($a,Capabilities::ATT_SELF);
        $db=Db::wpdb();
        $rows=$db->get_results($db->prepare("SELECT id,business_date,scope,status,reason,review_reason,requested_at,reviewed_at FROM ".Db::table('attendance_gps_exceptions')." WHERE company_id=%d AND employee_id=%d ORDER BY id DESC LIMIT 50",$a->companyId,$a->employeeId),ARRAY_A);
        if(($db->last_error??'')!=='')throw new DomainException('GPS exception list unavailable.','gps_exception_unavailable',503);
        return (array)$rows;
    }
    public static function inbox(Actor $a,int $branch):array {
        self::reviewGuard($a);Guard::branch($a,$branch,Capabilities::ATT_MANAGE);
        $db=Db::wpdb();
        $rows=$db->get_results($db->prepare("SELECT x.*,e.full_name FROM ".Db::table('attendance_gps_exceptions')." x JOIN ".Db::table('employees')." e ON e.company_id=x.company_id AND e.id=x.employee_id WHERE x.company_id=%d AND x.branch_id=%d AND x.status='pending' ORDER BY x.business_date DESC,x.id DESC LIMIT 200",$a->companyId,$branch),ARRAY_A);
        if(($db->last_error??'')!=='')throw new DomainException('GPS exception list unavailable.','gps_exception_unavailable',503);
        foreach($rows as &$row){$row['can_approve']=$row['business_date']===Db::today()&&(int)$row['employee_id']!==$a->employeeId;$row['can_reject']=(int)$row['employee_id']!==$a->employeeId;}unset($row);
        return (array)$rows;
    }
    public static function decide(Actor $a,int $id,array $input):array {
        self::reviewGuard($a);
        $decision=(string)($input['decision']??'');
        if(!in_array($decision,['approved','rejected'],true))throw new DomainException('Choose approve or reject.','gps_exception_decision_invalid',422);
        $reason=self::reason($input);
        return Transaction::run(function()use($a,$id,$decision,$reason){
            $db=Db::wpdb();$table=Db::table('attendance_gps_exceptions');
            $row=$db->get_row($db->prepare("SELECT * FROM {$table} WHERE company_id=%d AND id=%d FOR UPDATE",$a->companyId,$id),ARRAY_A);
            if(($db->last_error??'')!=='')throw new DomainException('GPS exception unavailable.','gps_exception_unavailable',503);
            if(!$row)throw new DomainException('GPS exception not found.','gps_exception_not_found',404);
            Guard::branch($a,(int)$row['branch_id'],Capabilities::ATT_MANAGE);
            if((int)$row['employee_id']===$a->employeeId)throw new DomainException('Cannot review your own request.','maker_checker_required',409);
            if($row['status']!=='pending')throw new DomainException('Request has already been reviewed.','gps_exception_state_invalid',409);
            if($decision==='approved'&&$row['business_date']!==Db::today())throw new DomainException('Expired GPS exception cannot be approved.','gps_exception_expired',409);
            $now=Db::now();
            if(Db::mustUpdate($db,$table,['status'=>$decision,'review_reason'=>$reason,'reviewed_by'=>$a->employeeId,'reviewed_at'=>$now],['company_id'=>$a->companyId,'id'=>$id,'status'=>'pending'])!==1)throw new DomainException('Request changed during review.','gps_exception_state_invalid',409);
            Audit::add($a,'attendance.gps_exception_decision','attendance_gps_exception',$id,['branch_id'=>(int)$row['branch_id'],'employee_id'=>(int)$row['employee_id'],'business_date'=>$row['business_date'],'scope'=>$row['scope'],'decision'=>$decision,'reason'=>$reason,'attendance_changed'=>false,'gps_evidence_created'=>false]);
            return ['id'=>$id,'status'=>$decision,'reviewed_at'=>$now];
        });
    }
}
