<?php
declare(strict_types=1);
/** Actual MariaDB SQL audit over canonical V7 Daily Order records; rollback-only v8_test. */
use ExcelHerbal\ERP7\DailyOrder\DailyFieldStockAudit;
use ExcelHerbal\ERP7\{Database\Db,Database\Schema,Security\Actor,Security\Capabilities};
$dsn=getenv('V8_TEST_DSN');
if(!$dsn){fwrite(STDERR,"V8_TEST_DSN required; cannot silently skip canonical stock audit\n");exit(2);}
if(!in_array('mysql',PDO::getAvailableDrivers(),true))throw new RuntimeException('PDO MySQL required');
$pdo=new PDO($dsn,getenv('V8_TEST_USER')?:'v8',getenv('V8_TEST_PASSWORD')?:'v8',
    [PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,PDO::ATTR_DEFAULT_FETCH_MODE=>PDO::FETCH_ASSOC]);
if($pdo->query('SELECT DATABASE()')->fetchColumn()!=='v8_test')
    throw new RuntimeException('Refuse a non-disposable MariaDB database');
$src=dirname(__DIR__,3).'/backend/excel-herbal-erp-v7/src/';
foreach(['Domain/DomainException.php','Database/Db.php','Database/Schema.php',
    'Security/Actor.php','Security/Capabilities.php','Security/Guard.php',
    'DailyOrder/DailyFieldStockAudit.php'] as $f)require_once $src.$f;
