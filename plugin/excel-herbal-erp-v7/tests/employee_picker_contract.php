<?php
// Synthetic-only employee picker tests: exercise actual access and projection logic.
define('ARRAY_A','ARRAY_A');
require_once __DIR__.'/../src/Domain/DomainException.php';
require_once __DIR__.'/../src/Database/Db.php';
require_once __DIR__.'/../src/Security/Actor.php';
require_once __DIR__.'/../src/Security/Capabilities.php';
require_once __DIR__.'/../src/Security/Guard.php';
require_once __DIR__.'/../src/Security/HierarchyScope.php';
require_once __DIR__.'/../src/Organization/EmployeeChoiceService.php';
require_once __DIR__.'/../src/Http/RouteRegistry.php';
require_once __DIR__.'/../src/Http/ApiContract.php';

use ExcelHerbal\ERP7\Security\Actor;
use ExcelHerbal\ERP7\Security\Capabilities;
use ExcelHerbal\ERP7\Security\HierarchyScope;
use ExcelHerbal\ERP7\Organization\EmployeeChoiceService;
use ExcelHerbal\ERP7\Http\RouteRegistry;
use ExcelHerbal\ERP7\Domain\DomainException;

final class SyntheticPickerDb {
    public string $prefix='wp_';
    public array $employees=[
      ['id'=>10,'employee_code'=>'HO','full_name'=>'Synthetic Manager','designation_code'=>'MD','assigned_branch_id'=>1,'reporting_employee_id'=>null,'status'=>'active'],
      ['id'=>11,'employee_code'=>'A1','full_name'=>'Synthetic Staff A','designation_code'=>'EMPLOYEE','assigned_branch_id'=>1,'reporting_employee_id'=>10,'status'=>'active'],
      ['id'=>12,'employee_code'=>'B1','full_name'=>'Synthetic Staff B','designation_code'=>'EMPLOYEE','assigned_branch_id'=>2,'reporting_employee_id'=>10,'status'=>'active'],
      ['id'=>13,'employee_code'=>'AD','full_name'=>'Synthetic Admin','designation_code'=>'SYSADMIN','assigned_branch_id'=>1,'reporting_employee_id'=>null,'status'=>'active'],
    ];
    public function prepare(string $sql,mixed ...$args):string{return vsprintf($sql,$args);}
    public function get_results(string $sql,mixed $format=null):array{
        $rows=$this->employees;
        if(preg_match('/\\bid IN \\(([0-9,]+)\\)/',$sql,$match)){
            $allowed=array_flip(array_map('intval',explode(',',$match[1])));
            $rows=array_values(array_filter($rows,fn($r)=>isset($allowed[(int)$r['id']])));
        }
        return $rows;
    }
}
$GLOBALS['wpdb']=new SyntheticPickerDb();
$a=new Actor(10,10,1,1,[1],[Capabilities::ACCESS_MANAGE,Capabilities::DAILY_OTHERS],'MD');
function must(bool $ok,string $msg):void{if(!$ok){fwrite(STDERR,"FAIL $msg\n");exit(1);}echo "PASS $msg\n";}
$rows=EmployeeChoiceService::list($a,1);
must(array_column($rows,'id')===[10,11,13],'picker contains only explicitly authorised branch employees');
must(!isset($rows[0]['mobile'])&&!isset($rows[0]['email'])&&!isset($rows[0]['monthly_salary']),'picker excludes contact and salary fields');
must(array_column(EmployeeChoiceService::list($a,1,true),'id')===[10],'own daily-order picker excludes other employees');
must(array_column(EmployeeChoiceService::list($a,1,false,true),'id')===[11,13],'picker can omit own identity');
must(array_column(EmployeeChoiceService::list($a,1,false,true,[11]),'id')===[11],'picker respects manager-only restriction');
try{EmployeeChoiceService::list($a,2);fwrite(STDERR,"FAIL other branch picker allowed\n");exit(1);}
catch(DomainException $e){must($e->codeKey==='branch_forbidden','other branch picker rejected');}
$paths=[
  '/performance/target-employees',
  '/communication/target-employees',
  '/daily/target-employees',
  '/organization/hr/employee-choices',
  '/administration/acting-employees',
  '/administration/access-employees',
  '/payroll/salary-employees',
];
$routes=RouteRegistry::routes();
foreach($paths as $path){
    $hits=array_values(array_filter($routes,fn($r)=>$r[0]==='GET'&&$r[1]===$path&&$r[3]===true));
    must(count($hits)===1,'authenticated employee picker route: '.$path);
}
$dispatch=file_get_contents(__DIR__.'/../src/Http/ApiDispatch.php');
foreach(['performance.target_employees','comm.target_employees','daily.target_employees','hr.employee_choices','admin.acting_employees','access.employees','payroll.salary_employees'] as $key){
    must(str_contains($dispatch,"'".$key."'=>"),'employee picker dispatch binding '.$key);
}
