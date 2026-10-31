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
