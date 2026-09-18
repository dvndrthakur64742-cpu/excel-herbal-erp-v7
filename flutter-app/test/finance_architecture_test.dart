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
    final books = File(
      'lib/screens/finance/finance_books.dart',
    ).readAsStringSync();
    final expenses = File(
      'lib/screens/finance/finance_expenses.dart',
    ).readAsStringSync();
    final closing = File(
      'lib/screens/finance/finance_closing.dart',
    ).readAsStringSync();
    final periods = File(
      'lib/screens/finance/finance_periods.dart',
    ).readAsStringSync();

    expect(main, contains("part 'finance_bank.dart';"));
    expect(main, contains("part 'finance_books.dart';"));
    expect(main, contains("part 'finance_expenses.dart';"));
    expect(main, contains("part 'finance_closing.dart';"));
    expect(main, contains("part 'finance_periods.dart';"));
    expect(main, contains('void _setFinanceState(VoidCallback update)'));
    expect(main, isNot(contains('Widget _bank(AppState app, dynamic api)')));
    expect(main, isNot(contains('Future<void> _createBankReconciliation()')));
    expect(main, isNot(contains('Future<void> _bankDetail(int id)')));
    expect(main, isNot(contains('Widget _books(AppState app, dynamic api)')));
    expect(main, isNot(contains('Widget _expenses(AppState app, dynamic api)')));
    expect(main, isNot(contains('Widget _closing(AppState app, dynamic api)')));
    expect(main, isNot(contains('Widget _periods(AppState app, dynamic api)')));
    expect(main.split('\n').length, lessThan(300));

    expect(bank, contains('extension _FinanceBankFeature'));
    expect(bank, contains('Widget _bank(AppState app, dynamic api)'));
    expect(bank, contains('Future<void> _createBankReconciliation()'));
    expect(bank, contains('Future<void> _bankDetail(int id)'));
    expect(bank, contains('Future<void> _addBankLine(int id)'));
    expect(bank, contains('Future<void> _resolveBankLine('));
    expect(bank, isNot(contains('setState(')));
    expect(books, contains('extension _FinanceBooksFeature'));
    expect(expenses, contains('extension _FinanceExpensesFeature'));
    expect(closing, contains('extension _FinanceClosingFeature'));
    expect(periods, contains('extension _FinancePeriodsFeature'));
    expect(books, isNot(contains('setState(')));
    expect(expenses, isNot(contains('setState(')));
    expect(closing, isNot(contains('setState(')));
    expect(periods, isNot(contains('setState(')));
  });
}
