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

/**
 * Allocate exactly one approved positive cash reward into one draft payroll
 * item. This creates payroll earnings; it NEVER pays the employee or posts
 * bank/accounting journals. One-to-one assignment prevents manual bonus
 * attribution and double payment until multi-reward reconciliation is designed.
 */
final class RewardPayrollAllocationService {
    private static function paise(mixed $value,string $name):int {
        return SalaryStructureService::paise((string)$value,$name);
    }

    private static function money(int $paise):string {
        return intdiv($paise,100).'.'.str_pad(
            (string)($paise%100),2,'0',STR_PAD_LEFT
        );
    }

    public static function allocate(Actor $actor,int $proposalId):array {
        Guard::cap($actor,Capabilities::REWARDS_APPROVE);
        Guard::cap($actor,Capabilities::PAYROLL_GENERATE);
        if($proposalId<1)throw new DomainException(
            'Reward allocation proposal does not exist.',
            'reward_payroll_proposal_not_found',404
        );
        return Transaction::run(function()use($actor,$proposalId){
            SalaryService::lockCompany($actor->companyId);
            $db=Db::wpdb();
            $proposals=Db::table('reward_payroll_link_proposals');
            $proposal=$db->get_row($db->prepare(
                "SELECT * FROM {$proposals} WHERE id=%d AND company_id=%d FOR UPDATE",
                $proposalId,$actor->companyId
            ),ARRAY_A);
            if(!$proposal)throw new DomainException(
                'Reward allocation proposal not found.',
                'reward_payroll_proposal_not_found',404
            );
            $branch=(int)$proposal['branch_id'];
            $employee=(int)$proposal['employee_id'];
            Guard::branch($actor,$branch,Capabilities::REWARDS_APPROVE);
            Guard::branch($actor,$branch,Capabilities::PAYROLL_GENERATE);
            HierarchyScope::assertCanViewEmployee($actor,$employee);
            if($proposal['status']!=='proposed_unfunded')
                throw new DomainException(
                    'Only a fresh unfunded candidate can be allocated.',
                    'reward_payroll_proposal_state_invalid',409
                );
            if((int)$proposal['created_by']===$actor->employeeId||
               $employee===$actor->employeeId)
                throw new DomainException(
                    'Allocation needs an independent actor.',
                    'maker_checker_required',409
                );
            $reward=$db->get_row($db->prepare(
                'SELECT * FROM '.Db::table('reward_adjustments').
                ' WHERE id=%d AND company_id=%d FOR UPDATE',
                (int)$proposal['reward_id'],$actor->companyId
            ),ARRAY_A);
            if(!$reward||
               (int)$reward['branch_id']!==$branch||
               (int)$reward['employee_id']!==$employee||
               $reward['status']!=='approved'||
               !in_array($reward['adjustment_type'],[
                   'incentive','bonus','recognition',
               ],true))
                throw new DomainException(
                    'Original reward approval or scope has changed.',
                    'reward_payroll_reward_changed',409
                );
            if((int)$reward['created_by']===$actor->employeeId)
                throw new DomainException(
                    'Reward maker cannot allocate own request.',
                    'maker_checker_required',409
                );
            $amount=self::paise($reward['amount'],'reward.amount');
            if($amount<=0||
               $amount!==self::paise(
                   $proposal['amount_snapshot'],'amount_snapshot'
               ))
                throw new DomainException(
                    'Reward amount differs from approved proposal.',
                    'reward_payroll_amount_changed',409
                );
            $e=$db->get_var($db->prepare(
                'SELECT id FROM '.Db::table('employees').
                " WHERE company_id=%d AND id=%d AND assigned_branch_id=%d AND status='active'",
                $actor->companyId,$employee,$branch
            ));
            if(!$e)throw new DomainException(
                'Employee has changed branch or employment status.',
                'reward_payroll_employee_changed',409
            );
            $runId=(int)$proposal['payroll_run_id'];
            $itemId=(int)$proposal['payroll_item_id'];
            $run=$db->get_row($db->prepare(
                'SELECT * FROM '.Db::table('payroll_runs').
                ' WHERE id=%d AND company_id=%d AND branch_id=%d FOR UPDATE',
                $runId,$actor->companyId,$branch
            ),ARRAY_A);
            if(!$run||$run['status']!=='draft'||
               ($run['calculation_version']??'')!=='7.3.5'||
               !empty($run['journal_entry_id'])||
               !empty($run['payment_journal_entry_id']))
                throw new DomainException(
                    'Payroll must be a corrected, unposted draft.',
                    'reward_payroll_run_not_draft',409
                );
            $items=Db::table('payroll_items');
            $item=$db->get_row($db->prepare(
                "SELECT * FROM {$items} WHERE id=%d AND payroll_run_id=%d FOR UPDATE",
                $itemId,$runId
            ),ARRAY_A);
            if(!$item||(int)$item['employee_id']!==$employee)
                throw new DomainException(
                    'Payroll item does not belong to beneficiary.',
                    'reward_payroll_item_mismatch',409
                );
            $before=self::paise($item['bonus'],'payroll.bonus');
            $snap=self::paise(
                $proposal['item_bonus_snapshot'],'item_bonus_snapshot'
            );
            if($before!==$snap||$before!==0)
                throw new DomainException(
                    'Payroll bonus has been manually changed or already used.',
                    'reward_payroll_bonus_conflict',409
                );
            $base=self::paise($item['attendance_salary'],'attendance_salary')+
                self::paise($item['salary_fund_earning'],'salary_fund_earning')+
                self::paise($item['allowances'],'allowances')-
                self::paise($item['deductions'],'deductions');
            $oldNet=self::paise($item['net_salary'],'net_salary');
            if($base<0||$oldNet!==$base||$base+$amount>99999999999999)
                throw new DomainException(
                    'Payroll item amounts are inconsistent or exceed limit.',
                    'reward_payroll_net_conflict',409
                );
            $alloc=Db::table('reward_payroll_allocations');
            if((int)$db->get_var($db->prepare(
                "SELECT id FROM {$alloc} WHERE company_id=%d".
                ' AND (reward_id=%d OR payroll_item_id=%d) LIMIT 1 FOR UPDATE',
                $actor->companyId,(int)$proposal['reward_id'],$itemId
            )))throw new DomainException(
                'Reward or payroll item already has an allocation.',
                'reward_payroll_allocation_duplicate',409
            );
            $newBonus=self::money($amount);
            $newNet=self::money($base+$amount);
            Db::mustInsert($db,$alloc,[
                'company_id'=>$actor->companyId,'branch_id'=>$branch,
                'employee_id'=>$employee,
                'reward_id'=>(int)$proposal['reward_id'],
                'proposal_id'=>$proposalId,
                'payroll_run_id'=>$runId,'payroll_item_id'=>$itemId,
                'reward_amount'=>$newBonus,
                'item_bonus_before'=>self::money($before),
                'item_bonus_after'=>$newBonus,'item_net_after'=>$newNet,
                'status'=>'allocated_unpaid',
                'allocated_by'=>$actor->employeeId,
                'allocated_at'=>Db::now(),
            ],'Reward or payroll item has an existing allocation.',
              'reward_payroll_allocation_duplicate');
            $id=(int)$db->insert_id;
            Db::mustUpdate($db,$items,[
                'bonus'=>$newBonus,'net_salary'=>$newNet,
            ],['id'=>$itemId,'payroll_run_id'=>$runId]);
            Db::mustUpdate($db,$proposals,[
                'status'=>'allocated_unpaid',
            ],['id'=>$proposalId,'company_id'=>$actor->companyId]);
            $editors=Db::table('payroll_editors');
            $seen=$db->get_var($db->prepare(
                "SELECT id FROM {$editors}".
                ' WHERE payroll_run_id=%d AND employee_id=%d',
                $runId,$actor->employeeId
            ));
            if(!$seen)Db::mustInsert($db,$editors,[
                'payroll_run_id'=>$runId,
                'employee_id'=>$actor->employeeId,
            ]);
            Audit::add($actor,'reward.payroll_allocated',
                'reward_payroll_allocation',$id,[
                    'company_id'=>$actor->companyId,
                    'branch_id'=>$branch,'employee_id'=>$employee,
                    'reward_id'=>(int)$proposal['reward_id'],
                    'proposal_id'=>$proposalId,'payroll_run_id'=>$runId,
                    'payroll_item_id'=>$itemId,'amount'=>$newBonus,
                    'bonus_before'=>self::money($before),
                    'net_after'=>$newNet,
                    'payment_posted'=>false,'settled'=>false,
            ]);
            return [
                'id'=>$id,'status'=>'allocated_unpaid',
                'reward_id'=>(int)$proposal['reward_id'],
                'payroll_run_id'=>$runId,'payroll_item_id'=>$itemId,
                'allocated_amount'=>$newBonus,'net_salary'=>$newNet,
                'payment_posted'=>false,'settled'=>false,
            ];
        });
    }

