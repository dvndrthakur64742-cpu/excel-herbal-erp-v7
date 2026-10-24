<?php
namespace ExcelHerbal\ERP7\Workforce;

use ExcelHerbal\ERP7\Domain\DomainException;

final class GpsDutyPolicy {
    public const START='10:30:00';
    public const STOP='17:00:00';

    public static function state(?array $attendance,?string $nowLocal=null):array {
        $tz=function_exists('wp_timezone')?wp_timezone():new \DateTimeZone('UTC');
        // Use the canonical WordPress business clock, also shared by payroll
        // and the attendance API; never infer duty from user-device time.
        $clock=$nowLocal??(function_exists('current_time')?current_time('mysql'):null);
        $now=$clock?new \DateTimeImmutable($clock,$tz):new \DateTimeImmutable('now',$tz);
        $date=(string)($attendance['business_date']??$now->format('Y-m-d'));
        $start=new \DateTimeImmutable($date.' '.self::START,$tz);
        $stop=new \DateTimeImmutable($date.' '.self::STOP,$tz);
        // GPS duty is independent from the employee's manual attendance.
        if($now<$start)$status='scheduled';
        elseif($now>=$stop)$status='auto_stopped';
        else $status='active';
        return [
            'gps_status'=>$status,
            'gps_should_track'=>$status==='active',
            'gps_start_time'=>'10:30',
            'gps_stop_time'=>'17:00',
            'gps_window_start'=>$start->format('Y-m-d H:i:s'),
            'gps_window_stop'=>$stop->format('Y-m-d H:i:s'),
            'gps_window_start_utc'=>$start->setTimezone(new \DateTimeZone('UTC'))->format('Y-m-d\TH:i:s\Z'),
            'gps_window_stop_utc'=>$stop->setTimezone(new \DateTimeZone('UTC'))->format('Y-m-d\TH:i:s\Z'),
            'manual_start_allowed'=>false,
            'manual_stop_allowed'=>false,
        ];
    }

    public static function assertRecordedAt(string $recordedUtc,array $attendance):void {
        $businessDate=(string)($attendance['business_date']??'');
        $local=get_date_from_gmt($recordedUtc,'Y-m-d H:i:s');
        if($businessDate===''||substr($local,0,10)!==$businessDate)throw new DomainException('GPS point is outside the active business day.','gps_recorded_date_invalid',422);
        $time=substr($local,11,8);
        if($time<self::START)throw new DomainException('GPS duty starts automatically at 10:30 AM.','gps_window_not_started',409);
        if($time>=self::STOP)throw new DomainException('GPS duty automatically stops at 5:00 PM.','gps_window_closed',409);
    }

    public static function assertFreshRecording(string $recordedUtc,string $serverUtc):void {
        $recorded=new \DateTimeImmutable($recordedUtc,new \DateTimeZone('UTC'));
        $now=new \DateTimeImmutable($serverUtc,new \DateTimeZone('UTC'));
        if($recorded<$now->modify('-15 minutes') || $recorded>$now->modify('+2 minutes'))
            throw new DomainException('GPS position must be recorded within 15 minutes of server time.','gps_recorded_time_invalid',422);
    }
}
