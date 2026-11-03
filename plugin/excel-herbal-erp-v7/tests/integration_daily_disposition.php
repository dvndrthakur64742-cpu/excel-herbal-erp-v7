<?php
/**
 * Real InnoDB daily request disposition test. Synthetic data ONLY.
 * This script drops/recreates disposable test tables: never run in production.
 */
define('EH7_INTEGRATION_LIBRARY_ONLY',true);
require __DIR__.'/integration_mariadb.php';
require_once __DIR__.'/../src/Core/Autoloader.php';
\ExcelHerbal\ERP7\Core\Autoloader::register(__DIR__.'/../src');

use ExcelHerbal\ERP7\Database\Db;
use ExcelHerbal\ERP7\Database\Schema;
use ExcelHerbal\ERP7\Domain\DomainException;
use ExcelHerbal\ERP7\DailyOrder\DailyCancellationService;
use ExcelHerbal\ERP7\DailyOrder\DailyRequestDispositionService as Disposition;
use ExcelHerbal\ERP7\Security\Actor;
use ExcelHerbal\ERP7\Security\Capabilities as C;

$database=(string)(getenv('EH7_MARIADB_DATABASE')?:'');
if(getenv('EH7_INTEGRATION_MODE')!=='synthetic'||!str_starts_with($database,'eh7_test_')){
    fwrite(STDERR,"REFUSED: synthetic test requires eh7_test_* database and synthetic mode\n");
    exit(2);
}
$db=eh7_setup_global_db();
$tables=[
    'audit_log','daily_issue_lines','evening_settlements','daily_requests',
    'daily_cycles','branch_closings','employees','branches','companies',
];
$schema=Schema::definitions();
foreach($tables as $table) {
    if($db->query('DROP TABLE IF EXISTS '.Db::table($table))===false)
        throw new RuntimeException('Drop failed: '.$table.' '.$db->last_error);
}
foreach(array_reverse($tables) as $table) {
    $sql='CREATE TABLE '.Db::table($table).' ('.$schema[$table].
        ') ENGINE=InnoDB DEFAULT CHARSET=utf8mb4';
    if($db->query($sql)===false)
        throw new RuntimeException('Create failed: '.$table.' '.$db->last_error);
}
function insertDaily(string $table,array $data):int {
    Db::mustInsert(Db::wpdb(),Db::table($table),$data);
    return (int)Db::wpdb()->insert_id;
}
function assertDaily(bool $ok,string $name):void {
    if(!$ok)throw new RuntimeException('FAIL '.$name);
    echo "PASS ".$name."\n";
}
function denyDaily(callable $action,string $code):void {
    try{$action();}catch(DomainException $e){
        assertDaily($e->codeKey===$code,'denied '.$code);return;
    }
    throw new RuntimeException('Expected failure '.$code);
}
$now=Db::now();
insertDaily('companies',['id'=>1,'name'=>'Synthetic Daily UAT','status'=>'active','created_at'=>$now]);
insertDaily('branches',['id'=>1,'company_id'=>1,'code'=>'B1',
    'name'=>'Synthetic Branch','created_at'=>$now]);
foreach([
    [11,'EMPLOYEE',20],
    [20,'SM',null],
    [30,'BM',null],
] as [$id,$designation,$manager]){
    insertDaily('employees',[
        'id'=>$id,'company_id'=>1,'employee_code'=>'TEST'.$id,
        'designation_code'=>$designation,'assigned_branch_id'=>1,
        'reporting_employee_id'=>$manager,'full_name'=>'Synthetic '.$id,
        'status'=>'active','created_at'=>$now,
    ]);
}
$maker=new Actor(11,11,1,1,[1],[C::DAILY_SELF],'EMPLOYEE');
$reviewer=new Actor(20,20,1,1,[1],[C::DAILY_OTHERS],'SM');
$unrelated=new Actor(30,30,1,1,[1],[C::DAILY_OTHERS],'BM');
$foreign=new Actor(20,20,1,2,[2],[C::DAILY_OTHERS],'SM');

