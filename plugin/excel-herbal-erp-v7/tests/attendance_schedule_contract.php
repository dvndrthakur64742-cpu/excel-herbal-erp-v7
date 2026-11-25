<?php
// Synthetic duty-time contract checks. No WordPress, database or real employee data.
require_once __DIR__.'/../src/Domain/DomainException.php';
require_once __DIR__.'/../src/Workforce/GpsDutyPolicy.php';
use ExcelHerbal\ERP7\Workforce\GpsDutyPolicy;
function dutyAssert(bool $ok,string $label):void{if(!$ok){fwrite(STDERR,"FAIL $label\n");exit(1);}echo "PASS $label\n";}
$attendance=['business_date'=>'2026-10-31','check_in_at'=>'2026-10-31 05:00:00','check_out_at'=>null];
$before=GpsDutyPolicy::state($attendance,'2026-10-31 10:29:59');
dutyAssert($before['gps_should_track']===false,'GPS disabled until duty begins');
$active=GpsDutyPolicy::state($attendance,'2026-10-31 10:30:00');
dutyAssert($active['gps_should_track']===true && $active['manual_start_allowed']===false,'GPS automatic at 10:30');
$closed=GpsDutyPolicy::state($attendance,'2026-10-31 17:00:00');
dutyAssert($closed['gps_should_track']===false && $closed['manual_stop_allowed']===false,'GPS stops at 17:00');
foreach(['WorkforceService.php'=>'ensureScheduledAttendance','ScheduledAttendanceService.php'=>"public const HOOK = 'eh7_scheduled_attendance_tick'"] as $file=>$needle){
  $src=file_get_contents(__DIR__.'/../src/Workforce/'.$file);
  dutyAssert(is_string($src)&&str_contains($src,$needle),'attendance scheduler exists: '.$file);
}
$work=file_get_contents(__DIR__.'/../src/Workforce/WorkforceService.php');
dutyAssert(str_contains($work,"'attendance_manual_disabled',403") && str_contains($work,"get_gmt_from_date"),'manual check-in denied and UTC duty times used');
$plugin=file_get_contents(__DIR__.'/../src/Core/Plugin.php');
dutyAssert(str_contains($plugin,'ScheduledAttendanceService::boot()')&&str_contains($plugin,'ScheduledAttendanceService::deactivate()'),'scheduler lifecycle registered');

require_once __DIR__.'/../src/Workforce/ScheduledAttendanceService.php';
use ExcelHerbal\ERP7\Workforce\ScheduledAttendanceService;
$now=1800000000;
foreach([
    [0,0,'not_scheduled'],
    [0,$now+300,'unverified'],
    [$now+60,$now+300,'clock_mismatch'],
    [$now-901,$now+300,'stale'],
    [$now-60,$now-901,'overdue'],
    [$now-900,$now+300,'recent'],
] as [$last,$next,$expected]){
    $health=ScheduledAttendanceService::evaluateHealth($last,$next,$now);
    dutyAssert($health['status']===$expected,'attendance scheduler telemetry '.$expected);
    dutyAssert($health['last_success_utc']===($last>0?gmdate('Y-m-d H:i:s',$last):null),'scheduler last successful UTC '.$expected);
}
$scheduler=file_get_contents(__DIR__.'/../src/Workforce/ScheduledAttendanceService.php');
dutyAssert(str_contains($scheduler,'self::recordSuccessfulTick();'),'successful tick telemetry recorded');
$diag=file_get_contents(__DIR__.'/../src/Administration/MaintenanceService.php');
dutyAssert(str_contains($diag,"'today_overdue_without_checkout'")&&str_contains($diag,'ScheduledAttendanceService::health()'),'read-only diagnostics include overdue today and scheduler health');


// Exercise the real scheduler with a disposable fake DB. A single failed
// write must not stop the remaining staff, and no false success is recorded.
require_once __DIR__.'/../src/Database/Db.php';
if (!defined('ARRAY_A')) define('ARRAY_A', 'ARRAY_A');
function current_time($format, $gmt = false) {
    return match ($format) {
        'H:i:s' => '17:05:00',
        'Y-m-d' => '2026-11-25',
        'mysql' => '2026-11-25 11:35:00',
        default => throw new RuntimeException('Unexpected fixture time format'),
    };
}
function get_gmt_from_date($value, $format = 'Y-m-d H:i:s') {
    return (new DateTimeImmutable($value, new DateTimeZone('Asia/Kolkata')))
        ->setTimezone(new DateTimeZone('UTC'))->format($format);
}
$GLOBALS['duty_heartbeats'] = 0;
function update_option($key, $value, $autoload = null) {
    if ($key === 'eh7_attendance_scheduler_last_success_utc') $GLOBALS['duty_heartbeats']++;
    return true;
}
final class DutySchedulerFixtureDb {
    public string $prefix = 'fixture_';
    public string $last_error = '';
    public bool $failFirst = true;
    public bool $failEligibility = false;
    public array $closed = [];
    public function prepare($sql, ...$args) { return [$sql, $args]; }
    public function get_results($query, $mode) {
        $this->last_error = $this->failEligibility ? 'fixture query failure' : '';
        return $this->failEligibility ? [] : [
            ['company_id'=>1,'employee_id'=>10,'branch_id'=>1],
            ['company_id'=>1,'employee_id'=>20,'branch_id'=>1],
        ];
    }
    public function query($query) {
        if ($this->failFirst && (int)$query[1][2] === 10) return false;
        return 1;
    }
    public function update($table, $data, $where) {
        if (isset($data['check_out_at'])) {
            $this->closed[] = [$where['employee_id'], $where['business_date'], $data['check_out_at']];
        }
        return 1;
    }
}
$wpdb = new DutySchedulerFixtureDb();
ScheduledAttendanceService::run();
dutyAssert($wpdb->closed === [[20,'2026-11-25','2026-11-25 11:30:00']], 'failed first employee does not block second checkout');
dutyAssert($GLOBALS['duty_heartbeats'] === 0, 'partial tick does not advance success heartbeat');
$wpdb->failFirst = false;
$wpdb->closed = [];
ScheduledAttendanceService::run();
dutyAssert(count($wpdb->closed) === 2 && $GLOBALS['duty_heartbeats'] === 1, 'next tick retries safely and records full success');
$wpdb->failEligibility = true;
$wpdb->closed = [];
ScheduledAttendanceService::run();
dutyAssert($wpdb->closed === [] && $GLOBALS['duty_heartbeats'] === 1, 'failed eligibility query does not mutate attendance or advance heartbeat');
