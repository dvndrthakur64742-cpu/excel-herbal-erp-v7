import 'dart:io';

import 'package:excel_herbal_erp/core/api_paths.dart';
import 'package:excel_herbal_erp/screens/sales/prepaid_returns_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('prepaid return and evidence paths match the real backend registry', () {
    expect(ApiPaths.prepaidReturns, '/sales/returns');
    expect(ApiPaths.prepaidReturn(41), '/sales/returns/41');
    expect(ApiPaths.prepaidReturnRequest(12), '/sales/orders/12/return');
    expect(ApiPaths.prepaidReturnInspect(41), '/sales/returns/41/inspect');
    expect(ApiPaths.prepaidReturnDecision(41), '/sales/returns/41/decision');
    expect(ApiPaths.prepaidRefundEvidence(41),
        '/sales/returns/41/refund-evidence');
    expect(ApiPaths.prepaidRefundEvidenceVerify(7),
        '/sales/refund-evidence/7/verify');
  });

  test('returns workspace exists without any disbursement action', () {
    expect(const PrepaidReturnsScreen(), isA<PrepaidReturnsScreen>());
    final source = File('lib/screens/sales/prepaid_returns_screen.dart')
        .readAsStringSync();
    expect(source, contains('evidence_complete'));
    expect(source, contains('finance.bank_reconcile'));
    expect(source, contains('finance.reversal.approve'));
    expect(source, contains('Refund')); // evidentiary workflow, not payout
    expect(source, contains('No money has been refunded by ERP'));
    expect(source, isNot(contains('ApiPaths.prepaidRefundPost(')));
    expect(source, isNot(contains('ApiPaths.prepaidCreditNotePost(')));
    expect(source, isNot(contains('ApiPaths.reversalExecute(')));
  });

  test('return intake originates only from already-posted prepaid order', () {
    final source = File('lib/screens/sales/prepaid_orders_screen.dart')
        .readAsStringSync();
    expect(source, contains("if (order['status'] == 'posted')"));
    expect(source, contains("app.can('finance.reversal.create')"));
    expect(source, contains('ApiPaths.prepaidReturnRequest(id)'));
    expect(source, contains('Request full-order return'));
  });
}
