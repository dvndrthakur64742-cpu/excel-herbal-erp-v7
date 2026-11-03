<?php
/** Synthetic reward approval and non-posting contract tests (no live SQL). */
require_once __DIR__.'/../src/Core/Autoloader.php';
\ExcelHerbal\ERP7\Core\Autoloader::register(__DIR__.'/../src');

use ExcelHerbal\ERP7\Payroll\RewardAdjustmentService as Reward;
use ExcelHerbal\ERP7\Domain\DomainException;
use ExcelHerbal\ERP7\Http\{ApiContract,RouteRegistry};
use ExcelHerbal\ERP7\Database\Schema;
use ExcelHerbal\ERP7\Security\Capabilities;

function rewardOkay(bool $okay,string $message):void{
    if(!$okay){fwrite(STDERR,"FAIL: ".$message."\n");exit(1);}
    echo "PASS ".$message."\n";
}
function rewardDenied(callable $fn,string $key):void{
    try{$fn();}catch(DomainException $e){
        rewardOkay($e->codeKey===$key,"reject ".$key);return;
    }
    rewardOkay(false,"expected rejection ".$key);
}
$base=[
    'adjustment_type'=>'bonus','amount'=>'190.25',
    'points'=>'1.50','reason'=>'Outstanding performance in this period',
];
$valid=Reward::payload($base);
rewardOkay($valid['amount']==='190.25'&&$valid['points']==='1.50',
    'money and points stored in integer hundredths');
rewardOkay(Reward::points('-0.01')==='-0.01','negative point scale exact');
rewardOkay(Reward::points('-0.00')==='0.00','negative zero normalized');
rewardDenied(fn()=>Reward::payload(array_replace($base,[
    'adjustment_type'=>'fraud',
])),'reward_type_invalid');
rewardDenied(fn()=>Reward::payload(array_replace($base,[
    'adjustment_type'=>'points_adjustment',
])),'reward_points_only');
rewardDenied(fn()=>Reward::payload(array_replace($base,[
    'adjustment_type'=>'recognition','points'=>'-1.00',
])),'reward_points_sign_invalid');
rewardDenied(fn()=>Reward::payload(array_replace($base,[
    'adjustment_type'=>'penalty','amount'=>'0.00','points'=>'0.00',
])),'reward_empty_invalid');
rewardDenied(fn()=>Reward::payload(array_replace($base,[
    'reason'=>'x',
])),'reward_reason_invalid');
rewardDenied(fn()=>Reward::payload(array_replace($base,[
    'amount'=>'0.001',
])),'salary_structure_amount_invalid');
rewardDenied(fn()=>Reward::points('1e5'),'reward_points_invalid');
rewardDenied(fn()=>Reward::points(INF),'reward_points_invalid');
rewardOkay(Reward::payload([
    'adjustment_type'=>'points_adjustment','amount'=>0,
    'points'=>'-2.35','reason'=>'Approved points correction',
])['points']==='-2.35','signed points-only correction requires explicit type');

$defs=Schema::definitions();
rewardOkay(Schema::VERSION==='7.3.12-reward-register-3'&&
    isset($defs['reward_adjustments'])&&
    str_contains($defs['reward_adjustments'],'maker_review')&&
    str_contains($defs['reward_adjustments'],'employee_status'),
    'additive reward table/version support audit and scope');
rewardOkay(Capabilities::REWARDS_VIEW==='rewards.view'&&
    Capabilities::REWARDS_MANAGE==='rewards.manage'&&
    Capabilities::REWARDS_APPROVE==='rewards.approve',
    'reward permissions distinct from payroll payouts');
$expected=[
    ['GET','/performance/reward-employees','performance.reward_employees',[]],
    ['GET','/performance/rewards','performance.rewards',[]],
    ['POST','/performance/rewards','performance.reward_create',
     ['branch_id','employee_id','adjustment_type','amount','points','reason']],
    ['POST','/performance/rewards/(?P<id>\\d+)/decision',
     'performance.reward_decision',['decision']],
];
$allRoutes=RouteRegistry::routes();
$api=ApiContract::describe()['routes'];
foreach($expected as [$method,$path,$handler,$required]){
    rewardOkay(count(array_filter($allRoutes,static fn($r)=>
        $r[0]===$method&&$r[1]===$path&&
        $r[2]===$handler&&$r[3]===true))===1,
        $handler.' is authenticated');
    rewardOkay(count(array_filter($api,static fn($r)=>
        $r['method']===$method&&$r['path']===$path&&
        $r['auth']===true&&$r['required_params']===$required&&
        $r['idempotency_required']===($method==='POST')))===1,
        $handler.' has exact API contract and idempotency');
}
$service=file_get_contents(__DIR__.'/../src/Payroll/RewardAdjustmentService.php');
foreach(['AccountingService::post(','StockService::move(','payPayroll(',
          "Db::table('performance_entries')","Db::table('payroll_items')"] as $bad){
    rewardOkay(!str_contains($service,$bad),
        'reward approval does not post money/points: '.$bad);
}
rewardOkay(!array_filter($allRoutes,static fn($r)=>
    $r[1]==='/performance/rewards/(?P<id>\\d+)/pay'),
    'unsupported reward payout route remains a release blocker');
echo "PASSED reward input, maker-checker contract and non-posting boundaries\n";
