<?php
require_once __DIR__.'/../src/Http/RouteRegistry.php';
require_once __DIR__.'/../src/Http/ApiContract.php';

use ExcelHerbal\ERP7\Http\RouteRegistry;
use ExcelHerbal\ERP7\Http\ApiContract;

function preflightAssert(bool $condition,string $label):void {
    if (!$condition) {fwrite(STDERR,"FAIL $label\n");exit(1);}
    echo "PASS $label\n";
}
$matches=array_values(array_filter(RouteRegistry::routes(),static fn($r)=>
    $r[0]==='GET' &&
    $r[1]==='/daily/requests/(?P<id>\\d+)/issue-preflight' &&
    $r[2]==='daily.issue_preflight' && $r[3]===true
));
preflightAssert(count($matches)===1,'issue preflight is authenticated GET, never a write');
$dispatch=file_get_contents(__DIR__.'/../src/Http/ApiDispatch.php');
preflightAssert(str_contains($dispatch,'DailyIssuePreflightService::inspect('),
    'issue preview dispatches to distinct read-only service');
$service=file_get_contents(__DIR__.'/../src/DailyOrder/DailyIssuePreflightService.php');
foreach ([
    "ActingDutyService::assertAction("=>'exact action access',
    "'daily.issue'" =>'daily issue authorization',
    'HierarchyScope::assertCanViewEmployee('=>'hierarchy protection',
    "'maker_checker_required'"=>'self-issue denial',
    "'daily_request_state_invalid'"=>'approved state only',
    'BranchDayGuard::assertOpen('=>'branch-day protection',
    'sb.custodian_key=0'=>'only branch warehouse stock',
    'bt.expires_on'=>'expired batch excluded',
    "'all_available'" =>'preview availability contract',
    "'requires_employee_receipt'=>true"=>'no automatic custody transfer',
    "'stock_moved'=>false"=>'read-only stock state',
] as $needle=>$label) {
    preflightAssert(str_contains($service,$needle),$label);
}
foreach(['Db::mustInsert(','Db::mustUpdate(','StockService::move(','StockService::transferCustody(','AccountingService::post('] as $forbidden){
    preflightAssert(!str_contains($service,$forbidden),'no business write '.$forbidden);
}
$contract=ApiContract::describe();
$routes=$contract['routes']??[];
preflightAssert(count(array_filter($routes,static fn($r)=>
    ($r['path']??'')==='/daily/requests/(?P<id>\\d+)/issue-preflight'
))===1,'runtime API contract describes preview');
echo "PASSED daily issue preflight API/static safety tests; database E2E still required\n";
