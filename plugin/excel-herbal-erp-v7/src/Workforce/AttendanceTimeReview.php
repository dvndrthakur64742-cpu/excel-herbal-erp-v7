<?php
namespace ExcelHerbal\ERP7\Workforce;
use ExcelHerbal\ERP7\Database\Db;
use ExcelHerbal\ERP7\Database\Transaction;
use ExcelHerbal\ERP7\Domain\DomainException;
use ExcelHerbal\ERP7\Security\Actor;
use ExcelHerbal\ERP7\Security\Audit;
use ExcelHerbal\ERP7\Security\Capabilities;
use ExcelHerbal\ERP7\Security\Guard;

/** Report-only approved correction of existing historical attendance.
 * Raw punches, GPS, paid-day status and posted payroll are never rewritten.
 */
final class AttendanceTimeReview {
    private static function reason(array $input):string {
        $r=trim((string)($input['reason']??''));
        if(strlen($r)<10||strlen($r)>250)throw new DomainException('Enter a reason of 10–250 characters.','attendance_time_reason_invalid',422);
        return $r;
    }
    private static function time(string $date,mixed $value):string {
        if(!is_string($value)||!preg_match('/^(?:[01][0-9]|2[0-3]):[0-5][0-9]$/D',$value))throw new DomainException('Use local time HH:MM.','attendance_time_invalid',422);
        $zone=function_exists('wp_timezone')?wp_timezone():new \DateTimeZone('UTC');
        $t=new \DateTimeImmutable($date.' '.$value.':00',$zone);
        return $t->setTimezone(new \DateTimeZone('UTC'))->format('Y-m-d H:i:s');
    }
    private static function eligible(array $row):bool {
        return ($row['status']??'')==='present'&&!empty($row['check_in_at'])&&$row['business_date']<Db::today()
            && (($row['check_in_mode']??null)!=='self'||!empty($row['check_out_at']));
    }
    private static function readRow(object $db,string $sql):?array {
        $row=$db->get_row($sql,ARRAY_A);
        if(($db->last_error??'')!=='')throw new DomainException('Attendance correction unavailable.','attendance_time_unavailable',503);
        return $row?:null;
    }
    public static function mine(Actor $a):array {
        Guard::cap($a,Capabilities::ATT_SELF);
        $db=Db::wpdb();$at=Db::table('attendance');$ct=Db::table('attendance_time_reviews');
        $rows=$db->get_results($db->prepare("SELECT a.id,a.branch_id,a.business_date,a.status,a.check_in_at,a.check_out_at,a.check_in_mode,
            c.id AS review_id,c.status AS review_status,c.proposed_in_at,c.proposed_out_at,c.reason,c.review_reason
            FROM {$at} a LEFT JOIN {$ct} c ON c.company_id=a.company_id AND c.attendance_id=a.id
            WHERE a.company_id=%d AND a.employee_id=%d AND a.business_date<%s ORDER BY a.business_date DESC LIMIT 90",$a->companyId,$a->employeeId,Db::today()),ARRAY_A);
        if(($db->last_error??'')!=='')throw new DomainException('Attendance correction unavailable.','attendance_time_unavailable',503);
        foreach($rows as &$row)$row['can_request']=self::eligible($row)&&$a->hasBranch((int)$row['branch_id'])&&empty($row['review_id']);unset($row);
        return (array)$rows;
    }
    public static function request(Actor $a,array $input):array {
        Guard::cap($a,Capabilities::ATT_SELF);$reason=self::reason($input);$id=(int)($input['attendance_id']??0);
        return Transaction::run(function()use($a,$id,$input,$reason){
            $db=Db::wpdb();$at=Db::table('attendance');$ct=Db::table('attendance_time_reviews');
            $row=self::readRow($db,$db->prepare("SELECT * FROM {$at} WHERE company_id=%d AND employee_id=%d AND id=%d FOR UPDATE",$a->companyId,$a->employeeId,$id));
            if(!$row)throw new DomainException('Own attendance record not found.','attendance_not_found',404);
            $branch=(int)$row['branch_id'];Guard::branch($a,$branch,Capabilities::ATT_SELF);
            if(!self::eligible($row))throw new DomainException('Only past existing attendance can be corrected after closure.','attendance_time_state_invalid',409);
            $in=self::time($row['business_date'],$input['check_in_local']??null);
            $out=self::time($row['business_date'],$input['check_out_local']??null);
            if($out<=$in||$out>Db::now()||($in===$row['check_in_at']&&$out===$row['check_out_at']))throw new DomainException('Provide a changed, valid same-day time range.','attendance_time_invalid',422);
            Db::mustInsert($db,$ct,['company_id'=>$a->companyId,'branch_id'=>$branch,'employee_id'=>$a->employeeId,'attendance_id'=>$id,'business_date'=>$row['business_date'],'original_in_at'=>$row['check_in_at'],'original_out_at'=>$row['check_out_at'],'proposed_in_at'=>$in,'proposed_out_at'=>$out,'reason'=>$reason,'status'=>'pending','requested_at'=>Db::now()],'A correction already exists for this record.','attendance_time_duplicate');
            $review=(int)$db->insert_id;
            Audit::add($a,'attendance.time_review_request','attendance_time_review',$review,['branch_id'=>$branch,'attendance_id'=>$id,'proposed_in_at'=>$in,'proposed_out_at'=>$out,'reason'=>$reason]);
            return ['id'=>$review,'status'=>'pending'];
        });
    }
    private static function guardReview(Actor $a):void {
        if(!AttendanceExceptionReview::canReview($a))throw new DomainException('Head Office attendance review authority required.','attendance_time_forbidden',403);
    }
    public static function inbox(Actor $a,int $branch):array {
        self::guardReview($a);Guard::branch($a,$branch,Capabilities::ATT_MANAGE);
        $db=Db::wpdb();$rows=$db->get_results($db->prepare("SELECT c.*,e.full_name FROM ".Db::table('attendance_time_reviews')." c JOIN ".Db::table('employees')." e ON e.company_id=c.company_id AND e.id=c.employee_id WHERE c.company_id=%d AND c.branch_id=%d AND c.status='pending' ORDER BY c.business_date DESC,c.id DESC LIMIT 200",$a->companyId,$branch),ARRAY_A);
        if(($db->last_error??'')!=='')throw new DomainException('Attendance correction unavailable.','attendance_time_unavailable',503);
        foreach($rows as &$row)$row['can_decide']=(int)$row['employee_id']!==$a->employeeId;unset($row);
        return (array)$rows;
    }
    public static function decide(Actor $a,int $id,array $input):array {
        self::guardReview($a);$reason=self::reason($input);$decision=(string)($input['decision']??'');
        if(!in_array($decision,['approved','rejected'],true))throw new DomainException('Choose approve or reject.','attendance_time_decision_invalid',422);
        return Transaction::run(function()use($a,$id,$reason,$decision){
            $db=Db::wpdb();$ct=Db::table('attendance_time_reviews');$at=Db::table('attendance');
            $row=self::readRow($db,$db->prepare("SELECT * FROM {$ct} WHERE company_id=%d AND id=%d FOR UPDATE",$a->companyId,$id));
            if(!$row)throw new DomainException('Correction not found.','attendance_time_not_found',404);
            Guard::branch($a,(int)$row['branch_id'],Capabilities::ATT_MANAGE);
            if((int)$row['employee_id']===$a->employeeId)throw new DomainException('Cannot review own correction.','maker_checker_required',409);
            if($row['status']!=='pending')throw new DomainException('Correction already reviewed.','attendance_time_state_invalid',409);
            if($decision==='approved'){
                $original=self::readRow($db,$db->prepare("SELECT * FROM {$at} WHERE company_id=%d AND branch_id=%d AND employee_id=%d AND id=%d FOR UPDATE",$a->companyId,(int)$row['branch_id'],(int)$row['employee_id'],(int)$row['attendance_id']));
                if(!$original||!self::eligible($original)||$original['business_date']!==$row['business_date']||$original['check_in_at']!==$row['original_in_at']||$original['check_out_at']!==$row['original_out_at'])throw new DomainException('Original attendance changed; reject and review independently.','attendance_time_stale',409);
            }
            $now=Db::now();
            if(Db::mustUpdate($db,$ct,['status'=>$decision,'review_reason'=>$reason,'reviewed_by'=>$a->employeeId,'reviewed_at'=>$now],['company_id'=>$a->companyId,'id'=>$id,'status'=>'pending'])!==1)throw new DomainException('Correction state changed.','attendance_time_state_invalid',409);
            Audit::add($a,'attendance.time_review_decision','attendance_time_review',$id,['branch_id'=>(int)$row['branch_id'],'attendance_id'=>(int)$row['attendance_id'],'decision'=>$decision,'reason'=>$reason,'original_punch_changed'=>false,'payroll_changed'=>false]);
            return ['id'=>$id,'status'=>$decision,'reviewed_at'=>$now];
        });
    }
}
