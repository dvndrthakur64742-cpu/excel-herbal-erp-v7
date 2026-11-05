import 'dart:io';

import 'package:excel_herbal_erp/core/prepaid_invoice_readiness.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> order(String status, String amount) => {
        'id': 10,
        'status': status,
        'net_amount': amount,
      };
  Map<String, dynamic> payment(
    String method,
    String status,
    String amount,
  ) =>
      {
        'id': 33,
        'method': method,
        'status': status,
        'amount': amount,
      };

  test('no invoice action before independent discount approval', () {
    final state = PrepaidInvoiceReadiness.check(
      order: order('discount_pending', '500.00'),
      payments: [],
    );
    expect(state.canPost, isFalse);
    expect(state.message, contains('discount approval'));
  });

  test('approved order without payment explains next action', () {
    final state = PrepaidInvoiceReadiness.check(
      order: order('approved', '500.00'),
      payments: [],
    );
    expect(state.canPost, isFalse);
    expect(state.remainingPaise, 50000);
    expect(state.message, contains('500.00'));
  });

  test('only fully covered confirmed Cash allows invoice', () {
    final partial = PrepaidInvoiceReadiness.check(
      order: order('approved', '500.00'),
      payments: [payment('cash', 'confirmed', '499.99')],
    );
    expect(partial.canPost, isFalse);
    expect(partial.remainingPaise, 1);
    expect(partial.message, contains('0.01'));

    final complete = PrepaidInvoiceReadiness.check(
      order: order('approved', '500.00'),
      payments: [payment('cash', 'confirmed', '500.00')],
    );
    expect(complete.canPost, isTrue);
    expect(complete.remainingPaise, 0);
    expect(complete.awaitingUpiVerification, isFalse);
  });

  test('pending UPI cannot post even after Cash partial collection', () {
    final cash = payment('cash', 'confirmed', '200.00');
    final upi = payment('upi', 'pending', '300.00');
    final pending = PrepaidInvoiceReadiness.check(
      order: order('approved', '500.00'),
      payments: [cash, upi],
    );
    expect(pending.canPost, isFalse);
    expect(pending.message, contains('independently verify'));
    expect(pending.awaitingUpiVerification, isTrue);
    final verified = PrepaidInvoiceReadiness.check(
      order: order('approved', '500.00'),
      payments: [cash, {...upi, 'status': 'confirmed'}],
    );
    expect(verified.canPost, isTrue);
  });

  test('overpayment, unrecognised method and malformed money fail closed', () {
    for (final rows in <List<Map<String, dynamic>>>[
      [payment('cash', 'confirmed', '500.01')],
      [payment('card', 'confirmed', '500.00')],
      [payment('cash', 'confirmed', 'NaN')],
      [payment('cash', 'confirmed', '500.001')],
    ]) {
      final state = PrepaidInvoiceReadiness.check(
        order: order('approved', '500.00'),
        payments: rows,
      );
      expect(state.canPost, isFalse);
    }
    expect(
      PrepaidInvoiceReadiness.check(
        order: order('approved', '500.001'),
        payments: [payment('cash', 'confirmed', '500.00')],
      ).canPost,
      isFalse,
    );
  });

  test('posted and invalid order states never create second invoice', () {
    expect(PrepaidInvoiceReadiness.check(
      order: order('posted', '500.00'),
      payments: [payment('cash', 'confirmed', '500.00')],
    ).canPost, isFalse);
    expect(PrepaidInvoiceReadiness.check(
      order: order('cancelled', '500.00'),
      payments: [],
    ).canPost, isFalse);
    expect(PrepaidInvoiceReadiness.check(
      order: order('approved', '0.00'),
      payments: [],
    ).canPost, isFalse);
  });

  test('invoice and return screens cannot show stale branch records', () {
    final sales =
        File('lib/screens/sales/prepaid_orders_screen.dart').readAsStringSync();
    final returns =
        File('lib/screens/sales/prepaid_returns_screen.dart').readAsStringSync();
    expect(sales, contains('final branchReady = branch != null && branch == _branch;'));
    expect(sales, contains('final visibleOrders = branchReady'));
    expect(sales, contains('invoice?.canPost == true'));
    expect(sales, contains('invoice.message'));
    expect(sales, contains("ApiPaths.prepaidPost("));
    expect(returns,
        contains('final visibleBranch = branch != null && branch == _loadedBranch;'));
    expect(returns, contains('final visibleReturns = visibleBranch'));
    for (final source in [sales, returns]) {
      expect(source, contains('ref.read(appStateProvider).currentBranchId != branch'));
      expect(source, contains('Loading authorised branch'));
    }
    expect(returns, isNot(contains('ApiPaths.prepaidRefundPost(')));
    expect(returns, isNot(contains('ApiPaths.prepaidCreditNotePost(')));
  });

  test('workflow states match backend authority: approval then payment, then post', () {
    final sequence = [
      PrepaidInvoiceReadiness.check(
        order: order('discount_pending', '100.00'), payments: []),
      PrepaidInvoiceReadiness.check(
        order: order('approved', '100.00'), payments: []),
      PrepaidInvoiceReadiness.check(
        order: order('approved', '100.00'),
        payments: [payment('upi', 'pending', '100.00')]),
      PrepaidInvoiceReadiness.check(
        order: order('approved', '100.00'),
        payments: [payment('upi', 'confirmed', '100.00')]),
      PrepaidInvoiceReadiness.check(
        order: order('posted', '100.00'),
        payments: [payment('upi', 'confirmed', '100.00')]),
    ];
    expect(sequence.map((state) => state.canPost),
        [false, false, false, true, false]);
  });
}
