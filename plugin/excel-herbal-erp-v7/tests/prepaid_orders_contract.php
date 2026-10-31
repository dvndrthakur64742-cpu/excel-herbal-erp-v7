<?php
// Staging contract regression. Requires separate MariaDB + WordPress E2E before release.
require_once __DIR__.'/../src/Domain/DomainException.php';
require_once __DIR__.'/../src/Core/Input.php';
require_once __DIR__.'/../src/Http/RouteRegistry.php';
require_once __DIR__.'/../src/Http/ApiContract.php';
require_once __DIR__.'/../src/Database/Schema.php';

use ExcelHerbal\ERP7\Http\RouteRegistry;
use ExcelHerbal\ERP7\Http\ApiContract;
use ExcelHerbal\ERP7\Database\Schema;

function assertRule(bool $ok,string $label):void{
    if(!$ok){fwrite(STDERR,"FAIL: $label\n");exit(1);}
    echo "PASS $label\n";
}
$expected=[
    'sales.distributor_quote'=>'GET',
    'sales.distributor_slabs'=>'POST',
    'sales.discount_policy'=>'GET',
    'sales.discount_policy_set'=>'POST',
    'sales.payment_accounts'=>'GET',
    'sales.order_list'=>'GET',
    'sales.order_create'=>'POST',
    'sales.order_detail'=>'GET',
    'sales.discount_approve'=>'POST',
    'sales.order_collect'=>'POST',
    'sales.upi_verify'=>'POST',
    'sales.order_post'=>'POST',
];
$all=RouteRegistry::routes();
foreach($expected as $name=>$method){
    $matches=array_values(array_filter($all,static fn($r)=>$r[2]===$name&&$r[0]===$method&&$r[3]===true));
    assertRule(count($matches)===1,'auth-protected route '.$name);
}
$contract=ApiContract::describe();
$flags=$contract['features']??[];
foreach(['prepaid_sales_orders_v1','distributor_volume_price_list','discount_ho_threshold_fail_closed','independent_sales_upi_verification'] as $f){
    assertRule(($flags[$f]??false)===true,'API feature '.$f);
}
$tables=Schema::definitions();
foreach(['distributor_price_slabs','prepaid_sales_orders','prepaid_sales_order_lines','prepaid_sales_order_payments'] as $t){
    assertRule(isset($tables[$t])&&str_contains($tables[$t],'PRIMARY KEY(id)'),'schema table '.$t);
}
assertRule(str_contains($tables['prepaid_sales_order_payments'],'UNIQUE KEY uq_collection_ref'),'unique UPI/cash references');
assertRule(str_contains($tables['prepaid_sales_order_payments'],'UNIQUE KEY uq_bank_evidence'),'unique bank evidence');
assertRule(str_contains($tables['prepaid_sales_orders'],'UNIQUE KEY uq_sale_link'),'single invoice link per order');
$service=file_get_contents(__DIR__.'/../src/Sales/PrepaidOrderService.php');
foreach([
  'function paymentAccounts('=>'least-privilege collection account lookup',
  'function list('=>'branch-scoped order queue',
  'function create('=>'create draft/approved order',
  'function approveDiscount('=>'independent discount approval',
  'function collect('=>'record cash and pending UPI',
  'function verifyUpi('=>'independent UPI confirmation',
  'function post('=>'atomic invoice posting',
  'FOR UPDATE'=>'row locking',
  'Transaction::run('=>'database transactions',
  "Money::requireCovered("=>'full-payment posting gate',
  "StockService::move("=>'stock movement on posting',
  "AccountingService::post("=>'journal posting',
  "Audit::add("=>'audit trail',
  'if($o[\'status\']===\'posted\''=>'idempotent duplicate posting',
  'Guard::branch($a,(int)$o[\'branch_id\'],Capabilities::BANK_RECONCILE)'=>'branch-scoped UPI verification',
] as $needle=>$label){
    assertRule(str_contains($service,$needle),$label);
}
echo "PASSED prepaid order static flow and route/schema contracts (not a database integration test)\n";
