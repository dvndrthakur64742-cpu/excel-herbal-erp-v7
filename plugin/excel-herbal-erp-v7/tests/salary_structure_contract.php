<?php
/** Exact-money and route/schema contract tests; no production DB access. */
require_once __DIR__.'/../src/Core/Autoloader.php';
\ExcelHerbal\ERP7\Core\Autoloader::register(__DIR__.'/../src');

use ExcelHerbal\ERP7\Payroll\SalaryStructureService as SalaryStructures;
use ExcelHerbal\ERP7\Domain\DomainException;
use ExcelHerbal\ERP7\Http\{RouteRegistry,ApiContract};
use ExcelHerbal\ERP7\Database\Schema;

function salaryPass(bool $test,string $label):void {
    if(!$test){fwrite(STDERR,"FAIL ".$label."\n");exit(1);}
    echo "PASS ".$label."\n";
}
function salaryReject(callable $call,string $code):void {
    try{$call();}catch(DomainException $e){
        salaryPass($e->codeKey===$code,'rejected '.$code);return;
    }
    salaryPass(false,'expected '.$code);
}

$sum=SalaryStructures::components([
    'monthly_basic'=>'12000.12','hra'=>'2500.05',
    'fixed_allowance'=>'100.10','other_fixed'=>'0.03',
]);
salaryPass($sum['monthly_basic']==='12000.12'&&
    $sum['hra']==='2500.05'&&
    $sum['fixed_allowance']==='100.10'&&
    $sum['other_fixed']==='0.03'&&
    $sum['gross_monthly']==='14600.30',
    'four components reconcile by exact integer paise');
salaryPass(SalaryStructures::paise(0,'hra')===0,'zero allowance is permitted');
salaryPass(SalaryStructures::paise(123.45,'basic')===12345,
    'JSON decimal input accepted without float summation');
salaryReject(fn()=>SalaryStructures::components([
    'monthly_basic'=>0,'hra'=>200,'fixed_allowance'=>0,'other_fixed'=>0,
]),'salary_structure_basic_invalid');
salaryReject(fn()=>SalaryStructures::components([
    'monthly_basic'=>100,'hra'=>0,'fixed_allowance'=>0,
]),'salary_structure_components_missing');
salaryReject(fn()=>SalaryStructures::components([
    'monthly_basic'=>'999999999999.99','hra'=>'0.01',
    'fixed_allowance'=>0,'other_fixed'=>0,
]),'salary_structure_total_invalid');
foreach(['-1','1.234','1e5','not-money','NaN','',INF,NAN,[],null] as $invalid){
    salaryReject(fn()=>SalaryStructures::paise($invalid,'hra'),
        'salary_structure_amount_invalid');
}

$routes=RouteRegistry::routes();
$contract=ApiContract::describe()['routes'];
$expected=[
    ['GET','/payroll/salary-structures','payroll.salary_structures',[]],
    ['POST','/payroll/salary-structures','payroll.salary_structure_create',
        ['branch_id','employee_id','monthly_basic','hra','fixed_allowance',
         'other_fixed','effective_from','change_reason']],
    ['POST','/payroll/salary-structures/(?P<id>\\d+)/approve',
        'payroll.salary_structure_approve',[]],
];
foreach($expected as [$method,$path,$handler,$required]){
    salaryPass(count(array_filter($routes,static fn($row)=>
        $row[0]===$method&&$row[1]===$path&&
        $row[2]===$handler&&$row[3]===true
    ))===1,'authenticated '.$handler);
    salaryPass(count(array_filter($contract,static fn($row)=>
        $row['method']===$method&&$row['path']===$path&&
        $row['auth']===true&&$row['required_params']===$required&&
        $row['idempotency_required']===($method==='POST')
    ))===1,'canonical '.$method.' route contract '.$handler);
}
$definitions=Schema::definitions();
salaryPass(Schema::VERSION==='7.3.12-promotion-review-4',
    'schema migration marker advanced');
salaryPass(isset($definitions['salary_structure_versions'])&&
    str_contains($definitions['salary_structure_versions'],'salary_revision_id')&&
    str_contains($definitions['salary_structure_versions'],'gross_monthly')&&
    str_contains($definitions['salary_structure_versions'],'employee_effective'),
    'component-version table supports approved revision lineage');
$src=file_get_contents(__DIR__.'/../src/Payroll/SalaryStructureService.php');
salaryPass(str_contains($src,'SalaryService::lockCompany(')&&
    str_contains($src,'salary_payroll_conflict')&&
    str_contains($src,"'maker_checker_required'"),
    'company lock, payroll intersection and checker gates are required');
foreach(['AccountingService::post(','StockService::move(','payPayroll('] as $forbidden){
    salaryPass(!str_contains($src,$forbidden),
        'structure approval cannot post payment or journal '.$forbidden);
}
echo "PASSED salary four-component, exact-paise, schema, route and release contracts\n";
