<?php
/** Pure Promotion/Increment review contract — no live employee/ledger writes. */
if(!function_exists('current_time')){function current_time(string $format,bool $gmt=false):string{
    return $format==='Y-m-d'?'2026-11-03':'2026-11-03 12:00:00';
}}
require_once __DIR__.'/../src/Core/Autoloader.php';
\ExcelHerbal\ERP7\Core\Autoloader::register(__DIR__.'/../src');

use ExcelHerbal\ERP7\Payroll\PromotionReviewService as Promotion;
use ExcelHerbal\ERP7\Domain\DomainException;
use ExcelHerbal\ERP7\Http\{RouteRegistry,ApiContract};
use ExcelHerbal\ERP7\Database\Schema;
use ExcelHerbal\ERP7\Security\Capabilities as C;

function promoPass(bool $success,string $label):void {
    if(!$success){fwrite(STDERR,"FAIL ".$label."\n");exit(1);}
    echo "PASS ".$label."\n";
}
function promoFail(callable $fn,string $code):void {
    try{$fn();}catch(DomainException $e){
        promoPass($e->codeKey===$code,'rejects '.$code);return;
    }
    promoPass(false,'expected '.$code);
}
$proposal=[
    'next_designation_code'=>'sm',
    'monthly_increment_amount'=>'125.75',
    'effective_from'=>'2026-11-03',
    'reason'=>'Qualified branch promotion review request',
];
$valid=Promotion::payload($proposal);
promoPass($valid['next_designation_code']==='SM'&&
    $valid['monthly_increment_amount']==='125.75'&&
    $valid['effective_from']==='2026-11-03',
    'promotion code canonicalized, money exact in integer paise, date valid');
promoPass(Promotion::payload(array_replace($proposal,[
    'monthly_increment_amount'=>0,
]))['monthly_increment_amount']==='0.00',
    'designation-only review can have zero monthly increment');
promoFail(fn()=>Promotion::payload(array_replace($proposal,[
    'monthly_increment_amount'=>'1.234',
])),'salary_structure_amount_invalid');
promoFail(fn()=>Promotion::payload(array_replace($proposal,[
    'effective_from'=>'2026-11-02',
])),'promotion_effective_date_invalid');
promoFail(fn()=>Promotion::payload(array_replace($proposal,[
    'next_designation_code'=>'invalid-designation',
])),'promotion_designation_invalid');
promoFail(fn()=>Promotion::payload(array_replace($proposal,[
    'reason'=>'No',
])),'promotion_reason_invalid');

$spec=Schema::definitions();
promoPass(Schema::VERSION==='7.3.12-reward-payroll-allocated-6'&&
    isset($spec['promotion_requests'])&&
    str_contains($spec['promotion_requests'],'eligibility_state')&&
    str_contains($spec['promotion_requests'],'execution_state')&&
    str_contains($spec['promotion_requests'],'maker_review'),
    'additive schema tracks eligibility and no-execution state');
promoPass(C::PROMOTION_VIEW==='promotion.view'&&
    C::PROMOTION_REQUEST==='promotion.request'&&
    C::PROMOTION_APPROVE==='promotion.approve',
    'promotions use separate explicit read, request and review capabilities');
$expected=[
    ['GET','/performance/promotion-employees','performance.promotion_employees',[]],
    ['GET','/performance/promotions','performance.promotions',[]],
    ['POST','/performance/promotions','performance.promotion_create',
     ['branch_id','employee_id','next_designation_code',
      'monthly_increment_amount','effective_from','reason']],
    ['POST','/performance/promotions/(?P<id>\\d+)/decision',
     'performance.promotion_decision',['decision']],
];
$registered=RouteRegistry::routes();
$described=ApiContract::describe()['routes'];
foreach($expected as [$method,$path,$handler,$required]){
    promoPass(count(array_filter($registered,static fn($row)=>
        $row[0]===$method&&$row[1]===$path&&
        $row[2]===$handler&&$row[3]===true))===1,
        'authenticated '.$handler);
    promoPass(count(array_filter($described,static fn($row)=>
        $row['method']===$method&&$row['path']===$path&&
        $row['auth']===true&&$row['required_params']===$required&&
        $row['idempotency_required']===($method==='POST')))===1,
        'mandatory request and idempotency contract '.$handler);
}
promoPass(count(array_filter($registered,static fn($row)=>
    $row[0]==='GET'&&
    $row[1]==='/performance/promotions/(?P<id>\\d+)/eligibility-evidence'&&
    $row[2]==='performance.promotion_eligibility_evidence'&&$row[3]===true))===1,
    'read-only authenticated HR eligibility evidence route');
promoPass(count(array_filter($described,static fn($row)=>
    $row['method']==='GET'&&
    $row['path']==='/performance/promotions/(?P<id>\\d+)/eligibility-evidence'&&
    $row['idempotency_required']===false&&
    $row['auth']===true))===1,
    'HR eligibility evidence contract never requests mutation idempotency');
$eligibilitySource=file_get_contents(
    __DIR__.'/../src/Payroll/PromotionEligibilityEvidenceService.php'
);
foreach(['Db::mustInsert(','Db::mustUpdate(','AccountingService::post(',
         "Db::table('employee_roles')",
         "Db::table('employee_designation_assignments')",
         "Db::table('salary_revisions')"] as $unsafe){
    promoPass(!str_contains($eligibilitySource,$unsafe),
        'eligibility preflight does not apply HR/financial changes '.$unsafe);
}
promoPass(str_contains($eligibilitySource,'promotion_points_qualifying_window_unapproved')&&
    str_contains($eligibilitySource,'promotion_minimum_days_policy_unapproved')&&
    str_contains($eligibilitySource,'execution_ready'),
    'unapproved policy window and service-day definition block execution');
$service=file_get_contents(__DIR__.'/../src/Payroll/PromotionReviewService.php');
foreach(["Db::table('employee_designation_assignments')",
          "Db::table('salary_revisions')",
          "Db::table('payroll_items')",
          "Db::table('performance_entries')",
          "Db::table('employee_roles')",
          "Db::table('journal_entries')",
          'AccountingService::post('] as $forbidden){
    promoPass(!str_contains($service,$forbidden),
        'review does not perform HR/financial execution '.$forbidden);
}
promoPass(str_contains($service,'Capabilities::HR_REVIEW')&&
    str_contains($service,'maker_checker_required')&&
    str_contains($service,'approved_pending_execution'),
    'independent HR checker and pending-execution status enforced');
echo "PASSED pure Promotion review-only money, authority, routes and zero-privilege effects\n";
