<?php
/** Run: php tests/regression.php (PHP 8.1+). No production database required. */
require_once __DIR__.'/../src/Core/Autoloader.php';
\ExcelHerbal\ERP7\Core\Autoloader::register(__DIR__.'/../src');
use ExcelHerbal\ERP7\Payroll\PayrollCalculator;
use ExcelHerbal\ERP7\Domain\DomainException;

$cases=json_decode(file_get_contents(__DIR__.'/payroll-fixtures.json'),true,512,JSON_THROW_ON_ERROR);$failed=0;
foreach($cases as$c){
    try{$result=PayrollCalculator::calculate($c['input']);
        if(isset($c['error']))throw new \RuntimeException('Expected error '.$c['error']);
        foreach($c['expected'] as$k=>$v)if(abs($result[$k]-$v)>0.00001)throw new \RuntimeException($k.': expected '.$v.' got '.$result[$k]);
        echo 'PASS '.$c['name'].PHP_EOL;
    }catch(DomainException $e){if(($c['error']??null)===$e->codeKey)echo 'PASS '.$c['name'].PHP_EOL;else{$failed++;echo 'FAIL '.$c['name'].': '.$e->codeKey.PHP_EOL;}}
    catch(\Throwable $e){$failed++;echo 'FAIL '.$c['name'].': '.$e->getMessage().PHP_EOL;}
}
// Exercise actual approval/overlap guards with controlled database responses.
define('ARRAY_A','ARRAY_A');
function current_time($format,$gmt=false){return $format==='Y-m-d'?'2026-09-30':'2026-09-30 12:00:00';}
final class GuardDb {
    public string $prefix='wp_';public string $last_error='';public string $scenario='';
    public function prepare($q,...$args){return $q;}
    public function query($q){return 1;}
    public function get_var($q){
        if(str_contains($q,'companies'))return 1;
        if(str_contains($q,'payroll_editors'))return 99;
        if(str_contains($q,'payroll_runs'))return 8;
        return null;
    }
    public function get_results($q,$mode){return [['id'=>1,'monthly_salary'=>30000,'employee_code'=>'E1']];}
    public function get_row($q,$mode){return ['id'=>8,'company_id'=>1,'branch_id'=>1,'status'=>'draft','created_by'=>2,'period_end'=>'2026-09-30','calculation_version'=>$this->scenario==='legacy'?null:'7.3.5'];}
}
$wpdb=new GuardDb();
$actor=new \ExcelHerbal\ERP7\Security\Actor(10,10,1,1,[1],[\ExcelHerbal\ERP7\Security\Capabilities::PAYROLL_APPROVE,\ExcelHerbal\ERP7\Security\Capabilities::PAYROLL_GENERATE],'BM');
$guardCases=[
 ['editor','maker_checker_required',fn()=>\ExcelHerbal\ERP7\Payroll\PayrollPerformanceService::approvePayroll($actor,8)],
 ['legacy','payroll_legacy_draft',fn()=>\ExcelHerbal\ERP7\Payroll\PayrollPerformanceService::approvePayroll($actor,8)],
 ['overlap','payroll_period_overlap',fn()=>\ExcelHerbal\ERP7\Payroll\PayrollPerformanceService::generate($actor,1,'2026-09-15','2026-09-30')],
];
foreach($guardCases as[$name,$error,$fn]){$wpdb->scenario=$name;try{$fn();$failed++;echo "FAIL {$name}: expected rejection\n";}catch(DomainException $e){if($e->codeKey===$error)echo "PASS {$name}\n";else{$failed++;echo "FAIL {$name}: {$e->codeKey}\n";}}}
echo ($failed?'FAILED':'PASSED').' regression suite'.PHP_EOL;exit($failed?1:0);
