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
        // A proposal supplies an auditable link candidate only. It is
        // NEVER proof that the bonus was posted in payroll or transferred.
        $proposal=$db->get_row($db->prepare(
            'SELECT lp.id,lp.payroll_run_id,lp.payroll_item_id,'.
            ' lp.status,lp.amount_snapshot,lp.item_bonus_snapshot,'.
            ' pr.status AS payroll_run_status,pr.payment_journal_entry_id,'.
            ' pi.employee_id AS item_employee_id,pi.bonus AS current_item_bonus'.
            ' FROM '.Db::table('reward_payroll_link_proposals').' lp'.
            ' LEFT JOIN '.Db::table('payroll_runs').' pr'.
            ' ON pr.id=lp.payroll_run_id AND pr.company_id=lp.company_id'.
            ' LEFT JOIN '.Db::table('payroll_items').' pi'.
            ' ON pi.id=lp.payroll_item_id AND pi.payroll_run_id=lp.payroll_run_id'.
            ' WHERE lp.company_id=%d AND lp.reward_id=%d LIMIT 1',
            $actor->companyId,$rewardId
        ),ARRAY_A);
        $proposalEvidence=null;
        if($proposal){
            $snapAmount=SalaryStructureService::paise(
                (string)$proposal['amount_snapshot'],'amount_snapshot'
            );
            $snapBonus=SalaryStructureService::paise(
                (string)$proposal['item_bonus_snapshot'],'item_bonus_snapshot'
            );
            $liveBonus=$proposal['current_item_bonus']===null?null:
                SalaryStructureService::paise(
                    (string)$proposal['current_item_bonus'],'current_bonus'
                );
            $sameSnapshot=$snapAmount===$amount &&
                $liveBonus!==null && $liveBonus===$snapBonus &&
                (int)($proposal['item_employee_id']??0)===$employee;
            if($proposal['status']==='proposed_unfunded'&&!$sameSnapshot)
                $blockers[]='reward_payroll_link_proposal_stale';
            $proposalEvidence=[
                'proposal_id'=>(int)$proposal['id'],
                'payroll_run_id'=>(int)$proposal['payroll_run_id'],
                'payroll_item_id'=>(int)$proposal['payroll_item_id'],
                'proposal_status'=>(string)$proposal['status'],
                'payroll_run_status'=>$proposal['payroll_run_status'],
                'snapshot_consistent'=>$sameSnapshot,
                'snapshot_consistency_is_payment_proof'=>false,
                'current_paid_journal_id_is_reward_proof'=>false,
            ];
        }
        // Allocated payroll bonus is evidence of draft earnings only. It
        // NEVER proves employee bank/UPI payment. A journal for an entire
        // payroll run cannot by itself prove per-reward settlement.
        $allocation=$db->get_row($db->prepare(
            'SELECT a.id,a.status,a.reward_amount,'.
            ' a.item_bonus_after,a.item_net_after,a.payroll_run_id,'.
            ' a.payroll_item_id,a.employee_id AS allocation_employee,'.
            ' pi.bonus AS live_bonus,pi.net_salary AS live_net,'.
            ' pi.employee_id AS item_employee,'.
            ' pr.status AS run_status,pr.payment_journal_entry_id'.
            ' FROM '.Db::table('reward_payroll_allocations').' a'.
            ' LEFT JOIN '.Db::table('payroll_runs').' pr'.
            ' ON pr.id=a.payroll_run_id AND pr.company_id=a.company_id'.
            ' LEFT JOIN '.Db::table('payroll_items').' pi'.
            ' ON pi.id=a.payroll_item_id'.
            ' AND pi.payroll_run_id=a.payroll_run_id'.
            ' WHERE a.company_id=%d AND a.reward_id=%d LIMIT 1',
            $actor->companyId,$rewardId
        ),ARRAY_A);
        $allocationEvidence=null;
        $allocationVerified=false;
        if($allocation){
            $allocationVerified=
                $allocation['status']==='allocated_unpaid'&&
                (int)($allocation['allocation_employee']??0)===$employee&&
                (int)($allocation['item_employee']??0)===$employee&&
                $allocation['live_bonus']!==null&&
                $allocation['live_net']!==null&&
                SalaryStructureService::paise(
                    (string)$allocation['reward_amount'],'allocated_reward'
                )===$amount&&
                SalaryStructureService::paise(
                    (string)$allocation['item_bonus_after'],'allocated_bonus'
                )===SalaryStructureService::paise(
                    (string)$allocation['live_bonus'],'live_bonus'
                )&&
                SalaryStructureService::paise(
                    (string)$allocation['item_net_after'],'allocated_net'
                )===SalaryStructureService::paise(
                    (string)$allocation['live_net'],'live_net'
                );
            if(!$allocationVerified)
                $blockers[]='reward_payroll_allocation_drift';
            $allocationEvidence=[
                'allocation_id'=>(int)$allocation['id'],
                'payroll_run_id'=>(int)$allocation['payroll_run_id'],
                'payroll_item_id'=>(int)$allocation['payroll_item_id'],
                'allocation_status'=>(string)$allocation['status'],
                'payroll_run_status'=>$allocation['run_status'],
                'draft_earnings_allocation_verified'=>$allocationVerified,
                'paid_payroll_journal_is_reward_settlement_proof'=>false,
            ];
        }
        if(!$allocationVerified)$blockers[]='reward_to_payroll_allocation_missing';
        $blockers[]='reward_settlement_execution_not_enabled';
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
            'reward_payroll_allocation_verified'=>$allocationVerified,
            'allocated_payroll_earnings'=>$allocationEvidence,
            'unfunded_link_proposal'=>$proposalEvidence,
            'unattributed_paid_payroll_runs'=>$related,
            'unattributed_runs_are_payment_proof'=>false,
            'blocking_reason_codes'=>array_values(array_unique($blockers)),
            'next_required_control'=>'immutable_reward_payroll_item_allocation_and_paid_journal_reconciliation',
        ];
    }
}
