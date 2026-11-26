<?php
namespace ExcelHerbal\ERP7\Workforce;

use ExcelHerbal\ERP7\Database\Db;
use ExcelHerbal\ERP7\Database\Transaction;
use ExcelHerbal\ERP7\Domain\DomainException;
use ExcelHerbal\ERP7\Recovery\GpsPointValidator;
use ExcelHerbal\ERP7\Security\Actor;
use ExcelHerbal\ERP7\Security\Audit;
use ExcelHerbal\ERP7\Security\Capabilities;
use ExcelHerbal\ERP7\Security\Guard;

/** Employee-owned punches; activated on an explicit company business date. */
final class SelfAttendanceService {
    private static function now(): \DateTimeImmutable {
        $zone = function_exists('wp_timezone') ? wp_timezone() : new \DateTimeZone('UTC');
        return new \DateTimeImmutable(current_time('mysql'), $zone);
    }

    private static function coordinates(?float $lat, ?float $lng, ?int $exceptionId = null): array {
        if ($exceptionId !== null) {
            if ($exceptionId < 1 || $lat !== null || $lng !== null) throw new DomainException('Choose GPS coordinates or one approved exception, not both.','gps_exception_invalid',422);
            return [null,null];
        }
        if ($lat === null || $lng === null) {
            throw new DomainException('Location is required for attendance.', 'attendance_location_required', 422);
        }
        try {
            $gps = GpsPointValidator::normalize(['lat'=>$lat, 'lng'=>$lng]);
        } catch (\InvalidArgumentException $e) {
            throw new DomainException($e->getMessage(), 'gps_invalid', 422);
        }
        return [$gps['latitude'], $gps['longitude']];
    }

    private static function excusedReason(Actor $a,int $branch,string $date): ?string {
        $db=Db::wpdb();
        $leave = Db::table('leave_requests');
        $holidays = Db::table('holidays');
        $onLeave = (int)$db->get_var($db->prepare("SELECT COUNT(*) FROM {$leave} WHERE company_id=%d AND employee_id=%d AND status='approved' AND date_from<=%s AND date_to>=%s",$a->companyId,$a->employeeId,$date,$date));
        if ($db->last_error !== '') throw new DomainException('Attendance eligibility unavailable.', 'attendance_eligibility_unavailable', 503);
        if ($onLeave>0) return 'approved_leave';
        $holiday = (int)$db->get_var($db->prepare("SELECT COUNT(*) FROM {$holidays} WHERE company_id=%d AND active=1 AND (branch_id IS NULL OR branch_id=%d) AND holiday_date=%s",$a->companyId,$branch,$date));
        if ($db->last_error !== '') throw new DomainException('Attendance eligibility unavailable.', 'attendance_eligibility_unavailable', 503);
        return $holiday>0 ? 'holiday' : null;
    }

    /** Re-read the clock after waiting for transaction locks. Never carry a
     * request across a business-date boundary or an expired punch window. */
    private static function lockedTime(string $date): \DateTimeImmutable {
        $now=self::now();
        if ($now->format('Y-m-d')!==$date) {
            throw new DomainException('Business date changed. Refresh attendance and try again.','attendance_date_changed',409);
        }
        return $now;
    }

