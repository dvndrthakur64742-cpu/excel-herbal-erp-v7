<?php
namespace ExcelHerbal\ERP7\Purchase;

use ExcelHerbal\ERP7\Database\Db;
use ExcelHerbal\ERP7\Domain\DomainException;
use ExcelHerbal\ERP7\Security\Actor;
use ExcelHerbal\ERP7\Security\Capabilities;
use ExcelHerbal\ERP7\Security\Guard;

/**
 * Internal, read-only evidence for a future partial supplier-return workflow.
 * No REST route, reservation, return entitlement, GST calculation or posting.
 * Warehouse quantities are shared across bills and can change after the read.
 */
final class PurchaseReturnPreflightService {
    public static function inspect(Actor $actor, int $billId): array {
        Guard::cap($actor, Capabilities::PURCHASE_VIEW);
        if ($billId < 1) {
            throw new DomainException('Valid purchase bill required.', 'purchase_not_found', 404);
        }
        $db = Db::wpdb();
        $bill = $db->get_row($db->prepare(
            'SELECT b.id,b.company_id,b.branch_id,b.supplier_id,b.bill_no,b.bill_date,'.
            'b.status,b.total_amount,b.paid_amount,b.outstanding_amount,'.
            's.name AS supplier_name,s.status AS supplier_status,s.gstin AS supplier_gstin '.
            'FROM '.Db::table('purchase_bills').' b '.
            'JOIN '.Db::table('suppliers').' s ON s.id=b.supplier_id AND s.company_id=b.company_id '.
            'WHERE b.id=%d AND b.company_id=%d',
            $billId, $actor->companyId
        ), ARRAY_A);
        if (!$bill) {
            throw new DomainException('Purchase bill not found.', 'purchase_not_found', 404);
        }
        Guard::branch($actor, (int)$bill['branch_id'], Capabilities::PURCHASE_VIEW);
        if ($bill['status'] !== 'posted') {
            throw new DomainException('Only posted purchase bills can be reviewed for return.', 'purchase_bill_not_posted', 409);
        }
        $lines = (array)$db->get_results($db->prepare(
            'SELECT l.id,l.product_id,l.batch_id,l.quantity,l.unit_cost,l.line_total,'.
            'p.sku,p.name AS product_name,p.uom,p.status AS product_status,'.
            'p.batch_tracking,p.expiry_tracking,'.
            'bt.batch_no,bt.expires_on,bt.status AS batch_status '.
            'FROM '.Db::table('purchase_bill_lines').' l '.
            'LEFT JOIN '.Db::table('products').' p ON p.id=l.product_id AND p.company_id=%d '.
            'LEFT JOIN '.Db::table('batches').' bt ON bt.id=l.batch_id '.
            'AND bt.company_id=%d AND bt.product_id=l.product_id '.
            'WHERE l.purchase_bill_id=%d ORDER BY l.id',
            $actor->companyId, $actor->companyId, $billId
        ), ARRAY_A);
        $items = [];
        foreach ($lines as $line) {
            $batchId = $line['batch_id'] === null ? null : (int)$line['batch_id'];
            $warehouse = $db->get_var($db->prepare(
                'SELECT quantity FROM '.Db::table('stock_balances').
                ' WHERE company_id=%d AND branch_id=%d AND product_id=%d '.
                'AND batch_key=%d AND custodian_key=0',
                $actor->companyId, (int)$bill['branch_id'], (int)$line['product_id'], $batchId ?? 0
            ));
            $items[] = [
                'purchase_bill_line_id' => (int)$line['id'],
                'product_id' => (int)$line['product_id'],
                'product_sku' => $line['sku'],
                'product_name' => $line['product_name'],
                'product_status' => $line['product_status'],
                'uom' => $line['uom'],
                'batch_id' => $batchId,
                'batch_no' => $line['batch_no'],
                'batch_status' => $line['batch_status'],
                'expires_on' => $line['expires_on'],
                'original_quantity' => (float)$line['quantity'],
                'original_unit_cost_snapshot' => (float)$line['unit_cost'],
                'original_line_total' => (float)$line['line_total'],
                'warehouse_quantity_at_read' => round((float)($warehouse ?? 0), 3),
                'quantity_is_shared_not_reserved' => true,
            ];
        }
        $payment = $db->get_row($db->prepare(
            'SELECT COUNT(*) AS posted_count,COALESCE(SUM(amount),0) AS posted_total '.
            'FROM '.Db::table('supplier_payments').
            " WHERE company_id=%d AND purchase_bill_id=%d AND status='posted'",
            $actor->companyId, $billId
        ), ARRAY_A);
        $postedTotal = (float)($payment['posted_total'] ?? 0);
        return [
            'purchase_bill_id' => (int)$bill['id'],
            'company_id' => (int)$bill['company_id'],
            'branch_id' => (int)$bill['branch_id'],
            'supplier_id' => (int)$bill['supplier_id'],
            'supplier_name' => $bill['supplier_name'],
            'supplier_status' => $bill['supplier_status'],
            'supplier_gstin' => $bill['supplier_gstin'],
            'bill_no' => $bill['bill_no'],
            'bill_date' => $bill['bill_date'],
            'bill_status' => $bill['status'],
            'original_total' => (float)$bill['total_amount'],
            'paid_amount_snapshot' => (float)$bill['paid_amount'],
            'outstanding_amount_snapshot' => (float)$bill['outstanding_amount'],
            'posted_supplier_payment_count' => (int)($payment['posted_count'] ?? 0),
            'posted_supplier_payment_total' => $postedTotal,
            'payment_snapshot_mismatch' => abs($postedTotal - (float)$bill['paid_amount']) > 0.005,
            'lines' => $items,
            'posting_allowed' => false,
            'return_quantity_authorized' => false,
            'credit_note_policy' => 'owner_approval_required',
            'read_only' => true,
        ];
    }
}
