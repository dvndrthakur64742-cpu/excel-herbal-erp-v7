<?php
declare(strict_types=1);
require_once __DIR__.'/../src/Domain/DomainException.php';
require_once __DIR__.'/../src/Security/Actor.php';
require_once __DIR__.'/../src/Security/Capabilities.php';
require_once __DIR__.'/../src/Security/Guard.php';
require_once __DIR__.'/../src/Core/Input.php';
require_once __DIR__.'/../src/Database/Db.php';
require_once __DIR__.'/../src/Database/Transaction.php';
require_once __DIR__.'/../src/Security/Audit.php';
require_once __DIR__.'/../src/Reporting/ReportingSubmissionService.php';
use ExcelHerbal\ERP7\Reporting\ReportingSubmissionService as R;
use ExcelHerbal\ERP7\Security\{Actor,Capabilities as C};
use ExcelHerbal\ERP7\Domain\DomainException;
function current_time(string $format,bool $gmt=false):string{return $format==='Y-m-d'?'2026-10-20':'2026-10-20 14:00:00';}
function wp_json_encode(mixed $x,int $opts=0):string{return json_encode($x,$opts|JSON_THROW_ON_ERROR);}
$checks=0;
function ok(bool $test,string $why):void {
 global $checks;if(!$test)throw new RuntimeException("FAIL ".$why);
 ++$checks;echo "PASS {$why}\n";
}
function reject(callable $fn,string $key):void{
 try{$fn();throw new RuntimeException("Expected rejection ".$key);}
 catch(DomainException $e){ok($e->codeKey===$key,"reject ".$key);}
}
$GLOBALS['wpdb']=new class{
    public string $prefix='wp_';public int $insert_id=0;public string $last_error='';
    private array $tables=[];private int $id=0;
    public function query(string $sql):int{return 1;}
    public function prepare(string $sql,mixed ...$args):string{
        if(count($args)===1&&is_array($args[0]))$args=$args[0];
        $n=0;
        $out=preg_replace_callback('/%[ds]/',function($match)use(&$n,$args){
            $v=$args[$n++];
            return $match[0]==='%d'?(string)(int)$v:"'".str_replace("'","''",(string)$v)."'";
        },$sql);
        if($n!==count($args))throw new RuntimeException('Bad SQL bind count');
        return (string)$out;
    }
    public function insert(string $table,array $row):int|false{
        $this->insert_id=++$this->id;$row['id']=$this->insert_id;
        if(str_ends_with($table,'report_submissions')){
            foreach($this->tables[$table]??[] as $old){
                if($old['company_id']===$row['company_id']
                   &&$old['branch_id']===$row['branch_id']
                   &&$old['report_type']===$row['report_type']
                   &&$old['period_date']===$row['period_date']){
                    $this->last_error='Duplicate entry 1062';return false;
                }
            }
        }
        $this->tables[$table][$this->insert_id]=$row;return 1;
    }
    public function update(string $table,array $data,array $where):int{
        $matches=0;
        if(!isset($this->tables[$table]))return 0;
        foreach($this->tables[$table] as &$row){
            foreach($where as $key=>$value){
                if(($row[$key]??null)!==$value)continue 2;
            }
            $row=array_merge($row,$data);$matches++;
        }
        unset($row);return $matches;
    }
    private function where(string $sql,array $row):bool{
        foreach(['company_id','branch_id','id','submission_id','status'] as $key){
            if(preg_match('/\b'.$key.'=([0-9]+|\'[^\']*\')/',$sql,$m)){
                $expected=trim($m[1],"'");
                if((string)($row[$key]??'')!==$expected)return false;
            }
        }
        foreach(['report_type','period_date'] as $key){
            if(preg_match('/\b'.$key.'=\'([^\']+)\'/',$sql,$m)&&($row[$key]??null)!==$m[1])return false;
        }
        return true;
    }
    public function get_row(string $sql,mixed $mode=null):?array{
        if(!preg_match('/FROM\s+([a-z0-9_]+)/i',$sql,$m))throw new RuntimeException('Bad SQL table');
        foreach($this->tables[$m[1]]??[] as $row)if($this->where($sql,$row))return $row;
        return null;
    }
    public function get_results(string $sql,mixed $mode=null):array{
        if(!preg_match('/FROM\s+([a-z0-9_]+)/i',$sql,$m))throw new RuntimeException('Bad SQL table');
        $rows=array_values(array_filter($this->tables[$m[1]]??[],fn($row)=>$this->where($sql,$row)));
        if(str_contains($sql,'ORDER BY id ASC'))usort($rows,fn($a,$b)=>$a['id']<=>$b['id']);
        else usort($rows,fn($a,$b)=>$b['id']<=>$a['id']);
        return $rows;
    }
};
if(!defined('ARRAY_A'))define('ARRAY_A','ARRAY_A');
$bm=new Actor(31,101,5,10,[10],[C::REPORTS_VIEW,C::REPORT_SUBMIT],'BM');
$regional=new Actor(32,202,5,20,[10,20],[C::REPORTS_VIEW,C::REPORT_REVIEW],'RM');
$otherBm=new Actor(33,103,5,10,[10],[C::REPORTS_VIEW,C::REPORT_SUBMIT],'BM');
$anotherRegion=new Actor(34,204,6,10,[10],[C::REPORTS_VIEW,C::REPORT_REVIEW],'RM');
$summary='Monday branch sales and stock report submitted for review';
$input=['branch_id'=>10,'report_type'=>'weekly_report','period_date'=>'2026-10-19','summary_text'=>$summary];
$first=R::submit($bm,$input);
ok($first['status']==='submitted'&&$first['revision']===1&&strlen($first['content_sha256'])===64,'manager may submit canonical period');
ok($first['external_verification']===false,'attestation never marks bank, stock or payroll verified');
reject(fn()=>R::submit($bm,$input),'report_submission_duplicate');
reject(fn()=>R::submit($otherBm,$input),'report_submission_duplicate');
reject(fn()=>R::submit($bm,array_merge($input,['period_date'=>'2026-10-20'])),'report_submission_schedule_invalid');
reject(fn()=>R::submit($bm,array_merge($input,['period_date'=>'2026-10-26'])),'report_submission_future');
reject(fn()=>R::submit($bm,array_merge($input,['summary_text'=>'short'])),'report_submission_text_invalid');
reject(fn()=>R::submit($bm,array_merge($input,['branch_id'=>20])),'branch_forbidden');
reject(fn()=>R::submit($regional,$input),'permission_denied');
reject(fn()=>R::decide($bm,$first['id'],['decision'=>'approve']),'permission_denied');
reject(fn()=>R::decide($regional,$first['id'],['decision'=>'reject','note'=>'no']),'report_submission_text_invalid');
$managerReview=new Actor(44,101,5,10,[10],[C::REPORTS_VIEW,C::REPORT_SUBMIT,C::REPORT_REVIEW],'RM');
reject(fn()=>R::decide($managerReview,$first['id'],['decision'=>'approve']),'report_maker_checker_forbidden');
reject(fn()=>R::decide($anotherRegion,$first['id'],['decision'=>'approve']),'report_submission_not_found');
$rejected=R::decide($regional,$first['id'],['decision'=>'reject','note'=>'Provide sales visit details']);
ok($rejected['status']==='rejected','authorized distinct regional reviewer may reject');
reject(fn()=>R::decide($regional,$first['id'],['decision'=>'approve']),'report_decision_conflict');
reject(fn()=>R::submit($otherBm,array_merge($input,['summary_text'=>'Different submitter revised rejected report'])),'report_submission_owner_forbidden');
$second=R::submit($bm,array_merge($input,['summary_text'=>'Revised Monday sales, stock and pending approvals summary']));
ok($second['revision']===2&&$second['status']==='submitted'&&$second['content_sha256']!==$first['content_sha256'],
   'original owner resubmits same period with revision two and new content hash');
