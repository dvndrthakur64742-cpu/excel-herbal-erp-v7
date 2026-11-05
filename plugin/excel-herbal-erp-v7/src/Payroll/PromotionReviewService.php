<?php
namespace ExcelHerbal\ERP7\Payroll;

use ExcelHerbal\ERP7\Core\Input;
use ExcelHerbal\ERP7\Database\Db;
use ExcelHerbal\ERP7\Database\Transaction;
use ExcelHerbal\ERP7\Domain\DomainException;
use ExcelHerbal\ERP7\Organization\EmployeeChoiceService;
use ExcelHerbal\ERP7\Security\Actor;
use ExcelHerbal\ERP7\Security\Audit;
use ExcelHerbal\ERP7\Security\Capabilities;
use ExcelHerbal\ERP7\Security\Guard;
use ExcelHerbal\ERP7\Security\HierarchyScope;

/**
 * Non-executing Promotion/Increment review.
 *
 * Reviewer approval only queues a controlled future HR execution. It never
 * changes primary designation, reporting tree, branch, capabilities, roles,
 * employee salary, payroll, or any journal. Eligibility points/days and the
 * future execution/rollback contract are intentionally release blockers.
 */
final class PromotionReviewService {
    private const VIEW=[
        Capabilities::PROMOTION_VIEW,
        Capabilities::PROMOTION_REQUEST,
        Capabilities::PROMOTION_APPROVE,
    ];

    public static function employeeChoices(Actor $actor,int $branch):array {
        Guard::branch($actor,$branch,Capabilities::PROMOTION_REQUEST);
        return EmployeeChoiceService::list($actor,$branch,false,true);
    }

    public static function list(Actor $actor,int $branch):array {
        Guard::branchAny($actor,$branch,self::VIEW);
        $ids=HierarchyScope::visibleEmployeeIds($actor,$branch);
        if(!$ids)return [];
        $db=Db::wpdb();
        $marks=implode(',',array_fill(0,count($ids),'%d'));
        return (array)$db->get_results($db->prepare(
            'SELECT p.*,e.full_name AS employee_name,e.employee_code'.
            ' FROM '.Db::table('promotion_requests').' p'.
            ' JOIN '.Db::table('employees').' e'.
            ' ON e.id=p.employee_id AND e.company_id=p.company_id'.
            ' WHERE p.company_id=%d AND p.branch_id=%d'.
            ' AND e.assigned_branch_id=%d'.
            " AND p.employee_id IN ({$marks})".
            ' ORDER BY p.created_at DESC,p.id DESC LIMIT 100',
            ...array_merge([$actor->companyId,$branch,$branch],$ids)
        ),ARRAY_A);
    }

    /** Pure input review — points/days eligibility is never presumed. */
    public static function payload(array $input):array {
        $next=strtoupper(trim((string)($input['next_designation_code']??'')));
        if(!preg_match('/^[A-Z0-9_]{2,30}$/D',$next))
            throw new DomainException(
                'Active destination designation code is required.',
                'promotion_designation_invalid',422
            );
        $date=Input::date((string)($input['effective_from']??''),
            'Promotion effective date');
        if($date<Db::today())
            throw new DomainException(
                'Backdated promotion is not supported in review stage.',
                'promotion_effective_date_invalid',422
            );
        $amount=SalaryStructureService::paise(
            $input['monthly_increment_amount']??null,'monthly_increment_amount'
        );
        $reason=trim((string)($input['reason']??''));
        if(strlen($reason)<5||strlen($reason)>255||
            preg_match('/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/',$reason))
            throw new DomainException(
                'Promotion reason must be 5-255 printable characters.',
                'promotion_reason_invalid',422
            );
        return [
            'next_designation_code'=>$next,
            'effective_from'=>$date,
            'monthly_increment_amount'=>intdiv($amount,100).'.'.
                str_pad((string)($amount%100),2,'0',STR_PAD_LEFT),
            'reason'=>$reason,
        ];
    }

