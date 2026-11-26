import 'package:excel_herbal_erp/core/bank_reconciliation_input.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String? validate({int? account = 1, String from = '2026-11-01',
      String to = '2026-11-26', String opening = '-1.25', String closing = '0'}) =>
      BankReconciliationInput.validate(accountId: account, from: from, to: to,
        opening: opening, closing: closing);

  test('valid signed bank balances are allowed', () {
    expect(validate(), isNull);
    expect(validate(opening: '999999999999.99'), isNull);
  });
  test('reject missing account, reversed dates and lossy balance amounts', () {
    expect(validate(account: null), isNotNull);
    expect(validate(from: '2026-11-27'), isNotNull);
    for (final amount in ['NaN', 'Infinity', '1.001', 'abc', '1000000000000', '']) {
      expect(validate(closing: amount), isNotNull);
    }
  });
}