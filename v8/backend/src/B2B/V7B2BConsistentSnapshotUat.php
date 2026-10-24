<?php
declare(strict_types=1);
namespace ExcelHerbal\ERP8\B2B;

use ExcelHerbal\ERP7\Database\Db;
use ExcelHerbal\ERP7\Security\{Actor,Capabilities,Guard};
use PDO;
use Throwable;

/**
 * Disposable MariaDB only: wraps the existing full branch/day reconciler in
 * a single InnoDB REPEATABLE READ / CONSISTENT SNAPSHOT / READ ONLY transaction.
 *
 * $duringSnapshot is a TEST-ONLY seam for a separate connection changing
 * already-committed data AFTER the snapshot is established. No HTTP/REST
 * route, scheduler, payment writer or production bootstrap uses this helper.
 */
final class V7B2BConsistentSnapshotUat
{
    private const V7_TABLES=[
        'b2b_retailer_sales','b2b_retailer_sale_lines','stock_ledger',
        'b2b_verified_tenders','journal_entries','journal_lines','accounts',
        'b2b_cash_remittances','b2b_cashier_receipts_uat',
    ];
    private const V8_TABLES=[
        'v8_b2b_sale_intents_uat','v8_b2b_verified_tenders',
        'v8_b2b_sale_tender_reservations_uat',
        'v8_b2b_payment_intents_uat','v8_b2b_tender_intake_evidence_uat',
    ];

    public static function inspect(Actor $actor,int $branch,string $businessDay,
        PDO $pdo,?\Closure $duringSnapshot=null):array
    {
        $db=Db::wpdb();
        // The existing UAT writer already demands development mode, fake
        // owner-approval test constants and DATABASE()='v8_test'.
        V7CanonicalPostingSinkUat::assertNonProductionEnvironment($db);
        Guard::branch($actor,$branch,Capabilities::ACCOUNTING_VIEW);
        if(!property_exists($db,'pdo') || !($db->pdo instanceof PDO) ||
            $db->pdo!==$pdo)
            throw new RetailerSaleError('Snapshot requires the same proven PDO connection as the canonical V7 wpdb adapter.');
        if($pdo->getAttribute(PDO::ATTR_DRIVER_NAME)!=='mysql' ||
            $pdo->getAttribute(PDO::ATTR_ERRMODE)!==PDO::ERRMODE_EXCEPTION ||
            $pdo->query('SELECT DATABASE()')->fetchColumn()!=='v8_test')
            throw new RetailerSaleError('Snapshot refuses non-MariaDB, non-strict or non-disposable connections.');
        if($pdo->inTransaction())
            throw new RetailerSaleError('Cannot start a branch snapshot inside an existing transaction.');

        // A consistent MVCC snapshot does NOT cover MyISAM/nontransactional
        // tables. Verify the entire source set, including UAT intents and
        // ledger receipts, rather than claiming full consistency otherwise.
        $tables=[
            ...array_map(static fn(string $name):string=>Db::table($name),self::V7_TABLES),
            ...self::V8_TABLES,
        ];
        $tables=array_values(array_unique($tables));
        if(count($tables)!==count(self::V7_TABLES)+count(self::V8_TABLES))
            throw new RetailerSaleError('Duplicate or inconsistent snapshot source table identity.');
        $in=implode(',',array_fill(0,count($tables),'?'));
        $st=$pdo->prepare(
            'SELECT TABLE_NAME,ENGINE FROM information_schema.TABLES'.
            ' WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME IN ('.$in.')'
        );
        if(!$st||!$st->execute($tables))
            throw new RetailerSaleError('Cannot verify transactional engine for complete V7/V8 sources.');
        $engines=$st->fetchAll(PDO::FETCH_ASSOC);
        if(count($engines)!==count($tables))
            throw new RetailerSaleError('Missing table in canonical B2B snapshot dependency set.');
        $found=[];
        foreach($engines as $row){
            $name=(string)($row['TABLE_NAME']??'');
            if(!in_array($name,$tables,true)||isset($found[$name])||
                strtoupper((string)($row['ENGINE']??''))!=='INNODB')
                throw new RetailerSaleError('Non-InnoDB or ambiguous source table blocks consistent snapshot.');
            $found[$name]=true;
        }

        $begun=false;
        try{
            // Only session-scoped for this next transaction. Never set
            // global isolation level or change the live database.
            $pdo->exec('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ');
            $pdo->exec('START TRANSACTION WITH CONSISTENT SNAPSHOT, READ ONLY');
            $begun=true;
            if(!$pdo->inTransaction())
                throw new RetailerSaleError('MariaDB failed to establish a tracked transaction.');

            if($duringSnapshot!==null)$duringSnapshot();

            $result=V7B2BBranchDayPreflightUat::inspect($actor,$branch,$businessDay);
            if(($result['read_only']??false)!==true
                ||($result['scope']??null)!=='disposable_v8_test_canonical_v7_only'
                ||($result['production_release_authorized']??true)!==false
                ||($result['snapshot_isolation_guaranteed']??true)!==false
                ||($result['complete_batch']??false)!==true)
                throw new RetailerSaleError('Branch/day preflight evidence contract was not satisfied.');
            // This MUST succeed before returning a green staging result.
            $pdo->rollBack();
            $begun=false;
            if($pdo->inTransaction())
                throw new RetailerSaleError('Snapshot transaction remained open after rollback.');
            $result['snapshot_isolation_guaranteed']=true;
            $result['snapshot_boundary']='mariadb_innodb_repeatable_read_consistent_snapshot';
            $result['read_only_transaction_verified']=true;
            $result['snapshot_transaction_closed']=true;
            $result['verified_innodb_source_tables']=count($tables);
            $result['production_release_authorized']=false;
            return $result;
        }catch(Throwable $error){
            if($begun){
                try{
                    $pdo->rollBack();
                }catch(Throwable $rollbackError){
                    throw new RetailerSaleError(
                        'Snapshot failed and rollback failed; discard this database connection.',
                        0,$rollbackError
                    );
                }
            }
            throw $error;
        }
    }
}
