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


// Verify read-only branch-scoped routes default to the actor's assigned branch.
try{
    $branchMethod=new \ReflectionMethod(\ExcelHerbal\ERP7\Http\ApiDispatch::class,'readBranch');
    $branchMethod->setAccessible(true);
    $branchActor=new \ExcelHerbal\ERP7\Security\Actor(10,10,1,9,[9,13],[],'BM');
    $missingBranchRequest=new class {
        public function get_param($key){return null;}
    };
    $explicitBranchRequest=new class {
        public function get_param($key){return $key==='branch_id'?13:null;}
    };
    $zeroBranchRequest=new class {
        public function get_param($key){return $key==='branch_id'?0:null;}
    };
    if($branchMethod->invoke(null,$missingBranchRequest,$branchActor)!==9)throw new \RuntimeException('missing branch did not default to actor branch');
    if($branchMethod->invoke(null,$explicitBranchRequest,$branchActor)!==13)throw new \RuntimeException('explicit branch was changed');
    if($branchMethod->invoke(null,$zeroBranchRequest,$branchActor)!==0)throw new \RuntimeException('explicit zero branch was silently rewritten');
    echo "PASS read_branch_default\n";
}catch(\Throwable $e){$failed++;echo "FAIL read_branch_default: {$e->getMessage()}\n";}

