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
use ExcelHerbal\ERP7\Security\HierarchyScope;

/**
 * Four-component monthly salary drafts with independent salary approval.
 * The existing approved salary_revisions ledger remains payroll's source of
 * truth. Drafts never modify employee salary, pay payroll, or post journals.
 */
final class SalaryStructureService {
    private const VIEW_CAPS=[
        Capabilities::SALARY_VIEW,
        Capabilities::SALARY_MANAGE,
        Capabilities::SALARY_APPROVE,
    ];
    private const MONEY_MAX_PAISE=99999999999999;

    /** Exact integer paise, no binary-float totals or fractional pennies. */
    public static function paise(mixed $value,string $field):int {
        if(!is_int($value)&&!is_float($value)&&!is_string($value))
            throw new DomainException('Invalid salary component.','salary_structure_amount_invalid',422);
        if(is_float($value)&&!is_finite($value))
            throw new DomainException('Non-finite salary component.','salary_structure_amount_invalid',422);
        $text=trim((string)$value);
        if(!preg_match('/^\d{1,12}(?:\.\d{1,2})?$/D',$text))
            throw new DomainException(
                'Salary component must have at most two decimal places: '.$field,
                'salary_structure_amount_invalid',422
            );
        [$whole,$dec]=array_pad(explode('.',$text,2),2,'');
        $amount=(int)$whole*100+(int)str_pad($dec,2,'0',STR_PAD_RIGHT);
        if($amount>self::MONEY_MAX_PAISE)
            throw new DomainException('Salary amount too large.','salary_structure_amount_invalid',422);
        return $amount;
    }

    private static function format(int $paise):string {
        return intdiv($paise,100).'.'.str_pad((string)($paise%100),2,'0',STR_PAD_LEFT);
    }

    /** @return array<string,string> */
    public static function components(array $data):array {
        $fields=['monthly_basic','hra','fixed_allowance','other_fixed'];
        $paise=[];$total=0;
        foreach($fields as $field){
            if(!array_key_exists($field,$data))
                throw new DomainException(
                    'All four salary components are required.',
                    'salary_structure_components_missing',422
                );
            $amount=self::paise($data[$field],$field);
            if($field==='monthly_basic'&&$amount<=0)
                throw new DomainException('Positive basic salary required.','salary_structure_basic_invalid',422);
            $paise[$field]=$amount;
            $total+=$amount;
        }
        if($total>self::MONEY_MAX_PAISE)
            throw new DomainException('Monthly salary total exceeds limit.','salary_structure_total_invalid',422);
        $out=[];
        foreach($paise as $field=>$amount)$out[$field]=self::format($amount);
        $out['gross_monthly']=self::format($total);
        return $out;
    }

    /** Read-only, authorized, branch/hierarchy-scoped review list. */
    public static function list(Actor $actor,int $branch):array {
        Guard::branchAny($actor,$branch,self::VIEW_CAPS);
        $employeeIds=HierarchyScope::visibleEmployeeIds($actor,$branch);
        if(!$employeeIds)return [];
        $db=Db::wpdb();
        $placeholders=implode(',',array_fill(0,count($employeeIds),'%d'));
        return (array)$db->get_results($db->prepare(
            'SELECT s.*,e.full_name employee_name,e.employee_code'.
            ' FROM '.Db::table('salary_structure_versions').' s'.
            ' JOIN '.Db::table('employees').' e'.
            ' ON e.id=s.employee_id AND e.company_id=s.company_id'.
            ' WHERE s.company_id=%d AND s.branch_id=%d'.
            ' AND e.assigned_branch_id=%d'.
            " AND s.employee_id IN ({$placeholders})".
            ' ORDER BY s.created_at DESC,s.id DESC LIMIT 100',
            ...array_merge([$actor->companyId,$branch,$branch],$employeeIds)
        ),ARRAY_A);
    }