    public static function create(Actor $actor,array $input):array {
        Guard::cap($actor,Capabilities::PROMOTION_REQUEST);
        $branch=filter_var($input['branch_id']??null,FILTER_VALIDATE_INT,
            ['options'=>['min_range'=>1]]);
        $employee=filter_var($input['employee_id']??null,FILTER_VALIDATE_INT,
            ['options'=>['min_range'=>1]]);
        if(!is_int($branch)||!is_int($employee))
            throw new DomainException(
                'Branch and employee required.','promotion_scope_invalid',422
            );
        Guard::branch($actor,$branch,Capabilities::PROMOTION_REQUEST);
        HierarchyScope::assertCanViewEmployee($actor,$employee);
        if($actor->employeeId===$employee)
            throw new DomainException(
                'Own promotion requires an independent requester.',
                'promotion_self_forbidden',403
            );
        $data=self::payload($input);
        return Transaction::run(function()use($actor,$branch,$employee,$data){
            SalaryService::lockCompany($actor->companyId);
            $db=Db::wpdb();
            $e=$db->get_row($db->prepare(
                'SELECT id,designation_code FROM '.Db::table('employees').
                " WHERE company_id=%d AND id=%d AND assigned_branch_id=%d AND status='active'",
                $actor->companyId,$employee,$branch
            ),ARRAY_A);
            if(!$e)throw new DomainException(
                'Active employee no longer belongs to branch.',
                'promotion_employee_mismatch',409
            );
            $current=strtoupper(trim((string)$e['designation_code']));
            $next=$data['next_designation_code'];
            if($current===$next)
                throw new DomainException(
                    'Destination must differ from current designation.',
                    'promotion_same_designation',422
                );
            $designation=$db->get_row($db->prepare(
                'SELECT code,promotion_min_points,minimum_days FROM '.
                Db::table('designations').
                " WHERE company_id=%d AND code=%s AND status='active'",
                $actor->companyId,$next
            ),ARRAY_A);
            if(!$designation)throw new DomainException(
                'Destination designation is not active.','promotion_designation_invalid',422
            );
            $open=(int)$db->get_var($db->prepare(
                'SELECT COUNT(*) FROM '.Db::table('promotion_requests').
                " WHERE company_id=%d AND employee_id=%d AND status IN ('pending','approved_pending_execution')",
                $actor->companyId,$employee
            ));
            if($open)throw new DomainException(
                'Another promotion review is already pending.',
                'promotion_pending_exists',409
            );
            Db::mustInsert($db,Db::table('promotion_requests'),[
                'company_id'=>$actor->companyId,'branch_id'=>$branch,
                'employee_id'=>$employee,
                'current_designation_code'=>$current,
                ...$data,
                'promotion_min_points_snapshot'=>$designation['promotion_min_points'],
                'minimum_days_snapshot'=>(int)$designation['minimum_days'],
                'eligibility_state'=>'requires_independent_verification',
                'execution_state'=>'not_executed',
                'status'=>'pending',
                'created_by'=>$actor->employeeId,
                'created_at'=>Db::now(),
            ]);
            $id=(int)$db->insert_id;
            Audit::add($actor,'promotion.request','promotion_request',$id,[
                'branch_id'=>$branch,'employee_id'=>$employee,
                'old_designation'=>$current,
                'next_designation'=>$next,
                'monthly_increment'=>$data['monthly_increment_amount'],
                'effective_from'=>$data['effective_from'],
                'reason'=>$data['reason'],
                'eligibility_verified'=>false,'executed'=>false,
            ]);
            return ['id'=>$id,'status'=>'pending',
                'eligibility_verified'=>false,'executed'=>false];
        });
    }

    public static function decide(Actor $actor,int $id,string $decision):array {
        Guard::cap($actor,Capabilities::PROMOTION_APPROVE);
        Guard::cap($actor,Capabilities::HR_REVIEW);
        if(!in_array($decision,['approved','rejected'],true))
            throw new DomainException(
                'Invalid promotion decision.','promotion_decision_invalid',422
            );
        return Transaction::run(function()use($actor,$id,$decision){
            SalaryService::lockCompany($actor->companyId);
            $db=Db::wpdb();
            $p=$db->get_row($db->prepare(
                'SELECT * FROM '.Db::table('promotion_requests').
                ' WHERE id=%d AND company_id=%d FOR UPDATE',
                $id,$actor->companyId
            ),ARRAY_A);
            if(!$p)throw new DomainException(
                'Promotion request not found.','promotion_not_found',404
            );
            $branch=(int)$p['branch_id'];
            $employee=(int)$p['employee_id'];
            Guard::branch($actor,$branch,Capabilities::PROMOTION_APPROVE);
            HierarchyScope::assertCanViewEmployee($actor,$employee);
            if($p['status']!=='pending')
                throw new DomainException(
                    'Request has already been reviewed.',
                    'promotion_state_invalid',409
                );
            if(in_array($actor->employeeId,[
                (int)$p['created_by'],$employee
            ],true))throw new DomainException(
                'Promotion decision needs an independent checker.',
                'maker_checker_required',409
            );
            if($decision==='approved'){
                $e=$db->get_row($db->prepare(
                    'SELECT designation_code FROM '.Db::table('employees').
                    " WHERE company_id=%d AND id=%d AND assigned_branch_id=%d AND status='active'",
                    $actor->companyId,$employee,$branch
                ),ARRAY_A);
                if(!$e||strtoupper(trim((string)$e['designation_code']))!==
                    (string)$p['current_designation_code'])
                    throw new DomainException(
                        'Employee designation/branch changed; request needs fresh review.',
                        'promotion_employee_changed',409
                    );
                $active=(int)$db->get_var($db->prepare(
                    'SELECT COUNT(*) FROM '.Db::table('designations').
                    " WHERE company_id=%d AND code=%s AND status='active'",
                    $actor->companyId,$p['next_designation_code']
                ));
                if(!$active||$p['effective_from']<Db::today())
                    throw new DomainException(
                        'Destination or effective date is no longer valid.',
                        'promotion_approval_stale',409
                    );
            }
            $status=$decision==='approved'?'approved_pending_execution':'rejected';
            Db::mustUpdate($db,Db::table('promotion_requests'),[
                'status'=>$status,'reviewed_by'=>$actor->employeeId,
                'reviewed_at'=>Db::now(),
            ],['id'=>$id,'company_id'=>$actor->companyId]);
            Audit::add($actor,'promotion.decision','promotion_request',$id,[
                'branch_id'=>$branch,'employee_id'=>$employee,
                'decision'=>$decision,'eligibility_verified'=>false,
                'executed'=>false,'salary_changed'=>false,
                'capabilities_changed'=>false,
            ]);
            return [
                'id'=>$id,'status'=>$status,'executed'=>false,
                'eligibility_verified'=>false,
                'payroll_posted'=>false,
                'roles_changed'=>false,
            ];
        });
    }
}