$initialCycle=insertDaily('daily_cycles',[
    'company_id'=>1,'branch_id'=>1,'employee_id'=>11,
    'business_date'=>'2026-11-02','status'=>'stock_requested',
    'created_by'=>11,'created_at'=>$now,
]);
$initialRequest=insertDaily('daily_requests',[
    'daily_cycle_id'=>$initialCycle,'type'=>'initial',
    'status'=>'submitted','requested_by'=>11,'created_at'=>$now,
]);
denyDaily(fn()=>Disposition::reject($maker,$initialRequest,'Missing required invoice'),'permission_denied');
denyDaily(fn()=>Disposition::reject($foreign,$initialRequest,'Needs correction'),'branch_forbidden');
$reject=Disposition::reject($reviewer,$initialRequest,'Insufficient request justification');
assertDaily($reject['status']==='rejected'&&
    (string)$db->get_var($db->prepare('SELECT status FROM '.Db::table('daily_cycles').' WHERE id=%d',$initialCycle))==='rejected',
    'initial reviewer rejection commits cycle and request');
assertDaily((int)$db->get_var("SELECT COUNT(*) FROM ".Db::table('audit_log').
    " WHERE action='daily_order.request_rejected'")===1,
    'initial rejection records audit');
$reopened=DailyCancellationService::reopen($maker,$initialCycle);
assertDaily($reopened['status']==='morning_draft'&&
    (string)$db->get_var($db->prepare('SELECT status FROM '.Db::table('daily_requests').' WHERE id=%d',$initialRequest))==='draft',
    'rejected initial request reopens without a new cycle');

$additionalCycle=insertDaily('daily_cycles',[
    'company_id'=>1,'branch_id'=>1,'employee_id'=>11,
    'business_date'=>'2026-11-03','status'=>'issued',
    'created_by'=>11,'created_at'=>$now,
]);
$additional=insertDaily('daily_requests',[
    'daily_cycle_id'=>$additionalCycle,'type'=>'additional',
    'status'=>'submitted','requested_by'=>11,'created_at'=>$now,
]);
$rejectExtra=Disposition::reject($reviewer,$additional,'Additional quantity is not justified');
assertDaily($rejectExtra['status']==='rejected'&&
    (string)$db->get_var($db->prepare('SELECT status FROM '.Db::table('daily_cycles').
    ' WHERE id=%d',$additionalCycle))==='issued',
    'reject additional leaves original issued cycle intact');

$withdrawal=insertDaily('daily_requests',[
    'daily_cycle_id'=>$additionalCycle,'type'=>'additional',
    'status'=>'reviewed','requested_by'=>11,'created_at'=>$now,
]);
denyDaily(fn()=>Disposition::cancelAdditional($unrelated,$withdrawal,'Trying to cancel employee request'),
    'daily_additional_cancel_forbidden');
$cancel=Disposition::cancelAdditional($maker,$withdrawal,'Actual stock requirement was withdrawn');
assertDaily($cancel['status']==='cancelled'&&$cancel['stock_moved']===false&&
    (string)$db->get_var($db->prepare('SELECT status FROM '.Db::table('daily_cycles').
    ' WHERE id=%d',$additionalCycle))==='issued',
    'pending additional withdrawn with no cycle mutation');
$latest=(string)$db->get_var("SELECT context_json FROM ".Db::table('audit_log').
    " WHERE action='daily_order.additional_cancelled' ORDER BY id DESC LIMIT 1");
assertDaily(str_contains($latest,'requirement was withdrawn'),
    'withdrawal reason persists in real InnoDB audit');

$approved=insertDaily('daily_requests',[
    'daily_cycle_id'=>$additionalCycle,'type'=>'additional',
    'status'=>'approved','requested_by'=>11,'created_at'=>$now,
]);
denyDaily(fn()=>Disposition::cancelAdditional($maker,$approved,'Cannot withdraw an approved allocation'),
    'daily_request_state_invalid');
$allocated=insertDaily('daily_requests',[
    'daily_cycle_id'=>$additionalCycle,'type'=>'additional',
    'status'=>'submitted','requested_by'=>11,'created_at'=>$now,
]);
insertDaily('daily_issue_lines',[
    'daily_request_id'=>$allocated,'product_id'=>900,'quantity'=>'1.000',
]);
denyDaily(fn()=>Disposition::reject($reviewer,$allocated,'Request already has stock'),
    'daily_request_has_dependencies');
denyDaily(fn()=>Disposition::cancelAdditional($maker,$allocated,'Request already has stock'),
    'daily_request_has_dependencies');
assertDaily((int)$db->get_var($db->prepare('SELECT COUNT(*) FROM '.Db::table('audit_log').
    ' WHERE entity_type=%s','daily_request'))===3,
    'no ghost audit for denied allocations');
echo "PASSED real MariaDB initial rejection, correction, withdrawal, allocation protection and audit\n";
