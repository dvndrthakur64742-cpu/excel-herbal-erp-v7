<?php
/** Non-posting reward-to-payroll link proposals are distinct from payment. */
require_once __DIR__.'/../src/Core/Autoloader.php';
\ExcelHerbal\ERP7\Core\Autoloader::register(__DIR__.'/../src');

use ExcelHerbal\ERP7\Database\Schema;
use ExcelHerbal\ERP7\Http\{ApiContract,RouteRegistry};

function linkAssert(bool $ok,string $label):void {
    if(!$ok){fwrite(STDERR,"FAIL ".$label."\n");exit(1);}
    echo "PASS ".$label."\n";
}
$path='/performance/rewards/(?P<id>\\d+)/payroll-link-proposal';
$routes=RouteRegistry::routes();
$contract=ApiContract::describe()['routes'];
linkAssert(count(array_filter($routes,static fn($r)=>
    $r[0]==='POST'&&$r[1]===$path&&
    $r[2]==='performance.reward_payroll_link_proposal'&&
    $r[3]===true))===1,'authenticated link proposal route');
linkAssert(count(array_filter($contract,static fn($r)=>
    $r['method']==='POST'&&$r['path']===$path&&
    $r['auth']===true&&$r['idempotency_required']===true&&
    $r['required_params']===['payroll_run_id','payroll_item_id','reason']))===1,
    'required IDs, audit reason and idempotency contract');
$schema=Schema::definitions();
linkAssert(Schema::VERSION==='7.3.12-reward-payroll-allocated-6',
    'additive migration marker advanced');
linkAssert(isset($schema['reward_payroll_link_proposals'])&&
    str_contains($schema['reward_payroll_link_proposals'],
        'UNIQUE KEY uq_company_reward(company_id,reward_id)')&&
    str_contains($schema['reward_payroll_link_proposals'],
        "status VARCHAR(35) NOT NULL DEFAULT 'proposed_unfunded'")&&
    str_contains($schema['reward_payroll_link_proposals'],
        'payroll_item_id BIGINT UNSIGNED NOT NULL'),
    'one reward identity per company with explicit unfunded draft provenance');
$service=file_get_contents(
    __DIR__.'/../src/Payroll/RewardPayrollLinkProposalService.php'
);
foreach(['Capabilities::REWARDS_APPROVE','Capabilities::PAYROLL_GENERATE',
    'SalaryService::lockCompany(','FOR UPDATE','maker_checker_required',
    'reward_payroll_link_duplicate','reward_payroll_run_not_draft',
    'reward_payroll_item_mismatch','reward_payroll_link_proposals',
    "payroll_bonus_updated'=>false","payment_posted'=>false"] as $key){
    linkAssert(str_contains($service,$key),
        'link proposal fails closed for '.$key);
}
foreach(["Db::table('payroll_items')", "Db::table('reward_adjustments')"] as $table){
    // Reading these relations is required but writing is forbidden.
    linkAssert(str_contains($service,$table),'scope verifies '.$table);
}
foreach(["Db::mustUpdate(","AccountingService::post(","StockService::move(",
         "Db::table('journal_entries')","Db::table('performance_entries')"] as $unsafe){
    linkAssert(!str_contains($service,$unsafe),
        'candidate does not write payroll/finance/points '.$unsafe);
}
linkAssert(!count(array_filter($routes,static fn($r)=>
    $r[0]==='POST'&&
    $r[1]==='/performance/rewards/(?P<id>\\d+)/pay')),
    'direct reward payout remains intentionally unimplemented');
echo "PASSED proposed-unfunded reward/payroll linkage contracts\n";
