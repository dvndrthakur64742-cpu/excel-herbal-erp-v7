<?php
namespace ExcelHerbal\ERP7\Database;

use ExcelHerbal\ERP7\Domain\DomainException;

final class Transaction {
    private static int $depth=0;

    public static function run(callable $fn): mixed {
        $db=Db::wpdb();$d=self::$depth;$sp='eh7_sp_'.$d;
        $started=$d===0?$db->query('START TRANSACTION'):$db->query("SAVEPOINT {$sp}");
        if($started===false)throw new DomainException($d===0?'Database transaction could not start.':'Database savepoint could not be created.','transaction_start_failed',500);
        self::$depth++;
        try{
            $r=$fn();
            $finished=$d===0?$db->query('COMMIT'):$db->query("RELEASE SAVEPOINT {$sp}");
            if($finished===false)throw new DomainException($d===0?'Database transaction commit failed.':'Database savepoint release failed.','transaction_commit_failed',500);
            self::$depth--;
            return$r;
        }catch(\Throwable $e){
            self::$depth--;
            $rolled=$d===0?$db->query('ROLLBACK'):$db->query("ROLLBACK TO SAVEPOINT {$sp}");
            if($rolled===false)error_log('EH7 transaction rollback failed at depth '.$d.': '.$e->getMessage());
            throw$e;
        }
    }
}
