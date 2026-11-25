<?php
namespace ExcelHerbal\ERP7\Workforce;

use ExcelHerbal\ERP7\Domain\DomainException;

/** Approved self-attendance schedule. Values are local business wall-clock times.
 * No salary, overtime or absence decision is made by this policy.
 */
final class SelfAttendancePolicy {
    public const DEFAULTS = [
        'duty_start'=>'09:00:00',
        'gps_start'=>'10:30:00',
        'gps_stop'=>'17:00:00',
        'duty_end'=>'18:00:00',
        'auto_checkout'=>'19:00:00',
    ];

    // A coordinated rollout starts on a business-date boundary. Existing
    // installations keep their previous mode until the approved cutover date.
    public static function enabled(int $companyId, string $date): bool {
        $from = function_exists('get_option')
            ? get_option('eh7_self_attendance_from_'.$companyId, '') : '';
        return is_string($from) && preg_match('/^\d{4}-\d{2}-\d{2}$/D', $from)
            && $from <= $date;
    }

    public static function schedule(array $settings = []): array {
        $times = array_replace(self::DEFAULTS, $settings);
        foreach (self::DEFAULTS as $key => $default) {
            $value = $times[$key];
            if (!is_string($value) || !preg_match('/^(?:[01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9]$/D', $value)) {
                throw new DomainException('Invalid attendance time: '.$key, 'attendance_policy_invalid', 422);
            }
        }
        if (array_diff_key($times, self::DEFAULTS)
            || !($times['duty_start'] <= $times['gps_start']
                && $times['gps_start'] < $times['gps_stop']
                && $times['gps_stop'] <= $times['duty_end']
                && $times['duty_end'] < $times['auto_checkout'])) {
            throw new DomainException('Attendance schedule times must be in order.', 'attendance_policy_invalid', 422);
        }
        return $times;
    }

    /** A date-specific snapshot, independent of subsequent settings changes. */
    public static function window(string $date, \DateTimeZone $zone, array $settings = []): array {
        $times = self::schedule($settings);
        $parsed = \DateTimeImmutable::createFromFormat('!Y-m-d', $date, $zone);
        if (!$parsed || $parsed->format('Y-m-d') !== $date) {
            throw new DomainException('Invalid business date.', 'attendance_date_invalid', 422);
        }
        $utc = new \DateTimeZone('UTC');
        $result = [];
        foreach ($times as $key => $time) {
            $result[$key] = new \DateTimeImmutable($date.' '.$time, $zone);
        }
        $result['auto_checkout_utc'] = $result['auto_checkout']->setTimezone($utc)->format('Y-m-d H:i:s');
        return $result;
    }

    public static function state(
        \DateTimeImmutable $now,
        ?\DateTimeImmutable $checkIn,
        ?\DateTimeImmutable $checkOut,
        bool $excused = false,
        array $settings = []
    ): array {
        $w = self::window($now->format('Y-m-d'), $now->getTimezone(), $settings);
        $open = $checkIn !== null && $checkOut === null;
        $punchWindow = $now >= $w['duty_start'] && $now < $w['auto_checkout'];
        return [
            'can_check_in'=>!$excused && $punchWindow && $checkIn === null && $checkOut === null,
            'can_check_out'=>$open && $punchWindow,
            'gps_should_track'=>$open && $now >= $checkIn && $now >= $w['gps_start'] && $now < $w['gps_stop'],
            'auto_checkout_due'=>$open && $now >= $w['auto_checkout'],
            'late_check_in'=>$checkIn !== null && $checkIn > $w['duty_start'],
            'early_checkout'=>$checkOut !== null && $checkOut < $w['duty_end'],
            'auto_checkout_utc'=>$w['auto_checkout_utc'],
        ];
    }
}
