<?php
/** Synthetic state-machine tests. No live DB or customers. */
if(!defined('ARRAY_A'))define('ARRAY_A','ARRAY_A');
if(!function_exists('current_time')){function current_time(string $format,bool $gmt=false):string{
    return $format==='Y-m-d'?'2026-11-03':'2026-11-03 12:00:00';
}}
if(!function_exists('wp_json_encode')){function wp_json_encode(mixed $v):string {
    return json_encode($v,JSON_THROW_ON_ERROR);
}}
require_once __DIR__.'/../src/Core/Autoloader.php';
\ExcelHerbal\ERP7\Core\Autoloader::register(__DIR__.'/../src');

use ExcelHerbal\ERP7\DailyOrder\DailyCancellationService as Cancellation;
use ExcelHerbal\ERP7\Domain\DomainException;
use ExcelHerbal\ERP7\Http\ApiContract;
use ExcelHerbal\ERP7\Http\RouteRegistry;
use ExcelHerbal\ERP7\Security\Actor;
use ExcelHerbal\ERP7\Security\Capabilities as Cap;

final class FakeCancelWpdb {
    public string $prefix='wp_';
    public string $cycle='morning_draft';
    public string $request='draft';
    public int $branch=1;
    public int $creator=11;
    public int $beneficiary=11;
    public bool $allocated=false;
    public bool $settled=false;
    public bool $closed=false;
    public array $commands=[];
    public array $updates=[];
    public array $insertions=[];
    public string $last_error='';
    public function prepare(string $sql,mixed ...$args):string{return $sql;}
    public function query(string $sql):int|false{$this->commands[]=$sql;return 1;}
    public function get_row(string $sql,mixed $format=null):?array {
        if(str_contains($sql,'wp_eh7_daily_cycles'))return [
            'id'=>70,'company_id'=>1,'branch_id'=>$this->branch,
            'employee_id'=>$this->beneficiary,'created_by'=>$this->creator,
            'business_date'=>'2026-11-03','status'=>$this->cycle
        ];
        if(str_contains($sql,'wp_eh7_daily_requests'))return [
            'id'=>71,'status'=>$this->request
        ];
        return null;
    }
    public function get_var(string $sql):int|string|null {
        if(str_contains($sql,'wp_eh7_branch_closings'))return $this->closed?'closed':'';
        if(str_contains($sql,'wp_eh7_daily_issue_lines'))return $this->allocated?1:0;
        if(str_contains($sql,'wp_eh7_evening_settlements'))return $this->settled?1:0;
        return null;
    }
    public function update(string $table,array $data,array $where):int {
        $this->updates[]=[$table,$data,$where];
        if(str_contains($table,'wp_eh7_daily_cycles'))$this->cycle=$data['status'];
        if(str_contains($table,'wp_eh7_daily_requests'))$this->request=$data['status'];
        return 1;
    }
    public function insert(string $table,array $data):int {
        $this->insertions[]=[$table,$data];return 1;
    }
}
$GLOBALS['wpdb']=new FakeCancelWpdb();
function checkCancel(bool $truth,string $label):void {
    if(!$truth){fwrite(STDERR,"FAIL ".$label."\n");exit(1);}
    echo "PASS ".$label."\n";
}
function rejectCancel(callable $action,string $code):void {
    try{$action();}catch(DomainException $e){
        checkCancel($e->codeKey===$code,'rejects '.$code);return;
    }
    checkCancel(false,'expected '.$code);
}
$db=$GLOBALS['wpdb'];
$employee=new Actor(11,11,1,1,[1],[Cap::DAILY_SELF],'EMPLOYEE');
$outsider=new Actor(11,11,1,1,[2],[Cap::DAILY_SELF],'EMPLOYEE');
rejectCancel(fn()=>Cancellation::cancel($employee,70,'bad'),'daily_cancel_reason_invalid');
rejectCancel(fn()=>Cancellation::cancel($outsider,70,'Reason within scope'),'branch_forbidden');
$db->cycle='approved';$db->request='approved';
rejectCancel(fn()=>Cancellation::cancel($employee,70,'Approved order cancel attempt'),'daily_request_state_invalid');
$db->cycle='stock_requested';$db->request='reviewed';$db->allocated=true;
rejectCancel(fn()=>Cancellation::cancel($employee,70,'Blocked after stock allocation'),'daily_order_has_dependencies');
$db->allocated=false;$db->settled=true;
rejectCancel(fn()=>Cancellation::cancel($employee,70,'Blocked after accounting settlement'),'daily_order_has_dependencies');
$db->settled=false;$db->cycle='morning_draft';$db->request='draft';
$cancel=Cancellation::cancel($employee,70,'Customer requested correction');
checkCancel($cancel['status']==='cancelled'&&$cancel['stock_moved']===false,
    'unallocated draft becomes cancelled without stock movement');
