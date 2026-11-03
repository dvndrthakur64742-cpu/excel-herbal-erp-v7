<?php
/**
 * Disposable InnoDB UAT of reward-to-draft-payroll allocation.
 * Intentionally does not pay a bank account or post any accounting journal.
 */
define('EH7_INTEGRATION_LIBRARY_ONLY',true);
require __DIR__.'/integration_mariadb.php';
require_once __DIR__.'/../src/Core/Autoloader.php';
\ExcelHerbal\ERP7\Core\Autoloader::register(__DIR__.'/../src');

use ExcelHerbal\ERP7\Database\{Db,Schema};
use ExcelHerbal\ERP7\Domain\DomainException;
use ExcelHerbal\ERP7\Payroll\{
    RewardAdjustmentService as Reward,
    RewardPayrollLinkProposalService as Proposal,
    RewardPayrollAllocationService as Allocation,
    RewardSettlementPreflightService as Settlement,
    PayrollPerformanceService as Payroll
};
use ExcelHerbal\ERP7\Security\{Actor,Capabilities as C};

if(getenv('EH7_INTEGRATION_MODE')!=='synthetic'||
   !str_starts_with((string)getenv('EH7_MARIADB_DATABASE'),'eh7_test_')){
    fwrite(STDERR,"REFUSED: disposable eh7_test_* MariaDB only\n");exit(2);
}
$db=eh7_setup_global_db();
$tables=[
    'audit_log','payroll_editors','reward_payroll_allocations',
    'reward_payroll_link_proposals','reward_adjustments',
    'payroll_items','payroll_runs','employees','branches','companies',
];
$definitions=Schema::definitions();
foreach($tables as $name){
    if($db->query('DROP TABLE IF EXISTS '.Db::table($name))===false)
        throw new RuntimeException('Drop failed '.$name.' '.$db->last_error);
}
foreach(array_reverse($tables) as $name){
    if(!isset($definitions[$name])||
       $db->query('CREATE TABLE '.Db::table($name).' ('.$definitions[$name].
            ') ENGINE=InnoDB DEFAULT CHARSET=utf8mb4')===false)
        throw new RuntimeException('Create failed '.$name.' '.$db->last_error);
}
function allocSeed(string $name,array $row):int{
    Db::mustInsert(Db::wpdb(),Db::table($name),$row);
    return (int)Db::wpdb()->insert_id;
}
function allocAssert(bool $good,string $name):void{
    if(!$good)throw new RuntimeException('ALLOCATION FAIL '.$name);
    echo "PASS ".$name."\n";
}
function allocDenied(callable $action,string $code):void{
    try{$action();}catch(DomainException $e){
        allocAssert($e->codeKey===$code,'deny '.$code);
        return;
    }
    throw new RuntimeException('Expected denial '.$code);
}
$now=Db::now();
$today=Db::today();
allocSeed('companies',[
    'id'=>1,'name'=>'Synthetic Reward Allocation','status'=>'active',
    'created_at'=>$now,
]);
foreach([[1,'B1'],[2,'B2']] as [$id,$code]){
    allocSeed('branches',[
        'id'=>$id,'company_id'=>1,'code'=>$code,
        'name'=>'Synthetic '.$code,'status'=>'active','created_at'=>$now,
    ]);
}
foreach([
    [11,'SALES',20],[20,'SM',null],[30,'SYSADMIN',null],
    [40,'SYSADMIN',null],
] as [$id,$code,$supervisor]){
    allocSeed('employees',[
        'id'=>$id,'company_id'=>1,'employee_code'=>'A'.$id,
        'designation_code'=>$code,'assigned_branch_id'=>1,
        'reporting_employee_id'=>$supervisor,
        'full_name'=>'Synthetic '.$id,
        'monthly_salary'=>'9000.00','joining_date'=>'2020-01-01',
        'status'=>'active','created_at'=>$now,
    ]);
}
$maker=new Actor(20,20,1,1,[1],[C::REWARDS_MANAGE],'SM');
$checker=new Actor(30,30,1,1,[1],[C::REWARDS_APPROVE],'SYSADMIN');
$linker=new Actor(30,30,1,1,[1],
    [C::REWARDS_APPROVE,C::PAYROLL_GENERATE],'SYSADMIN');
$allocator=new Actor(40,40,1,1,[1],
    [C::REWARDS_APPROVE,C::PAYROLL_GENERATE],'SYSADMIN');
$wrongBranch=new Actor(40,40,1,2,[2],
    [C::REWARDS_APPROVE,C::PAYROLL_GENERATE],'SYSADMIN');
$inspector=new Actor(40,40,1,1,[1],
    [C::REWARDS_APPROVE,C::PAYROLL_PAY],'SYSADMIN');

