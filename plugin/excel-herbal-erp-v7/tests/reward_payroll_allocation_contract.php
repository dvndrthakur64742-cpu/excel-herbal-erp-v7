<?php
/** Immutable reward-to-payroll draft allocation and path-safety contracts. */
require_once __DIR__.'/../src/Core/Autoloader.php';
\ExcelHerbal\ERP7\Core\Autoloader::register(__DIR__.'/../src');

use ExcelHerbal\ERP7\Database\Schema;
use ExcelHerbal\ERP7\Http\{RouteRegistry,ApiContract};

function arPass(bool $yes,string $label):void {
    if(!$yes){fwrite(STDERR,"FAIL ".$label."\n");exit(1);}
    echo "PASS ".$label."\n";
}
$path='/performance/reward-payroll-link-proposals/(?P<id>\\d+)/allocate';
$routes=RouteRegistry::routes();
$api=ApiContract::describe()['routes'];
arPass(count(array_filter($routes,static fn($r)=>
    $r[0]==='POST'&&$r[1]===$path&&
    $r[2]==='performance.reward_payroll_allocate'&&$r[3]===true
))===1,'independent allocation is an authenticated action');
arPass(count(array_filter($api,static fn($r)=>
    $r['method']==='POST'&&$r['path']===$path&&
    $r['auth']===true&&$r['idempotency_required']===true&&
    $r['required_params']===[]
))===1,'allocation inherits idempotency, never a direct Pay endpoint');
$schema=Schema::definitions();
arPass(Schema::VERSION==='7.3.12-reward-payroll-allocated-6',
    'allocation migration version is current');
$allocation=$schema['reward_payroll_allocations']??'';
foreach([
    'UNIQUE KEY uq_reward_allocation(company_id,reward_id)',
    'UNIQUE KEY uq_payroll_item_allocation(company_id,payroll_item_id)',
    'UNIQUE KEY uq_proposal_allocation(company_id,proposal_id)',
    "status VARCHAR(35) NOT NULL DEFAULT 'allocated_unpaid'",
] as $required){
    arPass(str_contains($allocation,$required),
        'unique immutable allocation contract '.$required);
}
$service=file_get_contents(
    __DIR__.'/../src/Payroll/RewardPayrollAllocationService.php'
);
foreach([
    'Capabilities::REWARDS_APPROVE',
    'Capabilities::PAYROLL_GENERATE',
    'SalaryService::lockCompany',
    'maker_checker_required',
    'reward_payroll_bonus_conflict',
    'reward_payroll_allocation_duplicate',
    'reward_payroll_allocation_drift',
    'RewardPayrollAllocationService', // class name present
    "'status'=>'allocated_unpaid'",
    "'payment_posted'=>false",
    "'settled'=>false",
] as $required){
    arPass(str_contains($service,$required),
        'allocator enforces '.$required);
}
foreach([
    'AccountingService::post(',
    "Db::table('journal_entries')",
    "Db::table('performance_entries')",
    'StockService::move(',
] as $forbidden){
    arPass(!str_contains($service,$forbidden),
        'allocation never posts ledger/points/bank '.$forbidden);
}
$payroll=file_get_contents(
    __DIR__.'/../src/Payroll/PayrollPerformanceService.php'
);
arPass(substr_count($payroll,'RewardPayrollAllocationService::assertDraftDiscardable(')>=2,
    'regenerate and discard cannot erase allocated payroll');
arPass(str_contains($payroll,'RewardPayrollAllocationService::assertItemUnlocked('),
    'manual payroll editor cannot change rewarded payroll item');
arPass(substr_count($payroll,'RewardPayrollAllocationService::assertRunInvariant(')>=2,
    'payroll approval and payout independently recheck immutable reward allocation');
arPass(!count(array_filter($routes,static fn($r)=>
    $r[0]==='POST'&&
    $r[1]==='/performance/rewards/(?P<id>\\d+)/pay')),
    'direct reward payment remains blocked');
echo "PASSED immutable reward allocation, safe payroll paths and zero-direct-payout contract\n";
