<?php
require __DIR__.'/../src/Core/Autoloader.php';
\ExcelHerbal\ERP7\Core\Autoloader::register(__DIR__.'/../src');
use ExcelHerbal\ERP7\Policy\FieldSalesRules;
use ExcelHerbal\ERP7\Domain\DomainException;
function eq($want,$actual,string $msg):void{if($want!==$actual)throw new RuntimeException($msg.' expected='.json_encode($want).' actual='.json_encode($actual));}
function rejects(callable $f,string $code):void{try{$f();}catch(DomainException $e){eq($code,$e->codeKey,'error code');return;}throw new RuntimeException('Expected error: '.$code);}
eq(35.,FieldSalesRules::retailQuantity(50.,15.,0.),'field sale issued-returned');
eq(25.,FieldSalesRules::retailQuantity(50.,15.,10.),'mixed retail and wholesale');
eq(0.,FieldSalesRules::retailQuantity(50.,50.,0.),'all stock returned');
rejects(fn()=>FieldSalesRules::retailQuantity(10,11,0),'evening_quantity_invalid');
rejects(fn()=>FieldSalesRules::retailQuantity(10,-1,0),'evening_quantity_invalid');
rejects(fn()=>FieldSalesRules::retailQuantity(10,1,10),'evening_quantity_invalid');
FieldSalesRules::requireFullPrepayment(1000,1000);
rejects(fn()=>FieldSalesRules::requireFullPrepayment(1000,900),'full_prepayment_required');
rejects(fn()=>FieldSalesRules::requireFullPrepayment(1000,1100),'full_prepayment_required');
FieldSalesRules::requireExactCollection(1000,600,400);
rejects(fn()=>FieldSalesRules::requireExactCollection(1000,600,399),'payment_mismatch');
rejects(fn()=>FieldSalesRules::requireExactCollection(1000,-1,1001),'payment_mismatch');
echo "PASSED field sales invariants (11 assertions)\n";
