<?php
require_once __DIR__.'/../src/Domain/DomainException.php';
require_once __DIR__.'/../src/Policy/PrepaidOrderRules.php';
use ExcelHerbal\ERP7\Domain\DomainException;
use ExcelHerbal\ERP7\Policy\PrepaidOrderRules as R;

function pass(string $label):void{echo "PASS $label\n";}
function check(mixed $actual,mixed $wanted,string $label):void{if($actual!==$wanted){fwrite(STDERR,"FAIL $label ".json_encode($actual)."\n");exit(1);}pass($label);}
function rejects(callable $fn,string $code):void{
    try{$fn();}catch(DomainException $e){check($e->codeKey,$code,$code);return;}
    fwrite(STDERR,"FAIL expected $code\n");exit(1);
}
check(R::minor('1.05'),105,'exact paise');
check(R::minor('0.01'),1,'one paisa');
check(R::format(123456),'1234.56','exact string formatting');
rejects(fn()=>R::minor('12.345'),'money_invalid');
rejects(fn()=>R::minor('-5'),'money_invalid');
rejects(fn()=>R::minor('1e3'),'money_invalid');
rejects(fn()=>R::minor(100.01),'money_invalid'); // no float parsing
$cash=['method'=>'cash','status'=>'confirmed','amount'=>'600.00'];
$upiPending=['method'=>'upi','status'=>'pending','amount'=>'400.00'];
$upiConfirmed=['method'=>'upi','status'=>'confirmed','amount'=>'400.00'];
rejects(fn()=>R::requireCovered(100000,[$cash,$upiPending]),'full_prepayment_required');
R::requireCovered(100000,[$cash,$upiConfirmed]);pass('full cash plus verified UPI allows invoice');
rejects(fn()=>R::requireCovered(100000,[['method'=>'upi','status'=>'pending','amount'=>'1000.00']]),'full_prepayment_required');
rejects(fn()=>R::requireCovered(100000,[['method'=>'credit','status'=>'confirmed','amount'=>'1000.00']]),'payment_mode_invalid');
rejects(fn()=>R::requireCovered(100000,[['method'=>'cash','status'=>'confirmed','amount'=>'1000.01']]),'payment_overpaid');
rejects(fn()=>R::requireCovered(0,[]),'order_amount_invalid');
check(R::discountAuthority(10000,0,null),'none','normal sale auto-approved');
rejects(fn()=>R::discountAuthority(10000,500,null),'discount_policy_unconfigured');
check(R::discountAuthority(10000,1000,'10.00'),'branch_manager','discount at configured cutoff');
check(R::discountAuthority(10000,1001,'10.00'),'head_office','discount above configured cutoff');
check(R::discountAuthority(10000,1,'0.00'),'head_office','zero cutoff escalates any discount');
rejects(fn()=>R::discountAuthority(10000,10000,'10.00'),'discount_invalid');
rejects(fn()=>R::discountAuthority(10000,1000,'101.00'),'discount_policy_invalid');
echo "PASSED prepaid order money/discount/payment gates\n";
