<?php
/**
 * Disposable InnoDB UAT for reward proposals, checker review and audit.
 * Refuses production or any unapproved DB name. Creates synthetic data only.
 */
define('EH7_INTEGRATION_LIBRARY_ONLY',true);
require __DIR__.'/integration_mariadb.php';
require_once __DIR__.'/../src/Core/Autoloader.php';
\ExcelHerbal\ERP7\Core\Autoloader::register(__DIR__.'/../src');

use ExcelHerbal\ERP7\Database\{Db,Schema};
use ExcelHerbal\ERP7\Domain\DomainException;
use ExcelHerbal\ERP7\Payroll\RewardAdjustmentService as Reward;
use ExcelHerbal\ERP7\Payroll\RewardSettlementPreflightService as Settlement;
use ExcelHerbal\ERP7\Security\{Actor,Capabilities as C};

$database=(string)(getenv('EH7_MARIADB_DATABASE')?:'');
if(getenv('EH7_INTEGRATION_MODE')!=='synthetic'||
    !str_starts_with($database,'eh7_test_')){
    fwrite(STDERR,"REFUSED: synthetic eh7_test_* database required\n");
    exit(2);
}
$db=eh7_setup_global_db();
$tables=['audit_log','reward_adjustments','payroll_items','payroll_runs',
    'employees','branches','companies'];
$schema=Schema::definitions();
foreach($tables as $table){
    if($db->query('DROP TABLE IF EXISTS '.Db::table($table))===false)
        throw new RuntimeException('Synthetic drop failed '.$table.' '.$db->last_error);
}
foreach(array_reverse($tables) as $table){
    if(!isset($schema[$table])||
        $db->query('CREATE TABLE '.Db::table($table).' ('.$schema[$table].
        ') ENGINE=InnoDB DEFAULT CHARSET=utf8mb4')===false)
        throw new RuntimeException('Synthetic create failed '.$table.' '.$db->last_error);
}
function rewardSeed(string $table,array $row):int{
    Db::mustInsert(Db::wpdb(),Db::table($table),$row);
    return (int)Db::wpdb()->insert_id;
}
function rewardAssert(bool $ok,string $reason):void{
    if(!$ok)throw new RuntimeException('REWARD FAIL '.$reason);
    echo "PASS ".$reason."\n";
}
function rewardFails(callable $fn,string $expected):void{
    try{$fn();}catch(DomainException $e){
        rewardAssert($e->codeKey===$expected,'deny '.$expected);return;
    }
    throw new RuntimeException('Expected denial '.$expected);
}
$now=Db::now();
rewardSeed('companies',[
    'id'=>1,'name'=>'Synthetic Rewards','status'=>'active','created_at'=>$now
]);
rewardSeed('branches',[
    'id'=>1,'company_id'=>1,'code'=>'B1','name'=>'Synthetic First Branch',
    'status'=>'active','created_at'=>$now
]);
rewardSeed('branches',[
    'id'=>2,'company_id'=>1,'code'=>'B2','name'=>'Synthetic Second Branch',
    'status'=>'active','created_at'=>$now
]);
foreach([[11,'EMPLOYEE',20],[20,'SM',null],[30,'SYSADMIN',null]] as [$id,$code,$manager]){
    rewardSeed('employees',[
        'id'=>$id,'company_id'=>1,'employee_code'=>'R'.$id,
        'designation_code'=>$code,'assigned_branch_id'=>1,
        'reporting_employee_id'=>$manager,'full_name'=>'Synthetic '.$id,
        'status'=>'active','created_at'=>$now,
    ]);
}
$maker=new Actor(20,20,1,1,[1],[C::REWARDS_MANAGE],'SM');
$checker=new Actor(30,30,1,1,[1],[C::REWARDS_APPROVE],'SYSADMIN');
$self=new Actor(11,11,1,1,[1],[C::REWARDS_MANAGE,C::REWARDS_APPROVE],'EMPLOYEE');
$otherBranch=new Actor(30,30,1,2,[2],[C::REWARDS_APPROVE],'SYSADMIN');
$viewer=new Actor(30,30,1,1,[1],[C::REWARDS_VIEW],'SYSADMIN');
$makerChecker=new Actor(20,20,1,1,[1],[C::REWARDS_MANAGE,C::REWARDS_APPROVE],'SM');
$input=[
    'branch_id'=>1,'employee_id'=>11,
    'adjustment_type'=>'bonus','amount'=>'155.25','points'=>'2.50',
    'reason'=>'Completed audited synthetic field target',
];
rewardFails(fn()=>Reward::create($self,$input),'reward_self_forbidden');
rewardFails(fn()=>Reward::create($viewer,$input),'permission_denied');
$choices=Reward::employeeChoices($maker,1);
rewardAssert(count($choices)===1&&(int)$choices[0]['id']===11&&
    !isset($choices[0]['monthly_salary']),
    'reward employee picker is limited to hierarchy and no salary data');
$created=Reward::create($maker,$input);
$id=(int)$created['id'];
rewardAssert($id>0&&$created['status']==='pending'&&
    $created['funds_posted']===false,'request stores pending with no money posted');
