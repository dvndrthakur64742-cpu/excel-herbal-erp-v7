<?php
/**
 * Disposable real-MariaDB test of promotion review and ZERO effective changes.
 * Refuses all databases except EH7 synthetic eh7_test_*.
 */
define('EH7_INTEGRATION_LIBRARY_ONLY',true);
require __DIR__.'/integration_mariadb.php';
require_once __DIR__.'/../src/Core/Autoloader.php';
\ExcelHerbal\ERP7\Core\Autoloader::register(__DIR__.'/../src');

use ExcelHerbal\ERP7\Database\{Db,Schema};
use ExcelHerbal\ERP7\Domain\DomainException;
use ExcelHerbal\ERP7\Payroll\PromotionReviewService as Promotion;
use ExcelHerbal\ERP7\Security\{Actor,Capabilities as C};

if(getenv('EH7_INTEGRATION_MODE')!=='synthetic'||
    !str_starts_with((string)getenv('EH7_MARIADB_DATABASE'),'eh7_test_')){
    fwrite(STDERR,"REFUSED: disposable synthetic database only\n");
    exit(2);
}
$db=eh7_setup_global_db();
$names=['audit_log','promotion_requests','designations',
        'employees','branches','companies'];
$defs=Schema::definitions();
foreach($names as $name){
    if($db->query('DROP TABLE IF EXISTS '.Db::table($name))===false)
        throw new RuntimeException('Drop failed '.$name.': '.$db->last_error);
}
foreach(array_reverse($names) as $name){
    if(!isset($defs[$name])||$db->query(
        'CREATE TABLE '.Db::table($name).' ('.$defs[$name].
        ') ENGINE=InnoDB DEFAULT CHARSET=utf8mb4'
    )===false)throw new RuntimeException('Create failed '.$name.' '.$db->last_error);
}
function promoSeed(string $name,array $record):int{
    Db::mustInsert(Db::wpdb(),Db::table($name),$record);
    return (int)Db::wpdb()->insert_id;
}
function promoCheck(bool $ok,string $message):void{
    if(!$ok)throw new RuntimeException('PROMOTION FAIL '.$message);
    echo "PASS ".$message."\n";
}
function promoDenied(callable $fn,string $code):void{
    try{$fn();}catch(DomainException $e){
        promoCheck($e->codeKey===$code,'reject '.$code);return;
    }
    throw new RuntimeException('Expected '.$code);
}
$now=Db::now();
$today=Db::today();
promoSeed('companies',['id'=>1,'name'=>'Synthetic Promotion Company',
    'status'=>'active','created_at'=>$now]);
foreach([[1,'B1'],[2,'B2']] as [$branch,$code]) {
    promoSeed('branches',['id'=>$branch,'company_id'=>1,'code'=>$code,
        'name'=>'Synthetic '.$code,'status'=>'active','created_at'=>$now]);
}
foreach([[11,'SALES',20],[20,'SM',null],[30,'SYSADMIN',null]] as [$id,$code,$manager]){
    promoSeed('employees',[
        'id'=>$id,'company_id'=>1,'employee_code'=>'P'.$id,
        'designation_code'=>$code,'assigned_branch_id'=>1,
        'reporting_employee_id'=>$manager,'full_name'=>'Synthetic '.$id,
        'monthly_salary'=>'9000.00','joining_date'=>'2020-01-01',
        'status'=>'active','created_at'=>$now,
    ]);
}
foreach([['SALES',10],['SM',20],['ASM',15]] as [$code,$seq]){
    promoSeed('designations',[
        'company_id'=>1,'code'=>$code,'name'=>$code,
        'sequence_no'=>$seq,'promotion_min_points'=>'200.00',
        'minimum_days'=>90,'status'=>'active',
    ]);
}
$maker=new Actor(20,20,1,1,[1],[C::PROMOTION_REQUEST],'SM');
$checker=new Actor(30,30,1,1,[1],
    [C::PROMOTION_APPROVE,C::HR_REVIEW],'SYSADMIN');
$makerChecker=new Actor(20,20,1,1,[1],
    [C::PROMOTION_REQUEST,C::PROMOTION_APPROVE,C::HR_REVIEW],'SM');
$beneficiary=new Actor(11,11,1,1,[1],
    [C::PROMOTION_REQUEST,C::PROMOTION_APPROVE,C::HR_REVIEW],'SALES');
