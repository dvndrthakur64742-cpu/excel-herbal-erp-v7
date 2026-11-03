<?php
namespace ExcelHerbal\ERP7\Payroll;

use ExcelHerbal\ERP7\Database\Db;
use ExcelHerbal\ERP7\Domain\DomainException;
use ExcelHerbal\ERP7\Security\Actor;
use ExcelHerbal\ERP7\Security\Capabilities;
use ExcelHerbal\ERP7\Security\Guard;
use ExcelHerbal\ERP7\Security\HierarchyScope;

/**
 * Read-only payout evidence preflight.
 *
 * Paid payroll records are NOT evidence that a specific reward was included.
 * Until an immutable reward-to-payroll-item allocation exists, this endpoint
 * always fails closed, never posts money, and never marks a reward settled.
 */
final class RewardSettlementPreflightService {
    /** @return array<string,mixed> */
    public static function inspect(Actor $actor,int $rewardId):array {
        Guard::cap($actor,Capabilities::REWARDS_APPROVE);
        Guard::cap($actor,Capabilities::PAYROLL_PAY);
        if($rewardId<1)
            throw new DomainException('Invalid reward ID.','reward_not_found',404);
        $db=Db::wpdb();
        $reward=$db->get_row($db->prepare(
            'SELECT * FROM '.Db::table('reward_adjustments').
            ' WHERE company_id=%d AND id=%d',
            $actor->companyId,$rewardId
        ),ARRAY_A);
        if(!$reward)
            throw new DomainException('Reward not found.','reward_not_found',404);
        $branch=(int)$reward['branch_id'];
        $employee=(int)$reward['employee_id'];
        Guard::branch($actor,$branch,Capabilities::REWARDS_APPROVE);
        Guard::branch($actor,$branch,Capabilities::PAYROLL_PAY);
        HierarchyScope::assertCanViewEmployee($actor,$employee);
        if(in_array($actor->employeeId,[
            $employee,(int)$reward['created_by'],
        ],true))
            throw new DomainException(
                'Reward requester or beneficiary cannot verify their own payout.',
                'maker_checker_required',409
            );

        $blockers=[];
        if($reward['status']!=='approved')
            $blockers[]='reward_not_approved';
        if(!in_array($reward['adjustment_type'],[
            'bonus','incentive','recognition',
        ],true))
            $blockers[]='reward_type_not_cash_reward';
        $amount=SalaryStructureService::paise(
            (string)$reward['amount'],'reward.amount'
        );
        if($amount<=0)$blockers[]='reward_amount_zero';

        // Informational ONLY: a payroll payment can exist without including
        // any part of this reward. Never infer reward attribution from an
        // employee ID, a bonus total, or a coincident payment date.
        $related=(array)$db->get_results($db->prepare(
            'SELECT pr.id AS payroll_run_id,pr.period_start,pr.period_end'.
            ' FROM '.Db::table('payroll_runs').' pr'.
            ' JOIN '.Db::table('payroll_items').' pi'.
            ' ON pi.payroll_run_id=pr.id'.
            ' WHERE pr.company_id=%d AND pr.branch_id=%d'.
            " AND pr.status='paid'".
            ' AND pr.payment_journal_entry_id IS NOT NULL'.
            ' AND pi.employee_id=%d'.
            ' ORDER BY pr.period_end DESC,pr.id DESC LIMIT 10',
            $actor->companyId,$branch,$employee
        ),ARRAY_A);
        $blockers[]='reward_to_payroll_allocation_missing';
        $blockers[]='reward_settlement_execution_not_enabled';

        return [
            'id'=>$rewardId,
            'employee_id'=>$employee,
            'branch_id'=>$branch,
            'status'=>(string)$reward['status'],
            'amount'=>(string)$reward['amount'],
            'payment_ready'=>false,
            'payment_posted'=>false,
            'settled'=>false,
            'reward_payroll_allocation_verified'=>false,
            'unattributed_paid_payroll_runs'=>$related,
            'unattributed_runs_are_payment_proof'=>false,
            'blocking_reason_codes'=>array_values(array_unique($blockers)),
            'next_required_control'=>'immutable_reward_payroll_item_allocation_and_paid_journal_reconciliation',
        ];
    }
}
