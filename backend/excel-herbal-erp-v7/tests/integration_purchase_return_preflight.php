<?php
/**
 * Included by integration_uat_smoke.php against its disposable MariaDB only.
 * Never call this file against Office staging or any operational database.
 */

use ExcelHerbal\ERP7\Database\Db;
use ExcelHerbal\ERP7\Domain\DomainException;
use ExcelHerbal\ERP7\Purchase\PurchaseReturnPreflightService;
use ExcelHerbal\ERP7\Security\Actor;
use ExcelHerbal\ERP7\Security\Capabilities;

uat_case('purchase_return_read_only_preflight_tenant_branch_batch_payment_zero_write', function () use ($wpdb) {
    $buyer = uat_actor(30, [1,2], [Capabilities::PURCHASE_CREATE, Capabilities::PURCHASE_VIEW], 'SYSADMIN');
    $reader = uat_actor(20, [1], [Capabilities::PURCHASE_VIEW], 'SYSADMIN');
    $wrongBranch = uat_actor(20, [2], [Capabilities::PURCHASE_VIEW], 'SYSADMIN');
    $noPermission = uat_actor(10, [1], [], 'FE');
    $wrongCompany = new Actor(502, 20, 2, 1, [1], [Capabilities::PURCHASE_VIEW], 'SYSADMIN');
    $expectDenied = static function (Actor $actor, int $billId, string $code, int $http): void {
        try {
            PurchaseReturnPreflightService::inspect($actor, $billId);
        } catch (DomainException $e) {
            if ($e->codeKey === $code && $e->httpStatus === $http) return;
            throw new RuntimeException('Unexpected preflight rejection: '.$e->codeKey.' '.$e->httpStatus, 0, $e);
        }
        throw new RuntimeException('Preflight incorrectly authorized '.$code);
    };
    if (!(int)$wpdb->get_var($wpdb->prepare(
        'SELECT id FROM '.Db::table('accounts').' WHERE company_id=%d AND code=%s', 1, 'AP'
    ))) {
        uat_insert($wpdb, 'accounts', [
            'company_id'=>1, 'code'=>'AP', 'name'=>'Accounts Payable',
            'type'=>'liability', 'subtype'=>null, 'active'=>1,
        ]);
    }
    $productId = (int)$wpdb->get_var('SELECT COALESCE(MAX(id),0)+1 FROM '.Db::table('products'));
    uat_insert($wpdb, 'products', [
        'id'=>$productId, 'company_id'=>1, 'sku'=>'UAT-RETURN-PREFLIGHT-'.$productId,
        'name'=>'Preflight batch-tracked synthetic product', 'uom'=>'PCS',
        'batch_tracking'=>'required', 'expiry_tracking'=>1, 'status'=>'active',
        'created_at'=>'2026-01-01 00:00:00',
    ]);
    $supplier = uat_dispatch('purchase.supplier_create', $buyer, [
        'name'=>'UAT Preflight Supplier', 'mobile'=>'9000000777',
    ]);
    $bill = uat_dispatch('purchase.bill', $buyer, [
        'branch_id'=>1, 'supplier_id'=>(int)$supplier['id'],
        'bill_no'=>'UAT-RETURN-PREFLIGHT-'.$productId, 'bill_date'=>uat_date(),
        'lines'=>[[
            'product_id'=>$productId, 'batch_no'=>'UAT-RETURN-BATCH-'.$productId,
            'expires_on'=>'2035-01-01', 'quantity'=>4, 'unit_cost'=>42.5,
        ]],
    ]);
    $billId = (int)$bill['id'];
    $snapshot = static function () use ($wpdb, $billId, $productId): array {
        $counts = [];
        foreach (['purchase_bills', 'purchase_bill_lines', 'supplier_payments',
                  'stock_balances', 'stock_ledger', 'journal_entries',
                  'journal_lines', 'audit_log', 'reversals'] as $table) {
            $counts[$table] = (int)$wpdb->get_var('SELECT COUNT(*) FROM '.Db::table($table));
        }
        $counts['bill'] = $wpdb->get_row($wpdb->prepare(
            'SELECT status,paid_amount,outstanding_amount FROM '.Db::table('purchase_bills').' WHERE id=%d',
            $billId
        ), ARRAY_A);
        $counts['warehouse'] = $wpdb->get_row($wpdb->prepare(
            'SELECT quantity,average_unit_cost FROM '.Db::table('stock_balances').
            ' WHERE company_id=1 AND branch_id=1 AND product_id=%d AND custodian_key=0',
            $productId
        ), ARRAY_A);
        return $counts;
    };
    $before = $snapshot();
    $result = PurchaseReturnPreflightService::inspect($reader, $billId);
    if ($result['posting_allowed'] !== false || $result['return_quantity_authorized'] !== false ||
        $result['read_only'] !== true || $result['credit_note_policy'] !== 'owner_approval_required' ||
        (int)$result['branch_id'] !== 1 || (int)$result['supplier_id'] !== (int)$supplier['id'] ||
        count($result['lines']) !== 1 ||
        abs($result['lines'][0]['original_quantity'] - 4.0) > .001 ||
        abs($result['lines'][0]['original_unit_cost_snapshot'] - 42.5) > .0001 ||
        abs($result['lines'][0]['warehouse_quantity_at_read'] - 4.0) > .001 ||
        !$result['lines'][0]['quantity_is_shared_not_reserved'] ||
        !$result['lines'][0]['batch_id'] ||
        $result['lines'][0]['batch_no'] !== 'UAT-RETURN-BATCH-'.$productId ||
        $result['posted_supplier_payment_count'] !== 0 ||
        $result['payment_snapshot_mismatch'] !== false) {
        throw new RuntimeException('Purchase return preflight provenance or safety contract invalid');
    }
    if (PurchaseReturnPreflightService::inspect($reader, $billId) !== $result) {
        throw new RuntimeException('Repeated preflight changed its evidence');
    }
    $expectDenied($noPermission, $billId, 'permission_denied', 403);
    $expectDenied($wrongBranch, $billId, 'branch_forbidden', 403);
    $expectDenied($wrongCompany, $billId, 'purchase_not_found', 404);
    $expectDenied($reader, 0, 'purchase_not_found', 404);
    if ($snapshot() !== $before) {
        throw new RuntimeException('Read-only/denied preflight changed bill, stock, GL, audit or reversal state');
    }
    $payer = uat_actor(20, [1,2], [Capabilities::SUPPLIER_PAYMENT], 'SYSADMIN');
    uat_dispatch('purchase.payment', $payer, [
        'purchase_bill_id'=>$billId, 'amount'=>25, 'payment_account_id'=>1,
    ]);
    $afterPayment = $snapshot();
    $paid = PurchaseReturnPreflightService::inspect($reader, $billId);
    if ($paid['posted_supplier_payment_count'] !== 1 ||
        abs($paid['posted_supplier_payment_total'] - 25) > .005 ||
        abs($paid['paid_amount_snapshot'] - 25) > .005 ||
        $paid['payment_snapshot_mismatch'] !== false ||
        $paid['posting_allowed'] !== false) {
        throw new RuntimeException('Paid-bill preflight incorrectly implies supplier credit authorization');
    }
    if ($snapshot() !== $afterPayment) {
        throw new RuntimeException('Paid-bill preflight mutated financial or stock records');
    }
    $wpdb->update(Db::table('purchase_bills'), ['paid_amount'=>0], ['id'=>$billId]);
    try {
        $mismatch = PurchaseReturnPreflightService::inspect($reader, $billId);
        if ($mismatch['payment_snapshot_mismatch'] !== true || $mismatch['posting_allowed'] !== false) {
            throw new RuntimeException('Supplier payment mismatch not reported');
        }
    } finally {
        $wpdb->update(Db::table('purchase_bills'), ['paid_amount'=>25], ['id'=>$billId]);
    }
    $wpdb->update(Db::table('purchase_bills'), ['status'=>'reversed'], ['id'=>$billId]);
    try {
        $expectDenied($reader, $billId, 'purchase_bill_not_posted', 409);
    } finally {
        $wpdb->update(Db::table('purchase_bills'), ['status'=>'posted'], ['id'=>$billId]);
    }
    if ($snapshot() !== $afterPayment) {
        throw new RuntimeException('Rejected reversed bill preflight had side effects');
    }
});
