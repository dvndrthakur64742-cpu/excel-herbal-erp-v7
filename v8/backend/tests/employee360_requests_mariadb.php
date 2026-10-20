<?php
declare(strict_types=1);

/**
 * Disposable integration test of actual V7 Daily Order schema and Employee 360
 * request/issue projection. NO WordPress deployment or live writes.
 */
$dsn=getenv('V8_TEST_DSN');
if (!$dsn) { fwrite(STDOUT,"SKIP Employee 360 stock requests: V8_TEST_DSN absent\n");exit(0); }
if (!in_array('mysql',PDO::getAvailableDrivers(),true)) {
    fwrite(STDERR,"pdo_mysql needed for real MariaDB verification\n");exit(2);
}
try {
    $db=new PDO($dsn,getenv('V8_TEST_USER')?:'v8',getenv('V8_TEST_PASSWORD')?:'v8',[
        PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE=>PDO::FETCH_ASSOC,
    ]);
    if ($db->query('SELECT DATABASE()')->fetchColumn()!=='v8_test')
        throw new RuntimeException('Refuse Employee 360 test outside disposable v8_test');
    $root=dirname(__DIR__,3);
    $src=$root.'/backend/excel-herbal-erp-v7/src/';
    require_once $src.'Database/Schema.php';
    require_once $src.'Database/Db.php';
    require_once $src.'Organization/Employee360Registers.php';
    if (!defined('ARRAY_A')) define('ARRAY_A','ARRAY_A');
    $defs=\ExcelHerbal\ERP7\Database\Schema::definitions();
    foreach (['daily_cycles','daily_requests','daily_request_lines','daily_issue_lines'] as $table) {
        if (!isset($defs[$table])) throw new RuntimeException('Missing canonical V7 table '.$table);
        $db->exec('CREATE TABLE IF NOT EXISTS wp_eh7_'.$table.' ('.$defs[$table].') ENGINE=InnoDB DEFAULT CHARSET=utf8mb4');
    }
    // Bound wpdb adapter executes real SQL against the SAME PDO MariaDB connection.
    $GLOBALS['wpdb']=new class($db) {
        public string $prefix='wp_';
        public function __construct(private PDO $db){}
        public function prepare(string $sql,mixed ...$args):string {
            if (count($args)===1 && is_array($args[0]))$args=$args[0];
            $n=0;
            $query=preg_replace_callback('/%[ds]/',function($m)use(&$n,$args){
                if(!array_key_exists($n,$args))throw new RuntimeException('Missing SQL binding');
                $value=$args[$n++];
                return $m[0]==='%d'?(string)(int)$value:$this->db->quote((string)$value);
            },$sql);
            if($n!==count($args))throw new RuntimeException('Unexpected SQL binding');
            return (string)$query;
        }
        public function get_results(string $sql,mixed $type=null):array {
            return $this->db->query($sql)->fetchAll(PDO::FETCH_ASSOC);
        }
    };
    $checks=0;
    $assert=static function(bool $valid,string $message)use(&$checks):void{
        if(!$valid)throw new RuntimeException('FAIL '.$message);
        $checks++;echo "PASS {$message}\n";
    };
    $company=987669811;$otherCompany=987669812;$employee=900091;
    $branch=601;$otherBranch=602;
    $db->beginTransaction();
    try {
        $cycle=static function(int $co,int $branchId,int $employeeId,string $date)use($db):int {
            $q=$db->prepare("INSERT INTO wp_eh7_daily_cycles(company_id,branch_id,employee_id,business_date,status,created_by,created_at) VALUES(?,?,?,?,'issued',?,'2026-10-20 03:00:00')");
            $q->execute([$co,$branchId,$employeeId,$date,$employeeId]);
            return (int)$db->lastInsertId();
        };
        $request=static function(int $cycleId,string $type,string $status,int $by)use($db):int {
            $q=$db->prepare("INSERT INTO wp_eh7_daily_requests(daily_cycle_id,type,status,requested_by,approved_by,issued_by,created_at,approved_at,issued_at) VALUES(?,?,?,?,?,?, '2026-10-20 03:00:00',NULL,NULL)");
            $q->execute([$cycleId,$type,$status,$by,$status==='issued'?777:null,$status==='issued'?888:null]);
            return (int)$db->lastInsertId();
        };
        $line=static function(string $table,int $requestId,int $product,int $quantity,?int $batch=null)use($db):void {
            $q=$db->prepare("INSERT INTO {$table}(daily_request_id,product_id,batch_id,quantity) VALUES(?,?,?,?)");
            if($table==='wp_eh7_daily_issue_lines') {
                // Canonical schema requires immutable commercial snapshots.
                $q=$db->prepare("INSERT INTO {$table}(daily_request_id,product_id,batch_id,quantity) VALUES(?,?,?,?)");
            }
            $q->execute([$requestId,$product,$batch,$quantity]);
        };
        $first=$cycle($company,$branch,$employee,'2026-10-20');
        $issued=$request($first,'initial','issued',$employee);
        $line('wp_eh7_daily_request_lines',$issued,11,3);
        $line('wp_eh7_daily_request_lines',$issued,12,2);
        $line('wp_eh7_daily_issue_lines',$issued,11,1,201);
        $line('wp_eh7_daily_issue_lines',$issued,11,2,202);
        $line('wp_eh7_daily_issue_lines',$issued,12,2);
        $pending=$request($first,'additional','submitted',$employee);
        $line('wp_eh7_daily_request_lines',$pending,11,4);
        $elsewhere=$cycle($company,$otherBranch,$employee,'2026-10-19');
        $elsewhereRequest=$request($elsewhere,'initial','approved',$employee);
        $line('wp_eh7_daily_request_lines',$elsewhereRequest,11,8);
        $alien=$cycle($otherCompany,$branch,$employee,'2026-10-20');
        $alienRequest=$request($alien,'initial','approved',$employee);
        $line('wp_eh7_daily_request_lines',$alienRequest,11,9);
        $other=$cycle($company,$branch,$employee+1,'2026-10-20');
        $otherRequest=$request($other,'initial','approved',$employee+1);
        $line('wp_eh7_daily_request_lines',$otherRequest,11,10);
        $reader=new \ExcelHerbal\ERP7\Organization\Employee360WpRegisterReader();
        $branchRows=$reader->requests($company,$employee,'2026-10-01','2026-10-20',[$branch],25,0);
        $assert(count($branchRows)===2,'manager sees exactly two original same-branch requests');
        $byId=[];foreach($branchRows as $row)$byId[(int)$row['request_id']]=$row;
        $a=$byId[$issued]??[];
        $assert((float)($a['requested_quantity']??0)===5.0,'requested quantities aggregate by request without duplicate join');
        $assert((float)($a['issued_quantity']??0)===5.0,'actual three issued batch lines sum exactly once');
        $assert((int)($a['requested_line_count']??0)===2 && (int)($a['issued_line_count']??0)===3,'requested and actual issue counts remain distinct');
        $assert(($a['request_status']??null)==='issued' && (int)($a['approved_by']??0)===777 && (int)($a['issued_by']??0)===888,'canonical reviewer and issuer evidence retained');
        $b=$byId[$pending]??[];
        $assert(($b['request_status']??null)==='submitted' && (float)($b['requested_quantity']??0)===4.0 && (float)($b['issued_quantity']??-1)===0.0,'unissued request never shown as issued stock');
        $assert(!array_key_exists('purchase_cost_snapshot',$a)&&!array_key_exists('sale_price_snapshot',$a),'employee request history contains no product or cost prices');
        $all=$reader->requests($company,$employee,'2026-10-01','2026-10-20',[],25,0);
        $assert(count($all)===3,'employee self-history includes prior authorized branch records but no other company');
        $assert((int)$all[0]['request_id']===$pending && (int)$all[1]['request_id']===$issued,'same-day multiple requests ordered consistently by request ID');
        $page=$reader->requests($company,$employee,'2026-10-01','2026-10-20',[$branch],1,1);
        $assert(count($page)===1 && (int)$page[0]['request_id']===$issued,'MariaDB LIMIT and OFFSET paginate historical requests correctly');
        echo "EMPLOYEE 360 STOCK REQUEST HISTORY REAL MARIADB: {$checks}/{$checks} PASS; v8_test only\n";
    } finally {
        if($db->inTransaction())$db->rollBack();
    }
} catch(Throwable $e) {
    fwrite(STDERR,'EMPLOYEE REQUEST MARIADB FAILED: '.$e::class.' '.$e->getMessage()." at ".$e->getFile().':'.$e->getLine()."\n");
    exit(1);
}
