<?php
// Executable least-privilege regression using synthetic employees only.
define('ARRAY_A', 'ARRAY_A');
require_once __DIR__.'/../src/Domain/DomainException.php';
require_once __DIR__.'/../src/Database/Db.php';
require_once __DIR__.'/../src/Security/Actor.php';
require_once __DIR__.'/../src/Security/Capabilities.php';
require_once __DIR__.'/../src/Security/Guard.php';
require_once __DIR__.'/../src/Security/HierarchyScope.php';
require_once __DIR__.'/../src/Security/AccessService.php';

use ExcelHerbal\ERP7\Security\Actor;
use ExcelHerbal\ERP7\Security\Capabilities;
use ExcelHerbal\ERP7\Security\HierarchyScope;
use ExcelHerbal\ERP7\Security\AccessService;
use ExcelHerbal\ERP7\Domain\DomainException;

final class FakeScopeWpdb {
    public string $prefix='wp_';
    public array $employees=[
        ['id'=>1,'assigned_branch_id'=>1,'reporting_employee_id'=>null,'designation_code'=>'MD'],
        ['id'=>2,'assigned_branch_id'=>1,'reporting_employee_id'=>1,'designation_code'=>'EMPLOYEE'],
        ['id'=>3,'assigned_branch_id'=>2,'reporting_employee_id'=>1,'designation_code'=>'EMPLOYEE'],
        ['id'=>4,'assigned_branch_id'=>1,'reporting_employee_id'=>null,'designation_code'=>'SYSADMIN'],
        ['id'=>5,'assigned_branch_id'=>1,'reporting_employee_id'=>null,'designation_code'=>'BM'],
        ['id'=>6,'assigned_branch_id'=>2,'reporting_employee_id'=>3,'designation_code'=>'EMPLOYEE'],
    ];
    public function prepare(string $sql, mixed ...$args):string{return vsprintf($sql,$args);}
    public function get_results(string $sql, mixed $format=null):array{return $this->employees;}
    public function get_var(string $sql):?string {if(!preg_match('/AND id=(\\d+)/',$sql,$m))return null;foreach($this->employees as $e){if((int)$e['id']===(int)$m[1])return (string)$e['designation_code'];}return null;}
}
$GLOBALS['wpdb']=new FakeScopeWpdb();
function actorFor(int $id, string $designation, array $branches, array $caps=[]):Actor {
    return new Actor($id,$id,1,$branches[0]??0,$branches,$caps,$designation);
}
function checkEqual(mixed $actual, mixed $expected, string $label):void {
    if($actual!==$expected){fwrite(STDERR,"FAIL $label: ".json_encode($actual)." vs ".json_encode($expected)."\n");exit(1);}
    echo "PASS $label\n";
}
function expectDenied(callable $fn,string $code,string $label):void {
    try{$fn();}catch(DomainException $e){checkEqual($e->codeKey,$code,$label);return;}
    fwrite(STDERR,"FAIL $label: missing permission denial\n");exit(1);
}
$md=actorFor(1,'MD',[1],[Capabilities::ACCESS_MANAGE]);
$sysadmin=actorFor(4,'SYSADMIN',[1],[Capabilities::ACCESS_MANAGE]);
checkEqual(HierarchyScope::visibleEmployeeIds($md),[1,2,4,5],'MD cannot see an unauthorised branch');
checkEqual(HierarchyScope::visibleEmployeeIds($sysadmin),[1,2,3,4,5,6],'system administrator has explicit company-wide scope');
checkEqual(HierarchyScope::visibleEmployeeIds(actorFor(3,'EMPLOYEE',[2])),[3],'ordinary employee sees only self');
checkEqual(HierarchyScope::visibleEmployeeIds(actorFor(5,'BM',[1])),[1,2,4,5],'branch manager limited to own branch');
expectDenied(fn()=>HierarchyScope::assertCanManageEmployeeAccess($md,3),'employee_scope_forbidden','HR access cannot cross branch');
expectDenied(fn()=>HierarchyScope::assertCanManageEmployeeAccess($md,1),'self_access_mutation_forbidden','HR cannot elevate own access');
expectDenied(fn()=>HierarchyScope::assertCanManageEmployeeAccess($md,4),'reserved_system_role_forbidden','non-admin cannot edit system administrator');
expectDenied(fn()=>HierarchyScope::assertCanManageEmployeeAccess(actorFor(5,'BM',[1]),2),'permission_denied','access management capability is required');
HierarchyScope::assertCanManageEmployeeAccess($md,2);
echo "PASS assigned-branch employee access allowed\n";
$roleGuard=new ReflectionMethod(AccessService::class,'isReservedRole');
checkEqual($roleGuard->invoke(null,'SYSTEM_ADMIN'),true,'system role is reserved');
checkEqual($roleGuard->invoke(null,'BRANCH_REVIEWER'),false,'ordinary role is not reserved');
$source=file_get_contents(__DIR__.'/../src/Organization/OrganizationEmployeeService.php');
foreach([
    '$provisionLogin=array_key_exists(\'provision_login\',$data)&&!empty($data[\'provision_login\'])',
    "'salary_invalid',422",
    'HierarchyScope::assertCanViewEmployee($a,$managerId)',
] as $needle) {
    if(!str_contains($source,$needle)){fwrite(STDERR,"FAIL missing employee security guard: $needle\n");exit(1);}
}
echo "PASS employee provisioning is opt-in, salary checked, managers scoped\n";
