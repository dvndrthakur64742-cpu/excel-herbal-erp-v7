<?php
namespace ExcelHerbal\ERP7\Workforce;

use ExcelHerbal\ERP7\Domain\DomainException;

final class GpsDutyPolicy {
    public const START='10:30:00';
    public const STOP='17:00:00';

    public static function state(?array $attendance,?string $nowLocal=null,?array $settings=null):array {
        $tz=function_exists('wp_timezone')?wp_timezone():new \DateTimeZone('UTC');
        $now=$nowLocal?new \DateTimeImmutable($nowLocal,$tz):new \DateTimeImmutable('now',$tz);
        $date=(string)($attendance['business_date']??$now->format('Y-m-d'));
        $settings=$settings??(($attendance['check_in_mode']??null)==='self'?SelfAttendancePolicy::snapshot($attendance):['gps_start'=>self::START,'gps_stop'=>self::STOP]);
        $start=new \DateTimeImmutable($date.' '.$settings['gps_start'],$tz);
        $stop=new \DateTimeImmutable($date.' '.$settings['gps_stop'],$tz);
        $checkedIn=!empty($attendance['check_in_at']);$checkedOut=!empty($attendance['check_out_at']);
        if(!$checkedIn)$status='not_checked_in';
        elseif($checkedOut)$status='checked_out';
        elseif($now<$start)$status='scheduled';
        elseif($now>=$stop)$status='auto_stopped';
        else $status='active';
        return [
            'gps_status'=>$status,
            'gps_should_track'=>$status==='active',
            'gps_start_time'=>substr($settings['gps_start'],0,5),
            'gps_stop_time'=>substr($settings['gps_stop'],0,5),
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
        $settings=($attendance['check_in_mode']??null)==='self'?SelfAttendancePolicy::snapshot($attendance):['gps_start'=>self::START,'gps_stop'=>self::STOP];
        if($time<$settings['gps_start'])throw new DomainException('GPS duty has not started.','gps_window_not_started',409);
        if($time>=$settings['gps_stop'])throw new DomainException('GPS duty window is closed.','gps_window_closed',409);
        if(($attendance['check_in_mode']??null)==='self' && $recordedUtc<(string)$attendance['check_in_at'])throw new DomainException('GPS point precedes employee check-in.','gps_recorded_time_invalid',422);
    }
}
