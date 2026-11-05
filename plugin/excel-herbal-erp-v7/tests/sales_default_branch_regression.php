<?php
/** Live observed Sales Orders 403 regression: omitted branch defaults to actor.
 * No database, staff login, or production requests are involved.
 */
declare(strict_types=1);
require_once __DIR__.'/../src/Core/Autoloader.php';
\ExcelHerbal\ERP7\Core\Autoloader::register(__DIR__.'/../src');
use ExcelHerbal\ERP7\Http\ApiDispatch;
use ExcelHerbal\ERP7\Security\Actor;
use ExcelHerbal\ERP7\Security\Capabilities;
use ExcelHerbal\ERP7\Domain\DomainException;
function checkSales(bool $result,string $msg):void {
  if(!$result){fwrite(STDERR,"FAIL ".$msg."\n");exit(1);}
}
$actor=new Actor(10,11,1,4,[4,7],[Capabilities::SALES_VIEW],'BM');
$ref=new ReflectionMethod(ApiDispatch::class,'readBranch');
$request=new class {
 public ?string $branchId=null;
 public function get_param($key){return $key==='branch_id'?$this->branchId:null;}
};
checkSales($ref->invoke(null,$request,$actor)===4,'missing branch must use current authorized assigned branch');
$request->branchId='';
checkSales($ref->invoke(null,$request,$actor)===4,'blank branch must use current authorized assigned branch');
$request->branchId='7';
checkSales($ref->invoke(null,$request,$actor)===7,'explicit authorized branch must remain selectable');
$request->branchId='99';
checkSales($ref->invoke(null,$request,$actor)===99,'explicit unauthorized branch must not be silently changed');
$request->branchId=null;
\ExcelHerbal\ERP7\Http\ApiContract::validate('sales.return_list',$request,'GET');
$request->branchId='not-a-branch';
try {
  \ExcelHerbal\ERP7\Http\ApiContract::validate('sales.return_list',$request,'GET');
  checkSales(false,'invalid branch token must fail API validation');
} catch(DomainException $e) {
  checkSales($e->codeKey==='parameter_invalid','invalid branch has wrong error');
}
$request->branchId='99';
try {
  \ExcelHerbal\ERP7\Sales\PrepaidOrderService::list($actor,99);
  checkSales(false,'unauthorized branch must be forbidden by sales service');
} catch(DomainException $e) {
  checkSales($e->codeKey==='branch_forbidden'&&$e->httpStatus===403,'incorrect unauthorized branch error');
}
$source=file_get_contents(__DIR__.'/../src/Http/ApiDispatch.php');
foreach([
 "'sales.order_list'=>\\ExcelHerbal\\ERP7\\Sales\\PrepaidOrderService::list(\$a,self::readBranch(\$r,\$a)",
 "'sales.return_list'=>\\ExcelHerbal\\ERP7\\Sales\\PrepaidReturnService::list(\$a,self::readBranch(\$r,\$a))",
 "'sales.payment_accounts'=>\\ExcelHerbal\\ERP7\\Sales\\PrepaidOrderService::paymentAccounts(\$a,self::readBranch(\$r,\$a))"
] as $contract) {
 checkSales(str_contains($source,$contract),'sales list dispatcher must use branch-safe fallback');
}
echo "PASS Sales GET defaults to assigned branch without bypassing scope\n";
echo "PASS explicit unauthorized sales branch still returns 403\n";
echo "PASS Orders, Returns and Payment Accounts follow shared branch selection\n";
