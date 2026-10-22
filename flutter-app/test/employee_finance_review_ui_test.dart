import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:excel_herbal_erp/screens/organization/employee_finance_review_panel.dart';

Map<String, dynamic> cashFixture() => {
  'read_only': true,
  'scope': 'canonical_posted_daily_cycles_only',
  'cash_remittance_status': 'not_available_in_legacy_v7',
  'employee_id': 42,
  'period': <String, dynamic>{'from': '2026-10-01', 'to': '2026-10-22'},
  'page': 1,
  'page_size': 25,
  'has_more': true,
  'page_totals': <String, dynamic>{
    'cash_reported_paise': 15000,
    'upi_reported_paise': 3000,
  },
  'page_flags': <String, dynamic>{
    'journal_mismatch_count': 1,
    'cash_remittance_unproven_count': 1,
  },
  'rows': [
    {
      'daily_cycle_id': 155,
      'business_date': '2026-10-22',
      'reported_cash_paise': 15000,
      'reported_upi_paise': 3000,
      'journal_check': 'journal_amount_mismatch',
    },
  ],
};

Map<String, dynamic> ledgerFixture() => {
  'read_only': true,
  'register': 'person_ledger',
  'scope': 'posted_gl_employee_tagged_and_canonical_stock_sales_points',
  'balance_basis': 'complete_tagged_movement_history_not_visible_page',
  'employee_cash_handover_verified': false,
  'upi_bank_settlement_verified': false,
  'employee_id': 42,
  'period': <String, dynamic>{'from': '2026-10-01', 'to': '2026-10-22'},
  'page': 1,
  'page_size': 25,
  'has_more': true,
  'rows': [<String, dynamic>{'event_type': 'gl', 'event_id': 555}],
  'financial_accounts': [
    {
      'account_code': 'EMPLOYEE_CASH_IN_TRANSIT',
      'currency': 'INR',
      'opening_debit_minus_credit': '0.00',
      'closing_debit_minus_credit': '200.00',
    },
  ],
};

EmployeeFinanceReviewSnapshot validSnapshot() =>
    EmployeeFinanceReviewSnapshot.fromResponses(
      employeeId: 42,
      from: '2026-10-01', to: '2026-10-22',
      cashResponse: cashFixture(),
      ledgerResponse: ledgerFixture(),
    );

