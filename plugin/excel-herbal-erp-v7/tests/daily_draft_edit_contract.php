<?php
/** Synthetic transactional Draft Edit tests: no database/host mutation. */
if(!defined('ARRAY_A'))define('ARRAY_A','ARRAY_A');
if(!function_exists('current_time')){function current_time(string $format,bool $gmt=false):string{
    return $format==='Y-m-d'?'2026-11-03':'2026-11-03 12:00:00';
}}
if(!function_exists('wp_json_encode')){function wp_json_encode(mixed $v):string {
    return json_encode($v,JSON_THROW_ON_ERROR);
}}
require_once __DIR__.'/../src/Core/Autoloader.php';
\ExcelHerbal\ERP7\Core\Autoloader::register(__DIR__.'/../src');

use ExcelHerbal\ERP7\DailyOrder\DailyDraftEditService as Draft;
use ExcelHerbal\ERP7\Domain\DomainException;
use ExcelHerbal\ERP7\Http\ApiContract;
use ExcelHerbal\ERP7\Http\RouteRegistry;
use ExcelHerbal\ERP7\Security\Actor;
use ExcelHerbal\ERP7\Security\Capabilities as C;

final class FakeDraftWpdb {
    public string $prefix='wp_';
    public string $last_error='';
    public int $insert_id=0;
    public array $commands=[];
    public array $insertions=[];
    public string $cycleStatus='morning_draft';
    public string $requestStatus='draft';
    public int $beneficiary=11;
    public int $createdBy=11;
    public int $branch=1;
    public bool $businessDayClosed=false;
    public bool $allocated=false;
    public bool $failInserts=false;

    public function prepare(string $sql,mixed ...$values):string{return $sql;}
    public function get_row(string $sql,mixed $output=null):?array {
        if(str_contains($sql,'eh7_daily_cycles')) return [
            'id'=>70,'company_id'=>1,'employee_id'=>$this->beneficiary,
            'created_by'=>$this->createdBy,'branch_id'=>$this->branch,
            'status'=>$this->cycleStatus,'business_date'=>'2026-11-03'
        ];
        if(str_contains($sql,'eh7_daily_requests'))return [
            'id'=>71,'status'=>$this->requestStatus
        ];
        if(str_contains($sql,'eh7_products')) return ['id'=>1,'status'=>'active'];
        return null;
    }
    public function get_var(string $sql):int|string|null {
        if(str_contains($sql,'eh7_branch_closings'))return $this->businessDayClosed?'closed':'';
        if(str_contains($sql,'eh7_daily_issue_lines'))return $this->allocated?1:0;
        return null;
    }
    public function query(string $sql):int|false {
        $this->commands[]=$sql;
        return 1;
    }
    public function insert(string $table,array $data):int|false {
        if($this->failInserts&&str_contains($table,'daily_request_lines')) {
            $this->last_error='synthetic failure';
            return false;
        }
        $this->insertions[]=[$table,$data];
        $this->insert_id++;
        return 1;
    }
}
$GLOBALS['wpdb']=new FakeDraftWpdb();
function expectDraft(bool $ok,string $label):void {
    if(!$ok){fwrite(STDERR,"FAIL $label\n");exit(1);}
    echo "PASS $label\n";
}
function rejectsDraft(callable $fn,string $expected):void {
    try{$fn();}catch(DomainException $e){
        expectDraft($e->codeKey===$expected,'rejects '.$expected);return;
    }
    expectDraft(false,'expected '.$expected);
}
$db=$GLOBALS['wpdb'];
$employee=new Actor(11,11,1,1,[1],[C::DAILY_SELF],'EMPLOYEE');
$other=new Actor(12,12,1,1,[1],[C::DAILY_SELF],'EMPLOYEE');
$valid=[['product_id'=>1,'quantity'=>2],['product_id'=>2,'quantity'=>3]];
rejectsDraft(fn()=>Draft::edit($employee,70,[]),'daily_draft_lines_invalid');
rejectsDraft(fn()=>Draft::edit($employee,70,[['product_id'=>1,'quantity'=>1.5]]),'whole_pcs_required');
rejectsDraft(fn()=>Draft::edit($employee,70,[['product_id'=>1,'quantity'=>0]]),'whole_pcs_required');
rejectsDraft(fn()=>Draft::edit($employee,70,[['product_id'=>null,'quantity'=>1]]),'duplicate_daily_line');
rejectsDraft(fn()=>Draft::edit($employee,70,[['product_id'=>1,'quantity'=>1],['product_id'=>1,'quantity'=>2]]),'duplicate_daily_line');
rejectsDraft(fn()=>Draft::edit($other,70,$valid),'permission_denied');
$db->cycleStatus='approved';
rejectsDraft(fn()=>Draft::edit($employee,70,$valid),'daily_request_state_invalid');
$db->cycleStatus='morning_draft';$db->requestStatus='submitted';
rejectsDraft(fn()=>Draft::edit($employee,70,$valid),'daily_request_state_invalid');
$db->requestStatus='draft';$db->businessDayClosed=true;
rejectsDraft(fn()=>Draft::edit($employee,70,$valid),'branch_day_closed');
$db->businessDayClosed=false;$db->allocated=true;
rejectsDraft(fn()=>Draft::edit($employee,70,$valid),'daily_request_state_invalid');
$db->allocated=false;$db->failInserts=true;
rejectsDraft(fn()=>Draft::edit($employee,70,$valid),'database_insert_failed');
expectDraft(in_array('ROLLBACK',$db->commands,true),'failed replacement triggers rollback');
$db->failInserts=false;$db->commands=[];$db->insertions=[];
$result=Draft::edit($employee,70,$valid);
expectDraft($result['id']===70&&$result['request_id']===71&&
    $result['status']==='morning_draft'&&$result['line_count']===2,
    'success preserves initial request and cycle status');
expectDraft(in_array('START TRANSACTION',$db->commands,true)&&
    in_array('COMMIT',$db->commands,true),
    'success commits one atomic transaction');
expectDraft(count(array_filter($db->commands,static fn($sql)=>
    str_contains($sql,'DELETE FROM wp_eh7_daily_request_lines')) )===1,
    'old draft lines replaced only after validation');
$lines=array_values(array_filter($db->insertions,static fn($row)=>
    str_contains($row[0],'daily_request_lines')));
expectDraft(count($lines)===2&&$lines[0][1]['quantity']===2&&
    $lines[1][1]['quantity']===3,'replacement stores exact whole PCS');
$audits=array_values(array_filter($db->insertions,static fn($row)=>
    str_contains($row[0],'audit_log')));
expectDraft(count($audits)===1&&$audits[0][1]['action']==='daily_order.draft_edit',
    'edit writes accountability audit event');
$routes=array_values(array_filter(RouteRegistry::routes(),static fn($r)=>
    $r[0]==='POST'&&$r[1]==='/daily/cycles/(?P<id>\\d+)/edit-draft'&&
    $r[2]==='daily.edit_draft'&&$r[3]===true));
expectDraft(count($routes)===1,'authenticated draft edit route');
$spec=array_values(array_filter(ApiContract::describe()['routes'],
    static fn($r)=>$r['method']==='POST'&&
    $r['path']==='/daily/cycles/(?P<id>\\d+)/edit-draft'));
expectDraft(count($spec)===1&&$spec[0]['required_params']===['lines']&&
    $spec[0]['idempotency_required']===true,'draft mutation requires lines and idempotency');
echo "PASSED synthetic atomic draft edit, rollback, scope and contract checks\n";
