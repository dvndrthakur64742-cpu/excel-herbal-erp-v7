<?php
namespace ExcelHerbal\ERP7\DailyOrder;

use ExcelHerbal\ERP7\Administration\ActingDutyService;
use ExcelHerbal\ERP7\Database\Db;
use ExcelHerbal\ERP7\Domain\DomainException;
use ExcelHerbal\ERP7\Finance\BranchDayGuard;
use ExcelHerbal\ERP7\Inventory\StockService;
use ExcelHerbal\ERP7\Security\Actor;
use ExcelHerbal\ERP7\Security\HierarchyScope;

/**
 * Read-only warehouse stock availability preview for an APPROVED daily issue.
 * Actual allocation and stock custody are controlled by DailyOrderService.
 * A preview is never a reservation: stock is revalidated during receipt.
 */
final class DailyIssuePreflightService {
    public static function inspect(Actor $a,int $requestId):array {
        $db=Db::wpdb();
        $r=$db->get_row($db->prepare(
            'SELECT r.*,c.branch_id,c.employee_id,c.company_id,c.business_date'.
            ' FROM '.Db::table('daily_requests').' r'.
            ' JOIN '.Db::table('daily_cycles').' c ON c.id=r.daily_cycle_id'.
            ' WHERE r.id=%d AND c.company_id=%d',
            $requestId,$a->companyId
        ),ARRAY_A);
        if (!$r) throw new DomainException(
            'Daily request not found.','daily_request_not_found',404
        );
        $branch=(int)$r['branch_id'];
        // Uses the same exact-action authority and maker separation as issue().
        // Delegated action access may add a security audit record.
        $authority=ActingDutyService::assertAction(
            $a,$branch,'daily.issue',(int)$r['requested_by']
        );
        if ($authority['mode']==='permanent')
            HierarchyScope::assertCanViewEmployee($a,(int)$r['employee_id']);
        if ($a->employeeId===(int)$r['employee_id']||
            $a->employeeId===(int)$r['requested_by'])
            throw new DomainException(
                'Beneficiary or maker cannot allocate own stock.',
                'maker_checker_required',409
            );
        if ($r['status']!=='approved')
            throw new DomainException(
                'Request not finally approved.','daily_request_state_invalid',409
            );
        BranchDayGuard::assertOpen($a,$branch,(string)$r['business_date']);

        $lines=(array)$db->get_results($db->prepare(
            'SELECT l.id,l.product_id,l.quantity'.
            ' FROM '.Db::table('daily_request_lines').' l'.
            ' WHERE l.daily_request_id=%d ORDER BY l.id',
            $requestId
        ),ARRAY_A);
        if (!$lines) throw new DomainException(
            'Approved request has no lines.','daily_request_lines_missing',409
        );
        $needed=[];
        foreach ($lines as $line) {
            $product=(int)$line['product_id'];
            $quantity=(float)$line['quantity'];
            if ($product<1||!is_finite($quantity)||$quantity<=0)
                throw new DomainException(
                    'Invalid approved request quantity.','daily_allocation_invalid',409
                );
            $needed[$product]=($needed[$product]??0.)+$quantity;
        }
        $available=[];
        foreach ($needed as $product=>$quantity) {
            $p=StockService::product($a,(int)$product);
            $mode=(string)$p['batch_tracking'];
            $where='sb.company_id=%d AND sb.branch_id=%d'.
                ' AND sb.product_id=%d AND sb.custodian_key=0'.
                ' AND sb.quantity>0';
            $args=[$a->companyId,$branch,(int)$product];
            if ($mode==='off') {
                $where.=' AND sb.batch_key=0';
            } elseif ($mode==='required') {
                $where.=" AND sb.batch_key<>0 AND bt.status='active'".
                    ' AND (bt.expires_on IS NULL OR bt.expires_on>=%s)';
                $args[]=Db::today();
            } else {
                $where.=" AND (sb.batch_key=0 OR (bt.status='active'".
                    ' AND (bt.expires_on IS NULL OR bt.expires_on>=%s)))';
                $args[]=Db::today();
            }
            $available[$product]=(float)$db->get_var($db->prepare(
                'SELECT COALESCE(SUM(sb.quantity),0)'.
                ' FROM '.Db::table('stock_balances').' sb'.
                ' LEFT JOIN '.Db::table('batches').' bt'.
                ' ON bt.id=NULLIF(sb.batch_key,0)'.
                ' WHERE '.$where,
                ...$args
            ));
        }

        $all=true;
        $rows=[];
        foreach ($lines as $line) {
            $product=(int)$line['product_id'];
            $enough=($available[$product]+0.0001 >= $needed[$product]);
            $all=$all&&$enough;
            $rows[]=[
                'request_line_id'=>(int)$line['id'],
                'product_id'=>$product,
                'required_quantity'=>(float)$line['quantity'],
                'available_quantity'=>round($available[$product],3),
                'issueable'=>$enough,
            ];
        }
        return [
            'request_id'=>$requestId,
            'status'=>'approved',
            'all_available'=>$all,
            'lines'=>$rows,
            'stock_reserved'=>false,
            'stock_moved'=>false,
            'requires_employee_receipt'=>true,
        ];
    }
}
