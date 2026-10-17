<?php
namespace ExcelHerbal\\ERP7\\Workforce;

use ExcelHerbal\\ERP7\\Database\\Db;

/**
 * Best-effort WordPress-Cron materialization of the server-owned duty window.
 *
 * WordPress-Cron runs when the site receives traffic; production should also
 * invoke wp-cron.php from the host scheduler for dependable timing.
 */
final class ScheduledAttendanceService {
    public const HOOK = 'eh7_scheduled_attendance_tick';
    public const INTERVAL = 'eh7_five_minutes';

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

    public static function run(): void {
        $localTime = current_time('H:i:s');
        if ($localTime < GpsDutyPolicy::START) {
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

        // Do not create a present attendance record for employees on approved
        // leave or on a branch/global holiday.
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

        foreach ((array)$rows as $row) {
            $companyId = (int)$row['company_id'];
            $employeeId = (int)$row['employee_id'];
            $branchId = (int)$row['branch_id'];

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
        }
    }
}
