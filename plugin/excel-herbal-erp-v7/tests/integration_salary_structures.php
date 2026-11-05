<?php
/**
 * Synthetic salary component draft / approval against disposable MariaDB.
 * NEVER run on production. Drops its tables in a synthetic-only database.
 */
define('EH7_INTEGRATION_LIBRARY_ONLY',true);
require __DIR__.'/integration_mariadb.php';
require_once __DIR__.'/../src/Core/Autoloader.php';
\ExcelHerbal\ERP7\Core\Autoloader::register(__DIR__.'/../src');

use ExcelHerbal\ERP7\Database\{Db,Schema};
use ExcelHerbal\ERP7\Domain\DomainException;
use ExcelHerbal\ERP7\Payroll\{SalaryStructureService,SalaryService};
use ExcelHerbal\ERP7\Security\{Actor,Capabilities as C};

$database=(string)(getenv('EH7_MARIADB_DATABASE')?:'');
if(getenv('EH7_INTEGRATION_MODE')!=='synthetic'||
    !str_starts_with($database,'eh7_test_')){
    fwrite(STDERR,"REFUSED: only synthetic eh7_test_* databases permitted\n");
    exit(2);
}
$db=eh7_setup_global_db();
$tables=[
    'audit_log','salary_structure_versions','salary_revisions','payroll_items',
    'payroll_runs','employees','branches','companies',
];
$definitions=Schema::definitions();
foreach($tables as $name){
    if($db->query('DROP TABLE IF EXISTS '.Db::table($name))===false)
        throw new RuntimeException('Drop failed '.$name.': '.$db->last_error);
}
foreach(array_reverse($tables) as $name){
    if(!isset($definitions[$name]))throw new RuntimeException('Missing '.$name.' schema');
    if($db->query('CREATE TABLE '.Db::table($name).' ('.$definitions[$name].
        ') ENGINE=InnoDB DEFAULT CHARSET=utf8mb4')===false)
        throw new RuntimeException('Create failed '.$name.': '.$db->last_error);
}
function salarySeed(string $name,array $row):int {
    Db::mustInsert(Db::wpdb(),Db::table($name),$row);
    return (int)Db::wpdb()->insert_id;
}
function salaryAssert(bool $ok,string $label):void {
    if(!$ok)throw new RuntimeException('FAILED salary integration: '.$label);
    echo "PASS ".$label."\n";
}
function salaryDeny(callable $fn,string $code):void {
    try{$fn();}catch(DomainException $e){
        salaryAssert($e->codeKey===$code,'denied '.$code);return;
    }
    throw new RuntimeException('Expected salary denial '.$code);
}
$today=Db::today();
$yesterday=(new DateTimeImmutable($today))->modify('-1 day')->format('Y-m-d');
$now=Db::now();
salarySeed('companies',['id'=>1,'name'=>'Synthetic Salary Company',
    'status'=>'active','created_at'=>$now]);
salarySeed('branches',['id'=>1,'company_id'=>1,'code'=>'B1',
    'name'=>'Synthetic Branch','status'=>'active','created_at'=>$now]);
salarySeed('branches',['id'=>2,'company_id'=>1,'code'=>'B2',
    'name'=>'Synthetic Other Branch','status'=>'active','created_at'=>$now]);
foreach([
    [11,'EMPLOYEE',20],
    [20,'SM',null],
    [30,'SYSADMIN',null],
] as [$id,$designation,$manager]){
    salarySeed('employees',[
        'id'=>$id,'company_id'=>1,'employee_code'=>'TEST'.$id,
        'designation_code'=>$designation,'assigned_branch_id'=>1,
        'reporting_employee_id'=>$manager,'full_name'=>'Synthetic '.$id,
        'monthly_salary'=>'9000.00','joining_date'=>'2020-01-01',
        'status'=>'active','created_at'=>$now,
    ]);
}
$maker=new Actor(20,20,1,1,[1],[C::SALARY_MANAGE],'SM');
$checker=new Actor(30,30,1,1,[1],[C::SALARY_APPROVE],'SYSADMIN');
$makerChecker=new Actor(20,20,1,1,[1],
    [C::SALARY_MANAGE,C::SALARY_APPROVE],'SM');
$beneficiaryChecker=new Actor(11,11,1,1,[1],
    [C::SALARY_APPROVE],'EMPLOYEE');
$outsider=new Actor(30,30,1,2,[2],[C::SALARY_APPROVE],'SYSADMIN');
$viewer=new Actor(30,30,1,1,[1],[C::SALARY_VIEW],'SYSADMIN');
$payload=[
    'branch_id'=>1,'employee_id'=>11,
    'monthly_basic'=>'10000.10','hra'=>'2000.15',
    'fixed_allowance'=>'500.25','other_fixed'=>'50.01',
    'effective_from'=>$today,
    'change_reason'=>'Reviewed monthly component increase',
];
salaryDeny(fn()=>SalaryStructureService::list($outsider,1),'branch_forbidden');
salaryDeny(fn()=>SalaryStructureService::create(
    $beneficiaryChecker,$payload),'permission_denied');