    public static function checkIn(Actor $a, int $branch, ?float $lat, ?float $lng, ?int $exceptionId = null): array {
        Guard::branch($a, $branch, Capabilities::ATT_SELF);
        if ($branch !== $a->assignedBranchId) {
            throw new DomainException('Check in at your assigned branch.', 'attendance_branch_invalid', 403);
        }
        [$lat, $lng] = self::coordinates($lat, $lng,$exceptionId);
        return Transaction::run(function () use ($a,$branch,$lat,$lng,$exceptionId) {
            $db = Db::wpdb();
            $now = self::now();
            $date = $now->format('Y-m-d');
            $revision=SelfAttendanceSettings::forDate($a->companyId,$date);
            if (!$revision) throw new DomainException('Self attendance is not active.','attendance_policy_inactive',409);
            $times=$revision['times'];
            $state = SelfAttendancePolicy::state($now, null, null,false,$times);
            if (!$state['can_check_in']) {
                throw new DomainException('Check-in is outside the permitted time window.', 'attendance_window_closed', 409);
            }
            $employees = Db::table('employees');
            $branches = Db::table('branches');
            $employee = $db->get_row($db->prepare(
                "SELECT e.id FROM {$employees} e JOIN {$branches} b ON b.company_id=e.company_id AND b.id=e.assigned_branch_id AND b.status='active' WHERE e.company_id=%d AND e.id=%d AND e.assigned_branch_id=%d AND e.status='active' FOR UPDATE",
                $a->companyId, $a->employeeId, $branch
            ), ARRAY_A);
            if (($db->last_error??'')!=='') throw new DomainException('Attendance eligibility unavailable.', 'attendance_eligibility_unavailable', 503);
            if (!$employee) throw new DomainException('Active assigned branch required.', 'attendance_branch_invalid', 403);
            self::lockedTime($date);
            if (self::excusedReason($a,$branch,$date)!==null) throw new DomainException('Attendance is not available on approved leave or a holiday.', 'attendance_excused', 409);
            $table = Db::table('attendance');
            $existing = $db->get_row($db->prepare("SELECT id FROM {$table} WHERE company_id=%d AND employee_id=%d AND business_date=%s FOR UPDATE",$a->companyId,$a->employeeId,$date),ARRAY_A);
            if (($db->last_error??'')!=='') throw new DomainException('Attendance unavailable.', 'attendance_unavailable', 503);
            if ($existing) throw new DomainException('An attendance record already exists for today.', 'attendance_exists', 409);
            $now=self::lockedTime($date);
            $state=SelfAttendancePolicy::state($now,null,null,false,$times);
            if (!$state['can_check_in']) throw new DomainException('Check-in is outside the permitted time window.','attendance_window_closed',409);
            $stamp = $now->setTimezone(new \DateTimeZone('UTC'))->format('Y-m-d H:i:s');
            Db::mustInsert($db, $table, [
                'company_id'=>$a->companyId,'branch_id'=>$branch,'employee_id'=>$a->employeeId,
                'business_date'=>$date,'status'=>'present','check_in_at'=>$stamp,
                'check_in_lat'=>$lat,'check_in_lng'=>$lng,'check_in_mode'=>'self',
                'auto_checkout_due_at'=>$state['auto_checkout_utc'],'attendance_policy_json'=>wp_json_encode($times),'created_at'=>$stamp,
            ], 'An attendance record already exists for today.', 'attendance_exists');
            $id = (int)$db->insert_id;
            if ($exceptionId !== null) GpsExceptionService::consume($a,$exceptionId,$branch,$date,'check_in',$id);
            Audit::add($a,'attendance.self_check_in','attendance',$id,['branch_id'=>$branch,'business_date'=>$date,'gps_exception_id'=>$exceptionId]);
            return ['id'=>$id,'check_in_at'=>$stamp,'check_in_mode'=>'self','auto_checkout_due_at'=>$state['auto_checkout_utc']];
        });
    }

