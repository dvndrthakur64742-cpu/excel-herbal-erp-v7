<?php
namespace ExcelHerbal\ERP7\Security;
final class Capabilities {
    public const ACCESS='erp.access', EMP_VIEW='organization.employee.view', EMP_MANAGE='organization.employee.manage', HR_VIEW='organization.hr.view', HR_MANAGE='organization.hr.manage', HR_REVIEW='organization.hr.review', BRANCH_VIEW='organization.branch.view', BRANCH_MANAGE='organization.branch.manage', ACCESS_MANAGE='administration.access.manage';
    public const ATT_SELF='workforce.attendance.self', ATT_MANAGE='workforce.attendance.manage', FIELD_SELF='workforce.field_visit.self', LEAVE_SELF='workforce.leave.self', LEAVE_MANAGE='workforce.leave.manage';
    public const DAILY_SELF='daily_order.self', DAILY_OTHERS='daily_order.others', DAILY_APPROVE='daily_order.approve', DAILY_ISSUE='daily_order.issue', DAILY_REVIEW='daily_order.review';
    public const PRODUCT_VIEW='catalog.product.view', PRODUCT_MANAGE='catalog.product.manage', SALES_VIEW='sales.view', SALES_CREATE='sales.create', RECEIPT_CREATE='sales.receipt.create';
    public const INVENTORY_VIEW='inventory.view', TRANSFER_CREATE='inventory.transfer.create', TRANSFER_RECEIVE='inventory.transfer.receive', TRANSFER_CANCEL='inventory.transfer.cancel', ADJ_CREATE='inventory.adjustment.create', ADJ_APPROVE='inventory.adjustment.approve';
    public const PURCHASE_VIEW='purchase.view', PURCHASE_CREATE='purchase.create', SUPPLIER_PAYMENT='finance.supplier_payment.create';
    public const FINANCE_VIEW='finance.view', ACCOUNTING_VIEW='finance.accounting.view', ACCOUNT_MANAGE='finance.account.manage', EXPENSE_CREATE='finance.expense.create', EXPENSE_APPROVE='finance.expense.approve', BRANCH_CLOSE='finance.branch_close', BRANCH_REOPEN='finance.branch_reopen', REVERSAL_CREATE='finance.reversal.create', REVERSAL_APPROVE='finance.reversal.approve', PERIOD_MANAGE='finance.period.manage', BANK_RECONCILE='finance.bank_reconcile';
    public const PAYROLL_GENERATE='payroll.generate', PAYROLL_APPROVE='payroll.approve', PAYROLL_PAY='payroll.pay', PERFORMANCE_VIEW='performance.view', PERFORMANCE_MANAGE='performance.manage', REPORTS_VIEW='reports.view', COMM_VIEW='communication.view', COMM_MANAGE='communication.manage', AUDIT_VIEW='administration.audit.view', DELEGATION_MANAGE='administration.delegation.manage';
}
