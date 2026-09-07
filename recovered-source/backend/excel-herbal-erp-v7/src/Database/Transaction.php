<?php
namespace ExcelHerbal\ERP7\Database;
final class Transaction {
    private static int $depth=0;
    public static function run(callable $fn): mixed {
        $db=Db::wpdb(); $d=self::$depth; $sp='eh7_sp_'.$d;
        if($d===0){$db->query('START TRANSACTION');}else{$db->query("SAVEPOINT {$sp}");}
        self::$depth++;
        try{$r=$fn();self::$depth--;if($d===0){$db->query('COMMIT');}else{$db->query("RELEASE SAVEPOINT {$sp}");}return$r;}
        catch(\Throwable $e){self::$depth--;if($d===0){$db->query('ROLLBACK');}else{$db->query("ROLLBACK TO SAVEPOINT {$sp}");}throw$e;}
    }
}