$noHr=new Actor(30,30,1,1,[1],[C::PROMOTION_APPROVE],'SYSADMIN');
$outsider=new Actor(30,30,1,2,[2],
    [C::PROMOTION_APPROVE,C::HR_REVIEW],'SYSADMIN');
$viewer=new Actor(30,30,1,1,[1],[C::PROMOTION_VIEW],'SYSADMIN');
$request=[
    'branch_id'=>1,'employee_id'=>11,
    'next_designation_code'=>'ASM',
    'monthly_increment_amount'=>'500.05',
    'effective_from'=>$today,
    'reason'=>'Review designation and monthly increment proposal',
];
promoDenied(fn()=>Promotion::create($beneficiary,$request),
    'promotion_self_forbidden');
$choices=Promotion::employeeChoices($maker,1);
promoCheck(count($choices)===1&&(int)$choices[0]['id']===11&&
    !isset($choices[0]['monthly_salary']),
    'promotion picker contains only authorized colleagues and no pay fields');
$created=Promotion::create($maker,$request);
$id=(int)$created['id'];
promoCheck($id>0&&$created['status']==='pending'&&
    $created['executed']===false&&$created['eligibility_verified']===false,
    'promotion request remains nonexecuting and eligibility unverified');
$row=$db->get_row($db->prepare(
    'SELECT * FROM '.Db::table('promotion_requests').' WHERE id=%d',$id
),ARRAY_A);
promoCheck($row['current_designation_code']==='SALES'&&
    $row['next_designation_code']==='ASM'&&
    $row['minimum_days_snapshot']==90&&
    $row['promotion_min_points_snapshot']==='200.00'&&
    $row['monthly_increment_amount']==='500.05',
    'proposal retains designation and policy threshold snapshots');
promoDenied(fn()=>Promotion::create($maker,$request),'promotion_pending_exists');
promoDenied(fn()=>Promotion::decide($makerChecker,$id,'approved'),
    'maker_checker_required');
promoDenied(fn()=>Promotion::decide($beneficiary,$id,'approved'),
    'maker_checker_required');
promoDenied(fn()=>Promotion::decide($noHr,$id,'approved'),
    'permission_denied');
promoDenied(fn()=>Promotion::decide($outsider,$id,'approved'),
    'branch_forbidden');
promoDenied(fn()=>Promotion::decide($checker,$id,'paid'),
    'promotion_decision_invalid');
$decision=Promotion::decide($checker,$id,'approved');
promoCheck($decision['status']==='approved_pending_execution'&&
    $decision['executed']===false&&
    $decision['roles_changed']===false&&
    $decision['payroll_posted']===false&&
    $decision['eligibility_verified']===false,
    'independent HR review records approval but never executes promotion');
$unchanged=$db->get_row('SELECT designation_code,monthly_salary,assigned_branch_id,reporting_employee_id'.
    ' FROM '.Db::table('employees').' WHERE id=11',ARRAY_A);
promoCheck($unchanged['designation_code']==='SALES'&&
    $unchanged['monthly_salary']==='9000.00'&&
    (int)$unchanged['assigned_branch_id']===1&&
    (int)$unchanged['reporting_employee_id']===20,
    'approved review leaves designation, pay, branch and reporting tree unchanged');
promoDenied(fn()=>Promotion::decide($checker,$id,'rejected'),
    'promotion_state_invalid');
promoDenied(fn()=>Promotion::create($maker,$request),'promotion_pending_exists');
$rows=Promotion::list($viewer,1);
promoCheck(count($rows)===1&&
    $rows[0]['status']==='approved_pending_execution'&&
    $rows[0]['employee_name']==='Synthetic 11',
    'reviewer sees approved-but-unexecuted proposal only in branch');
$events=$db->get_results('SELECT action,context_json FROM '.
    Db::table('audit_log').' ORDER BY id',ARRAY_A);
promoCheck(count($events)===2&&
    $events[0]['action']==='promotion.request'&&
    $events[1]['action']==='promotion.decision'&&
    str_contains((string)$events[1]['context_json'],'"salary_changed":false'),
    'review audit explicitly preserves nonexecuting status');
echo "PASSED real synthetic MariaDB promotion review and zero HR/payroll mutation\n";