    public static function create(Actor $actor,array $data):array {
        Guard::cap($actor,Capabilities::SALARY_MANAGE);
        $branch=filter_var($data['branch_id']??null,FILTER_VALIDATE_INT,
            ['options'=>['min_range'=>1]]);
        $employee=filter_var($data['employee_id']??null,FILTER_VALIDATE_INT,
            ['options'=>['min_range'=>1]]);
        if(!is_int($branch)||!is_int($employee))
            throw new DomainException('Valid branch and employee are required.','salary_structure_scope_invalid',422);
        Guard::branch($actor,$branch,Capabilities::SALARY_MANAGE);
        HierarchyScope::assertCanViewEmployee($actor,$employee);
        if($actor->employeeId===$employee)
            throw new DomainException('Own salary cannot be drafted.','salary_self_change',403);
        $date=Input::date((string)($data['effective_from']??''),'Salary effective date');
        if($date>Db::today())
            throw new DomainException(
                'Future salary effective dates are not enabled.',
                'salary_effective_date_invalid',422
            );
        $reason=trim((string)($data['change_reason']??''));
        if(strlen($reason)<5||strlen($reason)>255)
            throw new DomainException('A 5-255 character reason is required.','salary_structure_reason_invalid',422);
        $parts=self::components($data);
        return Transaction::run(function()use($actor,$branch,$employee,$date,$reason,$parts){
            SalaryService::lockCompany($actor->companyId);
            $db=Db::wpdb();
            $e=$db->get_row($db->prepare(
                'SELECT id,joining_date FROM '.Db::table('employees').
                " WHERE id=%d AND company_id=%d AND assigned_branch_id=%d AND status='active'",
                $employee,$actor->companyId,$branch
            ),ARRAY_A);
            if(!$e)throw new DomainException(
                'Active employee is not in authorized branch.',
                'employee_branch_mismatch',422
            );
            if(!empty($e['joining_date'])&&$date<$e['joining_date'])
                throw new DomainException('Date precedes joining.','salary_effective_date_invalid',422);
            $pending=(int)$db->get_var($db->prepare(
                'SELECT COUNT(*) FROM '.Db::table('salary_structure_versions').
                " WHERE company_id=%d AND employee_id=%d AND effective_from=%s AND status='draft'",
                $actor->companyId,$employee,$date
            ));
            $revision=(int)$db->get_var($db->prepare(
                'SELECT COUNT(*) FROM '.Db::table('salary_revisions').
                " WHERE company_id=%d AND employee_id=%d AND effective_from=%s AND status IN ('approved','pending')",
                $actor->companyId,$employee,$date
            ));
            if($pending||$revision)
                throw new DomainException(
                    'Salary proposal or active revision already exists for date.',
                    'salary_structure_date_conflict',409
                );
            Db::mustInsert($db,Db::table('salary_structure_versions'),[
                'company_id'=>$actor->companyId,
                'branch_id'=>$branch,
                'employee_id'=>$employee,
                'effective_from'=>$date,
                ...$parts,
                'change_reason'=>$reason,'status'=>'draft',
                'created_by'=>$actor->employeeId,'created_at'=>Db::now(),
            ]);
            $id=(int)$db->insert_id;
            Audit::add($actor,'salary_structure.draft','salary_structure',$id,[
                'branch_id'=>$branch,'employee_id'=>$employee,
                'effective_from'=>$date,'gross_monthly'=>$parts['gross_monthly'],
                'reason'=>$reason,
            ]);
            return [
                'id'=>$id,'status'=>'draft','employee_id'=>$employee,
                'gross_monthly'=>$parts['gross_monthly'],
            ];
        });
    }

