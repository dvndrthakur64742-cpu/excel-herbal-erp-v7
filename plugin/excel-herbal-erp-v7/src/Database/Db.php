<?php
namespace ExcelHerbal\ERP7\Database;

use ExcelHerbal\ERP7\Domain\DomainException;

final class Db {
    public static function wpdb(): object { global $wpdb; return $wpdb; }
    public static function table(string $name): string { $db=self::wpdb(); return $db->prefix.'eh7_'.$name; }
    public static function now(): string { return current_time('mysql', true); }
    /** Business-local datetime for journal entry_date and other business-date projections. */
    public static function businessNow(): string { return current_time('mysql'); }
    public static function today(): string { return current_time('Y-m-d'); }
    public static function mustUpdate(object $db,string $table,array $data,array $where): int {
        $result=$db->update($table,$data,$where);
        if($result===false)throw new DomainException('Required database update failed.','database_update_failed',500);
        return (int)$result;
    }
    public static function mustQuery(object $db,string $sql): int {
        $result=$db->query($sql);
        if($result===false)throw new DomainException('Required database query failed.','database_query_failed',500);
        return (int)$result;
    }
    public static function mustInsert(object $db,string $table,array $data,string $conflictMessage='Database record already exists.',string $conflictCode='database_conflict'): int {
        $result=$db->insert($table,$data);
        if($result===false){
            $error=strtolower(trim((string)($db->last_error??'')));
            // MySQL/MariaDB duplicate-key failures are client conflicts, not server faults.
            // Keep database details private while returning a stable REST-friendly 409.
            if(str_contains($error,'duplicate entry')||str_contains($error,'duplicate key')||str_contains($error,'1062')){
                throw new DomainException($conflictMessage,$conflictCode,409);
            }
            throw new DomainException('Required database insert failed.','database_insert_failed',500);
        }
        return (int)$result;
    }
}
