<?php
// Executable REST contract regression: no WordPress site or database is needed.
require_once __DIR__.'/../src/Domain/DomainException.php';
require_once __DIR__.'/../src/Core/Input.php';
require_once __DIR__.'/../src/Http/RouteRegistry.php';
require_once __DIR__.'/../src/Http/ApiContract.php';
use ExcelHerbal\ERP7\Domain\DomainException;
use ExcelHerbal\ERP7\Http\ApiContract;

final class ReportRequestStub {
    public function __construct(private array $values) {}
    public function get_param(string $key):mixed{return $this->values[$key]??null;}
}
$routes=ApiContract::describe()['routes'];
$matches=array_values(array_filter($routes,fn($r)=>$r['path']==='/reports/account-ledger'&&$r['method']==='GET'));
if(count($matches)!==1||$matches[0]['required_params']!==['account_id','from','to']) {
    fwrite(STDERR,"FAIL account ledger API contract missing required parameters\n");exit(1);
}
echo "PASS account ledger requires account ID and date range\n";
ApiContract::validate('reports.ledger',new ReportRequestStub(['account_id'=>12,'from'=>'2026-10-01','to'=>'2026-10-31']),'GET');
echo "PASS valid ledger request\n";
function requireRejection(array $params,string $expected):void{
    try{ApiContract::validate('reports.ledger',new ReportRequestStub($params),'GET');}
    catch(DomainException $e){if($e->codeKey===$expected)return;fwrite(STDERR,"FAIL unexpected error {$e->codeKey}\n");exit(1);}
    fwrite(STDERR,"FAIL invalid ledger request accepted\n");exit(1);
}
requireRejection(['from'=>'2026-10-01','to'=>'2026-10-31'],'parameter_required');
requireRejection(['account_id'=>2,'from'=>'2026-02-30','to'=>'2026-10-31'],'date_invalid');
echo "PASS missing account or invalid dates are rejected\n";