// FIN-01: exercise actual statement import service.
final class BankImportRegressionDb {
    public string $prefix='wp_';
    public string $last_error='';
    public array $rows=[];
    public array $queries=[];
    private array $params=[];
    public function prepare($q,...$args){$this->params=$args;return $q;}
    public function get_var($q){
        [$id,$date,$reference,$debit,$credit]=$this->params;
        foreach($this->rows as $r){
            if($r['reconciliation_id']===$id&&$r['txn_date']===$date&&trim($r['reference'])===$reference&&(float)$r['debit']===(float)$debit&&(float)$r['credit']===(float)$credit)return 1;
        }
        return null;
    }
    public function get_row($q,$mode){return ['id'=>1,'company_id'=>1,'branch_id'=>1,'status'=>'draft','statement_from'=>'2026-09-01','statement_to'=>'2026-09-30'];}
    public function query($q){$this->queries[]=$q;if($q==='ROLLBACK')$this->rows=[];return 1;}
    public function insert($table,$data){$this->rows[]=$data;return 1;}
}
$bankActor=new \ExcelHerbal\ERP7\Security\Actor(10,10,1,1,[1],[\ExcelHerbal\ERP7\Security\Capabilities::BANK_RECONCILE],'BM');
foreach([
    ['valid debit','25.50',0,true],
    ['valid credit',0,25.5,true],
    ['one paisa',0.01,0,true],
    ['negative debit',-10,100,false],
    ['negative credit',100,-10,false],
    ['negative sub-cent',-0.001,100,false],
    ['invalid numeric text','bad',100,false],
    ['nonfinite',INF,0,false],
    ['boolean',true,0,false],
    ['sub-cent',1.001,0,false],
    ['overflow',1000000000000,0,false],
    ['both positive',100,100,false],
    ['both zero',0,0,false],
] as [$name,$debit,$credit,$valid]){
    $wpdb=new BankImportRegressionDb();
    try{
        $result=\ExcelHerbal\ERP7\Finance\FinanceBankService::bankImport($bankActor,1,[['txn_date'=>'2026-09-08','debit'=>$debit,'credit'=>$credit]]);
        if(!$valid||$result['imported']!==1||count($wpdb->rows)!==1)throw new \RuntimeException('unexpected acceptance');
        echo "PASS bank import {$name}\n";
    }catch(DomainException $e){
        if(!$valid&&$e->codeKey==='bank_statement_amount_invalid'&&$wpdb->rows===[]&&in_array('ROLLBACK',$wpdb->queries,true))echo "PASS bank import {$name}\n";
        else{$failed++;echo "FAIL bank import {$name}: {$e->codeKey}\n";}
    }catch(\Throwable $e){$failed++;echo "FAIL bank import {$name}: {$e->getMessage()}\n";}
}
$wpdb=new BankImportRegressionDb();
try{
    \ExcelHerbal\ERP7\Finance\FinanceBankService::bankImport($bankActor,1,[['txn_date'=>'2026-09-08','debit'=>10,'credit'=>0],['txn_date'=>'2026-09-08','debit'=>-10,'credit'=>100]]);
    $failed++;echo "FAIL bank import mixed batch accepted\n";
}catch(DomainException $e){
    if($e->codeKey==='bank_statement_amount_invalid'&&$wpdb->rows===[]&&in_array('ROLLBACK',$wpdb->queries,true))echo "PASS bank import mixed batch rollback\n";
    else{$failed++;echo "FAIL bank import mixed batch rollback\n";}
}
// FIN-02: a repeated bank reference/date/direction/amount is a duplicate
// candidate, while matching amounts alone are not sufficient evidence.
$bankLine=['txn_date'=>'2026-09-08','reference'=>'BANK-001','debit'=>100,'credit'=>0];
foreach([
    ['same referenced transaction',[$bankLine,$bankLine],false],
    ['reference whitespace',[$bankLine,array_replace($bankLine,['reference'=>' BANK-001 '])],false],
    ['distinct references',[$bankLine,array_replace($bankLine,['reference'=>'BANK-002'])],true],
    ['distinct dates',[$bankLine,array_replace($bankLine,['txn_date'=>'2026-09-09'])],true],
    ['distinct amounts',[$bankLine,array_replace($bankLine,['debit'=>200])],true],
    ['distinct directions',[$bankLine,array_replace($bankLine,['debit'=>0,'credit'=>100])],true],
    ['missing references',[array_replace($bankLine,['reference'=>'']),array_replace($bankLine,['reference'=>''])],true],
] as [$name,$lines,$valid]){
    $wpdb=new BankImportRegressionDb();
    try{
        $result=\ExcelHerbal\ERP7\Finance\FinanceBankService::bankImport($bankActor,1,$lines);
        if(!$valid||$result['imported']!==2||count($wpdb->rows)!==2)throw new \RuntimeException('unexpected acceptance');
        echo "PASS bank duplicate {$name}\n";
    }catch(DomainException $e){
        if(!$valid&&$e->codeKey==='bank_statement_duplicate_candidate'&&$wpdb->rows===[]&&in_array('ROLLBACK',$wpdb->queries,true))echo "PASS bank duplicate {$name}\n";
        else{$failed++;echo "FAIL bank duplicate {$name}: {$e->codeKey}\n";}
    }catch(\Throwable $e){$failed++;echo "FAIL bank duplicate {$name}: {$e->getMessage()}\n";}
}
// FIN-05: a stale snapshot must not allow posting into a newly closed period.
final class PeriodPostingRegressionDb {
    public string $prefix='wp_';
    public string $last_error='';
    public array $queries=[];
    public int $insert_id=0;
    public string $scenario='';
    public function prepare($q,...$args){return $q;}
    public function query($q){$this->queries[]=$q;return 1;}
    public function get_row($q,$mode){return ['id'=>1,'type'=>'asset','active'=>1];}
    public function get_var($q){
        $this->queries[]=$q;
        if(str_contains($q,'eh7_companies')){
            if($this->scenario==='company lock failure'){$this->last_error='synthetic lock failure';return null;}
            return 1;
        }
        if(str_contains($q,'eh7_accounting_periods')){
            if(str_contains($q,'LOCK IN SHARE MODE')||str_contains($q,'FOR UPDATE')){
                if($this->scenario==='period query failure'){$this->last_error='synthetic read failure';return null;}
                return 8;
            }
            return null;
        }
        return 1;
    }
    public function insert($table,$data){throw new \RuntimeException('Unexpected write');}
}
foreach([
    ['closed period after stale read','accounting_period_closed'],
    ['company lock failure','period_lock_failed'],
    ['period query failure','period_read_failed'],
] as [$name,$expected]){
    $wpdb=new PeriodPostingRegressionDb();
    $wpdb->scenario=$name;
    try{
        \ExcelHerbal\ERP7\Finance\AccountingService::post($bankActor,1,'counter_sale',1,'2026-09-08 12:00:00',[
            ['account_id'=>1,'debit'=>100],['account_id'=>2,'credit'=>100]
        ]);
        $failed++;echo "FAIL period gate {$name}: posting accepted\n";
    }catch(DomainException $e){
        if($e->codeKey===$expected&&in_array('ROLLBACK',$wpdb->queries,true))echo "PASS period gate {$name}\n";
        else{$failed++;echo "FAIL period gate {$name}: {$e->codeKey}\n";}
    }catch(\Throwable $e){$failed++;echo "FAIL period gate {$name}: {$e->getMessage()}\n";}
}
// FIN-04: branch close must be enforced in the central journal writer.
final class BranchPostingRegressionDb {
    public string $prefix='wp_';
    public string $last_error='';
    public array $queries=[];
    public string $scenario='';
    public function prepare($q,...$args){return $q;}
    public function query($q){$this->queries[]=$q;return 1;}
    public function get_row($q,$mode){return ['id'=>1,'type'=>'asset','active'=>1];}
    public function get_var($q){
        $this->queries[]=$q;
        if(str_contains($q,'eh7_accounting_periods'))return null;
        if(str_contains($q,'eh7_branches')){
            if($this->scenario==='branch lock failure'){$this->last_error='synthetic lock failure';return null;}
            return 1;
        }
        if(str_contains($q,'eh7_branch_closings')){
            if($this->scenario==='branch read failure'){$this->last_error='synthetic read failure';return null;}
            return str_contains($q,'LOCK IN SHARE MODE')?'closed':null;
        }
        return 1;
    }
}
foreach([
    ['closed branch after stale read','branch_day_closed'],
    ['branch lock failure','branch_day_lock_failed'],
    ['branch read failure','branch_day_read_failed'],
] as [$name,$expected]){
    $wpdb=new BranchPostingRegressionDb();$wpdb->scenario=$name;
    try{
        \ExcelHerbal\ERP7\Finance\AccountingService::post($bankActor,1,'counter_sale',1,'2026-09-08 12:00:00',[
            ['account_id'=>1,'debit'=>100],['account_id'=>2,'credit'=>100]
        ]);
        $failed++;echo "FAIL branch journal gate {$name}: posting accepted\n";
    }catch(DomainException $e){
        if($e->codeKey===$expected&&in_array('ROLLBACK',$wpdb->queries,true))echo "PASS branch journal gate {$name}\n";
        else{$failed++;echo "FAIL branch journal gate {$name}: {$e->codeKey}\n";}
    }catch(\Throwable $e){$failed++;echo "FAIL branch journal gate {$name}: {$e->getMessage()}\n";}
}
// A failed preflight read must never be interpreted as zero blockers.
final class ClosingReadRegressionDb {
    public string $prefix='wp_';
    public string $last_error='';
    public string $failure='';
    public int $insert_id=9;
    public array $writes=[];
    public array $queries=[];
    public function prepare($q,...$args){return $q;}
    public function query($q){$this->queries[]=$q;return 1;}
    public function get_col($q){return [1];}
    public function get_row($q,$mode){return null;}
    public function get_var($q){
        $this->last_error='';
        if(str_contains($q,'eh7_companies'))return 1;
        if(str_contains($q,'eh7_accounting_periods'))return null;
        if(str_contains($q,'COUNT(*)')&&str_contains($q,$this->failure)){
            $this->last_error='synthetic failed blocker query';return null;
        }
        return 0;
    }
    public function get_results($q,$mode){
        $this->last_error='';
        if($this->failure==='missing_closings'){
            $this->last_error='synthetic failed closing query';return null;
        }
        return [];
    }
    public function insert($table,$data){$this->writes[]=$table;return 1;}
    public function update($table,$data,$where){$this->writes[]=$table;return 1;}
}
$closingActor=new \ExcelHerbal\ERP7\Security\Actor(10,10,1,1,[1],[
    \ExcelHerbal\ERP7\Security\Capabilities::BRANCH_CLOSE,
    \ExcelHerbal\ERP7\Security\Capabilities::PERIOD_MANAGE
],'BM');
foreach([
    ['branch daily check failure','eh7_daily_cycles',false],
    ['branch stock check failure','eh7_stock_balances',false],
    ['period expense check failure','eh7_expenses',true],
    ['period missing closings read failure','missing_closings',true],
] as [$name,$failure,$period]){
    $wpdb=new ClosingReadRegressionDb();$wpdb->failure=$failure;
    try{
        if($period)\ExcelHerbal\ERP7\Finance\FinancePeriodService::closePeriod($closingActor,'2026-09-01','2026-09-30');
        else \ExcelHerbal\ERP7\Finance\FinanceClosingService::closingPreflight($closingActor,1,'2026-09-08');
        $failed++;echo "FAIL closing read {$name}: accepted\n";
    }catch(DomainException $e){
        if($e->codeKey==='closing_preflight_unavailable'&&$wpdb->writes===[]&&(!$period||in_array('ROLLBACK',$wpdb->queries,true)))echo "PASS closing read {$name}\n";
        else{$failed++;echo "FAIL closing read {$name}: {$e->codeKey}\n";}
    }catch(\Throwable $e){$failed++;echo "FAIL closing read {$name}: {$e->getMessage()}\n";}
}
// PUR-01: batch creation must roll back with the bill, including failures
// during preparation of a later line.
final class PurchaseBatchRegressionDb {
    public string $prefix='wp_';
    public string $last_error='';
    public int $insert_id=0;
    public array $queries=[];
    public array $batches=[];
    private array $snapshot=[];
    public function prepare($q,...$args){return $q;}
    public function query($q){
        $this->queries[]=$q;
        if($q==='START TRANSACTION')$this->snapshot=$this->batches;
        if($q==='ROLLBACK')$this->batches=$this->snapshot;
        if(str_contains($q,'INSERT INTO wp_eh7_batches')){
            $this->batches[1]=true;$this->insert_id=1;
        }
        return 1;
    }
    public function get_var($q){
        if(str_contains($q,'eh7_branch_closings')||str_contains($q,'eh7_accounting_periods'))return null;
        return 1;
    }
    public function get_row($q,$mode){
        if(str_contains($q,'eh7_products'))return ['id'=>1,'batch_tracking'=>'required'];
        if(str_contains($q,'eh7_batches'))return ['manufactured_on'=>null,'expires_on'=>null];
        return null;
    }
}
$purchaseActor=new \ExcelHerbal\ERP7\Security\Actor(10,10,1,1,[1],[
    \ExcelHerbal\ERP7\Security\Capabilities::PURCHASE_CREATE
],'BM');
$validPurchaseLine=['product_id'=>1,'quantity'=>2,'unit_cost'=>50,'batch_no'=>'TEST-PUR-001'];
foreach([
    ['later invalid line',array_replace($validPurchaseLine,['quantity'=>0]),'domain_error'],
    ['later duplicate batch',$validPurchaseLine,'duplicate_purchase_line']
] as [$name,$second,$expected]){
    $wpdb=new PurchaseBatchRegressionDb();
    try{
        \ExcelHerbal\ERP7\Purchase\PurchaseService::bill($purchaseActor,1,1,'TEST-PUR','2026-09-08',[$validPurchaseLine,$second]);
        $failed++;echo "FAIL purchase batch rollback {$name}: accepted\n";
    }catch(DomainException $e){
        if($e->codeKey===$expected&&$wpdb->batches===[]&&in_array('ROLLBACK',$wpdb->queries,true))echo "PASS purchase batch rollback {$name}\n";
        else{$failed++;echo "FAIL purchase batch rollback {$name}: {$e->codeKey} batches=".count($wpdb->batches)."\n";}
    }catch(\Throwable $e){$failed++;echo "FAIL purchase batch rollback {$name}: {$e->getMessage()}\n";}
}
// INV-01: expiry-tracked goods must have a usable batch and expiry for outbound use.
final class ExpiryBatchRegressionDb {
    public string $prefix='wp_';
    public string $last_error='';
    public ?string $expiry=null;
    public int $insert_id=1;
    public function query($q){return 1;}
    public function prepare($q,...$args){return $q;}
    public function get_row($q,$mode){return ['id'=>1,'expires_on'=>$this->expiry];}
}
foreach([
    ['tracked missing batch','optional',1,null,null,true,'batch_required'],
    ['tracked off missing batch','off',1,null,null,true,'batch_required'],
    ['tracked missing expiry','required',1,1,null,true,'batch_expiry_required'],
    ['tracked expired','required',1,1,'2026-09-29',true,'batch_expired'],
    ['tracked expiry today','required',1,1,'2026-09-30',true,null],
    ['tracked future expiry','required',1,1,'2026-10-01',true,null],
    ['untracked optional','optional',0,null,null,true,null],
    ['untracked batch no expiry','required',0,1,null,true,null],
    ['legacy inbound batch missing expiry','required',1,1,null,false,null],
] as [$name,$mode,$tracked,$batch,$expiry,$out,$error]){
    $wpdb=new ExpiryBatchRegressionDb();$wpdb->expiry=$expiry;
    try{
        \ExcelHerbal\ERP7\Inventory\StockService::validateBatch($purchaseActor,['id'=>1,'batch_tracking'=>$mode,'expiry_tracking'=>$tracked],$batch,$out);
        if($error!==null)throw new \RuntimeException('unexpected acceptance');
        echo "PASS stock expiry {$name}\n";
    }catch(DomainException $e){
        if($e->codeKey===$error)echo "PASS stock expiry {$name}\n";
        else{$failed++;echo "FAIL stock expiry {$name}: {$e->codeKey}\n";}
    }catch(\Throwable $e){$failed++;echo "FAIL stock expiry {$name}: {$e->getMessage()}\n";}
}
// Expiry-required purchase lines and invalid product master settings.
foreach([
 ['receiving without batch',['id'=>1,'batch_tracking'=>'optional','expiry_tracking'=>1],[],null,'batch_required'],
 ['receiving without expiry',['id'=>1,'batch_tracking'=>'required','expiry_tracking'=>1],['batch_no'=>'NEW'],null,'batch_expiry_required'],
 ['receiving existing undated batch',['id'=>1,'batch_tracking'=>'required','expiry_tracking'=>1],['batch_id'=>1],null,'batch_expiry_required'],
 ['receiving existing dated batch',['id'=>1,'batch_tracking'=>'required','expiry_tracking'=>1],['batch_id'=>1],'2026-10-01',null],
 ['untracked optional receipt',['id'=>1,'batch_tracking'=>'optional','expiry_tracking'=>0],[],null,null]
] as [$name,$product,$line,$expiry,$expected]){
    $wpdb=new ExpiryBatchRegressionDb();$wpdb->expiry=$expiry;
    try{
        \ExcelHerbal\ERP7\Inventory\StockService::ensureBatch($purchaseActor,$product,$line);
        if($expected!==null)throw new \RuntimeException('unexpected acceptance');
        echo "PASS receipt expiry {$name}\n";
    }catch(DomainException $e){
        if($e->codeKey===$expected)echo "PASS receipt expiry {$name}\n";
        else{$failed++;echo "FAIL receipt expiry {$name}: {$e->codeKey}\n";}
    }catch(\Throwable $e){$failed++;echo "FAIL receipt expiry {$name}: {$e->getMessage()}\n";}
}
final class ExpiryMasterRegressionDb {
    public string $prefix='wp_';public string $last_error='';public int $insert_id=1;
    public array $writes=[];
    public function prepare($q,...$args){return $q;}
    public function query($q){return 1;}
    public function get_var($q){return 0;}
    public function get_row($q,$mode){return ['id'=>1,'status'=>'active','batch_tracking'=>'optional','expiry_tracking'=>1];}
    public function insert($table,$data){$this->writes[]=$table;return 1;}
    public function update($table,$data,$where){$this->writes[]=$table;return 1;}
}
$masterActor=new \ExcelHerbal\ERP7\Security\Actor(10,10,1,1,[1],[\ExcelHerbal\ERP7\Security\Capabilities::PRODUCT_MANAGE],'BM');
foreach(['create','update'] as $name){
    $wpdb=new ExpiryMasterRegressionDb();
    try{
        if($name==='create')\ExcelHerbal\ERP7\Organization\OrganizationProductService::createProduct($masterActor,['sku'=>'TEST','name'=>'Synthetic','batch_tracking'=>'off','expiry_tracking'=>true]);
        else \ExcelHerbal\ERP7\Organization\OrganizationProductService::updateProduct($masterActor,1,['batch_tracking'=>'off']);
        $failed++;echo "FAIL expiry master {$name}: accepted\n";
    }catch(DomainException $e){
        if($e->codeKey==='product_expiry_batch_required'&&$wpdb->writes===[])echo "PASS expiry master {$name}\n";
        else{$failed++;echo "FAIL expiry master {$name}: {$e->codeKey}\n";}
    }catch(\Throwable $e){$failed++;echo "FAIL expiry master {$name}: {$e->getMessage()}\n";}
}
// Quarantine release must not commit stock before resolution and audit.
final class QuarantineRegressionDb {
    public string $prefix='wp_';public string $last_error='';public int $insert_id=1;
    public string $scenario='';public string $status='open';public float $qty=0;
    public array $queries=[];public array $ledger=[];public array $audit=[];
    private array $snapshot=[];
    public function prepare($q,...$args){return $q;}
    public function query($q){
        $this->queries[]=$q;
        if($q==='START TRANSACTION')$this->snapshot=[$this->status,$this->qty,$this->ledger,$this->audit];
        if($q==='ROLLBACK')[$this->status,$this->qty,$this->ledger,$this->audit]=$this->snapshot;
        return 1;
    }
    public function get_var($q){
        if(str_contains($q,'eh7_branch_closings')||str_contains($q,'eh7_accounting_periods'))return null;
        return 1;
    }
    public function get_row($q,$mode){
        $this->queries[]=$q;
        if(str_contains($q,'eh7_stock_quarantine'))return ['id'=>1,'branch_id'=>1,'product_id'=>1,'batch_id'=>1,'quantity'=>2,'status'=>$this->status,'reason'=>'Synthetic hold'];
        if(str_contains($q,'eh7_products'))return ['id'=>1,'batch_tracking'=>'required','expiry_tracking'=>1];
        if(str_contains($q,'eh7_batches'))return ['id'=>1,'expires_on'=>$this->scenario==='expired'?'2026-09-29':'2026-10-01'];
        if(str_contains($q,'eh7_stock_balances'))return ['id'=>1,'quantity'=>$this->qty,'average_unit_cost'=>0];
        return null;
    }
    public function update($table,$data,$where){
        if(str_contains($table,'stock_balances'))$this->qty=(float)$data['quantity'];
        if(str_contains($table,'stock_quarantine')){
            if($this->scenario==='status failure')return false;
            $this->status=$data['status'];
        }
        return 1;
    }
    public function insert($table,$data){
        if(str_contains($table,'stock_ledger'))$this->ledger[]=$data;
        if(str_contains($table,'audit_log')){
            if($this->scenario==='audit failure')return false;
            $this->audit[]=$data;
        }
        return 1;
    }
}
$quarantineActor=new \ExcelHerbal\ERP7\Security\Actor(10,10,1,1,[1],[\ExcelHerbal\ERP7\Security\Capabilities::ADJ_APPROVE],'BM');
foreach([
    ['expired','batch_expired'],
    ['status failure','database_update_failed'],
    ['audit failure','database_insert_failed'],
] as [$name,$expected]){
    $wpdb=new QuarantineRegressionDb();$wpdb->scenario=$name;
    try{
        \ExcelHerbal\ERP7\Inventory\InventoryService::resolveQuarantine($quarantineActor,1,'release','Synthetic release');
        $failed++;echo "FAIL quarantine {$name}: accepted\n";
    }catch(DomainException $e){
        if($e->codeKey===$expected&&$wpdb->status==='open'&&$wpdb->qty===0.0&&$wpdb->ledger===[]&&$wpdb->audit===[]&&in_array('ROLLBACK',$wpdb->queries,true))echo "PASS quarantine {$name}\n";
        else{$failed++;echo "FAIL quarantine {$name}: {$e->codeKey} qty={$wpdb->qty}\n";}
    }catch(\Throwable $e){$failed++;echo "FAIL quarantine {$name}: {$e->getMessage()}\n";}
}
$wpdb=new QuarantineRegressionDb();
try{
    $result=\ExcelHerbal\ERP7\Inventory\InventoryService::resolveQuarantine($quarantineActor,1,'release','Synthetic release');
    $locked=array_filter($wpdb->queries,fn($q)=>str_contains($q,'eh7_stock_quarantine')&&str_contains($q,'FOR UPDATE'));
    if($result['status']!=='released'||$wpdb->qty!==2.0||count($wpdb->ledger)!==1||count($wpdb->audit)!==1||!$locked)throw new \RuntimeException('release is not locked and audited');
    try{\ExcelHerbal\ERP7\Inventory\InventoryService::resolveQuarantine($quarantineActor,1,'release','Synthetic retry');throw new \RuntimeException('retry accepted');}
    catch(DomainException $e){if($e->codeKey!=='quarantine_already_resolved')throw $e;}
    if($wpdb->qty!==2.0||count($wpdb->ledger)!==1)throw new \RuntimeException('duplicate release');
    echo "PASS quarantine single release\n";
}catch(\Throwable $e){$failed++;echo "FAIL quarantine single release: {$e->getMessage()}\n";}
// COM-01: reject lossy PHP coercion and out-of-range fixed decimal inputs.
foreach([
 ['text','sale_price','abc',false],
 ['boolean','bm_profit',true,false],
 ['null','salary_fund',null,false],
 ['array','points',[1],false],
 ['negative','ho_amount',-0.001,false],
 ['infinite','office_expense',INF,false],
 ['sub-paisa','sale_price',0.001,false],
 ['overflow money','mrp','1000000000000.00',false],
 ['overflow cost','purchase_cost','10000000000.0000',false],
 ['excess cost precision','purchase_cost','1.00001',false],
 ['valid money','sale_price','12.34',true],
 ['valid cost','purchase_cost','12.3456',true],
 ['explicit zero','points',0,true],
] as [$name,$field,$value,$valid]){
    $wpdb=new ExpiryMasterRegressionDb();
    try{
        \ExcelHerbal\ERP7\Organization\OrganizationProductService::commercialRevision($masterActor,1,[$field=>$value]);
        if(!$valid)throw new \RuntimeException('unexpected acceptance');
        echo "PASS commercial decimal {$name}\n";
    }catch(DomainException $e){
        if(!$valid&&$e->codeKey==='commercial_value_invalid'&&$wpdb->writes===[])echo "PASS commercial decimal {$name}\n";
        else{$failed++;echo "FAIL commercial decimal {$name}: {$e->codeKey}\n";}
    }catch(\Throwable $e){$failed++;echo "FAIL commercial decimal {$name}: {$e->getMessage()}\n";}
}