$reward=Reward::create($maker,[
    'branch_id'=>1,'employee_id'=>11,'adjustment_type'=>'bonus',
    'amount'=>'155.25','points'=>'1.00',
    'reason'=>'Evidence-backed synthetic achievement bonus',
]);
$rewardId=(int)$reward['id'];
Reward::decide($checker,$rewardId,'approved');
$run=allocSeed('payroll_runs',[
    'company_id'=>1,'branch_id'=>1,
    'period_start'=>$today,'period_end'=>$today,
    'calculation_version'=>'7.3.5',
    'status'=>'draft','created_by'=>30,'created_at'=>$now,
]);
$item=allocSeed('payroll_items',[
    'payroll_run_id'=>$run,'employee_id'=>11,
    'fixed_salary'=>'9000.00','attendance_salary'=>'9000.00',
    'salary_fund_earning'=>'0.00','allowances'=>'10.20',
    'deductions'=>'5.10','bonus'=>'0.00','net_salary'=>'9005.10',
]);
$link=Proposal::create($linker,$rewardId,$run,$item,
    'Reviewed candidate for independently controlled draft payroll');
$linkId=(int)$link['id'];

allocDenied(fn()=>Allocation::allocate($wrongBranch,$linkId),
    'branch_forbidden');
allocDenied(fn()=>Allocation::allocate($linker,$linkId),
    'maker_checker_required');
$allocated=Allocation::allocate($allocator,$linkId);
allocAssert($allocated['status']==='allocated_unpaid'&&
    $allocated['allocated_amount']==='155.25'&&
    $allocated['net_salary']==='9160.35'&&
    $allocated['payment_posted']===false,
    'approved reward enters payroll earnings, not payment');
$line=$db->get_row($db->prepare(
    'SELECT bonus,net_salary FROM '.Db::table('payroll_items').
    ' WHERE id=%d',$item
),ARRAY_A);
allocAssert($line['bonus']==='155.25'&&$line['net_salary']==='9160.35',
    'bonus and net salary increased exactly once, preserving allowances');
allocAssert((int)$db->get_var($db->prepare(
    'SELECT COUNT(*) FROM '.Db::table('payroll_editors').
    ' WHERE payroll_run_id=%d AND employee_id=%d',$run,40
))===1,'allocation actor barred from later payroll checker approval');
allocDenied(fn()=>Allocation::allocate($allocator,$linkId),
    'reward_payroll_proposal_state_invalid');
allocDenied(fn()=>Payroll::updateItem($allocator,$run,$item,200,0,0),
    'reward_payroll_item_locked');
allocDenied(fn()=>Payroll::discardDraft($allocator,$run,
    'Cannot destroy documented reward allocations'),
    'reward_payroll_draft_locked');
Allocation::assertRunInvariant($db,1,$run);
$preflight=Settlement::inspect($inspector,$rewardId);
allocAssert($preflight['reward_payroll_allocation_verified']===true&&
    $preflight['allocated_payroll_earnings']['draft_earnings_allocation_verified']===true&&
    $preflight['payment_ready']===false&&
    $preflight['payment_posted']===false&&
    $preflight['settled']===false,
    'finance sees verified draft allocation but no payout proof');
allocAssert((string)$db->get_var($db->prepare(
    'SELECT monthly_salary FROM '.Db::table('employees').' WHERE id=%d',11
))==='9000.00','fixed salary and employee rights were not changed');
allocAssert((int)$db->get_var('SELECT COUNT(*) FROM '.Db::table('reward_payroll_allocations'))===1,
    'exactly one immutable per-reward allocation record exists');
$ledger=$db->get_row('SELECT * FROM '.Db::table('reward_payroll_allocations').
    ' LIMIT 1',ARRAY_A);
unset($ledger['id']);
allocDenied(fn()=>Db::mustInsert($db,Db::table('reward_payroll_allocations'),
    $ledger,'Reward duplicate','reward_payroll_allocation_duplicate'),
    'reward_payroll_allocation_duplicate');
Db::mustUpdate($db,Db::table('payroll_items'),[
    'net_salary'=>'9160.34',
],['id'=>$item]);
allocDenied(fn()=>Allocation::assertRunInvariant($db,1,$run),
    'reward_payroll_allocation_drift');
$stale=Settlement::inspect($inspector,$rewardId);
allocAssert($stale['reward_payroll_allocation_verified']===false&&
    in_array('reward_payroll_allocation_drift',
        $stale['blocking_reason_codes'],true),
    'stale payroll net invalidates reward allocation evidence');
Db::mustUpdate($db,Db::table('payroll_items'),[
    'net_salary'=>'9160.35',
],['id'=>$item]);
Allocation::assertRunInvariant($db,1,$run);
allocAssert((int)$db->get_var(
    'SELECT COUNT(*) FROM '.Db::table('audit_log').
    " WHERE action='reward.payroll_allocated'"
)===1,'one independently authorized allocation audit entry');
allocAssert((int)$db->get_var($db->prepare(
    'SELECT COUNT(*) FROM '.Db::table('payroll_runs').
    ' WHERE id=%d AND status=%s',$run,'draft'
))===1,'payroll still draft; no journal or payout was posted');
echo "PASSED disposable MariaDB bonus allocation, duplicate, scope, manual-edit lock, discard protection, drift audit and no payout\n";
