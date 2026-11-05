<?php
namespace ExcelHerbal\ERP7\Payroll;

use ExcelHerbal\ERP7\Database\Db;
use ExcelHerbal\ERP7\Database\Transaction;
use ExcelHerbal\ERP7\Domain\DomainException;
use ExcelHerbal\ERP7\Security\Actor;
use ExcelHerbal\ERP7\Security\Audit;
use ExcelHerbal\ERP7\Security\Capabilities;
use ExcelHerbal\ERP7\Security\Guard;
use ExcelHerbal\ERP7\Security\HierarchyScope;
use ExcelHerbal\ERP7\Organization\EmployeeChoiceService;

/**
 * Non-posting reward/penalty approval register.
 *
 * Deliberately does NOT modify payroll_items, performance_entries, payment
 * accounts, ledger journals, employee designations or balances. The separate
 * reward-pay endpoint is a release blocker until a paid payroll/ledger
 * allocation contract, duplicate-prevention, and recovery are implemented.
 */
final class RewardAdjustmentService {
    private const TYPES=[
        'incentive','bonus','recognition','penalty','points_adjustment'
    ];
    private const VIEW=[
        Capabilities::REWARDS_VIEW,
        Capabilities::REWARDS_MANAGE,
        Capabilities::REWARDS_APPROVE,
    ];

    /** Decimal hundredths, signed only when explicitly permitted. */
    public static function points(mixed $raw):string {
        if(!is_string($raw)&&!is_int($raw)&&!is_float($raw))
            throw new DomainException('Invalid points.', 'reward_points_invalid',422);
        if(is_float($raw)&&!is_finite($raw))
            throw new DomainException('Non-finite points.', 'reward_points_invalid',422);
        $value=trim((string)$raw);
        if(!preg_match('/^-?[0-9]{1,10}(?:\.[0-9]{1,2})?$/D',$value))
            throw new DomainException('Points support two decimal places.','reward_points_invalid',422);
        $negative=str_starts_with($value,'-');
        $numeric=$negative?substr($value,1):$value;
        [$whole,$dec]=array_pad(explode('.',$numeric,2),2,'');
        $hundredths=(int)$whole*100+(int)str_pad($dec,2,'0',STR_PAD_RIGHT);
        if($hundredths>999999999999)
            throw new DomainException('Points out of range.','reward_points_invalid',422);
        $prefix=$negative&&$hundredths>0?'-':'';
        return $prefix.intdiv($hundredths,100).'.'.
            str_pad((string)($hundredths%100),2,'0',STR_PAD_LEFT);
    }

    /** @return array{adjustment_type:string,amount:string,points:string,reason:string} */
    public static function payload(array $data):array {
        $type=trim((string)($data['adjustment_type']??''));
        if(!in_array($type,self::TYPES,true))
            throw new DomainException('Unsupported reward type.','reward_type_invalid',422);
        $amountCents=SalaryStructureService::paise($data['amount']??null,'amount');
        $points=self::points($data['points']??null);
        $reason=trim((string)($data['reason']??''));
        if(strlen($reason)<5||strlen($reason)>255||
            preg_match('/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/',$reason))
            throw new DomainException(
                'Explanation of 5-255 printable characters required.',
                'reward_reason_invalid',422
            );
        if($type==='points_adjustment'&&$amountCents!==0)
            throw new DomainException(
                'Points-only adjustment must have zero money amount.',
                'reward_points_only',422
            );
        if(!in_array($type,['penalty','points_adjustment'],true)&&
            str_starts_with($points,'-'))
            throw new DomainException(
                'Negative points require penalty or points adjustment.',
                'reward_points_sign_invalid',422
            );
        if($amountCents===0&&$points==='0.00')
            throw new DomainException(
                'Nonzero amount or points is required.','reward_empty_invalid',422
            );
        return [
            'adjustment_type'=>$type,
            'amount'=>intdiv($amountCents,100).'.'.
                str_pad((string)($amountCents%100),2,'0',STR_PAD_LEFT),
            'points'=>$points,
            'reason'=>$reason,
        ];
    }

    private static function branch(Actor $actor,int $branch):void {
        Guard::branchAny($actor,$branch,self::VIEW);
    }

    /** Privacy-minimal active employee selection; never exposes salary figures. */
    public static function employeeChoices(Actor $actor,int $branch):array {
        Guard::branch($actor,$branch,Capabilities::REWARDS_MANAGE);
        return EmployeeChoiceService::list($actor,$branch,false,true);
    }

    /** Branch/hierarchy-scoped review queue; read-only. */
    public static function list(Actor $actor,int $branch):array {
        self::branch($actor,$branch);
        $ids=HierarchyScope::visibleEmployeeIds($actor,$branch);
        if(!$ids)return [];
        $db=Db::wpdb();
        $marks=implode(',',array_fill(0,count($ids),'%d'));
        return (array)$db->get_results($db->prepare(
            'SELECT r.*,e.employee_code,e.full_name AS employee_name'.
            ' FROM '.Db::table('reward_adjustments').' r'.
            ' JOIN '.Db::table('employees').' e'.
            ' ON e.company_id=r.company_id AND e.id=r.employee_id'.
            ' WHERE r.company_id=%d AND r.branch_id=%d'.
            ' AND e.assigned_branch_id=%d'.
            " AND r.employee_id IN ({$marks})".
            ' ORDER BY r.created_at DESC,r.id DESC LIMIT 100',
            ...array_merge([$actor->companyId,$branch,$branch],$ids)
        ),ARRAY_A);
    }

