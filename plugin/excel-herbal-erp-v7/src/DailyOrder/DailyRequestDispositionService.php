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
 * Only unallocated, unposted requests may be rejected or withdrawn.
 * Reviewer rejection is independent of maker and beneficiary.
 * This class never moves stock, posts a journal, or reverses a settled order.
 */
final class DailyRequestDispositionService {
    private static function reason(string $reason):string {
        $reason=trim($reason);
        if(strlen($reason)<5||strlen($reason)>255||
            preg_match('/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/',$reason)) {
            throw new DomainException(
                'Reason must contain 5-255 printable characters.',
                'daily_disposition_reason_invalid',422
            );
        }
        return $reason;
    }

    /** @return array{0:array,1:array} locked request and cycle */
    private static function lock(Actor $actor,int $requestId):array {
        $db=Db::wpdb();
        // Lock the parent cycle first, just as Daily Order cancellation does.
        $cycle=$db->get_row($db->prepare(
            'SELECT c.* FROM '.Db::table('daily_cycles').' c'.
            ' JOIN '.Db::table('daily_requests').' r ON r.daily_cycle_id=c.id'.
            ' WHERE r.id=%d AND c.company_id=%d FOR UPDATE',
            $requestId,$actor->companyId
        ),ARRAY_A);
        if(!$cycle)throw new DomainException(
            'Daily request not found.','daily_request_not_found',404
        );
        $branch=(int)$cycle['branch_id'];
        $request=$db->get_row($db->prepare(
            'SELECT * FROM '.Db::table('daily_requests').
            ' WHERE id=%d AND daily_cycle_id=%d FOR UPDATE',
            $requestId,(int)$cycle['id']
        ),ARRAY_A);
        if(!$request)throw new DomainException(
            'Daily request not found.','daily_request_not_found',404
        );
        BranchDayGuard::assertOpen($actor,$branch,(string)$cycle['business_date']);
        $alloc=(int)$db->get_var($db->prepare(
            'SELECT COUNT(*) FROM '.Db::table('daily_issue_lines').
            ' WHERE daily_request_id=%d',$requestId
        ));
        $settlement=(int)$db->get_var($db->prepare(
            'SELECT COUNT(*) FROM '.Db::table('evening_settlements').
            ' WHERE daily_cycle_id=%d',(int)$cycle['id']
        ));
        if($alloc||$settlement)throw new DomainException(
            'Request has stock allocation or settlement.',
            'daily_request_has_dependencies',409
        );
        return [$request,$cycle];
    }

    public static function reject(Actor $actor,int $requestId,string $reason):array {
        $reason=self::reason($reason);
        return Transaction::run(function()use($actor,$requestId,$reason){
            [$request,$cycle]=self::lock($actor,$requestId);
            $branch=(int)$cycle['branch_id'];
            Guard::branch($actor,$branch,Capabilities::DAILY_OTHERS);
            HierarchyScope::assertCanViewEmployee($actor,(int)$cycle['employee_id']);
            $designation=strtoupper(trim($actor->designationCode));
            if(!in_array($designation,[
                'SM','SALES_MANAGER','ASM','ASSISTANT_SALES_MANAGER',
                'SYSADMIN','SYSTEM_ADMIN','ADMIN','ADMINISTRATOR'
            ],true))throw new DomainException(
                'Independent SM/ASM reviewer is required.',
                'daily_reviewer_required',403
            );
            if(in_array($actor->employeeId,[
                (int)$request['requested_by'],(int)$cycle['employee_id']
            ],true))throw new DomainException(
                'Maker or beneficiary cannot reject their own request.',
                'maker_checker_required',409
            );
            if($request['status']!=='submitted'||
               !in_array($request['type'],['initial','additional'],true)) {
                throw new DomainException(
                    'Only a submitted request may be rejected.',
                    'daily_request_state_invalid',409
                );
            }
            if(($request['type']==='initial'&&$cycle['status']!=='stock_requested')||
               ($request['type']==='additional'&&$cycle['status']!=='issued')) {
                throw new DomainException(
                    'Request and daily cycle are out of sync.',
                    'daily_request_state_invalid',409
                );
            }
            $db=Db::wpdb();
            Db::mustUpdate($db,Db::table('daily_requests'),[
                'status'=>'rejected',
            ],['id'=>$requestId]);
            if($request['type']==='initial') {
                Db::mustUpdate($db,Db::table('daily_cycles'),[
                    'status'=>'rejected',
                ],['id'=>(int)$cycle['id'],'company_id'=>$actor->companyId]);
            }
            Audit::add($actor,'daily_order.request_rejected',
                'daily_request',$requestId,[
                    'branch_id'=>$branch,'cycle_id'=>(int)$cycle['id'],
                    'request_type'=>(string)$request['type'],
                    'prior_status'=>'submitted','reason'=>$reason,
                ]);
            return [
                'id'=>$requestId,'cycle_id'=>(int)$cycle['id'],
                'status'=>'rejected','stock_moved'=>false,
            ];
        });
    }

    public static function cancelAdditional(
        Actor $actor,int $requestId,string $reason
    ):array {
        $reason=self::reason($reason);
        return Transaction::run(function()use($actor,$requestId,$reason){
            [$request,$cycle]=self::lock($actor,$requestId);
            $branch=(int)$cycle['branch_id'];
            $beneficiary=(int)$cycle['employee_id'];
            $cap=$beneficiary===$actor->employeeId
                ? Capabilities::DAILY_SELF : Capabilities::DAILY_OTHERS;
            Guard::branch($actor,$branch,$cap);
            if($beneficiary!==$actor->employeeId)
                HierarchyScope::assertCanViewEmployee($actor,$beneficiary);
            if(!in_array($actor->employeeId,[
                $beneficiary,(int)$request['requested_by']
            ],true))throw new DomainException(
                'Only requester or beneficiary may withdraw this request.',
                'daily_additional_cancel_forbidden',403
            );
            if($request['type']!=='additional'||
               !in_array($request['status'],[
                    'draft','submitted','reviewed'
               ],true)||$cycle['status']!=='issued') {
                throw new DomainException(
                    'Only pending, unallocated Additional Stock may be cancelled.',
                    'daily_request_state_invalid',409
                );
            }
            Db::mustUpdate(Db::wpdb(),Db::table('daily_requests'),[
                'status'=>'cancelled'
            ],['id'=>$requestId]);
            Audit::add($actor,'daily_order.additional_cancelled',
                'daily_request',$requestId,[
                    'branch_id'=>$branch,
                    'cycle_id'=>(int)$cycle['id'],
                    'prior_status'=>(string)$request['status'],
                    'reason'=>$reason,
                ]);
            return [
                'id'=>$requestId,'cycle_id'=>(int)$cycle['id'],
                'status'=>'cancelled','stock_moved'=>false,
            ];
        });
    }
}
