<?php
/** Run: php tests/regression.php (PHP 8.1+). No production database required. */
require_once __DIR__.'/../src/Core/Autoloader.php';
\ExcelHerbal\ERP7\Core\Autoloader::register(__DIR__.'/../src');
use ExcelHerbal\ERP7\Payroll\PayrollCalculator;
use ExcelHerbal\ERP7\Domain\DomainException;

$cases=json_decode(file_get_contents(__DIR__.'/payroll-fixtures.json'),true,512,JSON_THROW_ON_ERROR);$failed=0;
foreach($cases as$c){
    try{$result=PayrollCalculator::calculate($c['input']);
        if(isset($c['error']))throw new \RuntimeException('Expected error '.$c['error']);
        foreach($c['expected'] as$k=>$v)if(abs($result[$k]-$v)>0.00001)throw new \RuntimeException($k.': expected '.$v.' got '.$result[$k]);
        echo 'PASS '.$c['name'].PHP_EOL;
    }catch(DomainException $e){if(($c['error']??null)===$e->codeKey)echo 'PASS '.$c['name'].PHP_EOL;else{$failed++;echo 'FAIL '.$c['name'].': '.$e->codeKey.PHP_EOL;}}
    catch(\Throwable $e){$failed++;echo 'FAIL '.$c['name'].': '.$e->getMessage().PHP_EOL;}
}
// Exercise actual approval/overlap guards with controlled database responses.
define('ARRAY_A','ARRAY_A');
function current_time($format,$gmt=false){return $format==='Y-m-d'?'2026-09-30':'2026-09-30 12:00:00';}
if(!function_exists('wp_json_encode')){function wp_json_encode($value,$flags=0){return json_encode($value,$flags);}}
final class GuardDb {
    public string $prefix='wp_';public string $last_error='';public string $scenario='';
    public function prepare($q,...$args){return $q;}
    public function query($q){return 1;}
    public function get_var($q){
        if(str_contains($q,'companies'))return 1;
        if(str_contains($q,'payroll_editors'))return 99;
        if(str_contains($q,'payroll_runs'))return 8;
        return null;
    }
    public function get_results($q,$mode){return [['id'=>1,'monthly_salary'=>30000,'employee_code'=>'E1']];}
    public function get_row($q,$mode){return ['id'=>8,'company_id'=>1,'branch_id'=>1,'status'=>'draft','created_by'=>2,'period_end'=>'2026-09-30','calculation_version'=>$this->scenario==='legacy'?null:'7.3.5'];}
}
$wpdb=new GuardDb();
$actor=new \ExcelHerbal\ERP7\Security\Actor(10,10,1,1,[1],[\ExcelHerbal\ERP7\Security\Capabilities::PAYROLL_APPROVE,\ExcelHerbal\ERP7\Security\Capabilities::PAYROLL_GENERATE],'BM');
$guardCases=[
 ['editor','maker_checker_required',fn()=>\ExcelHerbal\ERP7\Payroll\PayrollPerformanceService::approvePayroll($actor,8)],
 ['legacy','payroll_legacy_draft',fn()=>\ExcelHerbal\ERP7\Payroll\PayrollPerformanceService::approvePayroll($actor,8)],
 ['overlap','payroll_period_overlap',fn()=>\ExcelHerbal\ERP7\Payroll\PayrollPerformanceService::generate($actor,1,'2026-09-15','2026-09-30')],
];
foreach($guardCases as[$name,$error,$fn]){$wpdb->scenario=$name;try{$fn();$failed++;echo "FAIL {$name}: expected rejection\n";}catch(DomainException $e){if($e->codeKey===$error)echo "PASS {$name}\n";else{$failed++;echo "FAIL {$name}: {$e->codeKey}\n";}}}

// Exercise transaction/savepoint and payload-bound idempotency primitives.
final class TransactionDb {
    public string $prefix='wp_';public string $last_error='';public array $queries=[];
    public function query($q){$this->queries[]=$q;return 1;}
}
$wpdb=new TransactionDb();
try{
    $result=\ExcelHerbal\ERP7\Database\Transaction::run(fn()=>42);
    if($result!==42||$wpdb->queries!==['START TRANSACTION','COMMIT'])throw new \RuntimeException('unexpected query sequence');
    echo "PASS transaction_commit\n";
}catch(\Throwable $e){$failed++;echo "FAIL transaction_commit: {$e->getMessage()}\n";}

$wpdb=new TransactionDb();
try{
    \ExcelHerbal\ERP7\Database\Transaction::run(function(){throw new \RuntimeException('rollback probe');});
    $failed++;echo "FAIL transaction_rollback: expected exception\n";
}catch(\RuntimeException $e){
    if($e->getMessage()==='rollback probe'&&$wpdb->queries===['START TRANSACTION','ROLLBACK'])echo "PASS transaction_rollback\n";
    else{$failed++;echo "FAIL transaction_rollback: wrong rollback sequence\n";}
}

