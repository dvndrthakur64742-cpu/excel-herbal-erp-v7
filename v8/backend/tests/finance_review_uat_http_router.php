<?php
declare(strict_types=1);
/**
 * CI-only HTTP over real disposable MariaDB rows already seeded by
 * v7_canonical_real_mariadb.php. NOT a WordPress route or live API.
 * Only the synthetic, loopback host and database v8_test are permitted.
 */
header('Cache-Control: no-store, private');
header('X-Content-Type-Options: nosniff');
header('Content-Type: application/json; charset=utf-8');

$fail=static function(int $status,string $code):never {
    http_response_code($status);
    echo json_encode(['ok'=>false,'code'=>$code],JSON_THROW_ON_ERROR);
    exit;
};
if(($_SERVER['REMOTE_ADDR']??'')!=='127.0.0.1'
    ||($_SERVER['SERVER_ADDR']??'')!=='127.0.0.1'
    ||getenv('V8_FINANCE_HTTP_CI_ONLY')!=='1'
    ||!getenv('V8_TEST_DSN')) $fail(403,'outside_disposable_ci');

if(!defined('ARRAY_A'))define('ARRAY_A','ARRAY_A');
foreach(['EH8_ALLOW_V7_B2B_UAT_POSTING','EH8_B2B_TAX_POLICY_APPROVED',
    'EH8_B2B_REVERSAL_POLICY_APPROVED','EH8_B2B_TRUSTED_TENDER_APPROVED'] as $flag)
    if(!defined($flag))define($flag,true);
function wp_get_environment_type():string{return 'development';}
function current_time(string $format,bool $gmt=false):string{
    $t=new DateTimeImmutable('2026-10-19 15:30:00',new DateTimeZone('Asia/Kolkata'));
    return ($gmt?$t->setTimezone(new DateTimeZone('UTC')):$t)->format($format==='mysql'?'Y-m-d H:i:s':$format);
}