    /**
     * Invariant must be tested before draft approval or payroll payment.
     * A tampered/missing item or altered reward makes the whole run invalid.
     */
    public static function assertRunInvariant(
        object $db,int $companyId,int $runId
    ):void {
        $orphaned=(int)$db->get_var($db->prepare(
            'SELECT COUNT(*) FROM '.Db::table('reward_payroll_link_proposals').' p'.
            ' LEFT JOIN '.Db::table('reward_payroll_allocations').' a'.
            ' ON a.company_id=p.company_id AND a.proposal_id=p.id'.
            ' WHERE p.company_id=%d AND p.payroll_run_id=%d'.
            " AND p.status='allocated_unpaid' AND a.id IS NULL",
            $companyId,$runId
        ));
        if($orphaned)throw new DomainException(
            'Allocated payroll proposal is missing its immutable ledger.',
            'reward_payroll_allocation_drift',409
        );
        $rows=(array)$db->get_results($db->prepare(
            'SELECT a.*,pi.bonus AS current_bonus,'.
            ' pi.net_salary AS current_net,pi.employee_id AS item_employee,'.
            ' pi.attendance_salary AS current_attendance,'.
            ' pi.salary_fund_earning AS current_fund,'.
            ' pi.allowances AS current_allowances,'.
            ' pi.deductions AS current_deductions,'.
            ' r.status AS reward_status,r.amount AS current_reward_amount,'.
            ' p.status AS proposal_status'.
            ' FROM '.Db::table('reward_payroll_allocations').' a'.
            ' LEFT JOIN '.Db::table('payroll_items').' pi'.
            ' ON pi.id=a.payroll_item_id AND pi.payroll_run_id=a.payroll_run_id'.
            ' LEFT JOIN '.Db::table('reward_adjustments').' r'.
            ' ON r.id=a.reward_id AND r.company_id=a.company_id'.
            ' LEFT JOIN '.Db::table('reward_payroll_link_proposals').' p'.
            ' ON p.id=a.proposal_id AND p.company_id=a.company_id'.
            ' AND p.reward_id=a.reward_id AND p.payroll_item_id=a.payroll_item_id'.
            ' WHERE a.company_id=%d AND a.payroll_run_id=%d',
            $companyId,$runId
        ),ARRAY_A);
        foreach($rows as $row){
            if($row['status']!=='allocated_unpaid'||
               $row['reward_status']!=='approved'||
               ($row['proposal_status']??null)!=='allocated_unpaid'||
               (int)($row['item_employee']??0)!==(int)$row['employee_id']||
               $row['current_bonus']===null||$row['current_net']===null||
               self::paise($row['reward_amount'],'reward_amount')!==
                   self::paise($row['current_reward_amount'],'current_reward_amount')||
               self::paise($row['item_bonus_after'],'item_bonus_after')!==
                   self::paise($row['current_bonus'],'current_bonus')||
               self::paise($row['item_net_after'],'item_net_after')!==
                   self::paise($row['current_net'],'current_net')||
               self::paise($row['current_net'],'current_net')!==
                   self::paise($row['current_attendance'],'attendance_salary')+
                   self::paise($row['current_fund'],'salary_fund_earning')+
                   self::paise($row['current_allowances'],'allowances')-
                   self::paise($row['current_deductions'],'deductions')+
                   self::paise($row['reward_amount'],'reward_amount'))
                throw new DomainException(
                    'Approved reward allocation has changed. Restore/review before posting payroll.',
                    'reward_payroll_allocation_drift',409
                );
        }
    }

    public static function assertItemUnlocked(
        object $db,int $runId,int $itemId
    ):void {
        if((int)$db->get_var($db->prepare(
            'SELECT id FROM '.Db::table('reward_payroll_allocations').
            " WHERE payroll_run_id=%d AND payroll_item_id=%d LIMIT 1",
            $runId,$itemId
        )))throw new DomainException(
            'Reward-allocated payroll item is locked from manual edits.',
            'reward_payroll_item_locked',409
        );
    }

    public static function assertDraftDiscardable(
        object $db,int $runId
    ):void {
        if((int)$db->get_var($db->prepare(
            'SELECT id FROM '.Db::table('reward_payroll_allocations').
            ' WHERE payroll_run_id=%d LIMIT 1',
            $runId
        )))throw new DomainException(
            'Payroll with approved reward allocations cannot be discarded.',
            'reward_payroll_draft_locked',409
        );
    }
}