$wpdb=new TransactionDb();
try{
    $result=\ExcelHerbal\ERP7\Database\Transaction::run(function(){
        try{\ExcelHerbal\ERP7\Database\Transaction::run(function(){throw new \RuntimeException('nested rollback probe');});}
        catch(\RuntimeException $e){if($e->getMessage()!=='nested rollback probe')throw $e;}
        return 'outer-ok';
    });
    $expected=['START TRANSACTION','SAVEPOINT eh7_sp_1','ROLLBACK TO SAVEPOINT eh7_sp_1','COMMIT'];
    if($result!=='outer-ok'||$wpdb->queries!==$expected)throw new \RuntimeException('unexpected savepoint sequence');
    echo "PASS transaction_savepoint_rollback\n";
}catch(\Throwable $e){$failed++;echo "FAIL transaction_savepoint_rollback: {$e->getMessage()}\n";}

final class IdempotencyDb {
    public string $prefix='wp_';public string $last_error='';public array $queries=[];public ?array $existing=null;public ?array $inserted=null;public ?array $updated=null;
    public function query($q){$this->queries[]=$q;return 1;}
    public function prepare($q,...$args){return $q;}
    public function get_row($q,$mode){return $this->existing;}
    public function insert($table,$data){$this->inserted=$data;return 1;}
    public function update($table,$data,$where){$this->updated=$data;return 1;}
}
$idActor=new \ExcelHerbal\ERP7\Security\Actor(10,10,1,1,[1],[],'BM');
$payload=['b'=>2,'a'=>1];
$payloadHash=hash('sha256',(string)json_encode(['a'=>1,'b'=>2],JSON_UNESCAPED_SLASHES|JSON_UNESCAPED_UNICODE));

$wpdb=new IdempotencyDb();
$wpdb->existing=['payload_hash'=>$payloadHash,'status'=>'complete','response_json'=>json_encode(['cached'=>true])];
$called=0;
try{
    $out=\ExcelHerbal\ERP7\Security\Idempotency::run($idActor,'replay-key','probe',function()use(&$called){$called++;return['cached'=>false];},$payload);
    if($out!==['cached'=>true]||$called!==0)throw new \RuntimeException('completed request was re-executed');
    echo "PASS idempotency_replay_cache\n";
}catch(\Throwable $e){$failed++;echo "FAIL idempotency_replay_cache: {$e->getMessage()}\n";}

$wpdb=new IdempotencyDb();
$wpdb->existing=['payload_hash'=>hash('sha256','different'),'status'=>'complete','response_json'=>'{}'];
try{
    \ExcelHerbal\ERP7\Security\Idempotency::run($idActor,'mismatch-key','probe',fn()=>['unexpected'=>true],$payload);
    $failed++;echo "FAIL idempotency_payload_mismatch: expected rejection\n";
}catch(DomainException $e){
    if($e->codeKey==='idempotency_payload_mismatch')echo "PASS idempotency_payload_mismatch\n";
    else{$failed++;echo "FAIL idempotency_payload_mismatch: {$e->codeKey}\n";}
}

$wpdb=new IdempotencyDb();
try{
    $out=\ExcelHerbal\ERP7\Security\Idempotency::run($idActor,'new-key','probe',fn()=>['saved'=>1],$payload);
    $response=$wpdb->updated?json_decode((string)($wpdb->updated['response_json']??''),true):null;
    if($out!==['saved'=>1]||($wpdb->inserted['status']??null)!=='in_progress'||($wpdb->updated['status']??null)!=='complete'||$response!==['saved'=>1]){
        throw new \RuntimeException('idempotent response was not persisted');
    }
    echo "PASS idempotency_persist_response\n";
}catch(\Throwable $e){$failed++;echo "FAIL idempotency_persist_response: {$e->getMessage()}\n";}


// Verify bearer header compatibility across common FastCGI/proxy server variables.
try{
    $headerMethod=new \ReflectionMethod(\ExcelHerbal\ERP7\Security\MobileAuth::class,'authorizationHeader');
    $headerMethod->setAccessible(true);
    $serverBackup=$_SERVER;
    $headerCases=[
        ['HTTP_AUTHORIZATION','Bearer primary-token','auth_header_http_authorization'],
        ['REDIRECT_HTTP_AUTHORIZATION','Bearer redirect-token','auth_header_redirect_authorization'],
        ['Authorization','Bearer direct-token','auth_header_direct_authorization'],
    ];
    foreach($headerCases as[$key,$value,$name]){
        unset($_SERVER['HTTP_AUTHORIZATION'],$_SERVER['REDIRECT_HTTP_AUTHORIZATION'],$_SERVER['Authorization']);
        $_SERVER[$key]=$value;
        $actual=$headerMethod->invoke(null);
        if($actual!==$value){$failed++;echo "FAIL {$name}: header fallback mismatch\n";}else echo "PASS {$name}\n";
    }
    $_SERVER=$serverBackup;
}catch(\Throwable $e){$failed++;echo "FAIL auth_header_fallbacks: {$e->getMessage()}\n";}

echo ($failed?'FAILED':'PASSED').' regression suite'.PHP_EOL;exit($failed?1:0);
