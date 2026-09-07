#!/usr/bin/env python3
from pathlib import Path
import re
ROOT=Path(__file__).resolve().parents[1]
registry=(ROOT/'backend/excel-herbal-erp-v7/src/Http/RouteRegistry.php').read_text()
api=(ROOT/'backend/excel-herbal-erp-v7/src/Http/Api.php').read_text()
sales=(ROOT/'backend/excel-herbal-erp-v7/src/Sales/SalesService.php').read_text()
purchase=(ROOT/'backend/excel-herbal-erp-v7/src/Purchase/PurchaseService.php').read_text()
daily=(ROOT/'backend/excel-herbal-erp-v7/src/DailyOrder/DailyOrderService.php').read_text()
inv=(ROOT/'backend/excel-herbal-erp-v7/src/Inventory/InventoryService.php').read_text()
finance=(ROOT/'backend/excel-herbal-erp-v7/src/Finance/FinanceService.php').read_text()
org=(ROOT/'backend/excel-herbal-erp-v7/src/Organization/OrganizationService.php').read_text()
payroll=(ROOT/'backend/excel-herbal-erp-v7/src/Payroll/PayrollPerformanceService.php').read_text()
flutter_sales=(ROOT/'flutter/excel_herbal_erp/lib/screens/sales/sales_screen.dart').read_text()

raw_routes=[(m,p,h,a=='true') for m,p,h,a in re.findall(r"\['(GET|POST)','([^']+)','([^']+)',(true|false)\]",registry)]
routes={(m,p.replace('(?P<id>\\\\d+)','{id}')):(h,a) for m,p,h,a in raw_routes}

def need(method,path,handler=None,auth=True):
    assert (method,path) in routes, f'missing route {method} {path}'
    h,a=routes[(method,path)]
    if handler: assert h==handler, (path,h,handler)
    assert a is auth, f'auth mismatch {method} {path}'

# Critical employee lifecycle.
for method,path in [
 ('POST','/workforce/attendance/check-in'),('POST','/workforce/attendance/check-out'),
 ('POST','/daily/cycles'),('POST','/daily/cycles/{id}/submit'),
 ('POST','/daily/requests/{id}/approve'),('POST','/daily/requests/{id}/issue'),
 ('POST','/daily/cycles/{id}/evening/start'),('POST','/daily/cycles/{id}/evening/submit'),
 ('POST','/daily/cycles/{id}/final-post')]: need(method,path)

# Transfer lifecycle and correction/cancel controls.
for method,path in [
 ('POST','/inventory/transfers'),('POST','/inventory/transfers/{id}/pack'),
 ('POST','/inventory/transfers/{id}/dispatch'),('POST','/inventory/transfers/{id}/receive'),
 ('POST','/inventory/transfers/{id}/approve-correction'),('POST','/inventory/transfers/{id}/cancel')]: need(method,path)
assert 'maker_checker_required' in inv and 'STOCK_VARIANCE' in inv

# Customer receipt must be sale-specific. No FIFO/advance engine.
need('GET','/sales/open-sales','sales.open_sales')
need('POST','/sales/receipts','sales.receipt')
assert "get_param('sale_id')" in api and "get_param('customer_id')" in api  # customer still used by customer creation/counter sale.
receipt_method=sales[sales.index(' public static function receipt('):]
assert 'int $saleId' in receipt_method
assert "outstanding_amount>0" in sales
assert 'customer_receipt_allocations' not in sales
assert "'sale_id'=>$saleId" in sales
assert 'customer_advance_disabled' in sales
assert 'ApiPaths.openSales' in flutter_sales and "'sale_id': saleId" in flutter_sales

# Supplier payment is bill-specific and advances are disabled.
need('GET','/purchase/open-bills','purchase.open_bills')
need('POST','/purchase/payments','purchase.payment')
assert 'int $billId' in purchase and "'purchase_bill_id'=>$billId" in purchase
assert 'supplier_advance_disabled' in purchase

# Posted accounting corrections use reversal chain, never delete.
for method,path in [
 ('POST','/finance/reversals'),('POST','/finance/reversals/{id}/decision'),('POST','/finance/reversals/{id}/execute')]: need(method,path)
assert 'dependent_receipt_exists' in finance
assert "sale_id=%d" in finance and 'reverseCustomerReceipt' in finance
assert 'delete(' not in finance.lower()

# Maker-checker controls for high-risk workflows.
assert daily.count('maker_checker_required') >= 2
assert 'Maker cannot approve own payroll' in (ROOT/'backend/excel-herbal-erp-v7/src/Payroll/PayrollPerformanceService.php').read_text()
assert 'Maker cannot approve own expense' in finance or 'maker_checker_required' in finance


# Payroll is a complete canonical payable lifecycle, not approval-only.
handlers={h for _,_,h,_ in raw_routes}
for handler in {'payroll.list','payroll.generate','payroll.detail','payroll.item_update','payroll.approve','payroll.pay'}:
    assert handler in handlers, f'missing payroll handler {handler}'
assert 'employee_branch_history' in payroll
assert "branch_id=%d AND employee_id=%d" in payroll
assert "'PAYROLL_EXPENSE'" in payroll and "'PAYROLL_PAYABLE'" in payroll
assert "'payroll_payment'" in payroll and 'AccountingService::paymentAccount' in payroll
assert 'BranchDayGuard::assertOpen' in payroll
assert "'status' => 'paid'" in payroll
assert "'payroll','payroll_payment'" in finance
assert "if($type==='payroll_payment')" in finance and "if($type==='payroll')" in finance

# Primary branch future scheduling is blocked until an executor exists.
assert 'future_transfer_not_supported' in org
assert "if($date>Db::today())" in org

# API-level idempotency applies to authenticated non-GET mutations.
assert "Idempotency::run" in api
for (method,path),(handler,auth) in routes.items():
    if method=='POST' and handler not in {'auth.login','auth.refresh','setup.initialize'}:
        assert auth, f'mutation route unexpectedly unauthenticated: {path}'
setup=(ROOT/'backend/excel-herbal-erp-v7/src/Setup/SetupService.php').read_text()
assert "current_user_can('manage_options')" in setup and 'setup_already_initialized' in setup
assert 'SYSTEM_ADMIN' in setup and 'PAYROLL_PAYABLE' in setup and 'STOCK_VARIANCE' in setup

print(f'PASS workflow UAT contracts across {len(routes)} registered API routes')