if(!defined('ARRAY_A'))define('ARRAY_A','ARRAY_A');
foreach(['daily_cycles','daily_requests','daily_issue_lines','evening_settlements',
    'evening_lines','stock_ledger','journal_entries','journal_lines',
    'accounts','performance_entries'] as $name){
    $definition=Schema::definitions()[$name]??throw new RuntimeException('Canonical '.$name.' missing');
    $pdo->exec('CREATE TABLE IF NOT EXISTS wp_eh7_'.$name.' ('.$definition.') ENGINE=InnoDB DEFAULT CHARSET=utf8mb4');
}
$GLOBALS['wpdb']=new class($pdo) {
    public string $prefix='wp_';public string $last_error='';
    public function __construct(private PDO $pdo){}
    public function prepare(string $sql,mixed ...$args):string {
        $i=0;$built=preg_replace_callback('/%[ds]/',function($m)use(&$i,$args){
            if(!array_key_exists($i,$args))throw new RuntimeException('SQL placeholder missing');
            $v=$args[$i++];
            return $m[0]==='%d'?(string)(int)$v:$this->pdo->quote((string)$v);
        },$sql);
        if($i!==count($args))throw new RuntimeException('Extra SQL bindings');
        return $built;
    }
    public function get_results(string $sql,mixed $type=null):array{
        return $this->pdo->query($sql)->fetchAll(PDO::FETCH_ASSOC);
    }
};
$pass=0;
$ok=static function(bool $yes,string $reason)use(&$pass):void{
    if(!$yes)throw new RuntimeException('FAIL: '.$reason);
    $pass++;echo 'PASS '.$reason."\n";
};
$company=8800;$branch=8801;$employee=8802;$cycle=880051;$request=880071;
$actor=new Actor(1,500,$company,$branch,[$branch],[Capabilities::ACCOUNTING_VIEW],'RM');
$run=static fn()=>DailyFieldStockAudit::inspect($actor,$cycle);
$insert=static function(string $table,array $fields)use($pdo):void{
    $names=array_keys($fields);
    $sql='INSERT INTO wp_eh7_'.$table.' ('.implode(',',$names).') VALUES ('.implode(',',array_fill(0,count($names),'?')).')';
    $pdo->prepare($sql)->execute(array_values($fields));
};
$pdo->beginTransaction();
try{
    $insert('daily_cycles',['id'=>$cycle,'company_id'=>$company,'branch_id'=>$branch,
        'employee_id'=>$employee,'business_date'=>'2026-10-20','status'=>'completed',
        'created_by'=>500,'created_at'=>'2026-10-20 03:00:00']);
    $insert('daily_requests',['id'=>$request,'daily_cycle_id'=>$cycle,'type'=>'initial',
        'status'=>'issued','requested_by'=>$employee,'approved_by'=>500,
        'issued_by'=>500,'created_at'=>'2026-10-20 03:01:00']);
    $insert('daily_issue_lines',['id'=>880091,'daily_request_id'=>$request,'product_id'=>8810,
        'batch_id'=>null,'quantity'=>'6.000']);
    $insert('evening_settlements',['id'=>880081,'daily_cycle_id'=>$cycle,'status'=>'posted',
        'expected_amount'=>'400.00','cash_amount'=>'150.00','upi_amount'=>'250.00',
        'created_at'=>'2026-10-20 12:00:00']);
    $insert('evening_lines',['id'=>880095,'evening_settlement_id'=>880081,'issue_line_id'=>880091,
        'product_id'=>8810,'batch_id'=>null,'issued_quantity'=>'6.000','return_quantity'=>'2.000',
        'retail_quantity'=>'3.000','wholesale_quantity'=>'1.000','total_amount'=>'400.00']);
    foreach([
        [880101,'daily_issue',$request,null,'OUT','6.000'],
        [880102,'daily_issue',$request,$employee,'IN','6.000'],
        [880103,'daily_sale',$cycle,$employee,'OUT','4.000'],
        [880104,'daily_return',$cycle,$employee,'OUT','2.000'],
        [880105,'daily_return',$cycle,null,'IN','2.000'],
    ] as [$id,$source,$sid,$cust,$direction,$qty]){
        $insert('stock_ledger',['id'=>$id,'company_id'=>$company,'branch_id'=>$branch,
            'product_id'=>8810,'batch_id'=>null,'custodian_employee_id'=>$cust,
            'source_type'=>$source,'source_id'=>$sid,'direction'=>$direction,
            'quantity'=>$qty,'created_by'=>500,'occurred_at'=>'2026-10-20 12:10:00']);
    }
    $insert('journal_entries',['id'=>880501,'company_id'=>$company,'branch_id'=>$branch,
        'entry_no'=>'DAILY-AUDIT-ROLLBACK-ONLY-880051','entry_date'=>'2026-10-20 23:59:59',
        'source_type'=>'daily_cycle','source_id'=>$cycle,'status'=>'posted',
        'created_by'=>500,'created_at'=>'2026-10-20 13:00:00']);
    foreach([
        [880301,'BR_CASH','asset','cash'],
        [880302,'BR_UPI','asset','upi'],
        [880303,'SALES','income',null],
        [880304,'COGS','expense',null],
        [880305,'INVENTORY','asset',null],
    ] as [$id,$code,$type,$subtype]){
        $insert('accounts',['id'=>$id,'company_id'=>$company,'code'=>$code,
            'name'=>'Synthetic '.$code,'type'=>$type,'subtype'=>$subtype,'active'=>1]);
    }
    foreach([
        [880401,880301,'150.00','0.00'],
        [880402,880302,'250.00','0.00'],
        [880403,880303,'0.00','400.00'],
        [880404,880304,'200.00','0.00'],
        [880405,880305,'0.00','200.00'],
    ] as [$lineId,$accountId,$debit,$credit]){
        $insert('journal_lines',['id'=>$lineId,'journal_entry_id'=>880501,
            'account_id'=>$accountId,'debit'=>$debit,'credit'=>$credit]);
    }
    $insert('performance_entries',['id'=>880502,'company_id'=>$company,'branch_id'=>$branch,
        'employee_id'=>$employee,'business_date'=>'2026-10-20','source_type'=>'daily_cycle',
        'source_id'=>$cycle,'points'=>'8.00','salary_fund'=>'12.00','created_at'=>'2026-10-20 13:00:00']);

    $r=$run();
    $ok($r['state']==='posted_stock_reconciled_financial_proof_pending'
        &&$r['stock_ledger_reconciled']===true
        &&$r['issued_milli']===6000&&$r['sold_milli']===4000&&$r['returned_milli']===2000
        &&$r['stock_movement_count']===5&&$r['journal_header_count']===1
        &&$r['ready_for_production_financial_signoff']===false
        &&$r['canonical_gl_line_totals_match']===true
        &&$r['journal_line_count']===5,

        'actual MariaDB canonical Daily Order issue 6, sold 4, return 2 and GL presence reconcile');
    $pdo->exec('SAVEPOINT badsale');
    $pdo->exec("UPDATE wp_eh7_stock_ledger SET quantity='4.001' WHERE id=880103");
    $r=$run();
    $ok($r['state']==='blocked_integrity_exception'
        &&in_array('stock_ledger_quantity_mismatch',$r['exceptions'],true),
        'actual tampered employee sale OUT is blocked');
    $pdo->exec('ROLLBACK TO SAVEPOINT badsale');
    $ok($run()['stock_ledger_reconciled']===true,'roll back ledger tamper and recover consistency');
    $pdo->exec('SAVEPOINT badreturn');
    $pdo->exec("UPDATE wp_eh7_stock_ledger SET branch_id=8809 WHERE id=880105");
    $ok(in_array('stock_ledger_quantity_mismatch',$run()['exceptions'],true),
        'cross-branch stock-return IN disappears from scoped ledger and blocks cycle');
    $pdo->exec('ROLLBACK TO SAVEPOINT badreturn');
    $pdo->exec('SAVEPOINT badclosing');
    $pdo->exec("UPDATE wp_eh7_evening_lines SET return_quantity='1.000' WHERE id=880095");
    $ok(in_array('closing_quantity_mismatch',$run()['exceptions'],true),
        'changed canonical closing quantity does not silently net against stock movements');
    $pdo->exec('ROLLBACK TO SAVEPOINT badclosing');
    $pdo->exec('SAVEPOINT wrongheader');
    $pdo->exec("UPDATE wp_eh7_journal_entries SET branch_id=8809 WHERE id=880501");
    $ok(in_array('canonical_journal_header_missing_or_duplicate',$run()['exceptions'],true),
        'cross-branch journal source does not count as valid daily cycle finance evidence');
    $pdo->exec('ROLLBACK TO SAVEPOINT wrongheader');
    $pdo->exec('SAVEPOINT corruptGL');
    $pdo->exec("UPDATE wp_eh7_journal_lines SET debit='149.00' WHERE id=880401");
    $r=$run();
    $ok(in_array('gl_cash_debit_mismatch',$r['exceptions'],true)
        &&in_array('gl_unbalanced',$r['exceptions'],true)
        &&$r['canonical_gl_line_totals_match']===false,
        'actual MariaDB tampered Cash journal debit fails stock + finance reconciliation');
    $pdo->exec('ROLLBACK TO SAVEPOINT corruptGL');
    $pdo->exec('SAVEPOINT corruptUPI');
    $pdo->exec("UPDATE wp_eh7_journal_lines SET debit='249.00' WHERE id=880402");
    $ok(in_array('gl_upi_debit_mismatch',$run()['exceptions'],true),
        'actual MariaDB UPI journal shortfall blocks GL reconciliation');
    $pdo->exec('ROLLBACK TO SAVEPOINT corruptUPI');
    $pdo->exec('SAVEPOINT corruptCOGS');
    $pdo->exec("UPDATE wp_eh7_journal_lines SET debit='199.00' WHERE id=880404");
    $ok(in_array('gl_cogs_inventory_mismatch',$run()['exceptions'],true),
        'actual MariaDB inventory and COGS imbalance blocks field cycle acceptance');
    $pdo->exec('ROLLBACK TO SAVEPOINT corruptCOGS');
    $ok($run()['canonical_gl_line_totals_match']===true,
        'rollback restores all canonical five-line GL amounts exactly');
    $pdo->exec('SAVEPOINT open');
    $pdo->exec("UPDATE wp_eh7_daily_cycles SET status='issued' WHERE id=880051");
    $pdo->exec("DELETE FROM wp_eh7_evening_lines WHERE id=880095");
    $pdo->exec("DELETE FROM wp_eh7_evening_settlements WHERE id=880081");
    $pdo->exec("DELETE FROM wp_eh7_journal_entries WHERE id=880501");
    $pdo->exec("DELETE FROM wp_eh7_performance_entries WHERE id=880502");
    $pdo->exec("DELETE FROM wp_eh7_stock_ledger WHERE id IN (880103,880104,880105)");
    $r=$run();
    $ok($r['state']==='open_cycle_not_finalized'
        &&$r['stock_ledger_reconciled']===true&&$r['ready_for_production_financial_signoff']===false,
        'real MariaDB issued cycle not falsely finalized even with correctly issued stock');
    $pdo->exec('ROLLBACK TO SAVEPOINT open');
    $ok($run()['stock_ledger_reconciled']===true,'transaction savepoint restores posted fixture after open-state test');
} finally {
    $pdo->rollBack();
}
$left=$pdo->query("SELECT COUNT(*) FROM wp_eh7_daily_cycles WHERE id=880051")->fetchColumn();
$ok((int)$left===0&&!$pdo->inTransaction(),'all synthetic field stock rows rolled back; no V7 posting retained');
echo "REAL MARIADB DAILY FIELD STOCK AUDIT: {$pass}/{$pass} PASS\n";