    public static function checkOut(Actor $a, ?float $lat, ?float $lng, ?int $exceptionId = null): array {
        Guard::cap($a, Capabilities::ATT_SELF);
        [$lat,$lng] = self::coordinates($lat,$lng,$exceptionId);
        return Transaction::run(function () use ($a,$lat,$lng,$exceptionId) {
            $db = Db::wpdb();
            $now = self::now();
            $table = Db::table('attendance');
            $row = $db->get_row($db->prepare("SELECT * FROM {$table} WHERE company_id=%d AND employee_id=%d AND business_date=%s FOR UPDATE",$a->companyId,$a->employeeId,$now->format('Y-m-d')),ARRAY_A);
            if (($db->last_error??'')!=='') throw new DomainException('Attendance unavailable.', 'attendance_unavailable', 503);
            if (!$row || empty($row['check_in_at']) || !empty($row['check_out_at'])
                || (int)($row['checkout_exception']??0)!==0
                || ($row['check_in_mode']??null)!=='self' || empty($row['auto_checkout_due_at'])) {
                throw new DomainException('An open self check-in is required.', 'attendance_open_required', 409);
            }
            $branch = (int)$row['branch_id'];
            Guard::branch($a,$branch,Capabilities::ATT_SELF);
            $now=self::lockedTime((string)$row['business_date']);
            $utc = new \DateTimeZone('UTC');
            $stamp = $now->setTimezone($utc)->format('Y-m-d H:i:s');
            if ($stamp >= $row['auto_checkout_due_at']) {
                throw new DomainException('Self checkout has closed; automatic checkout is due.', 'attendance_checkout_due', 409);
            }
            if ($stamp < $row['check_in_at']) throw new DomainException('Invalid checkout time.', 'attendance_time_invalid', 409);
            if ($exceptionId !== null) GpsExceptionService::consume($a,$exceptionId,$branch,$row['business_date'],'check_out',(int)$row['id']);
            $updated = Db::mustUpdate($db,$table,[
                'check_out_at'=>$stamp,'check_out_lat'=>$lat,'check_out_lng'=>$lng,
                'checkout_mode'=>'self','checkout_processed_at'=>$stamp,
            ],['id'=>(int)$row['id'],'company_id'=>$a->companyId,'check_out_at'=>null]);
            if ($updated!==1) throw new DomainException('Attendance changed during checkout.','attendance_open_required',409);
            Audit::add($a,'attendance.self_checkout','attendance',(int)$row['id'],['branch_id'=>$branch,'business_date'=>$row['business_date'],'gps_exception_id'=>$exceptionId]);
            return ['id'=>(int)$row['id'],'check_out_at'=>$stamp,'checkout_mode'=>'self'];
        });
    }

    public static function today(Actor $a): array {
        $now = self::now();
        $date = $now->format('Y-m-d');
        $db = Db::wpdb();
        $row = $db->get_row($db->prepare("SELECT * FROM ".Db::table('attendance')." WHERE company_id=%d AND employee_id=%d AND business_date=%s",$a->companyId,$a->employeeId,$date),ARRAY_A);
        if ($db->last_error !== '') throw new DomainException('Attendance unavailable.', 'attendance_unavailable', 503);
        $utc = new \DateTimeZone('UTC');
        $in = !empty($row['check_in_at']) ? new \DateTimeImmutable($row['check_in_at'],$utc) : null;
        $out = !empty($row['check_out_at']) ? new \DateTimeImmutable($row['check_out_at'],$utc) : null;
        $revision=SelfAttendanceSettings::forDate($a->companyId,$date);
        if (!$revision) throw new DomainException('Self attendance is not active.','attendance_policy_inactive',409);
        $times=($row['check_in_mode']??null)==='self'?SelfAttendancePolicy::snapshot($row):$revision['times'];
        $state = SelfAttendancePolicy::state($now,$in,$out,false,$times);
        $state['can_check_in'] = $state['can_check_in'] && !$row && $a->hasBranch($a->assignedBranchId);
        $state['check_in_block_reason']=null;
        if ($state['can_check_in']) {
            $employees=Db::table('employees'); $branches=Db::table('branches');
            $eligible=$db->get_var($db->prepare("SELECT e.id FROM {$employees} e JOIN {$branches} b ON b.company_id=e.company_id AND b.id=e.assigned_branch_id AND b.status='active' WHERE e.company_id=%d AND e.id=%d AND e.assigned_branch_id=%d AND e.status='active'",$a->companyId,$a->employeeId,$a->assignedBranchId));
            if (($db->last_error??'')!=='') throw new DomainException('Attendance eligibility unavailable.', 'attendance_eligibility_unavailable', 503);
            $state['check_in_block_reason']=(int)$eligible===$a->employeeId ? self::excusedReason($a,$a->assignedBranchId,$date) : 'inactive_assignment';
            $state['can_check_in']=$state['check_in_block_reason']===null;
        }
        $state['can_check_out'] = $state['can_check_out'] && ($row['check_in_mode']??null)==='self' && $a->hasBranch((int)($row['branch_id']??0)) && (int)($row['checkout_exception']??0)===0;
        return array_merge($row??['business_date'=>$date],GpsDutyPolicy::state($row,$now->format('Y-m-d H:i:s'),$times),$state,[
            'attendance_mode'=>'self','assigned_branch_id'=>$a->assignedBranchId,
            'official_start'=>substr($times['duty_start'],0,5),'official_end'=>substr($times['duty_end'],0,5),'auto_checkout_time'=>substr($times['auto_checkout'],0,5),
            'latest_gps_at'=>$row ? $db->get_var($db->prepare("SELECT recorded_at FROM ".Db::table('gps_points')." WHERE company_id=%d AND employee_id=%d AND attendance_id=%d ORDER BY recorded_at DESC,id DESC LIMIT 1",$a->companyId,$a->employeeId,(int)$row['id'])) : null,
        ]);
    }

