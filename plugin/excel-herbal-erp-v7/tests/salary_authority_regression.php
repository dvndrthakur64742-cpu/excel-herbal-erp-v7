<?php
// Synthetic DB double: exercise public salary entry points and no-write denials.
define('ARRAY_A','ARRAY_A');
foreach(['Domain/DomainException','Database/Db','Database/Transaction','Core/Input','Security/Actor','Security/Capabilities','Security/Guard','Security/HierarchyScope','Security/Audit','Payroll/SalaryService'] as $file)require_once __DIR__.'/../src/'.$file.'.php';
use ExcelHerbal\ERP7\Security\Actor;
use ExcelHerbal\ERP7\Security\Capabilities as C;
use ExcelHerbal\ERP7\Payroll\SalaryService as S;
use ExcelHerbal\ERP7\Domain\DomainException;
function current_time(string $format,bool $utc=false):string{return $format==='Y-m-d'?'2026-10-31':'2026-10-31 10:00:00';}
function wp_json_encode(mixed $value):string{return json_encode($value);}
final class SalaryAuthorityDb {
    public string $prefix='wp_';
    public string $last_error='';
    public int $insert_id=100;
    public array $writes=[];
    public array $queries=[];
    public array $employees=[];
    public array $revision=[];
    public function __construct(){
        foreach([[1,1,null,'SM',1],[2,1,1,'EMPLOYEE',1],[3,1,null,'EMPLOYEE',1],[4,2,1,'EMPLOYEE',1],[5,1,1,'EMPLOYEE',2]] as [$id,$branch,$manager,$designation,$company]){
            $this->employees[$id]=['id'=>$id,'assigned_branch_id'=>$branch,'reporting_employee_id'=>$manager,'designation_code'=>$designation,'company_id'=>$company,'status'=>'active','joining_date'=>'2026-01-01','monthly_salary'=>'10000.00'];
        }
        $this->revision=['id'=>10,'company_id'=>1,'employee_id'=>2,'created_by'=>9,'status'=>'pending','monthly_salary'=>12000,'effective_from'=>'2026-10-01','reason'=>'Annual review'];
    }
    public function prepare(string $sql,mixed ...$args):string{return vsprintf($sql,$args);}
    public function query(string $sql):int{$this->queries[]=$sql;return 1;}
    public function get_var(string $sql):mixed{
        if(str_contains($sql,'eh7_companies'))return 1;
        if(str_contains($sql,'SELECT monthly_salary'))return 12000;
        return null;
    }
    public function get_row(string $sql,mixed $format=null):?array{
        if(str_contains($sql,'eh7_salary_revisions'))return $this->revision;
        if(preg_match('/company_id=(\d+) AND id=(\d+)/',$sql,$m)){
            $row=$this->employees[(int)$m[2]]??null;
            return $row&&$row['company_id']===(int)$m[1]?$row:null;
        }
        throw new RuntimeException('Unexpected query: '.$sql);
    }
    public function get_results(string $sql,mixed $format=null):array{
        if(str_contains($sql,'eh7_salary_revisions'))return [$this->revision];
        if(str_contains($sql,'eh7_employees'))return array_values(array_filter($this->employees,fn($e)=>$e['company_id']===1));
        throw new RuntimeException('Unexpected query: '.$sql);
    }
    public function insert(string $table,array $data):int{$this->writes[]=[$table,$data];$this->insert_id++;return 1;}
    public function update(string $table,array $data,array $where):int{$this->writes[]=[$table,$data,$where];return 1;}
}
function actor(array $caps):Actor{return new Actor(1,1,1,1,[1],$caps,'SM');}
function resetDb():SalaryAuthorityDb{return $GLOBALS['wpdb']=new SalaryAuthorityDb();}
function check(bool $ok,string $label):void{if(!$ok)throw new RuntimeException('FAIL '.$label);echo 'PASS '.$label."\n";}
function denied(callable $fn,string $code,string $label):void{
    $db=$GLOBALS['wpdb'];$before=count($db->writes);
    try{$fn();}catch(DomainException $e){check($e->codeKey===$code,$label.' error');check(count($db->writes)===$before,$label.' no mutation or audit');return;}
    throw new RuntimeException('FAIL '.$label.' allowed');
}
$data=['monthly_salary'=>12000,'effective_from'=>'2026-10-01','reason'=>'Annual review'];
resetDb();check(count(S::history(actor([C::SALARY_VIEW]),2))===1,'salary viewer needs no payroll generation permission');
$db=resetDb();check(S::request(actor([C::SALARY_MANAGE]),2,$data)['status']==='pending','salary manager can request without payroll generation');check(count($db->writes)===2,'request writes revision and audit');
foreach([true,false] as $approve){$db=resetDb();check(S::approve(actor([C::SALARY_APPROVE]),10,$approve)['status']===($approve?'approved':'rejected'),'independent salary reviewer needs no payroll approval');check(count($db->writes)===($approve?3:2),'review writes expected records and audit');}
foreach([3=>'employee_scope_forbidden',4=>'branch_forbidden',5=>'employee_not_found'] as $target=>$code){
    resetDb();denied(fn()=>S::history(actor([C::SALARY_VIEW,C::PAYROLL_GENERATE]),$target),$code,'history target '.$target);
    $db=resetDb();denied(fn()=>S::request(actor([C::SALARY_MANAGE,C::PAYROLL_GENERATE]),$target,$data),$code,'request target '.$target);check(end($db->queries)==='ROLLBACK','denied request rolls back');
    foreach([true,false] as $approve){$db=resetDb();$db->revision['employee_id']=$target;denied(fn()=>S::approve(actor([C::SALARY_APPROVE,C::PAYROLL_APPROVE]),10,$approve),$code,'review target '.$target);check(end($db->queries)==='ROLLBACK','denied review rolls back');}
}
resetDb();denied(fn()=>S::history(actor([C::PAYROLL_GENERATE]),2),'permission_denied','payroll permission alone cannot read salary');
resetDb();denied(fn()=>S::request(actor([C::PAYROLL_GENERATE]),2,$data),'permission_denied','payroll permission alone cannot request salary');
resetDb();denied(fn()=>S::approve(actor([C::PAYROLL_APPROVE]),10,true),'permission_denied','payroll permission alone cannot review salary');
resetDb();denied(fn()=>S::request(actor([C::SALARY_MANAGE]),1,$data),'salary_self_change','self salary request');
foreach(['created_by','employee_id'] as $field){$db=resetDb();$db->revision[$field]=1;denied(fn()=>S::approve(actor([C::SALARY_APPROVE]),10,true),'maker_checker_required','independent checker '.$field);}
echo "Salary authority regression passed.\n";
