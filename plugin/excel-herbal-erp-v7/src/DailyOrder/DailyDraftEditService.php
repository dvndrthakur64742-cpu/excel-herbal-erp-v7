<?php
namespace ExcelHerbal\ERP7\DailyOrder;

use ExcelHerbal\ERP7\Database\Db;
use ExcelHerbal\ERP7\Database\Transaction;
use ExcelHerbal\ERP7\Domain\DomainException;
use ExcelHerbal\ERP7\Finance\BranchDayGuard;
use ExcelHerbal\ERP7\Inventory\StockService;
use ExcelHerbal\ERP7\Security\Actor;
use ExcelHerbal\ERP7\Security\Audit;
use ExcelHerbal\ERP7\Security\Capabilities;
use ExcelHerbal\ERP7\Security\Guard;
use ExcelHerbal\ERP7\Security\HierarchyScope;

/**
 * Replace only unsubmitted, unallocated initial request lines in one atomic
 * transaction. A submitted/approved/issued/settled order is never editable.
 */
final class DailyDraftEditService {
    public static function edit(Actor $actor,int $cycleId,array $lines):array {
        if($cycleId<1||!$lines||count($lines)>100)
            throw new DomainException(
                'Draft needs 1-100 product lines.','daily_draft_lines_invalid',422
            );
        $prepared=[];$seen=[];
        foreach($lines as $line){
            if(!is_array($line))
                throw new DomainException('Invalid product line.','daily_draft_lines_invalid',422);
            $productId=filter_var($line['product_id']??null,FILTER_VALIDATE_INT,[
                'options'=>['min_range'=>1]
            ]);
            $rawQty=$line['quantity']??null;
            if(!(is_int($rawQty)||is_string($rawQty))||
                !preg_match('/^[1-9][0-9]{0,8}$/',(string)$rawQty))
                throw new DomainException(
                    'Positive whole PCS required.','whole_pcs_required',422
                );
            $qty=(int)$rawQty;
            if($productId===false||isset($seen[(int)$productId]))
                throw new DomainException(
                    'Product ID is invalid or repeated.','duplicate_daily_line',422
                );
            $seen[(int)$productId]=true;
            $prepared[]=['product_id'=>(int)$productId,'quantity'=>$qty];
        }
        return Transaction::run(function()use($actor,$cycleId,$prepared){
            $db=Db::wpdb();
            $cycle=$db->get_row($db->prepare(
                'SELECT * FROM '.Db::table('daily_cycles').
                ' WHERE id=%d AND company_id=%d FOR UPDATE',
                $cycleId,$actor->companyId
            ),ARRAY_A);
            if(!$cycle)throw new DomainException(
                'Daily Order not found.','daily_order_not_found',404
            );
            $beneficiary=(int)$cycle['employee_id'];
            $branch=(int)$cycle['branch_id'];
            $cap=$beneficiary===$actor->employeeId
                ? Capabilities::DAILY_SELF : Capabilities::DAILY_OTHERS;
            Guard::branch($actor,$branch,$cap);
            if($beneficiary!==$actor->employeeId)
                HierarchyScope::assertCanViewEmployee($actor,$beneficiary);
            if(!in_array($actor->employeeId,[
                $beneficiary,(int)$cycle['created_by']
            ],true)) {
                throw new DomainException(
                    'Only the order creator or beneficiary may edit its draft.',
                    'daily_draft_edit_forbidden',403
                );
            }
            BranchDayGuard::assertOpen($actor,$branch,(string)$cycle['business_date']);
            if($cycle['status']!=='morning_draft')
                throw new DomainException(
                    'Only unsubmitted Morning Draft can be edited.',
                    'daily_request_state_invalid',409
                );
            $request=$db->get_row($db->prepare(
                'SELECT id,status FROM '.Db::table('daily_requests').
                " WHERE daily_cycle_id=%d AND type='initial' FOR UPDATE",
                $cycleId
            ),ARRAY_A);
            if(!$request||$request['status']!=='draft')
                throw new DomainException(
                    'Initial request is no longer a draft.','daily_request_state_invalid',409
                );
            $requestId=(int)$request['id'];
            $allocated=(int)$db->get_var($db->prepare(
                'SELECT COUNT(*) FROM '.Db::table('daily_issue_lines').
                ' WHERE daily_request_id=%d',$requestId
            ));
            if($allocated>0)
                throw new DomainException(
                    'Draft already has stock allocations.','daily_request_state_invalid',409
                );

            foreach($prepared as $line)StockService::product($actor,$line['product_id']);
            $deleted=$db->query($db->prepare(
                'DELETE FROM '.Db::table('daily_request_lines').
                ' WHERE daily_request_id=%d',$requestId
            ));
            if($deleted===false)throw new DomainException(
                'Draft lines could not be replaced.','daily_draft_store_failed',500
            );
            foreach($prepared as $line){
                Db::mustInsert($db,Db::table('daily_request_lines'),[
                    'daily_request_id'=>$requestId,
                    'product_id'=>$line['product_id'],
                    'batch_id'=>null,
                    'quantity'=>$line['quantity'],
                ]);
            }
            Audit::add($actor,'daily_order.draft_edit','daily_cycle',$cycleId,[
                'branch_id'=>$branch,'employee_id'=>$beneficiary,
                'request_id'=>$requestId,'line_count'=>count($prepared),
            ]);
            return [
                'id'=>$cycleId,'request_id'=>$requestId,
                'status'=>'morning_draft','line_count'=>count($prepared),
            ];
        });
    }
}