    /** Idempotent recovery using the original, persisted cutoff. Never edits
     * legacy rows or invents GPS coordinates. The processed time is distinct.
     */
    public static function closeDue(): int {
        $db = Db::wpdb();
        $table = Db::table('attendance');
        $now = Db::now();
        $where="check_in_mode='self' AND check_in_at IS NOT NULL AND check_out_at IS NULL
                AND checkout_exception=0 AND auto_checkout_due_at IS NOT NULL
                AND auto_checkout_due_at>=check_in_at AND auto_checkout_due_at<=%s";
        $ids=$db->get_results($db->prepare("SELECT id FROM {$table} WHERE {$where} ORDER BY auto_checkout_due_at,id LIMIT 500",$now),ARRAY_A);
        if (($db->last_error??'')!=='') throw new DomainException('Automatic checkout query failed.','attendance_checkout_unavailable',503);
        $closed=0;$failed=0;
        foreach ((array)$ids as $candidate) {
            try {
                $closed+=Transaction::run(function()use($db,$table,$where,$now,$candidate){
                    $row=$db->get_row($db->prepare("SELECT * FROM {$table} WHERE id=%d AND {$where} FOR UPDATE",(int)$candidate['id'],$now),ARRAY_A);
                    if (($db->last_error??'')!=='') throw new DomainException('Automatic checkout read failed.','attendance_checkout_unavailable',503);
                    if (!$row) return 0;
                    $id=(int)$row['id'];
                    $updated=Db::mustUpdate($db,$table,[
                        'check_out_at'=>$row['auto_checkout_due_at'],'checkout_mode'=>'auto','checkout_processed_at'=>$now,
                    ],['id'=>$id,'company_id'=>(int)$row['company_id'],'check_out_at'=>null]);
                    if ($updated!==1) throw new DomainException('Automatic checkout did not update exactly one row.','attendance_checkout_unavailable',503);
                    Db::mustInsert($db,Db::table('audit_log'),[
                        'company_id'=>(int)$row['company_id'],'branch_id'=>(int)$row['branch_id'],
                        'employee_id'=>null,'wp_user_id'=>null,'action'=>'attendance.auto_checkout',
                        'entity_type'=>'attendance','entity_id'=>(string)$id,
                        'context_json'=>wp_json_encode(['employee_id'=>(int)$row['employee_id'],'business_date'=>$row['business_date'],
                            'scheduled_checkout_utc'=>$row['auto_checkout_due_at'],'processed_utc'=>$now,'verified_employee_punch'=>false]),
                        'created_at'=>$now,
                    ]);
                    return 1;
                });
            } catch (\Throwable $e) {
                $failed++;
            }
        }
        if ($failed>0) throw new DomainException('Automatic checkout recovery has pending failures.','attendance_checkout_unavailable',503);
        return $closed;
    }
}
