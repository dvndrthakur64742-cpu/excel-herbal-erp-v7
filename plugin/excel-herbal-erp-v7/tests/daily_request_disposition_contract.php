<?php
/** Synthetic permissions and atomic state tests; never accesses production DB. */
if(!defined('ARRAY_A'))define('ARRAY_A','ARRAY_A');
if(!function_exists('current_time'))function current_time(string $format,bool $gmt=false):string{
    return $format==='Y-m-d'?'2026-11-03':'2026-11-03 12:00:00';
}
if(!function_exists('wp_json_encode'))function wp_json_encode(mixed $v):string{
    return json_encode($v,JSON_THROW_ON_ERROR);
}
require_once __DIR__.'/../src/Core/Autoloader.php';
\ExcelHerbal\ERP7\Core\Autoloader::register(__DIR__.'/../src');
use ExcelHerbal\ERP7\DailyOrder\DailyRequestDispositionService as Disposition;
use ExcelHerbal\ERP7\Domain\DomainException;
use ExcelHerbal\ERP7\Http\RouteRegistry;
use ExcelHerbal\ERP7\Http\ApiContract;
use ExcelHerbal\ERP7\Security\Actor;
use ExcelHerbal\ERP7\Security\Capabilities as C;

final class SyntheticDispositionDb {
    public string $prefix='wp_';
    public string $last_error='';
    public string $cycleStatus='stock_requested';
    public string $requestStatus='submitted';
    public string $requestType='initial';
    public int $maker=11;
    public int $beneficiary=11;
    public bool $allocated=false;
    public bool $settled=false;
    public bool $dayClosed=false;
    public array $sql=[];
    public array $audits=[];
    public function prepare(string $sql,mixed ...$params):string {return $sql;}
    public function get_row(string $sql,mixed $format=null):?array {
        if(str_contains($sql,'wp_eh7_daily_cycles'))return [
            'id'=>70,'company_id'=>1,'branch_id'=>1,'employee_id'=>$this->beneficiary,
            'created_by'=>11,'business_date'=>'2026-11-03','status'=>$this->cycleStatus,
        ];
        if(str_contains($sql,'wp_eh7_daily_requests'))return [
            'id'=>71,'daily_cycle_id'=>70,'status'=>$this->requestStatus,
            'type'=>$this->requestType,'requested_by'=>$this->maker,
        ];
        return null;
    }
    public function get_var(string $sql):int|string|null {
        if(str_contains($sql,'wp_eh7_branch_closings'))return $this->dayClosed?'closed':'';
        if(str_contains($sql,'wp_eh7_daily_issue_lines'))return $this->allocated?1:0;
        if(str_contains($sql,'wp_eh7_evening_settlements'))return $this->settled?1:0;
        return null;
    }
    public function get_results(string $sql,mixed $output=null):array{
        if(str_contains($sql,'wp_eh7_employees'))return [
            ['id'=>11,'assigned_branch_id'=>1,'reporting_employee_id'=>20,'designation_code'=>'SALES'],
            ['id'=>20,'assigned_branch_id'=>1,'reporting_employee_id'=>null,'designation_code'=>'SM'],
            ['id'=>30,'assigned_branch_id'=>1,'reporting_employee_id'=>null,'designation_code'=>'BM'],
            ['id'=>40,'assigned_branch_id'=>2,'reporting_employee_id'=>20,'designation_code'=>'SALES'],
        ];
        return [];
    }
    public function query(string $sql):int {
        $this->sql[]=$sql;return 1;
    }
    public function update(string $table,array $data,array $where):int{
        $this->sql[]='UPDATE '.$table;
        if(str_contains($table,'wp_eh7_daily_requests'))$this->requestStatus=$data['status'];
        if(str_contains($table,'wp_eh7_daily_cycles'))$this->cycleStatus=$data['status'];
        return 1;
    }
    public function insert(string $table,array $data):int{
        if(str_contains($table,'wp_eh7_audit_log'))$this->audits[]=$data;
        return 1;
    }
}
$GLOBALS['wpdb']=new SyntheticDispositionDb();
function dispOk(bool $v,string $name):void {
    if(!$v){fwrite(STDERR,"FAIL ".$name."\n");exit(1);}
    echo "PASS ".$name."\n";
}
function dispNo(callable $fn,string $key):void {
    try {$fn();}catch(DomainException $e){
        dispOk($e->codeKey===$key,"deny ".$key);return;
    }
    dispOk(false,"missing denial ".$key);
}
$db=$GLOBALS['wpdb'];
$maker=new Actor(11,11,1,1,[1],[C::DAILY_SELF,C::DAILY_OTHERS],'SM');
$reviewer=new Actor(20,20,1,1,[1],[C::DAILY_OTHERS],'SM');
$bm=new Actor(30,30,1,1,[1],[C::DAILY_APPROVE,C::DAILY_OTHERS],'BM');
$other=new Actor(30,30,1,1,[1],[C::DAILY_OTHERS],'BM');
$outside=new Actor(20,20,1,2,[2],[C::DAILY_OTHERS],'SM');
dispNo(fn()=>Disposition::reject($reviewer,71,'bad'),'daily_disposition_reason_invalid');
dispNo(fn()=>Disposition::reject($outside,71,'A sufficiently clear reason'),'branch_forbidden');
dispNo(fn()=>Disposition::reject($bm,71,'A sufficiently clear reason'),'daily_reviewer_required');
dispNo(fn()=>Disposition::reject($maker,71,'A sufficiently clear reason'),'maker_checker_required');
$db->allocated=true;
dispNo(fn()=>Disposition::reject($reviewer,71,'A sufficiently clear reason'),'daily_request_has_dependencies');
$db->allocated=false;$db->settled=true;
dispNo(fn()=>Disposition::reject($reviewer,71,'A sufficiently clear reason'),'daily_request_has_dependencies');
$db->settled=false;$db->requestStatus='reviewed';
dispNo(fn()=>Disposition::reject($reviewer,71,'A sufficiently clear reason'),'daily_request_state_invalid');
$db->requestStatus='submitted';
$result=Disposition::reject($reviewer,71,'Request incomplete and needs correction');
dispOk($result['status']==='rejected'&&$result['stock_moved']===false&&
    $db->requestStatus==='rejected'&&$db->cycleStatus==='rejected',
    'reviewer rejects submitted initial request and changes cycle state');
