<?php
namespace ExcelHerbal\ERP7\Workforce;

use ExcelHerbal\ERP7\Database\Db;

/**
 * Best-effort WordPress-Cron materialization of the server-owned duty window.
 *
 * WordPress-Cron runs when the site receives traffic; production should also
 * invoke wp-cron.php from the host scheduler for dependable timing.
 */
final class ScheduledAttendanceService {
    public const HOOK = 'eh7_scheduled_attendance_tick';
    public const INTERVAL = 'eh7_five_minutes';
    private const LAST_SUCCESS_OPTION = 'eh7_attendance_scheduler_last_success_utc';
    private const STALE_AFTER_SECONDS = 900;

    public static function boot(): void {
        add_filter('cron_schedules', [self::class, 'cronSchedules']);
        add_action(self::HOOK, [self::class, 'run']);
        if (!wp_next_scheduled(self::HOOK)) {
            wp_schedule_event(time() + 60, self::INTERVAL, self::HOOK);
        }
    }

    public static function deactivate(): void {
        wp_clear_scheduled_hook(self::HOOK);
    }

    public static function cronSchedules(array $schedules): array {
        $schedules[self::INTERVAL] = [
            'interval' => 300,
            'display' => 'Every five minutes (Excel Herbal ERP duty schedule)',
        ];
        return $schedules;
    }

    /**
     * Read-only scheduler telemetry. A recent successful tick is evidence that
     * the scheduler ran, not proof that an employee was physically present.
     */
    public static function health(): array {
        $last = function_exists('get_option') ? (int)get_option(self::LAST_SUCCESS_OPTION, 0) : 0;
        $next = function_exists('wp_next_scheduled') ? (int)wp_next_scheduled(self::HOOK) : 0;
        return self::evaluateHealth($last, $next, time());
    }

    public static function evaluateHealth(int $last, int $next, int $now): array {
        $status = match (true) {
            $next <= 0 => 'not_scheduled',
            $last <= 0 => 'unverified',
            $last > $now => 'clock_mismatch',
            $now - $last > self::STALE_AFTER_SECONDS => 'stale',
            $now - $next > self::STALE_AFTER_SECONDS => 'overdue',
            default => 'recent',
        };
        return [
            'status' => $status,
            'last_success_utc' => $last > 0 ? gmdate('Y-m-d H:i:s', $last) : null,
            'next_due_utc' => $next > 0 ? gmdate('Y-m-d H:i:s', $next) : null,
            'stale_after_seconds' => self::STALE_AFTER_SECONDS,
        ];
    }

    private static function recordSuccessfulTick(): void {
        if (function_exists('update_option')) {
            update_option(self::LAST_SUCCESS_OPTION, time(), false);
        }
    }

    public static function run(): void {
        $localTime = current_time('H:i:s');
        if ($localTime < GpsDutyPolicy::START) {
            self::recordSuccessfulTick();
            return;
        }

        $db = Db::wpdb();
        $date = Db::today();
        $startUtc = get_gmt_from_date($date . ' ' . GpsDutyPolicy::START);
        $stopUtc = get_gmt_from_date($date . ' ' . GpsDutyPolicy::STOP);
        $attendance = Db::table('attendance');
        $employees = Db::table('employees');
        $branches = Db::table('branches');
        $leave = Db::table('leave_requests');
        $holidays = Db::table('holidays');

        // Approved leave and branch/global holidays are excluded.
        $rows = $db->get_results($db->prepare(
            "SELECT e.company_id,e.id employee_id,e.assigned_branch_id branch_id
             FROM {$employees} e
             JOIN {$branches} b ON b.id=e.assigned_branch_id
                 AND b.company_id=e.company_id AND b.status='active'
             WHERE e.status='active'
               AND NOT EXISTS (
                   SELECT 1 FROM {$leave} l
                   WHERE l.company_id=e.company_id AND l.employee_id=e.id
                     AND l.status='approved' AND l.date_from<=%s AND l.date_to>=%s
               )
               AND NOT EXISTS (
                   SELECT 1 FROM {$holidays} h
                   WHERE h.company_id=e.company_id AND h.active=1
                     AND (h.branch_id IS NULL OR h.branch_id=e.assigned_branch_id)
                     AND h.holiday_date=%s
               )
             ORDER BY e.company_id,e.id",
            $date, $date, $date
        ), ARRAY_A);

        if ($db->last_error !== '') {
            error_log('EH7 scheduled attendance eligibility query failed; heartbeat not advanced.');
            return;
        }

        $failed = 0;
        foreach ((array)$rows as $row) {
            $companyId = (int)$row['company_id'];
            $employeeId = (int)$row['employee_id'];
            $branchId = (int)$row['branch_id'];

            try {
                Db::mustQuery($db, $db->prepare(
                    "INSERT INTO {$attendance}
                        (company_id,branch_id,employee_id,business_date,status,check_in_at,created_at)
                     VALUES (%d,%d,%d,%s,'present',%s,%s)
                     ON DUPLICATE KEY UPDATE id=id",
                    $companyId, $branchId, $employeeId, $date, $startUtc, Db::now()
                ));

                Db::mustUpdate($db, $attendance, [
                    'branch_id' => $branchId,
                    'check_in_at' => $startUtc,
                    'status' => 'present',
                ], [
                    'company_id' => $companyId,
                    'employee_id' => $employeeId,
                    'business_date' => $date,
                    'check_in_at' => null,
                ]);

                if ($localTime >= GpsDutyPolicy::STOP) {
                    Db::mustUpdate($db, $attendance, [
                        'check_out_at' => $stopUtc,
                    ], [
                        'company_id' => $companyId,
                        'employee_id' => $employeeId,
                        'business_date' => $date,
                        'check_out_at' => null,
                    ]);
                }
            } catch (\Throwable $error) {
                // A failed employee row must not prevent later employees or
                // other WordPress cron jobs from being processed. The next
                // scheduled tick safely retries the idempotent writes.
                $failed++;
            }
        }
        if ($failed > 0) {
            error_log('EH7 scheduled attendance: '.$failed.' employee row(s) failed; retry on next tick; heartbeat not advanced.');
            return;
        }
        self::recordSuccessfulTick();
    }
}
