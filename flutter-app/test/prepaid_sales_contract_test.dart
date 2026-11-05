import 'package:excel_herbal_erp/core/api_paths.dart';
import 'package:excel_herbal_erp/core/transaction_guardrails.dart';
import 'package:excel_herbal_erp/screens/sales/prepaid_orders_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('prepaid order routes use separate approval, collection and posting', () {
    expect(ApiPaths.prepaidOrders, '/sales/orders');
    expect(ApiPaths.prepaidOrder(42), '/sales/orders/42');
    expect(ApiPaths.prepaidOrderPayments(42), '/sales/orders/42/payments');
    expect(ApiPaths.prepaidApproveDiscount(42),
        '/sales/orders/42/approve-discount');
    expect(ApiPaths.prepaidVerifyUpi(17), '/sales/payments/17/verify-upi');
    expect(ApiPaths.prepaidPost(42), '/sales/orders/42/post');
    expect(ApiPaths.prepaidPaymentAccounts, '/sales/payment-accounts');
    expect(ApiPaths.distributorQuote, '/sales/distributor/quote');
  });

  test('legacy counter UI never authorizes a credit or partial invoice', () {
    for (final customer in <int?>[null, 8]) {
      expect(TransactionGuardrails.counterSale(
          gross: 500, paid: 499, customerId: customer,
          paymentAccountId: 3), isNotNull);
      expect(TransactionGuardrails.counterSale(
          gross: 500, paid: 500, customerId: customer,
          paymentAccountId: 3), isNull);
    }
    expect(TransactionGuardrails.counterSale(
        gross: 500, paid: 500, customerId: 8,
        paymentAccountId: null), isNotNull);
  });

  test('prepaid workspace is a concrete Flutter widget', () {
    expect(const PrepaidOrdersScreen(), isA<PrepaidOrdersScreen>());
  });
}