// ERP startup and other REST success/error responses must not be cached.
if(!defined('EH7_VERSION'))define('EH7_VERSION','7.3.12-rc1');
class WP_REST_Response {
    public array $headers=[];
    public function __construct(public array $data,public int $status){}
    public function header($key,$value){$this->headers[$key]=$value;}
}
$apiResponse=new \ReflectionMethod(\ExcelHerbal\ERP7\Http\Api::class,'response');
foreach([200,401,403,500,503] as $status){
    try{
        $body=['ok'=>$status===200];
        $response=$apiResponse->invoke(null,$body,$status,'synthetic-request');
        if(($response->headers['Cache-Control']??'')!=='private, no-store, no-cache, max-age=0, must-revalidate'
            ||($response->headers['X-Request-Id']??'')!=='synthetic-request'
            ||$response->status!==$status||$response->data!==$body){
            throw new \RuntimeException('Response cache or transport contract mismatch.');
        }
        echo "PASS API no-store {$status}\n";
    }catch(\Throwable $e){$failed++;echo "FAIL API no-store {$status}: {$e->getMessage()}\n";}
}

// AC-059: branch close/reopen must serialize with period closing and preserve history.
final class ClosingTransitionRegressionDb {
    public string $prefix='wp_';
    public string $last_error='';
    public string $status='draft';
    public string $scenario='';
    public int $insert_id=1;
    public array $queries=[];
    public array $writes=[];
    public function prepare($q,...$args){return $q;}
    public function query($q){$this->queries[]=$q;return 1;}
    public function get_row($q,$mode){
        $this->queries[]=$q;
        $this->last_error=$this->scenario==='row error'?'synthetic failed read':'';
        return ['id'=>9,'branch_id'=>1,'business_date'=>'2026-09-08','created_by'=>20,'status'=>$this->status];
    }
    public function get_var($q){
        $this->queries[]=$q;$this->last_error='';
        if(str_contains($q,'eh7_companies'))return $this->scenario==='gate failed'?null:1;
        if(str_contains($q,'eh7_accounting_periods'))return $this->scenario==='period closed'?1:null;
        if(str_contains($q,'COUNT(*)'))return 0;
        return 1;
    }
    public function update($table,$data,$where){$this->writes[]=[$table,$data];return 1;}
    public function insert($table,$data){
        if($this->scenario==='audit failure')return false;
        $this->writes[]=[$table,$data];return 1;
    }
}
$transitionActor=new \ExcelHerbal\ERP7\Security\Actor(10,10,1,1,[1],[
    \ExcelHerbal\ERP7\Security\Capabilities::BRANCH_CLOSE,
    \ExcelHerbal\ERP7\Security\Capabilities::BRANCH_REOPEN
],'BM');
foreach([
    ['duplicate close','closed','','branch_closing_invalid_state',false],
    ['unknown state','cancelled','','branch_closing_invalid_state',false],
    ['close read failure','draft','row error','branch_day_read_failed',false],
    ['close gate failure','draft','gate failed','period_lock_failed',false],
    ['close inside locked period','draft','period closed','accounting_period_closed',false],
    ['reopen inside locked period','closed','period closed','accounting_period_closed',true],
    ['close audit failure','draft','audit failure','database_insert_failed',false],
    ['close draft','draft','',null,false],
    ['close reopened','reopened','',null,false],
    ['reopen open period','closed','',null,true],
] as [$name,$status,$scenario,$expected,$reopen]){
    $wpdb=new ClosingTransitionRegressionDb();$wpdb->status=$status;$wpdb->scenario=$scenario;
    try{
        $result=$reopen?
            \ExcelHerbal\ERP7\Finance\FinanceClosingService::reopenBranch($transitionActor,9,'Synthetic reason'):
            \ExcelHerbal\ERP7\Finance\FinanceClosingService::closeBranch($transitionActor,9);
        if($expected!==null)throw new \RuntimeException('unexpected acceptance');
        if(($result['status']??'')!==($reopen?'reopened':'closed')||count($wpdb->writes)!==2||
           $wpdb->writes[1][1]['action']!==($reopen?'branch_closing.reopen':'branch_closing.close')||
           !str_contains($wpdb->queries[1]??'','eh7_companies')||
           !str_contains($wpdb->queries[1]??'','LOCK IN SHARE MODE')||
           !in_array('COMMIT',$wpdb->queries,true))throw new \RuntimeException('transition/audit/gate mismatch');
        echo "PASS closing transition {$name}\n";
    }catch(DomainException $e){
        if($expected!==null&&$e->codeKey===$expected&&in_array('ROLLBACK',$wpdb->queries,true)&&
           !in_array('COMMIT',$wpdb->queries,true)&&($scenario==='audit failure'||$wpdb->writes===[]))echo "PASS closing transition {$name}\n";
        else{$failed++;echo "FAIL closing transition {$name}: {$e->codeKey}\n";}
    }catch(\Throwable $e){$failed++;echo "FAIL closing transition {$name}: {$e->getMessage()}\n";}
}
echo ($failed?'FAILED':'PASSED').' regression suite'.PHP_EOL;exit($failed?1:0);