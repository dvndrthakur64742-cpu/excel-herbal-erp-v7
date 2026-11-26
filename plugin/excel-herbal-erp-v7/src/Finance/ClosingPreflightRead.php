<?php
namespace ExcelHerbal\ERP7\Finance;

use ExcelHerbal\ERP7\Domain\DomainException;

/** Closing must fail closed when a blocker query cannot be verified. */
final class ClosingPreflightRead {
    public static function count(object $db,string $sql):int{
        $value=$db->get_var($sql);
        if(!empty($db->last_error)||(!is_int($value)&&!(is_string($value)&&ctype_digit($value)))||(int)$value<0){
            throw new DomainException('Closing checks unavailable. Retry before closing.','closing_preflight_unavailable',503);
        }
        return (int)$value;
    }

    public static function rows(object $db,string $sql,string $mode):array{
        $value=$db->get_results($sql,$mode);
        if(!empty($db->last_error)||!is_array($value)){
            throw new DomainException('Closing checks unavailable. Retry before closing.','closing_preflight_unavailable',503);
        }
        return $value;
    }
}
