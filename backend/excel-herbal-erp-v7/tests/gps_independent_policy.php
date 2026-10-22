<?php
declare(strict_types=1);
/** Independent GPS duty time validation: no WordPress credentials or database writes. */
require __DIR__.'/../src/Domain/DomainException.php';
require __DIR__.'/../src/Workforce/GpsDutyPolicy.php';
require __DIR__.'/../src/Recovery/GpsPointValidator.php';
use ExcelHerbal\ERP7\Workforce\GpsDutyPolicy;
use ExcelHerbal\ERP7\Recovery\GpsPointValidator;
use ExcelHerbal\ERP7\Domain\DomainException;
function wp_timezone(): DateTimeZone { return new DateTimeZone('Asia/Kolkata'); }
function get_date_from_gmt(string $utc,string $fmt='Y-m-d H:i:s'): string {
    return (new DateTimeImmutable($utc,new DateTimeZone('UTC')))->setTimezone(wp_timezone())->format($fmt);
}
function requireStatus(string $local,string $expected):void {
    $s=GpsDutyPolicy::state(['business_date'=>'2026-10-22'],'2026-10-22 '.$local);
    if($s['gps_status']!==$expected)throw new RuntimeException("GPS window ".$local.": ".$s['gps_status']);
    if($s['manual_start_allowed']||$s['manual_stop_allowed'])throw new RuntimeException('Manual GPS toggle enabled');
}
requireStatus('10:29:59','scheduled');
requireStatus('10:30:00','active');
requireStatus('16:59:59','active');
requireStatus('17:00:00','auto_stopped');
if(!GpsDutyPolicy::state(null,'2026-10-22 11:00:00')['gps_should_track'])
    throw new RuntimeException('GPS is incorrectly coupled to manual attendance');
GpsDutyPolicy::assertRecordedAt('2026-10-22 05:00:00',['business_date'=>'2026-10-22']); //10:30 IST
GpsDutyPolicy::assertRecordedAt('2026-10-22 11:29:59',['business_date'=>'2026-10-22']); //16:59 IST
try{GpsDutyPolicy::assertRecordedAt('2026-10-22 11:30:00',['business_date'=>'2026-10-22']);throw new RuntimeException('After-hours position accepted');}
catch(DomainException $e){if($e->codeKey!=='gps_window_closed')throw $e;}
GpsDutyPolicy::assertFreshRecording('2026-10-22 06:35:00','2026-10-22 06:50:00');
try{GpsDutyPolicy::assertFreshRecording('2026-10-22 06:34:59','2026-10-22 06:50:00');throw new RuntimeException('Stale point accepted');}
catch(DomainException $e){if($e->codeKey!=='gps_recorded_time_invalid')throw $e;}
try{GpsDutyPolicy::assertFreshRecording('2026-10-22 06:52:01','2026-10-22 06:50:00');throw new RuntimeException('Future point accepted');}
catch(DomainException $e){if($e->codeKey!=='gps_recorded_time_invalid')throw $e;}
$browser=GpsPointValidator::normalize(['lat'=>31.0,'lng'=>76.0,'source'=>'duty_web']);
if($browser['source']!=='duty_web')throw new RuntimeException('Valid browser GPS source rejected');
echo "PASS independent GPS: attendance-null, 10:30–17:00, freshness, source safety\n";