    public static function create(Actor $actor,array $input):array {
        Guard::cap($actor,Capabilities::REWARDS_MANAGE);
        $branch=filter_var($input['branch_id']??null,FILTER_VALIDATE_INT,
            ['options'=>['min_range'=>1]]);
        $employee=filter_var($input['employee_id']??null,FILTER_VALIDATE_INT,
            ['options'=>['min_range'=>1]]);
        if(!is_int($branch)||!is_int($employee))
            throw new DomainException(
                'Branch and employee are required.','reward_scope_invalid',422
            );
        Guard::branch($actor,$branch,Capabilities::REWARDS_MANAGE);
        HierarchyScope::assertCanViewEmployee($actor,$employee);
        if($actor->employeeId===$employee)
            throw new DomainException('Self reward proposals prohibited.','reward_self_forbidden',403);
        $data=self::payload($input);
        return Transaction::run(function()use($actor,$branch,$employee,$data){
            SalaryService::lockCompany($actor->companyId);
            $db=Db::wpdb();
            $e=$db->get_row($db->prepare(
                'SELECT id FROM '.Db::table('employees').
                " WHERE company_id=%d AND id=%d AND assigned_branch_id=%d AND status='active'",
                $actor->companyId,$employee,$branch
            ),ARRAY_A);
            if(!$e)
                throw new DomainException('Employee is not active in branch.','reward_employee_mismatch',409);
            Db::mustInsert($db,Db::table('reward_adjustments'),[
                'company_id'=>$actor->companyId,
                'branch_id'=>$branch,'employee_id'=>$employee,
                ...$data,'status'=>'pending',
                'created_by'=>$actor->employeeId,
                'created_at'=>Db::now(),
            ]);
            $id=(int)$db->insert_id;
            Audit::add($actor,'reward.request','reward_adjustment',$id,[
                'branch_id'=>$branch,'employee_id'=>$employee,
                'adjustment_type'=>$data['adjustment_type'],
                'amount'=>$data['amount'],'points'=>$data['points'],
                'reason'=>$data['reason'],
                'funds_posted'=>false,
            ]);
            return ['id'=>$id,'status'=>'pending','funds_posted'=>false,
                'points_applied'=>false];
        });
    }

    public static function decide(Actor $actor,int $id,string $decision):array {
        Guard::cap($actor,Capabilities::REWARDS_APPROVE);
        if(!in_array($decision,['approved','rejected'],true))
            throw new DomainException('Invalid reviewer decision.','reward_decision_invalid',422);
        return Transaction::run(function()use($actor,$id,$decision){
            SalaryService::lockCompany($actor->companyId);
            $db=Db::wpdb();
            $record=$db->get_row($db->prepare(
                'SELECT * FROM '.Db::table('reward_adjustments').
                ' WHERE id=%d AND company_id=%d FOR UPDATE',
                $id,$actor->companyId
            ),ARRAY_A);
            if(!$record)
                throw new DomainException('Reward request not found.','reward_not_found',404);
            $branch=(int)$record['branch_id'];
            Guard::branch($actor,$branch,Capabilities::REWARDS_APPROVE);
            HierarchyScope::assertCanViewEmployee(
                $actor,(int)$record['employee_id']
            );
            if($record['status']!=='pending')
                throw new DomainException('Reward request already reviewed.','reward_state_invalid',409);
            if(in_array($actor->employeeId,[
                (int)$record['created_by'],(int)$record['employee_id']
            ],true))throw new DomainException(
                'Independent checker required.','maker_checker_required',409
            );
            $active=$db->get_var($db->prepare(
                'SELECT id FROM '.Db::table('employees').
                " WHERE company_id=%d AND id=%d AND assigned_branch_id=%d AND status='active'",
                $actor->companyId,(int)$record['employee_id'],$branch
            ));
            if(!$active)
                throw new DomainException('Employee transferred or inactive.','reward_employee_mismatch',409);
            Db::mustUpdate($db,Db::table('reward_adjustments'),[
                'status'=>$decision,'reviewed_by'=>$actor->employeeId,
                'reviewed_at'=>Db::now(),
            ],['company_id'=>$actor->companyId,'id'=>$id]);
            Audit::add($actor,'reward.decision','reward_adjustment',$id,[
                'branch_id'=>$branch,'employee_id'=>(int)$record['employee_id'],
                'decision'=>$decision,
                'funds_posted'=>false,'points_applied'=>false,
            ]);
            return ['id'=>$id,'status'=>$decision,
                'funds_posted'=>false,'points_applied'=>false,
                'payroll_linked'=>false];
        });
    }
}
