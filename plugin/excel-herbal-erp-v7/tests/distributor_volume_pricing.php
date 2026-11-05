<?php
require_once __DIR__.'/../src/Domain/DomainException.php';
require_once __DIR__.'/../src/Policy/DistributorVolumePricing.php';
use ExcelHerbal\ERP7\Policy\DistributorVolumePricing;
use ExcelHerbal\ERP7\Domain\DomainException;

function eq(mixed $actual,mixed $expected,string $name):void{
    if($actual!==$expected){fwrite(STDERR,"FAIL $name ".json_encode($actual)."\n");exit(1);}
    echo "PASS $name\n";
}
function reject(callable $fn,string $code):void{
    try{$fn();}catch(DomainException $e){eq($e->codeKey,$code,$code);return;}
    fwrite(STDERR,"FAIL missing exception $code\n");exit(1);
}
$slabs=[
  ['id'=>1,'min_qty'=>'1','max_qty'=>'9','unit_price'=>'500.00'],
  ['id'=>2,'min_qty'=>'10','max_qty'=>'49','unit_price'=>'470.00'],
  ['id'=>3,'min_qty'=>'50','max_qty'=>null,'unit_price'=>'440.00']
];
eq(DistributorVolumePricing::quote(1,$slabs)['line_total'],'500.00','first quantity slab');
eq(DistributorVolumePricing::quote(10,$slabs)['unit_price'],'470.00','slab boundary');
eq(DistributorVolumePricing::quote(49,$slabs)['slab_id'],2,'last quantity in middle slab');
eq(DistributorVolumePricing::quote(50,$slabs)['unit_price'],'440.00','unbounded quantity slab');
eq(DistributorVolumePricing::quote(60,$slabs)['line_total'],'26400.00','per-order price on all 60 units');
eq(DistributorVolumePricing::quote(60,array_reverse($slabs))['line_total'],'26400.00','unsorted slabs resolved correctly');
eq(DistributorVolumePricing::quote(3,[['id'=>7,'min_qty'=>1,'max_qty'=>null,'unit_price'=>'0.75']])['line_total'],'2.25','currency minor unit exact');
reject(fn()=>DistributorVolumePricing::quote(0,$slabs),'quantity_invalid');
reject(fn()=>DistributorVolumePricing::quote(3,[]),'price_slabs_missing');
reject(fn()=>DistributorVolumePricing::quote(8,[
  ['id'=>1,'min_qty'=>1,'max_qty'=>9,'unit_price'=>'500.00'],
  ['id'=>2,'min_qty'=>9,'max_qty'=>20,'unit_price'=>'490.00']
]),'price_slabs_overlap');
reject(fn()=>DistributorVolumePricing::quote(10,[
  ['id'=>1,'min_qty'=>1,'max_qty'=>9,'unit_price'=>'500.00']
]),'price_slab_not_found');
reject(fn()=>DistributorVolumePricing::quote(2,[
  ['id'=>1,'min_qty'=>1,'max_qty'=>9,'unit_price'=>'10.999']
]),'price_slab_invalid');
reject(fn()=>DistributorVolumePricing::quote(2,[
  ['id'=>1,'min_qty'=>1,'max_qty'=>9,'unit_price'=>'-10.00']
]),'price_slab_invalid');
echo "PASS distributor volume slab quote engine (pure, no invoice posting)\n";