$record=$db->get_row($db->prepare(
    'SELECT * FROM '.Db::table('reward_adjustments').' WHERE id=%d',$id
),ARRAY_A);
rewardAssert($record['amount']==='155.25'&&$record['points']==='2.50'&&
    (int)$record['created_by']===20,'exact requested reward and original maker retained');
rewardFails(fn()=>Reward::decide($makerChecker,$id,'approved'),
    'maker_checker_required');
rewardFails(fn()=>Reward::decide($self,$id,'approved'),'maker_checker_required');
rewardFails(fn()=>Reward::decide($otherBranch,$id,'approved'),'branch_forbidden');
rewardFails(fn()=>Reward::decide($checker,$id,'paid'),'reward_decision_invalid');
$approved=Reward::decide($checker,$id,'approved');
rewardAssert($approved['status']==='approved'&&
    $approved['funds_posted']===false&&
    $approved['points_applied']===false&&
    $approved['payroll_linked']===false,
    'independent checker only approves register, never payroll or points');
rewardFails(fn()=>Reward::decide($checker,$id,'approved'),
    'reward_state_invalid');
$rows=Reward::list($viewer,1);
rewardAssert(count($rows)===1&&
    $rows[0]['employee_name']==='Synthetic 11'&&
    $rows[0]['status']==='approved',
    'branch-scoped review queue shows approved status');
// Even a paid payroll item with an identical bonus cannot prove this
// specific approved reward was allocated. No disbursement is performed.
$finance=new Actor(30,30,1,1,[1],
    [C::REWARDS_APPROVE,C::PAYROLL_PAY],'SYSADMIN');
$financeOutside=new Actor(30,30,1,2,[2],
    [C::REWARDS_APPROVE,C::PAYROLL_PAY],'SYSADMIN');
$financeMaker=new Actor(20,20,1,1,[1],
    [C::REWARDS_APPROVE,C::PAYROLL_PAY],'SM');
$financeBeneficiary=new Actor(11,11,1,1,[1],
    [C::REWARDS_APPROVE,C::PAYROLL_PAY],'EMPLOYEE');
rewardFails(fn()=>Settlement::inspect($checker,$id),
    'permission_denied');
rewardFails(fn()=>Settlement::inspect($financeOutside,$id),
    'branch_forbidden');
rewardFails(fn()=>Settlement::inspect($financeMaker,$id),
    'maker_checker_required');
rewardFails(fn()=>Settlement::inspect($financeBeneficiary,$id),
    'maker_checker_required');
$before=Settlement::inspect($finance,$id);
rewardAssert($before['payment_ready']===false&&
    $before['payment_posted']===false&&
    $before['reward_payroll_allocation_verified']===false&&
    in_array('reward_to_payroll_allocation_missing',
        $before['blocking_reason_codes'],true)&&
    $before['unattributed_paid_payroll_runs']===[],
    'reward preflight blocked without immutable payroll allocation');
$paidRun=rewardSeed('payroll_runs',[
    'company_id'=>1,'branch_id'=>1,
    'period_start'=>'2026-11-01','period_end'=>'2026-11-30',
    'status'=>'paid','payment_journal_entry_id'=>991,
    'created_by'=>30,'created_at'=>$now,
]);
rewardSeed('payroll_items',[
    'payroll_run_id'=>$paidRun,'employee_id'=>11,
    'bonus'=>'155.25','net_salary'=>'155.25',
]);
$after=Settlement::inspect($finance,$id);
rewardAssert($after['payment_ready']===false&&
    $after['settled']===false&&
    $after['unattributed_runs_are_payment_proof']===false&&
    count($after['unattributed_paid_payroll_runs'])===1&&
    (int)$after['unattributed_paid_payroll_runs'][0]['payroll_run_id']===$paidRun,
    'matching paid payroll amount remains unproven reward attribution');
rewardAssert((string)$db->get_var($db->prepare(
    'SELECT status FROM '.Db::table('reward_adjustments').' WHERE id=%d',$id
))==='approved',
    'read-only settlement preflight cannot mark reward paid');

$rejectedInput=$input;
$rejectedInput['adjustment_type']='points_adjustment';
$rejectedInput['amount']='0.00';
$rejectedInput['points']='-1.25';
$rejectedInput['reason']='Evidence-backed points correction requested';
$rejected=Reward::create($maker,$rejectedInput);
$result=Reward::decide($checker,(int)$rejected['id'],'rejected');
rewardAssert($result['status']==='rejected'&&
    $result['points_applied']===false,
    'negative points proposal can be rejected without effect');
$events=(array)$db->get_results('SELECT * FROM '.Db::table('audit_log').
    ' ORDER BY id',ARRAY_A);
rewardAssert(count($events)===4&&
    $events[0]['action']==='reward.request'&&
    $events[1]['action']==='reward.decision'&&
    $events[2]['action']==='reward.request'&&
    $events[3]['action']==='reward.decision',
    'only committed request and review events are audited');
rewardAssert(!empty($events[1]['context_json'])&&
    str_contains((string)$events[1]['context_json'],'"funds_posted":false'),
    'review audit explicitly states no funds posted');
echo "PASSED disposable MariaDB reward maker-checker, read scope, exact money and zero-posting UAT\n";