dispOk(in_array('COMMIT',$db->sql,true)&&
    count($db->audits)===1&&
    $db->audits[0]['action']==='daily_order.request_rejected'&&
    str_contains((string)$db->audits[0]['context_json'],'Request incomplete'),
    'rejection commits and records reason audit');
dispNo(fn()=>Disposition::reject($reviewer,71,'Second rejection attempt'),'daily_request_state_invalid');

$db->cycleStatus='issued';$db->requestStatus='submitted';$db->requestType='additional';
$result=Disposition::reject($reviewer,71,'Additional stock not justified');
dispOk($result['status']==='rejected'&&
    $db->cycleStatus==='issued'&&$db->requestStatus==='rejected',
    'additional rejection leaves existing issued cycle untouched');
$db->requestStatus='approved';
dispNo(fn()=>Disposition::cancelAdditional($maker,71,'Withdraw approved stock'),'daily_request_state_invalid');
$db->requestStatus='awaiting_receipt';$db->allocated=true;
dispNo(fn()=>Disposition::cancelAdditional($maker,71,'Withdraw already allocated stock'),'daily_request_has_dependencies');
$db->requestStatus='reviewed';$db->allocated=false;
dispNo(fn()=>Disposition::cancelAdditional($other,71,'Withdrawal by unrelated employee'),'daily_additional_cancel_forbidden');
$db->requestStatus='submitted';$db->dayClosed=true;
dispNo(fn()=>Disposition::cancelAdditional($maker,71,'Withdraw pending stock request'),'branch_day_closed');
$db->dayClosed=false;
$result=Disposition::cancelAdditional($maker,71,'Employee no longer needs extra stock');
dispOk($result['status']==='cancelled'&&
    $db->cycleStatus==='issued'&&$db->requestStatus==='cancelled'&&
    $result['stock_moved']===false,
    'request owner withdraws unallocated additional without stock movement');
dispOk(count($db->audits)===3&&
    $db->audits[2]['action']==='daily_order.additional_cancelled'&&
    str_contains((string)$db->audits[2]['context_json'],'no longer needs'),
    'additional cancellation reason remains auditable');
dispNo(fn()=>Disposition::cancelAdditional($maker,71,'Duplicate withdrawal'),'daily_request_state_invalid');
$db->requestStatus='submitted';$db->requestType='initial';$db->cycleStatus='stock_requested';
dispNo(fn()=>Disposition::cancelAdditional($maker,71,'Wrong request type'),'daily_request_state_invalid');

$routes=RouteRegistry::routes();$described=ApiContract::describe()['routes'];
foreach([
    'daily.reject'=>'/daily/requests/(?P<id>\\d+)/reject',
    'daily.cancel_additional'=>'/daily/requests/(?P<id>\\d+)/cancel-additional',
] as $handler=>$path) {
    dispOk(count(array_filter($routes,static fn($r)=>
        $r[0]==='POST'&&$r[1]===$path&&$r[2]===$handler&&$r[3]===true
    ))===1,'authenticated route '.$handler);
    dispOk(count(array_filter($described,static fn($r)=>
        $r['method']==='POST'&&$r['path']===$path&&$r['auth']===true&&
        $r['idempotency_required']===true&&$r['required_params']===['reason']
    ))===1,'idempotent reason contract '.$handler);
}
$src=file_get_contents(__DIR__.'/../src/DailyOrder/DailyRequestDispositionService.php');
foreach(['StockService::move(','StockService::transferCustody(','AccountingService::post('] as $unsafe){
    dispOk(!str_contains($src,$unsafe),'no unintended stock/journal mutation '.$unsafe);
}
echo "PASSED synthetic daily rejection/withdrawal contracts\n";
