import 'package:excel_herbal_erp/core/transaction_guardrails.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('counter sale', () {
    test('credit requires registered customer', () {
      expect(
        TransactionGuardrails.counterSale(
          gross: 1000,
          paid: 500,
          customerId: null,
          paymentAccountId: 1,
        ),
        isNotNull,
      );
      expect(
        TransactionGuardrails.counterSale(
          gross: 1000,
          paid: 500,
          customerId: 7,
          paymentAccountId: 1,
        ),
        isNull,
      );
    });

    test('paid amount cannot be negative or exceed gross', () {
      expect(
        TransactionGuardrails.counterSale(
          gross: 1000,
          paid: -1,
          customerId: 7,
          paymentAccountId: 1,
        ),
        isNotNull,
      );
      expect(
        TransactionGuardrails.counterSale(
          gross: 1000,
          paid: 1000.01,
          customerId: 7,
          paymentAccountId: 1,
        ),
        isNotNull,
      );
    });
  });

  test('customer receipt cannot exceed outstanding', () {
    expect(
      TransactionGuardrails.customerReceipt(
        saleId: 1,
        paymentAccountId: 2,
        amount: 501,
        outstanding: 500,
      ),
      isNotNull,
    );
    expect(
      TransactionGuardrails.customerReceipt(
        saleId: 1,
        paymentAccountId: 2,
        amount: 500,
        outstanding: 500,
      ),
      isNull,
    );
  });

  test('required batch is enforced for selected purchase line', () {
    expect(
      TransactionGuardrails.purchaseLine(
        quantity: 3,
        unitCost: 10,
        batchRequired: true,
        batchNo: '',
      ),
      isNotNull,
    );
    expect(
      TransactionGuardrails.purchaseLine(
        quantity: 3,
        unitCost: 0,
        batchRequired: false,
        batchNo: '',
      ),
      isNull,
    );
  });

  test('supplier payment cannot exceed outstanding', () {
    expect(
      TransactionGuardrails.supplierPayment(
        billId: 2,
        paymentAccountId: 3,
        amount: 1001,
        outstanding: 1000,
      ),
      isNotNull,
    );
  });

  test('expense amount must be positive', () {
    expect(
      TransactionGuardrails.expense(
        expenseHeadId: 1,
        paymentAccountId: 2,
        amount: 0,
      ),
      isNotNull,
    );
  });

  test('bank statement requires exactly one positive side', () {
    expect(
      TransactionGuardrails.bankStatementLine(
        date: '2026-09-08',
        debit: 100,
        credit: 0,
      ),
      isNull,
    );
    expect(
      TransactionGuardrails.bankStatementLine(
        date: '2026-09-08',
        debit: 100,
        credit: 100,
      ),
      isNotNull,
    );
    expect(
      TransactionGuardrails.bankStatementLine(
        date: '2026-09-08',
        debit: 0,
        credit: 0,
      ),
      isNotNull,
    );
  });

  group('master and stock entry guardrails', () {
    test('employee creation validates required fields email mobile and date', () {
      expect(
        TransactionGuardrails.employeeCreate(
          employeeCode: '',
          fullName: 'Test Employee',
          designationCode: 'SM',
          roleId: 1,
          mobile: '',
          email: '',
          joiningDate: '2026-09-30',
        ),
        isNotNull,
      );
      expect(
        TransactionGuardrails.employeeCreate(
          employeeCode: 'E-100',
          fullName: 'Test Employee',
          designationCode: 'SM',
          roleId: 1,
          mobile: '9876543210',
          email: 'bad-email',
          joiningDate: '2026-09-30',
        ),
        isNotNull,
      );
      expect(
        TransactionGuardrails.employeeCreate(
          employeeCode: 'E-100',
          fullName: 'Test Employee',
          designationCode: 'SM',
          roleId: 1,
          mobile: '+91 98765 43210',
          email: 'employee@example.com',
          joiningDate: '2026-09-30',
        ),
        isNull,
      );
    });

    test('product creation validates master structure', () {
      expect(
        TransactionGuardrails.productCreate(
          sku: 'SKU-1',
          name: 'Product',
          uom: 'PCS',
          batchMode: 'off',
          expiryTracking: true,
        ),
        isNotNull,
      );
      expect(
        TransactionGuardrails.productCreate(
          sku: 'SKU-1',
          name: 'Product',
          uom: 'PCS',
          batchMode: 'optional',
          expiryTracking: true,
        ),
        isNull,
      );
    });

    test('stock transfer validates branch item and quantity', () {
      expect(
        TransactionGuardrails.stockTransfer(
          sourceBranchId: 1,
          destinationBranchId: 1,
          itemSelected: true,
          quantity: 1,
          available: 10,
        ),
        isNotNull,
      );
      expect(
        TransactionGuardrails.stockTransfer(
          sourceBranchId: 1,
          destinationBranchId: 2,
          itemSelected: true,
          quantity: 11,
          available: 10,
        ),
        isNotNull,
      );
      expect(
        TransactionGuardrails.stockTransfer(
          sourceBranchId: 1,
          destinationBranchId: 2,
          itemSelected: true,
          quantity: 10,
          available: 10,
        ),
        isNull,
      );
    });
  });

  test('date range validates format and sequence', () {
    expect(TransactionGuardrails.dateRange('2026-09-01', '2026-09-08'), isNull);
    expect(TransactionGuardrails.dateRange('2026-09-09', '2026-09-08'), isNotNull);
    expect(TransactionGuardrails.dateRange('2026-02-31', '2026-03-01'), isNotNull);
  });
}