    public static function approve(Actor $actor,int $id):array {
        Guard::cap($actor,Capabilities::SALARY_APPROVE);
        if($id<1)throw new DomainException(
            'Invalid salary structure ID.','salary_structure_not_found',404
        );
        return Transaction::run(function()use($actor,$id){
            SalaryService::lockCompany($actor->companyId);
            $db=Db::wpdb();
            $table=Db::table('salary_structure_versions');
            $s=$db->get_row($db->prepare(
                "SELECT * FROM {$table} WHERE id=%d AND company_id=%d FOR UPDATE",
                $id,$actor->companyId
            ),ARRAY_A);
            if(!$s)throw new DomainException(
                'Salary structure not found.','salary_structure_not_found',404
            );
            $branch=(int)$s['branch_id'];
            $employee=(int)$s['employee_id'];
            Guard::branch($actor,$branch,Capabilities::SALARY_APPROVE);
            HierarchyScope::assertCanViewEmployee($actor,$employee);
            if((int)$s['created_by']===$actor->employeeId||
                $employee===$actor->employeeId)
                throw new DomainException(
                    'Independent salary approver required.','maker_checker_required',409
                );
            if($s['status']!=='draft')
                throw new DomainException(
                    'Only draft salary structures can be approved.',
                    'salary_structure_state_invalid',409
                );
            $e=$db->get_row($db->prepare(
                'SELECT id,joining_date FROM '.Db::table('employees').
                " WHERE id=%d AND company_id=%d AND assigned_branch_id=%d AND status='active'",
                $employee,$actor->companyId,$branch
            ),ARRAY_A);
            if(!$e)throw new DomainException(
                'Employee transferred or no longer active. New review required.',
                'employee_branch_mismatch',409
            );
            $date=(string)$s['effective_from'];
            if($date>Db::today()||
                (!empty($e['joining_date'])&&$date<$e['joining_date']))
                throw new DomainException(
                    'Effective date is outside approved employee period.',
                    'salary_effective_date_invalid',422
                );
            $revisionTable=Db::table('salary_revisions');
            $duplicate=(int)$db->get_var($db->prepare(
                "SELECT COUNT(*) FROM {$revisionTable}".
                " WHERE company_id=%d AND employee_id=%d AND effective_from=%s AND status IN ('approved','pending')",
                $actor->companyId,$employee,$date
            ));
            if($duplicate)throw new DomainException(
                'Effective salary revision already exists.','salary_structure_date_conflict',409
            );
            // Same interval and lock policy as SalaryService::approve.
            $next=$db->get_var($db->prepare(
                "SELECT MIN(effective_from) FROM {$revisionTable}".
                " WHERE company_id=%d AND employee_id=%d AND status IN ('approved','baseline') AND effective_from>%s",
                $actor->companyId,$employee,$date
            ));
            $end=$next?(new \DateTimeImmutable((string)$next))
                ->modify('-1 day')->format('Y-m-d'):'9999-12-31';
            $payrollConflict=(int)$db->get_var($db->prepare(
                'SELECT pr.id FROM '.Db::table('payroll_runs').' pr'.
                ' JOIN '.Db::table('payroll_items').' pi ON pi.payroll_run_id=pr.id'.
                ' WHERE pr.company_id=%d AND pi.employee_id=%d'.
                ' AND pr.period_end>=%s AND pr.period_start<=%s LIMIT 1',
                $actor->companyId,$employee,$date,$end
            ));
            if($payrollConflict)throw new DomainException(
                'Existing payroll intersects salary effective period.',
                'salary_payroll_conflict',409
            );
            Db::mustInsert($db,$revisionTable,[
                'company_id'=>$actor->companyId,
                'employee_id'=>$employee,'effective_from'=>$date,
                'monthly_salary'=>$s['gross_monthly'],'status'=>'approved',
                'reason'=>$s['change_reason'],
                'created_by'=>(int)$s['created_by'],
                'approved_by'=>$actor->employeeId,
                'created_at'=>$s['created_at'],'approved_at'=>Db::now(),
            ]);
            $revisionId=(int)$db->insert_id;
            Db::mustUpdate($db,$table,[
                'status'=>'approved','salary_revision_id'=>$revisionId,
                'approved_by'=>$actor->employeeId,'approved_at'=>Db::now(),
            ],['id'=>$id,'company_id'=>$actor->companyId]);
            $latest=$db->get_var($db->prepare(
                "SELECT monthly_salary FROM {$revisionTable}".
                " WHERE company_id=%d AND employee_id=%d".
                " AND status IN ('approved','baseline') AND effective_from<=%s".
                ' ORDER BY effective_from DESC,id DESC LIMIT 1',
                $actor->companyId,$employee,Db::today()
            ));
            if($latest===null)throw new DomainException(
                'Approved salary could not be resolved.','salary_structure_salary_missing',500
            );
            Db::mustUpdate($db,Db::table('employees'),[
                'monthly_salary'=>$latest,'updated_at'=>Db::now(),
            ],['id'=>$employee,'company_id'=>$actor->companyId]);
            Audit::add($actor,'salary_structure.approve','salary_structure',$id,[
                'branch_id'=>$branch,'employee_id'=>$employee,
                'salary_revision_id'=>$revisionId,
                'effective_from'=>$date,'gross_monthly'=>$s['gross_monthly'],
            ]);
            return [
                'id'=>$id,'status'=>'approved',
                'salary_revision_id'=>$revisionId,
                'gross_monthly'=>(string)$s['gross_monthly'],
                'payroll_posted'=>false,
            ];
        });
    }
}
