<?php
namespace ExcelHerbal\ERP7\DailyOrder;

use ExcelHerbal\ERP7\Database\Db;
use ExcelHerbal\ERP7\Database\Transaction;
use ExcelHerbal\ERP7\Domain\DomainException;
use ExcelHerbal\ERP7\Finance\BranchDayGuard;
use ExcelHerbal\ERP7\Security\Actor;
use ExcelHerbal\ERP7\Security\Audit;
use ExcelHerbal\ERP7\Security\Capabilities;
use ExcelHerbal\ERP7\Security\Guard;
use ExcelHerbal\ERP7\Security\HierarchyScope;

/**
 * Cancel and optionally reopen unallocated Daily Order drafts.
 * Never rewinds stock, a posted settlement, or a final-approved request.
 */
final class DailyCancellationService {
    /** @return array{0:array,1:array} locked cycle and initial request */
    private static function lock(Actor $actor,int $cycleId):array {
        $db=Db::wpdb();
        $cycle=$db->get_row($db->prepare(
            'SELECT * FROM '.Db::table('daily_cycles').
            ' WHERE company_id=%d AND id=%d FOR UPDATE',
            $actor->companyId,$cycleId
        ),ARRAY_A);
        if(!$cycle)throw new DomainException(
            'Daily Order not found.','daily_order_not_found',404
        );
        $branch=(int)$cycle['branch_id'];
        $beneficiary=(int)$cycle['employee_id'];
        $cap=$beneficiary===$actor->employeeId
            ? Capabilities::DAILY_SELF : Capabilities::DAILY_OTHERS;
        Guard::branch($actor,$branch,$cap);
        if($beneficiary!==$actor->employeeId)
            HierarchyScope::assertCanViewEmployee($actor,$beneficiary);
        if(!in_array($actor->employeeId,[
            $beneficiary,(int)$cycle['created_by'],
        ],true))throw new DomainException(
            'Only creator or beneficiary can change this draft.',
            'daily_draft_edit_forbidden',403
        );
        BranchDayGuard::assertOpen($actor,$branch,(string)$cycle['business_date']);
        $request=$db->get_row($db->prepare(
            'SELECT * FROM '.Db::table('daily_requests').
            " WHERE daily_cycle_id=%d AND type='initial' FOR UPDATE",$cycleId
        ),ARRAY_A);
        if(!$request)throw new DomainException(
            'Initial request missing.','daily_request_state_invalid',409
        );
        $requestId=(int)$request['id'];
        $allocated=(int)$db->get_var($db->prepare(
            'SELECT COUNT(*) FROM '.Db::table('daily_issue_lines').
            ' WHERE daily_request_id=%d',$requestId
        ));
        $settled=(int)$db->get_var($db->prepare(
            'SELECT COUNT(*) FROM '.Db::table('evening_settlements').
            ' WHERE daily_cycle_id=%d',$cycleId
        ));
        if($allocated||$settled)
            throw new DomainException(
                'Cannot cancel a stock-allocated or settled order.',
                'daily_order_has_dependencies',409
            );
        return [$cycle,$request];
    }

    public static function cancel(Actor $actor,int $cycleId,string $reason):array {
        $reason=trim($reason);
        if(strlen($reason)<5||strlen($reason)>255)
            throw new DomainException(
                'Cancellation reason must contain 5-255 characters.',
                'daily_cancel_reason_invalid',422
            );
        return Transaction::run(function()use($actor,$cycleId,$reason){
            [$cycle,$request]=self::lock($actor,$cycleId);
            if(!in_array((string)$cycle['status'],[
                'morning_draft','stock_requested',
            ],true)||!in_array((string)$request['status'],[
                'draft','submitted','reviewed',
            ],true))throw new DomainException(
                'Only unallocated draft or pending review may be cancelled.',
                'daily_request_state_invalid',409
            );
            $db=Db::wpdb();
            Db::mustUpdate($db,Db::table('daily_requests'),[
                'status'=>'cancelled',
            ],['id'=>(int)$request['id']]);
            Db::mustUpdate($db,Db::table('daily_cycles'),[
                'status'=>'cancelled',
            ],['id'=>$cycleId,'company_id'=>$actor->companyId]);
            Audit::add($actor,'daily_order.cancel','daily_cycle',$cycleId,[
                'branch_id'=>(int)$cycle['branch_id'],
                'request_id'=>(int)$request['id'],
                'prior_status'=>(string)$cycle['status'],
                'reason'=>$reason,
            ]);
            return ['id'=>$cycleId,'status'=>'cancelled','stock_moved'=>false];
        });
    }

    public static function reopen(Actor $actor,int $cycleId):array {
        return Transaction::run(function()use($actor,$cycleId){
            [$cycle,$request]=self::lock($actor,$cycleId);
            if(!in_array($cycle['status'],['cancelled','rejected'],true)||
               $request['status']!==$cycle['status'])
                throw new DomainException(
                    'Only a cancelled or reviewer-rejected unallocated order may reopen.',
                    'daily_request_state_invalid',409
                );
            $db=Db::wpdb();
            Db::mustUpdate($db,Db::table('daily_requests'),[
                'status'=>'draft','reviewed_by'=>null,'reviewed_at'=>null,
                'approved_by'=>null,'approved_at'=>null,
            ],['id'=>(int)$request['id']]);
            Db::mustUpdate($db,Db::table('daily_cycles'),[
                'status'=>'morning_draft',
            ],['id'=>$cycleId,'company_id'=>$actor->companyId]);
            Audit::add($actor,'daily_order.reopen_draft','daily_cycle',$cycleId,[
                'branch_id'=>(int)$cycle['branch_id'],
                'request_id'=>(int)$request['id'],
                'prior_status'=>(string)$cycle['status'],
            ]);
            return ['id'=>$cycleId,'status'=>'morning_draft','stock_moved'=>false];
        });
    }
}
