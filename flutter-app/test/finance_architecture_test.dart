import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Finance bank reconciliation stays split from the main finance shell', () {
    final main = File(
      'lib/screens/finance/finance_screen.dart',
    ).readAsStringSync();
    final bank = File(
      'lib/screens/finance/finance_bank.dart',
    ).readAsStringSync();

    expect(main, contains("part 'finance_bank.dart';"));
    expect(main, contains('void _setFinanceState(VoidCallback update)'));
    expect(main, isNot(contains('Widget _bank(AppState app, dynamic api)')));
    expect(main, isNot(contains('Future<void> _createBankReconciliation()')));
    expect(main, isNot(contains('Future<void> _bankDetail(int id)')));

    expect(bank, contains('extension _FinanceBankFeature'));
    expect(bank, contains('Widget _bank(AppState app, dynamic api)'));
    expect(bank, contains('Future<void> _createBankReconciliation()'));
    expect(bank, contains('Future<void> _bankDetail(int id)'));
    expect(bank, contains('Future<void> _addBankLine(int id)'));
    expect(bank, contains('Future<void> _resolveBankLine('));
    expect(bank, isNot(contains('setState(')));
  });
}
