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

/** Draft implementation for coordinated API/UI cutover. No hook is installed here. */
final class SelfAttendanceService {
    private static function now(): \DateTimeImmutable {
        return new \DateTimeImmutable('now', wp_timezone());
    }

    private static function coordinates(?float $lat, ?float $lng): array {
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

    public static function checkIn(Actor $a, int $branch, ?float $lat, ?float $lng): array {
        Guard::branch($a, $branch, Capabilities::ATT_SELF);
        if ($branch !== $a->assignedBranchId) {
            throw new DomainException('Check in at your assigned branch.', 'attendance_branch_invalid', 403);
        }
        [$lat, $lng] = self::coordinates($lat, $lng);
        return Transaction::run(function () use ($a,$branch,$lat,$lng) {
            $db = Db::wpdb();
            $now = self::now();
            $date = $now->format('Y-m-d');
            $state = SelfAttendancePolicy::state($now, null, null);
            if (!$state['can_check_in']) {
                throw new DomainException('Check-in is outside the permitted time window.', 'attendance_window_closed', 409);
            }
            $employees = Db::table('employees');
            $branches = Db::table('branches');
            $employee = $db->get_row($db->prepare(
                "SELECT e.id FROM {$employees} e JOIN {$branches} b ON b.company_id=e.company_id AND b.id=e.assigned_branch_id AND b.status='active' WHERE e.company_id=%d AND e.id=%d AND e.assigned_branch_id=%d AND e.status='active' FOR UPDATE",
                $a->companyId, $a->employeeId, $branch
            ), ARRAY_A);
            if (!$employee) throw new DomainException('Active assigned branch required.', 'attendance_branch_invalid', 403);
            $leave = Db::table('leave_requests');
            $holidays = Db::table('holidays');
            $onLeave = (int)$db->get_var($db->prepare("SELECT COUNT(*) FROM {$leave} WHERE company_id=%d AND employee_id=%d AND status='approved' AND date_from<=%s AND date_to>=%s",$a->companyId,$a->employeeId,$date,$date));
            $holiday = (int)$db->get_var($db->prepare("SELECT COUNT(*) FROM {$holidays} WHERE company_id=%d AND active=1 AND (branch_id IS NULL OR branch_id=%d) AND holiday_date=%s",$a->companyId,$branch,$date));
            if ($onLeave || $holiday) throw new DomainException('Attendance is not available on approved leave or a holiday.', 'attendance_excused', 409);
            $table = Db::table('attendance');
            $existing = $db->get_row($db->prepare("SELECT id FROM {$table} WHERE company_id=%d AND employee_id=%d AND business_date=%s FOR UPDATE",$a->companyId,$a->employeeId,$date),ARRAY_A);
            if ($existing) throw new DomainException('An attendance record already exists for today.', 'attendance_exists', 409);
            $stamp = $now->setTimezone(new \DateTimeZone('UTC'))->format('Y-m-d H:i:s');
            $id = Db::mustInsert($db, $table, [
                'company_id'=>$a->companyId,'branch_id'=>$branch,'employee_id'=>$a->employeeId,
                'business_date'=>$date,'status'=>'present','check_in_at'=>$stamp,
                'check_in_lat'=>$lat,'check_in_lng'=>$lng,'check_in_mode'=>'self',
                'auto_checkout_due_at'=>$state['auto_checkout_utc'],'created_at'=>$stamp,
            ], 'An attendance record already exists for today.', 'attendance_exists');
            Audit::add($a,'attendance.self_check_in','attendance',$id,['branch_id'=>$branch,'business_date'=>$date]);
            return ['id'=>$id,'check_in_at'=>$stamp,'check_in_mode'=>'self','auto_checkout_due_at'=>$state['auto_checkout_utc']];
        });
    }

    public static function checkOut(Actor $a, ?float $lat, ?float $lng): array {
        Guard::cap($a, Capabilities::ATT_SELF);
        [$lat,$lng] = self::coordinates($lat,$lng);
        return Transaction::run(function () use ($a,$lat,$lng) {
            $db = Db::wpdb();
            $now = self::now();
            $table = Db::table('attendance');
            $row = $db->get_row($db->prepare("SELECT * FROM {$table} WHERE company_id=%d AND employee_id=%d AND business_date=%s FOR UPDATE",$a->companyId,$a->employeeId,$now->format('Y-m-d')),ARRAY_A);
            if (!$row || empty($row['check_in_at']) || !empty($row['check_out_at'])
                || ($row['check_in_mode']??null)!=='self' || empty($row['auto_checkout_due_at'])) {
                throw new DomainException('An open self check-in is required.', 'attendance_open_required', 409);
            }
            $branch = (int)$row['branch_id'];
            Guard::branch($a,$branch,Capabilities::ATT_SELF);
            $utc = new \DateTimeZone('UTC');
            $stamp = $now->setTimezone($utc)->format('Y-m-d H:i:s');
            if ($stamp >= $row['auto_checkout_due_at']) {
                throw new DomainException('Self checkout has closed; automatic checkout is due.', 'attendance_checkout_due', 409);
            }
            if ($stamp < $row['check_in_at']) throw new DomainException('Invalid checkout time.', 'attendance_time_invalid', 409);
            Db::mustUpdate($db,$table,[
                'check_out_at'=>$stamp,'check_out_lat'=>$lat,'check_out_lng'=>$lng,
                'checkout_mode'=>'self','checkout_processed_at'=>$stamp,
            ],['id'=>(int)$row['id'],'company_id'=>$a->companyId,'check_out_at'=>null]);
            Audit::add($a,'attendance.self_checkout','attendance',(int)$row['id'],['branch_id'=>$branch,'business_date'=>$row['business_date']]);
            return ['id'=>(int)$row['id'],'check_out_at'=>$stamp,'checkout_mode'=>'self'];
        });
    }

    /** Idempotent recovery using the original, persisted cutoff. Never edits
     * legacy rows or invents GPS coordinates. The processed time is distinct.
     */
    public static function closeDue(): int {
        $db = Db::wpdb();
        $table = Db::table('attendance');
        $now = Db::now();
        return Db::mustQuery($db,$db->prepare(
            "UPDATE {$table} SET check_out_at=auto_checkout_due_at,checkout_mode='auto',checkout_processed_at=%s
             WHERE check_in_mode='self' AND check_in_at IS NOT NULL AND check_out_at IS NULL
             AND checkout_exception=0 AND auto_checkout_due_at IS NOT NULL
             AND auto_checkout_due_at>=check_in_at AND auto_checkout_due_at<=%s",
            $now,$now
        ));
    }
}
