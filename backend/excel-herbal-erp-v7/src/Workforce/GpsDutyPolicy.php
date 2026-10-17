<?php
namespace ExcelHerbal\ERP7\Workforce;

use ExcelHerbal\ERP7\Domain\DomainException;

final class GpsDutyPolicy {
    public const START='10:30:00';
    public const STOP='17:00:00';

    public static function state(?array $attendance,?string $nowLocal=null):array {
        $tz=function_exists('wp_timezone')?wp_timezone():new \DateTimeZone('UTC');
        $now=$nowLocal?new \DateTimeImmutable($nowLocal,$tz):new \DateTimeImmutable('now',$tz);
        $date=(string)($attendance['business_date']??$now->format('Y-m-d'));
        $start=new \DateTimeImmutable($date.' '.self::START,$tz);
        $stop=new \DateTimeImmutable($date.' '.self::STOP,$tz);
        $checkedIn=!empty($attendance['check_in_at']);
        if(!$checkedIn)$status='not_checked_in';
        elseif($now<$start)$status='scheduled';
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
}