checkCancel($db->cycle==='cancelled'&&$db->request==='cancelled'&&
    in_array('COMMIT',$db->commands,true),'cycle and request cancellation atomic');
$audit=array_values(array_filter($db->insertions,static fn($row)=>
    str_contains($row[0],'wp_eh7_audit_log')));
checkCancel(count($audit)===1&&$audit[0][1]['action']==='daily_order.cancel'&&
    str_contains((string)$audit[0][1]['context_json'],'Customer requested correction'),
    'cancel reason written to audit');
rejectCancel(fn()=>Cancellation::cancel($employee,70,'Repeated cancel attempt'),'daily_request_state_invalid');
$reopen=Cancellation::reopen($employee,70);
checkCancel($reopen['status']==='morning_draft'&&$reopen['stock_moved']===false&&
    $db->cycle==='morning_draft'&&$db->request==='draft',
    'cancelled draft can safely reopen without stock changes');
$audits=array_values(array_filter($db->insertions,static fn($row)=>
    str_contains($row[0],'wp_eh7_audit_log')));
checkCancel(count($audits)===2&&
    $audits[1][1]['action']==='daily_order.reopen_draft',
    'reopening records separate audit event');
rejectCancel(fn()=>Cancellation::reopen($employee,70),'daily_request_state_invalid');
$db->cycle='cancelled';$db->request='cancelled';$db->allocated=true;
rejectCancel(fn()=>Cancellation::reopen($employee,70),'daily_order_has_dependencies');
$db->allocated=false;$db->closed=true;
rejectCancel(fn()=>Cancellation::reopen($employee,70),'branch_day_closed');

$db->closed=false;$db->cycle='rejected';$db->request='rejected';
$reopened=Cancellation::reopen($employee,70);
checkCancel($reopened['status']==='morning_draft'&&$db->request==='draft',
    'reviewer rejected unallocated order may reopen to editable draft');
$reopenedAudit=end($db->insertions);
checkCancel($reopenedAudit[1]['action']==='daily_order.reopen_draft'&&
    str_contains((string)$reopenedAudit[1]['context_json'],'rejected'),
    'rejected original state preserved in reopen audit');
$routes=RouteRegistry::routes();$contracts=ApiContract::describe()['routes'];
foreach([
    'daily.cancel'=>['/daily/cycles/(?P<id>\\d+)/cancel',['reason']],
    'daily.reopen_draft'=>['/daily/cycles/(?P<id>\\d+)/reopen-draft',[]],
] as $handler=>[$path,$required]){
    checkCancel(count(array_filter($routes,static fn($r)=>
        $r[0]==='POST'&&$r[1]===$path&&$r[2]===$handler&&$r[3]))===1,
        'authenticated '.$handler);
    checkCancel(count(array_filter($contracts,static fn($r)=>
        $r['path']===$path&&$r['method']==='POST'&&$r['auth']===true&&
        $r['idempotency_required']===true&&$r['required_params']===$required))===1,
        'required contract '.$handler);
}
$src=file_get_contents(__DIR__.'/../src/DailyOrder/DailyCancellationService.php');
foreach(['StockService::move(','AccountingService::post(','StockService::transferCustody('] as $unsafe){
    checkCancel(!str_contains($src,$unsafe),'no stock/ledger mutation in cancellation: '.$unsafe);
}
echo "PASSED synthetic Daily Order cancellation/reopen state and authorization contracts\n";
