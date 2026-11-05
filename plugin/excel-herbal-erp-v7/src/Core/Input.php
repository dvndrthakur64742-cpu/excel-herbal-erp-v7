<?php
namespace ExcelHerbal\ERP7\Core;

use ExcelHerbal\ERP7\Domain\DomainException;

final class Input
{
    public static function date(string $value, string $label='Date'): string
    {
        $value=trim($value);
        $parsed=\DateTimeImmutable::createFromFormat('!Y-m-d',$value);
        $errors=\DateTimeImmutable::getLastErrors();
        if(!$parsed||$parsed->format('Y-m-d')!==$value||($errors!==false&&(($errors['warning_count']??0)>0||($errors['error_count']??0)>0))){
            throw new DomainException($label.' must be YYYY-MM-DD.','date_invalid',422);
        }
        return $value;
    }

    /** @return array{0:string,1:string} */
    public static function dateRange(string $from,string $to,string $label='Date range'): array
    {
        $from=self::date($from,$label.' start');
        $to=self::date($to,$label.' end');
        if($from>$to)throw new DomainException($label.' start cannot be after end.','date_range_invalid',422);
        return[$from,$to];
    }

    /** @return array{0:string,1:string} UTC start inclusive, UTC end exclusive */
    public static function utcBoundsForBusinessRange(string $from,string $to,string $label='Date range'): array
    {
        [$from,$to]=self::dateRange($from,$to,$label);
        $tz=wp_timezone();
        $utc=new \DateTimeZone('UTC');
        $start=new \DateTimeImmutable($from.' 00:00:00',$tz);
        $end=(new \DateTimeImmutable($to.' 00:00:00',$tz))->modify('+1 day');
        return[$start->setTimezone($utc)->format('Y-m-d H:i:s'),$end->setTimezone($utc)->format('Y-m-d H:i:s')];
    }

    /**
     * Accepts an ISO-8601/MySQL second-precision datetime and normalises it to UTC.
     * A value without an explicit timezone is interpreted in the WordPress business timezone.
     */
    public static function utcDateTime(string $value,string $label='Date/time'): string
    {
        $value=trim($value);
        if(!preg_match('/^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})?$/',$value)){
            throw new DomainException($label.' must be a valid date/time.','datetime_invalid',422);
        }
        $hasZone=(bool)preg_match('/(?:Z|[+-]\d{2}:\d{2})$/',$value);
        try{
            $parsed=$hasZone?new \DateTimeImmutable($value):new \DateTimeImmutable($value,wp_timezone());
            $errors=\DateTimeImmutable::getLastErrors();
            if($errors!==false&&(($errors['warning_count']??0)>0||($errors['error_count']??0)>0))throw new \Exception('Invalid date/time');
        }catch(\Throwable $e){
            throw new DomainException($label.' must be a valid date/time.','datetime_invalid',422);
        }
        return $parsed->setTimezone(new \DateTimeZone('UTC'))->format('Y-m-d H:i:s');
    }

    /** @return array{0:string,1:string} UTC start/end inclusive */
    public static function utcDateTimeRange(string $from,string $to,string $label='Date/time range'): array
    {
        $today=current_time('Y-m-d');
        $from=trim($from);$to=trim($to);
        if($from==='')$from=$today;
        if($to==='')$to=$today;

        if(preg_match('/^\d{4}-\d{2}-\d{2}$/',$from)){
            [$start]=self::utcBoundsForBusinessRange($from,$from,$label);
        }else{$start=self::utcDateTime($from,$label.' start');}

        if(preg_match('/^\d{4}-\d{2}-\d{2}$/',$to)){
            [, $exclusiveEnd]=self::utcBoundsForBusinessRange($to,$to,$label);
            $end=(new \DateTimeImmutable($exclusiveEnd,new \DateTimeZone('UTC')))->modify('-1 second')->format('Y-m-d H:i:s');
        }else{$end=self::utcDateTime($to,$label.' end');}

        if($start>$end)throw new DomainException($label.' start cannot be after end.','datetime_range_invalid',422);
        return[$start,$end];
    }

    public static function optionalDate(string $value,string $label='Date'): ?string
    {
        $value=trim($value);
        return $value===''?null:self::date($value,$label);
    }

    public static function optionalUtcDateTime(string $value,string $label='Date/time',bool $dateMeansEndOfDay=false): ?string
    {
        $value=trim($value);
        if($value==='')return null;
        if(preg_match('/^\d{4}-\d{2}-\d{2}$/',$value)){
            [$start,$end]=self::utcDateTimeRange($value,$value,$label);
            return $dateMeansEndOfDay?$end:$start;
        }
        return self::utcDateTime($value,$label);
    }
}
