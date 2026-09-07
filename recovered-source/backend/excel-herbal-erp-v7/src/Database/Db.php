<?php
namespace ExcelHerbal\ERP7\Database;

use ExcelHerbal\ERP7\Domain\DomainException;

final class Db {
    public static function wpdb(): object { global $wpdb; return $wpdb; }
    public static function table(string $name): string { $db=self::wpdb(); return $db->prefix.'eh7_'.$name; }
    public static function now(): string { return current_time('mysql', true); }
    public static function today(): string { return current_time('Y-m-d'); }
    public static function mustInsert(object $db,string $table,array $data): int {
        $result=$db->insert($table,$data);
        if($result===false){
            throw new DomainException('Required database insert failed.','database_insert_failed',500);
        }
        return (int)$result;
    }
}
