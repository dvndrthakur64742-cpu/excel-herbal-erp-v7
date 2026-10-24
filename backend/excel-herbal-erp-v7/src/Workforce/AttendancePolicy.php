<?php
namespace ExcelHerbal\ERP7\Workforce;

use ExcelHerbal\ERP7\Domain\DomainException;

/** Attendance time limits are distinct from GpsDutyPolicy's 10:30–17:00 route. */
final class AttendancePolicy {
    public const SELF_CHECK_IN_START = '09:00:00';
    public const SELF_CHECK_IN_END = '18:00:00';
    public const SELF_CHECK_OUT_START = '18:00:00';
    public const AUTO_CHECK_OUT = '20:00:00';

    public static function assertCheckInTime(string $localTime): void {
        if ($localTime < self::SELF_CHECK_IN_START || $localTime >= self::SELF_CHECK_IN_END) {
            throw new DomainException('Self check-in is available from 9 AM until 6 PM. The actual arrival time is recorded.','attendance_checkin_window',409);
        }
    }

    public static function assertCheckOutTime(string $localTime): void {
        if ($localTime < self::SELF_CHECK_OUT_START || $localTime >= self::AUTO_CHECK_OUT) {
            throw new DomainException('Self check-out is available from 6 PM until 8 PM; unchecked-out attendance closes automatically at 8 PM.','attendance_checkout_window',409);
        }
    }

    public static function autoCheckOutDue(string $localTime): bool {
        return $localTime >= self::AUTO_CHECK_OUT;
    }
}