$approved=R::decide($regional,$first['id'],['decision'=>'approve','note'=>'Checked submission and notes']);
ok($approved['status']==='approved'&&$approved['revision']===2,'separate reviewer approves current revision');
reject(fn()=>R::submit($bm,$input),'report_submission_duplicate');
$history=R::history($bm,$first['id']);
ok($history['audit_events_append_only']===true&&count($history['history'])===4,'submit/reject/resubmit/approve all stored');
ok($history['history'][0]['content_sha256']===$first['content_sha256']
    &&$history['history'][2]['content_sha256']===$second['content_sha256'],
   'original and revised content hashes preserved in independent history');
$list=R::list($regional,10,'approved');
ok(count($list['records'])===1&&$list['records'][0]['status']==='approved','authorized reviewer sees approved submission');
ok(count(R::list($bm,10,'all')['records'])===1,'BM sees own report');
ok(count(R::list($otherBm,10,'all')['records'])===0,'other BM cannot view colleague attestation');
reject(fn()=>R::list($bm,20),'branch_forbidden');
reject(fn()=>R::list($regional,10,'unknown'),'report_submission_filter_invalid');
reject(fn()=>R::history($otherBm,$first['id']),'report_submission_forbidden');
reject(fn()=>R::history($anotherRegion,$first['id']),'report_submission_not_found');
$salary=['branch_id'=>10,'report_type'=>'salary_receipts','period_date'=>'2026-10-10','summary_text'=>'Salary receipts uploaded and list confirmed'];
reject(fn()=>R::submit($bm,$salary),'permission_denied');
$salaryBm=new Actor(32,101,5,10,[10],[C::REPORTS_VIEW,C::REPORT_SUBMIT,C::SALARY_VIEW],'BM');
$salarySubmission=R::submit($salaryBm,$salary);
ok($salarySubmission['status']==='submitted','salary receipt workflow requires explicit salary permission');
ok(count(R::list($bm,10)['records'])===1,'non salary-view actor cannot see salary receipt attestation');
reject(fn()=>R::decide($regional,$salarySubmission['id'],['decision'=>'approve']),'permission_denied');
$salaryRegional=new Actor(35,202,5,20,[10,20],[C::REPORTS_VIEW,C::REPORT_REVIEW,C::SALARY_VIEW],'RM');
ok(R::decide($salaryRegional,$salarySubmission['id'],['decision'=>'approve'])['status']==='approved',
    'salary-authorized regional reviewer may approve distinct maker');
echo "MANAGER REPORT SUBMISSION MAKER-CHECKER PHP: {$checks}/{$checks} PASS\n";
