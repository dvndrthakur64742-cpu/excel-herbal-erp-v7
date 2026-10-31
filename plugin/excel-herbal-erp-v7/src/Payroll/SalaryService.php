<?php
namespace ExcelHerbal\ERP7\Payroll;
use ExcelHerbal\ERP7\Core\Input;
use ExcelHerbal\ERP7\Database\Db;
use ExcelHerbal\ERP7\Database\Transaction;
use ExcelHerbal\ERP7\Domain\DomainException;
use ExcelHerbal\ERP7\Security\Actor;
use ExcelHerbal\ERP7\Security\Audit;
use ExcelHerbal\ERP7\Security\Capabilities;
use ExcelHerbal\ERP7\Security\Guard;

final class SalaryService {
    public static function employeeChoices(Actor $a,?int $branch=null):array{
        Guard::any($a,[Capabilities::SALARY_VIEW,Capabilities::SALARY_MANAGE,Capabilities::SALARY_APPROVE]);
        if($branch!==null)Guard::branchAny($a,$branch,[Capabilities::SALARY_VIEW,Capabilities::SALARY_MANAGE,Capabilities::SALARY_APPROVE]);
        return \ExcelHerbal\ERP7\Organization\EmployeeChoiceService::list($a,$branch,false,true);
    }
    public static function lockCompany(int $company):void {
        $db=Db::wpdb();
        $id=$db->get_var($db->prepare('SELECT id FROM '.Db::table('companies').' WHERE id=%d FOR UPDATE',$company));
        if (!$id || !empty($db->last_error)) throw new DomainException('Unable to lock payroll company.', 'payroll_lock_failed', 500);
    }
    public static function history(Actor $a,int $employee):array {
        Guard::cap($a,Capabilities::SALARY_VIEW);
        self::employee($a,$employee,Capabilities::PAYROLL_GENERATE);
        $db=Db::wpdb();
        return (array)$db->get_results($db->prepare('SELECT * FROM '.Db::table('salary_revisions').' WHERE company_id=%d AND employee_id=%d ORDER BY effective_from,id',$a->companyId,$employee),ARRAY_A);
    }
    private static function employee(Actor $a,int $id,string $cap):array {
        $db=Db::wpdb();$e=$db->get_row($db->prepare('SELECT * FROM '.Db::table('employees').' WHERE company_id=%d AND id=%d',$a->companyId,$id),ARRAY_A);
        if (!$e) throw new DomainException('Employee not found.','employee_not_found',404);
        Guard::branch($a,(int)$e['assigned_branch_id'],$cap);return $e;
    }
    public static function request(Actor $a,int $employee,array $data):array {
        Guard::cap($a,Capabilities::SALARY_MANAGE);
        return Transaction::run(function()use($a,$employee,$data){
            self::lockCompany($a->companyId);$e=self::employee($a,$employee,Capabilities::PAYROLL_GENERATE);
            if($employee===$a->employeeId)throw new DomainException('Use another authorized maker for your salary change.','salary_self_change',403);
            $amount=$data['monthly_salary']??null;$date=Input::date((string)($data['effective_from']??''),'Salary effective date');$reason=trim((string)($data['reason']??''));
            if(!is_numeric($amount)||!is_finite((float)$amount)||(float)$amount<=0||(float)$amount>999999999999.99||strlen($reason)<5||strlen($reason)>255)throw new DomainException('Positive salary and a reason of 5–255 characters are required.','salary_revision_invalid',422);
            if($date>Db::today()||(!empty($e['joining_date'])&&$date<$e['joining_date']))throw new DomainException('Effective date must be between joining and today. Future revisions are not supported in this release.','salary_effective_date_invalid',422);
            $db=Db::wpdb();$pending=$db->get_var($db->prepare("SELECT id FROM ".Db::table('salary_revisions')." WHERE company_id=%d AND employee_id=%d AND effective_from=%s AND status='pending' LIMIT 1",$a->companyId,$employee,$date));if($pending)throw new DomainException('A pending revision already exists for this date.','salary_revision_pending',409);Db::mustInsert($db,Db::table('salary_revisions'),['company_id'=>$a->companyId,'employee_id'=>$employee,'effective_from'=>$date,'monthly_salary'=>round((float)$amount,2),'status'=>'pending','reason'=>$reason,'created_by'=>$a->employeeId,'created_at'=>Db::now()]);$id=(int)$db->insert_id;
            Audit::add($a,'salary.request','salary_revision',$id,['employee_id'=>$employee,'branch_id'=>(int)$e['assigned_branch_id'],'monthly_salary'=>round((float)$amount,2),'effective_from'=>$date,'reason'=>$reason]);return ['id'=>$id,'status'=>'pending'];
        });
    }
    public static function approve(Actor $a,int $id,bool $approve):array {
        Guard::cap($a,Capabilities::SALARY_APPROVE);
        return Transaction::run(function()use($a,$id,$approve){
            self::lockCompany($a->companyId);$db=Db::wpdb();$t=Db::table('salary_revisions');
            $r=$db->get_row($db->prepare("SELECT * FROM {$t} WHERE company_id=%d AND id=%d FOR UPDATE",$a->companyId,$id),ARRAY_A);
            if(!$r)throw new DomainException('Salary revision not found.','salary_revision_not_found',404);
            $e=self::employee($a,(int)$r['employee_id'],Capabilities::PAYROLL_APPROVE);
            if($r['status']!=='pending')throw new DomainException('Only pending revisions can be reviewed.','salary_revision_state',409);
            if((int)$r['created_by']===$a->employeeId||(int)$r['employee_id']===$a->employeeId)throw new DomainException('Salary review requires an independent checker.','maker_checker_required',409);
            if($approve){
                // A revision may not alter any already generated payroll, including drafts.
                $next=$db->get_var($db->prepare("SELECT MIN(effective_from) FROM {$t} WHERE company_id=%d AND employee_id=%d AND status IN ('approved','baseline') AND effective_from>%s",$a->companyId,(int)$r['employee_id'],$r['effective_from']));
                $end=$next?(new \DateTimeImmutable($next))->modify('-1 day')->format('Y-m-d'):'9999-12-31';
                $conflict=$db->get_var($db->prepare('SELECT pr.id FROM '.Db::table('payroll_runs').' pr JOIN '.Db::table('payroll_items').' pi ON pi.payroll_run_id=pr.id WHERE pr.company_id=%d AND pi.employee_id=%d AND pr.period_end>=%s AND pr.period_start<=%s LIMIT 1',$a->companyId,(int)$r['employee_id'],$r['effective_from'],$end));
                if($conflict)throw new DomainException('Existing payroll intersects this salary revision. Resolve the draft or use a reviewed arrears process.','salary_payroll_conflict',409);
                $duplicate=$db->get_var($db->prepare("SELECT id FROM {$t} WHERE company_id=%d AND employee_id=%d AND effective_from=%s AND status='approved' LIMIT 1",$a->companyId,(int)$r['employee_id'],$r['effective_from']));
                if($duplicate)throw new DomainException('An approved revision already exists for this date.','salary_revision_duplicate',409);
            }
            Db::mustUpdate($db,$t,['status'=>$approve?'approved':'rejected','approved_by'=>$a->employeeId,'approved_at'=>Db::now()],['id'=>$id]);
            if($approve){$latest=$db->get_var($db->prepare("SELECT monthly_salary FROM {$t} WHERE company_id=%d AND employee_id=%d AND status IN ('approved','baseline') AND effective_from<=%s ORDER BY effective_from DESC,id DESC LIMIT 1",$a->companyId,(int)$r['employee_id'],Db::today()));Db::mustUpdate($db,Db::table('employees'),['monthly_salary'=>$latest,'updated_at'=>Db::now()],['id'=>(int)$r['employee_id'],'company_id'=>$a->companyId]);}
            Audit::add($a,'salary.review','salary_revision',$id,['employee_id'=>(int)$r['employee_id'],'branch_id'=>(int)$e['assigned_branch_id'],'approved'=>$approve,'old_current_salary'=>$e['monthly_salary'],'requested_salary'=>$r['monthly_salary'],'effective_from'=>$r['effective_from'],'reason'=>$r['reason']]);return ['id'=>$id,'status'=>$approve?'approved':'rejected'];
        });
    }
    public static function policy(Actor $a,?array $data=null):array {
        Guard::allActiveBranches($a,Capabilities::PAYROLL_APPROVE);$db=Db::wpdb();$key='payroll_leave_types';
        if($data===null){$raw=$db->get_var($db->prepare('SELECT setting_value FROM '.Db::table('settings').' WHERE company_id=%d AND setting_key=%s',$a->companyId,$key));return ['basis'=>'scheduled_working_days','leave_types'=>json_decode((string)$raw,true)?:[]];}
        Guard::cap($a,Capabilities::ACCESS_MANAGE);$map=$data['leave_types']??null;$reason=trim((string)($data['reason']??''));
        if(!is_array($map)||strlen($reason)<5)throw new DomainException('leave_types map and reason are required.','payroll_policy_invalid',422);
        $clean=[];foreach($map as$k=>$v){$k=strtoupper(trim((string)$k));if($k===''||strlen($k)>50||!is_bool($v)||array_key_exists($k,$clean))throw new DomainException('Leave type values must be true (paid) or false (unpaid).','payroll_policy_invalid',422);$clean[$k]=$v;}
        return Transaction::run(function()use($a,$clean,$reason,$key){self::lockCompany($a->companyId);$db=Db::wpdb();$t=Db::table('settings');$old=$db->get_row($db->prepare("SELECT * FROM {$t} WHERE company_id=%d AND setting_key=%s",$a->companyId,$key),ARRAY_A);$values=['setting_value'=>wp_json_encode($clean),'updated_by'=>$a->employeeId,'updated_at'=>Db::now()];if($old)Db::mustUpdate($db,$t,$values,['id'=>(int)$old['id']]);else Db::mustInsert($db,$t,['company_id'=>$a->companyId,'setting_key'=>$key]+$values);Audit::add($a,'payroll.policy','setting',$key,['old'=>json_decode((string)($old['setting_value']??''),true),'new'=>$clean,'reason'=>$reason]);return ['basis'=>'scheduled_working_days','leave_types'=>$clean];});
    }
}
