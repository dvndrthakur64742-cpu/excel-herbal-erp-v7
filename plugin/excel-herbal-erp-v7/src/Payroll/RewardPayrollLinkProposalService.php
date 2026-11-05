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
 * Draft-only non-posting reward-to-payroll-item proposal.
 *
 * A link proposal is NOT a booked payroll bonus, not a reservation, not
 * settlement evidence, and not a payroll or bank payment. It cannot
 * change payroll item bonus/net salary or any accounting/points balance.
 */
final class RewardPayrollLinkProposalService {
    public static function create(
        Actor $actor,int $rewardId,int $runId,int $itemId,string $reason
    ):array {
        Guard::cap($actor,Capabilities::REWARDS_APPROVE);
        Guard::cap($actor,Capabilities::PAYROLL_GENERATE);
        if($rewardId<1||$runId<1||$itemId<1)
            throw new DomainException(
                'Valid reward, payroll run and item IDs are required.',
                'reward_payroll_link_scope_invalid',422
            );
        $reason=trim($reason);
        if(strlen($reason)<5||strlen($reason)>255||
            preg_match('/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/',$reason))
            throw new DomainException(
                'Link proposal reason must be 5-255 printable characters.',
                'reward_payroll_link_reason_invalid',422
            );
        return Transaction::run(function()use(
            $actor,$rewardId,$runId,$itemId,$reason
        ){
            SalaryService::lockCompany($actor->companyId);
            $db=Db::wpdb();
            $reward=$db->get_row($db->prepare(
                'SELECT * FROM '.Db::table('reward_adjustments').
                ' WHERE company_id=%d AND id=%d FOR UPDATE',
                $actor->companyId,$rewardId
            ),ARRAY_A);
            if(!$reward)throw new DomainException(
                'Reward not found.','reward_not_found',404
            );
            $branch=(int)$reward['branch_id'];
            $employee=(int)$reward['employee_id'];
            Guard::branch($actor,$branch,Capabilities::REWARDS_APPROVE);
            Guard::branch($actor,$branch,Capabilities::PAYROLL_GENERATE);
            HierarchyScope::assertCanViewEmployee($actor,$employee);
            if(in_array($actor->employeeId,[
                $employee,(int)$reward['created_by']
            ],true))throw new DomainException(
                'Reward maker or beneficiary cannot create payroll linkage.',
                'maker_checker_required',409
            );
            if($reward['status']!=='approved'||
               !in_array($reward['adjustment_type'],[
                    'incentive','bonus','recognition',
               ],true)||
               SalaryStructureService::paise(
                   (string)$reward['amount'],'amount'
               )<1)throw new DomainException(
                'Only positive approved cash rewards can be proposed.',
                'reward_payroll_link_reward_invalid',409
            );
            $run=$db->get_row($db->prepare(
                'SELECT * FROM '.Db::table('payroll_runs').
                ' WHERE id=%d AND company_id=%d AND branch_id=%d FOR UPDATE',
                $runId,$actor->companyId,$branch
            ),ARRAY_A);
            if(!$run)throw new DomainException(
                'Payroll run is outside the authorized branch.',
                'reward_payroll_run_not_found',404
            );
            if($run['status']!=='draft'||
               ($run['calculation_version']??'')!=='7.3.5'){
                throw new DomainException(
                    'Only corrected, unapproved draft payroll can be linked.',
                    'reward_payroll_run_not_draft',409
                );
            }
            $item=$db->get_row($db->prepare(
                'SELECT * FROM '.Db::table('payroll_items').
                ' WHERE id=%d AND payroll_run_id=%d FOR UPDATE',
                $itemId,$runId
            ),ARRAY_A);
            if(!$item||(int)$item['employee_id']!==$employee)
                throw new DomainException(
                    'Payroll item is not for reward beneficiary.',
                    'reward_payroll_item_mismatch',409
                );
            $existing=(int)$db->get_var($db->prepare(
                'SELECT id FROM '.Db::table('reward_payroll_link_proposals').
                ' WHERE company_id=%d AND reward_id=%d LIMIT 1 FOR UPDATE',
                $actor->companyId,$rewardId
            ));
            if($existing)throw new DomainException(
                'Reward already has a payroll link proposal.',
                'reward_payroll_link_duplicate',409
            );
            // Snapshot only; do not infer that recorded manual bonus
            // is this reward. Recheck all these facts at actual allocation.
            Db::mustInsert($db,Db::table('reward_payroll_link_proposals'),[
                'company_id'=>$actor->companyId,'branch_id'=>$branch,
                'employee_id'=>$employee,'reward_id'=>$rewardId,
                'payroll_run_id'=>$runId,'payroll_item_id'=>$itemId,
                'amount_snapshot'=>(string)$reward['amount'],
                'item_bonus_snapshot'=>(string)$item['bonus'],
                'status'=>'proposed_unfunded','reason'=>$reason,
                'created_by'=>$actor->employeeId,'created_at'=>Db::now(),
            ],'Reward already linked to a payroll proposal.',
              'reward_payroll_link_duplicate');
            $id=(int)$db->insert_id;
            Audit::add($actor,'reward.payroll_link_proposed',
                'reward_payroll_link_proposal',$id,[
                    'branch_id'=>$branch,
                    'employee_id'=>$employee,'reward_id'=>$rewardId,
                    'payroll_run_id'=>$runId,
                    'payroll_item_id'=>$itemId,
                    'amount_snapshot'=>(string)$reward['amount'],
                    'status'=>'proposed_unfunded',
                    'reason'=>$reason,
                    'payroll_bonus_updated'=>false,
                    'settled'=>false,
                ]);
            return [
                'id'=>$id,'reward_id'=>$rewardId,'payroll_run_id'=>$runId,
                'payroll_item_id'=>$itemId,'status'=>'proposed_unfunded',
                'payroll_bonus_updated'=>false,'payment_posted'=>false,
                'reward_allocation_verified'=>false,'settled'=>false,
            ];
        });
    }
}