$created=SalaryStructureService::create($maker,$payload);
$id=(int)$created['id'];
salaryAssert($created['status']==='draft'&&
    $created['gross_monthly']==='12550.51',
    'draft preserves four components with exact-paise gross');
salaryAssert((int)$db->get_var('SELECT COUNT(*) FROM '.Db::table('salary_revisions'))===0,
    'draft creates no effective salary revisions');
salaryAssert((string)$db->get_var($db->prepare(
    'SELECT monthly_salary FROM '.Db::table('employees').' WHERE id=%d',11
))==='9000.00','draft does not modify employee monthly salary');
$rows=SalaryStructureService::list($viewer,1);
salaryAssert(count($rows)===1&&
    $rows[0]['gross_monthly']==='12550.51'&&
    (int)$rows[0]['employee_id']===11,
    'read-only salary list is visible only by authorized branch hierarchy');
salaryDeny(fn()=>SalaryStructureService::create($maker,$payload),
    'salary_structure_date_conflict');
salaryAssert((int)$db->get_var('SELECT COUNT(*) FROM '.Db::table('salary_structure_versions'))===1,
    'duplicate proposal is atomic and does not insert another row');
salaryDeny(fn()=>SalaryStructureService::approve($makerChecker,$id),
    'maker_checker_required');
salaryDeny(fn()=>SalaryStructureService::approve($beneficiaryChecker,$id),
    'maker_checker_required');
salaryDeny(fn()=>SalaryStructureService::approve($outsider,$id),
    'branch_forbidden');
$approved=SalaryStructureService::approve($checker,$id);
salaryAssert($approved['status']==='approved'&&
    $approved['payroll_posted']===false&&
    (int)$approved['salary_revision_id']>0,
    'checker approves one historical salary revision without payroll posting');
$rev=$db->get_row($db->prepare(
    'SELECT * FROM '.Db::table('salary_revisions').
    ' WHERE company_id=%d AND employee_id=%d',1,11
),ARRAY_A);
salaryAssert($rev!==null&&$rev['status']==='approved'&&
    $rev['monthly_salary']==='12550.51'&&
    (int)$rev['created_by']===20&&
    (int)$rev['approved_by']===30,
    'approved salary history preserves maker/checker lineage and gross salary');
salaryAssert((string)$db->get_var($db->prepare(
    'SELECT monthly_salary FROM '.Db::table('employees').' WHERE id=%d',11
))==='12550.51','employee current salary reflects latest approved revision');
salaryAssert((int)$db->get_var(
    'SELECT COUNT(*) FROM '.Db::table('salary_revisions')
)===1,'salary revision written exactly once');
salaryDeny(fn()=>SalaryStructureService::approve($checker,$id),
    'salary_structure_state_invalid');
salaryDeny(fn()=>SalaryStructureService::create($maker,$payload),
    'salary_structure_date_conflict');

$previous=$payload;
$previous['effective_from']=$yesterday;
$previous['change_reason']='Past-dated salary change with payroll conflict';
$older=SalaryStructureService::create($maker,$previous);
$run=salarySeed('payroll_runs',[
    'company_id'=>1,'branch_id'=>1,'period_start'=>$yesterday,
    'period_end'=>$yesterday,'status'=>'draft','created_by'=>30,
    'created_at'=>$now,
]);
salarySeed('payroll_items',['payroll_run_id'=>$run,'employee_id'=>11]);
salaryDeny(fn()=>SalaryStructureService::approve($checker,(int)$older['id']),
    'salary_payroll_conflict');
salaryAssert((string)$db->get_var($db->prepare(
    'SELECT status FROM '.Db::table('salary_structure_versions').
    ' WHERE id=%d',$older['id']
))==='draft','payroll conflict keeps proposed salary unapproved');
salaryAssert((int)$db->get_var('SELECT COUNT(*) FROM '.Db::table('salary_revisions'))===1,
    'payroll conflict cannot generate an effective revision');
$events=(array)$db->get_results('SELECT action FROM '.Db::table('audit_log').
    ' ORDER BY id',ARRAY_A);
salaryAssert(count($events)===3&&
    $events[0]['action']==='salary_structure.draft'&&
    $events[1]['action']==='salary_structure.approve'&&
    $events[2]['action']==='salary_structure.draft',
    'audit history contains only committed draft and approval actions');
echo "PASSED synthetic real-MariaDB salary proposal, independent approval, gross reconciliation, payroll conflict and audit\n";