void main() {
  test('Finance Review reads only existing protected Employee 360 REST routes', () {
    final profile = File('lib/screens/organization/employee_360_screen.dart')
        .readAsStringSync();
    final review = File('lib/screens/organization/employee_finance_review_panel.dart')
        .readAsStringSync();
    expect(profile, contains("if (financeVisible) const Tab(text: 'Finance Review')"));
    expect(profile, contains('EmployeeFinanceReviewPanel('));
    expect(review, contains("appStateProvider).can('finance.accounting.view')"));
    expect(review, contains('ApiPaths.employee360CashControl(widget.employeeId)'));
    expect(review, contains('ApiPaths.employee360Register(widget.employeeId)'));
    expect(review, contains("'type': 'person_ledger'"));
    expect(review, contains('api.get('));
    expect(review, isNot(contains('api.post(')));
    expect(review, isNot(contains('api.put(')));
    expect(review, contains('No verified cross-source total'));
  });

  test('Bookkeeping amounts and tagged GL remain separate evidence', () {
    final snapshot = validSnapshot();
    expect(snapshot.cashBookedPaise, 15000);
    expect(snapshot.upiBookedPaise, 3000);
    expect(snapshot.mismatches, 1);
    expect(snapshot.unprovenCash, 1);
    expect(snapshot.hasMore, isTrue);
    expect(snapshot.ledgerHasMore, isTrue);
    expect(snapshot.ledgerEventPageCount, 1);
    expect(snapshot.accounts.single['closing_debit_minus_credit'], '200.00');
    expect(EmployeeFinanceReviewSnapshot.inr(snapshot.cashBookedPaise), '₹150.00');
  });

  test('Wrong employee, forged finance proof or unsafe page fails closed', () {
    expect(
      () => EmployeeFinanceReviewSnapshot.fromResponses(
        employeeId: 99, from: '2026-10-01', to: '2026-10-22', cashResponse: cashFixture(), ledgerResponse: ledgerFixture()),
      throwsFormatException,
    );
    final forgedLedger = ledgerFixture()..['employee_cash_handover_verified'] = true;
    expect(
      () => EmployeeFinanceReviewSnapshot.fromResponses(
        employeeId: 42, from: '2026-10-01', to: '2026-10-22', cashResponse: cashFixture(), ledgerResponse: forgedLedger),
      throwsFormatException,
    );
    final forgedCash = cashFixture()..['cash_remittance_status'] = 'confirmed';
    expect(
      () => EmployeeFinanceReviewSnapshot.fromResponses(
        employeeId: 42, from: '2026-10-01', to: '2026-10-22', cashResponse: forgedCash, ledgerResponse: ledgerFixture()),
      throwsFormatException,
    );
    final wrongPage = cashFixture()..['page'] = 2;
    expect(
      () => EmployeeFinanceReviewSnapshot.fromResponses(
        employeeId: 42, from: '2026-10-01', to: '2026-10-22', cashResponse: wrongPage, ledgerResponse: ledgerFixture()),
      throwsFormatException,
    );
  });

  test('Forged totals, missing field or overcount flags fail closed', () {
    final negative = cashFixture();
    (negative['page_totals'] as Map)['cash_reported_paise'] = '-100';
    expect(
      () => EmployeeFinanceReviewSnapshot.fromResponses(
        employeeId: 42, from: '2026-10-01', to: '2026-10-22', cashResponse: negative, ledgerResponse: ledgerFixture()),
      throwsFormatException,
    );
    final excess = cashFixture();
    (excess['page_flags'] as Map)['journal_mismatch_count'] = 2;
    expect(
      () => EmployeeFinanceReviewSnapshot.fromResponses(
        employeeId: 42, from: '2026-10-01', to: '2026-10-22', cashResponse: excess, ledgerResponse: ledgerFixture()),
      throwsFormatException,
    );
    final malformed = ledgerFixture();
    (malformed['financial_accounts'] as List).first['currency'] = 'USD';
    expect(
      () => EmployeeFinanceReviewSnapshot.fromResponses(
        employeeId: 42, from: '2026-10-01', to: '2026-10-22', cashResponse: cashFixture(), ledgerResponse: malformed),
      throwsFormatException,
    );
  });

  test('stale financial period, ledger page or forged closure date fail closed', () {
    EmployeeFinanceReviewSnapshot parse(
      Map<String, dynamic> cash, Map<String, dynamic> ledger,
    ) => EmployeeFinanceReviewSnapshot.fromResponses(
      employeeId: 42, from: '2026-10-01', to: '2026-10-22',
      cashResponse: cash, ledgerResponse: ledger,
    );

    final staleCash = cashFixture();
    (staleCash['period'] as Map)['from'] = '2026-09-01';
    expect(() => parse(staleCash, ledgerFixture()), throwsFormatException);

    final staleLedger = ledgerFixture();
    (staleLedger['period'] as Map)['to'] = '2026-09-30';
    expect(() => parse(cashFixture(), staleLedger), throwsFormatException);

    final wrongLedgerPage = ledgerFixture()..['page'] = 2;
    expect(() => parse(cashFixture(), wrongLedgerPage), throwsFormatException);

    final wrongLedgerSize = ledgerFixture()..['page_size'] = 10;
    expect(() => parse(cashFixture(), wrongLedgerSize), throwsFormatException);

    final shiftedClosing = cashFixture();
    ((shiftedClosing['rows'] as List).first as Map)['business_date'] =
        '2026-09-30';
    expect(() => parse(shiftedClosing, ledgerFixture()), throwsFormatException);

    final forgedLedgerPage = ledgerFixture()
      ..['rows'] = List.generate(26, (n) => {'event_id': n + 1});
    expect(() => parse(cashFixture(), forgedLedgerPage), throwsFormatException);
  });

  testWidgets('Finance Review renders live-source figures with unverified warnings',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: EmployeeFinanceReviewView(snapshot: validSnapshot())),
    ));
    expect(find.text('Employee Finance Review'), findsOneWidget);
    expect(find.text('More Person Ledger transactions exist'), findsWidgets);
    expect(find.text('Cash booked · first 25'), findsOneWidget);
    expect(find.text('₹150.00'), findsOneWidget);
    expect(find.text('UPI booked · first 25'), findsOneWidget);
    expect(find.text('₹30.00'), findsOneWidget);
    expect(find.text('Journal mismatches · first 25'), findsOneWidget);
    expect(find.text('Cash handovers unproven · first 25'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -650));
    await tester.pumpAndSettle();
    expect(find.text('Cashier handover: NOT VERIFIED'), findsWidgets);
    expect(find.text('UPI bank settlement: NOT VERIFIED'), findsWidgets);
    expect(find.text('Daily Orders / B2B linking: NOT VERIFIED'), findsWidgets);
    await tester.drag(find.byType(ListView), const Offset(0, -650));
    await tester.pumpAndSettle();
    expect(find.text('Employee-tagged GL accounts'), findsOneWidget);
    expect(find.text('EMPLOYEE_CASH_IN_TRANSIT'), findsOneWidget);
  });
}