final class ReadOnlyFinanceUatWpdb {
    public string $prefix='wp_';
    public string $last_error='';
    public function __construct(private PDO $pdo){}
    public function prepare(string $sql,mixed ...$args):string{
        if(count($args)===1&&is_array($args[0]))$args=$args[0];
        $at=0;
        $query=preg_replace_callback('/%(?:d|s|f)/',
            function(array $m)use(&$at,$args):string{
                if(!array_key_exists($at,$args))throw new RuntimeException('SQL placeholder underflow');
                $v=$args[$at++];
                return match($m[0]){
                    '%d'=>(string)(int)$v,
                    '%f'=>(string)(float)$v,
                    '%s'=>$v===null?'NULL':$this->pdo->quote((string)$v),
                };
            },$sql);
        if($at!==count($args))throw new RuntimeException('SQL placeholder overflow');
        return (string)$query;
    }
    private function select(string $query):PDOStatement{
        if(!preg_match('/^\s*SELECT\b/i',$query))
            throw new RuntimeException('No financial SQL mutations over UAT HTTP');
        return $this->pdo->query($query);
    }
    public function get_var(string $sql):mixed {
        $this->last_error='';
        try{return $this->select($sql)->fetchColumn();}
        catch(Throwable $e){$this->last_error=$e->getMessage();return null;}
    }
    public function get_row(string $sql,mixed $mode=null):?array{
        $this->last_error='';
        try{$row=$this->select($sql)->fetch(PDO::FETCH_ASSOC);return $row===false?null:$row;}
        catch(Throwable $e){$this->last_error=$e->getMessage();return null;}
    }
    public function get_results(string $sql,mixed $mode=null):array{
        $this->last_error='';
        try{return $this->select($sql)->fetchAll(PDO::FETCH_ASSOC);}
        catch(Throwable $e){$this->last_error=$e->getMessage();return [];}
    }
}
try{
    $pdo=new PDO((string)getenv('V8_TEST_DSN'),
        (string)getenv('V8_TEST_USER'),(string)getenv('V8_TEST_PASSWORD'),
        [PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,
         PDO::ATTR_DEFAULT_FETCH_MODE=>PDO::FETCH_ASSOC]);
    if($pdo->query('SELECT DATABASE()')->fetchColumn()!=='v8_test')
        $fail(403,'not_disposable_database');
    $GLOBALS['wpdb']=new ReadOnlyFinanceUatWpdb($pdo);
    $base=dirname(__DIR__,3);
    $root=$base.'/backend/excel-herbal-erp-v7/src/';
    spl_autoload_register(static function(string $name)use($root):void{
        $prefix='ExcelHerbal\ERP7\\';
        if(!str_starts_with($name,$prefix))return;
        $file=$root.str_replace('\\','/',substr($name,strlen($prefix))).'.php';
        if(is_file($file))require_once $file;
    });
    require_once $root.'Organization/Employee360Service.php';
    require_once $root.'Organization/EmployeeCashControl.php';
    $dir=dirname(__DIR__).'/src/B2B/';
    foreach([
        'RetailerCashSale.php','V7CanonicalPostingSinkUat.php',
        'V7CanonicalCashHandoverUat.php','V7B2BCrossLedgerAuditUat.php',
        'V7EmployeeCrossSourceCashAuditUat.php',
        'V7FinanceReviewReadEndpointUat.php',
    ] as $file)require_once $dir.$file;
    $uri=parse_url($_SERVER['REQUEST_URI']??'',PHP_URL_PATH);
    if($uri!=='/ci-only/v8/finance/employee-cash-evidence')
        $fail(404,'no_such_ci_route');
    // The token map belongs only to loopback UAT and is never a production
    // authentication provider. Real WordPress bearer validation is separate.
    $tokens=[
        'Bearer synthetic-finance'=>new \ExcelHerbal\ERP7\Security\Actor(
            8010,9010,987665531,4001,[4001],[
              \ExcelHerbal\ERP7\Security\Capabilities::ACCOUNTING_VIEW,
              \ExcelHerbal\ERP7\Security\Capabilities::EMP_VIEW],'RM'),
        'Bearer synthetic-accounting-only'=>new \ExcelHerbal\ERP7\Security\Actor(
            8010,9010,987665531,4001,[4001],[
              \ExcelHerbal\ERP7\Security\Capabilities::ACCOUNTING_VIEW],'RM'),
        'Bearer synthetic-field'=>new \ExcelHerbal\ERP7\Security\Actor(
            8001,9001,987665531,4001,[4001],[
              \ExcelHerbal\ERP7\Security\Capabilities::DAILY_SELF],'FSE'),
        'Bearer synthetic-branch-2'=>new \ExcelHerbal\ERP7\Security\Actor(
            8040,9040,987665531,4002,[4002],[
              \ExcelHerbal\ERP7\Security\Capabilities::ACCOUNTING_VIEW,
              \ExcelHerbal\ERP7\Security\Capabilities::EMP_VIEW],'RM'),
        'Bearer synthetic-other-company'=>new \ExcelHerbal\ERP7\Security\Actor(
            8050,9050,987665532,4001,[4001],[
              \ExcelHerbal\ERP7\Security\Capabilities::ACCOUNTING_VIEW,
              \ExcelHerbal\ERP7\Security\Capabilities::EMP_VIEW],'RM'),
    ];
    $authorization=$_SERVER['HTTP_AUTHORIZATION']??'';
    if(!isset($tokens[$authorization]))$fail(401,'not_authenticated');
    $authority=static fn($action,$who,$company,$branch,$target)=>
        $action==='employee.cash.cross_source.view'
        &&$who===8010&&$company===987665531
        &&$branch===4001&&$target===9001;
    $result=\ExcelHerbal\ERP8\B2B\V7FinanceReviewReadEndpointUat::get(
        $tokens[$authorization],(string)($_SERVER['REQUEST_METHOD']??''),
        $_GET,$authority);
    http_response_code(200);
    echo json_encode($result,JSON_THROW_ON_ERROR);
}catch(\ExcelHerbal\ERP7\Domain\DomainException $e){
    $fail(403,'finance_permission_denied');
}catch(Throwable $e){
    // No SQL, stack trace, personal data, financial proof or auth context in
    // error output. These failures are expected negative-role UAT outcomes.
    $fail(422,'finance_evidence_not_authorized_or_invalid');
}
