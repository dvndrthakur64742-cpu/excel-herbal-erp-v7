<?php
namespace ExcelHerbal\ERP7\Workforce;

use ExcelHerbal\ERP7\Database\Db;

/**
 * Best-effort 8 PM auto-closure of self-checked-in attendance; GPS duty is separate.
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
            'display' => 'Every five minutes (Excel Herbal ERP attendance closure)',
        ];
        return $schedules;
    }

    public static function run(): void {
        // Only close TODAY's attendance that employees themselves opened.
        // No automatic check-in, no backdating, no historical repair and no GPS modification.
        if (!AttendancePolicy::autoCheckOutDue(current_time('H:i:s'))) return;
        $db = Db::wpdb();
        $today = Db::today();
        $stopUtc = get_gmt_from_date($today . ' ' . AttendancePolicy::AUTO_CHECK_OUT);
        $table = Db::table('attendance');
        Db::mustQuery($db, $db->prepare(
            "UPDATE {$table} SET check_out_at=%s
             WHERE business_date=%s AND check_in_at IS NOT NULL AND check_out_at IS NULL",
            $stopUtc, $today
        ));
    }
}
