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
  'page_evidence_gaps': <String, dynamic>{
    'cash_without_independent_receipt_paise': 15000,
    'upi_without_bank_confirmation_paise': 3000,
    'interpretation': 'booked_tenders_without_independent_proof_not_outstanding',
    'basis': 'canonical_daily_order_page_only',
  },
  'page_flags': <String, dynamic>{
    'journal_mismatch_count': 1,
    'cash_remittance_unproven_count': 1,
    'upi_bank_unproven_count': 1,
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
    expect(review, contains("ref.read(appStateProvider).can('finance.accounting.view')"));
    expect(review.indexOf("ref.read(appStateProvider).can('finance.accounting.view')"),
        lessThan(review.indexOf('final api = ref.read(apiClientProvider);')));
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
    expect(snapshot.unprovenUpi, 1);
    expect(snapshot.cashEvidencePendingPaise, 15000);
    expect(snapshot.upiEvidencePendingPaise, 3000);
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

  test('Evidence gaps never claim employee debt and must match booked tender', () {
    EmployeeFinanceReviewSnapshot parse(Map<String, dynamic> cash) =>
        EmployeeFinanceReviewSnapshot.fromResponses(
          employeeId: 42,
          from: '2026-10-01',
          to: '2026-10-22',
          cashResponse: cash,
          ledgerResponse: ledgerFixture(),
        );

    final fakeDebt = cashFixture();
    (fakeDebt['page_evidence_gaps'] as Map)['interpretation'] =
        'employee_cash_outstanding';
    expect(() => parse(fakeDebt), throwsFormatException);

    final inflatedCash = cashFixture();
    (inflatedCash['page_evidence_gaps'] as Map)
        ['cash_without_independent_receipt_paise'] = 20000;
    expect(() => parse(inflatedCash), throwsFormatException);

    final inflatedUpi = cashFixture();
    (inflatedUpi['page_evidence_gaps'] as Map)
        ['upi_without_bank_confirmation_paise'] = 4000;
    expect(() => parse(inflatedUpi), throwsFormatException);

    final fakePage = cashFixture();
    (fakePage['page_evidence_gaps'] as Map)['basis'] = 'all_employees';
    expect(() => parse(fakePage), throwsFormatException);

    final fakeUpiCount = cashFixture();
    (fakeUpiCount['page_flags'] as Map)['upi_bank_unproven_count'] = 0;
    expect(() => parse(fakeUpiCount), throwsFormatException);

    final fakeCashCount = cashFixture();
    (fakeCashCount['page_flags'] as Map)['cash_remittance_unproven_count'] = 0;
    expect(() => parse(fakeCashCount), throwsFormatException);

    final legacy = cashFixture()
      ..remove('page_evidence_gaps');
    (legacy['page_flags'] as Map).remove('upi_bank_unproven_count');
    expect(parse(legacy).cashEvidencePendingPaise, 15000);
    expect(parse(legacy).unprovenUpi, 1);
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

  test('Finance Review links to the existing paginated Employee 360 registers', () {
    final profile = File('lib/screens/organization/employee_360_screen.dart')
        .readAsStringSync();
    final panel = File('lib/screens/organization/employee_finance_review_panel.dart')
        .readAsStringSync();
    expect(profile, contains("tabs.indexWhere((tab) => tab.text == 'Cash Control')"));
    expect(profile, contains("tabs.indexWhere((tab) => tab.text == 'Person Ledger')"));
    expect(profile, contains('DefaultTabController.of(financeTabContext)'));
    expect(profile, contains('.animateTo(cashControlIndex)'));
    expect(profile, contains('.animateTo(personLedgerIndex)'));
    expect(panel, contains('widget.onOpenCashControl'));
    expect(panel, contains('widget.onOpenPersonLedger'));
    expect(panel, isNot(contains('api.post(')));
    expect(panel, isNot(contains('api.put(')));
  });

  testWidgets('Finance Review opens original Cash Control and Person Ledger tabs',
      (tester) async {
    var cashOpened = 0;
    var ledgerOpened = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: EmployeeFinanceReviewView(
          snapshot: validSnapshot(),
          onOpenCashControl: () => cashOpened++,
          onOpenPersonLedger: () => ledgerOpened++,
        ),
      ),
    ));
    expect(find.text('Open Cash Control'), findsOneWidget);
    expect(find.text('Open Person Ledger'), findsOneWidget);
    await tester.tap(find.text('Open Cash Control'));
    await tester.pump();
    await tester.tap(find.text('Open Person Ledger'));
    await tester.pump();
    expect(cashOpened, 1);
    expect(ledgerOpened, 1);
  });

  testWidgets('Finance Review renders live-source figures with unverified warnings',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: EmployeeFinanceReviewView(snapshot: validSnapshot())),
    ));
    expect(find.text('Employee Finance Review'), findsOneWidget);
    expect(find.textContaining('EVIDENCE PENDING is NOT employee outstanding'),
        findsOneWidget);
    // The expanded evidence metrics span multiple rows on narrower screens.
    // Scroll as an actual reviewer would: ListView children outside the
    // viewport are legitimately lazy and must not be treated as missing.
    for (final label in <String>[
      'Cash booked · first 25',
      'UPI booked · first 25',
      'Journal mismatches · first 25',
      'Cash handovers unproven · first 25',
      'UPI confirmations unproven · first 25',
      'Cash booked without receipt proof · first 25',
      'UPI booked without bank proof · first 25',
      'More Person Ledger transactions exist',
      'Cashier handover: NOT VERIFIED',
      'UPI bank settlement: NOT VERIFIED',
      'Daily Orders / B2B linking: NOT VERIFIED',
      'Employee-tagged GL accounts',
      'EMPLOYEE_CASH_IN_TRANSIT',
    ]) {
      await tester.scrollUntilVisible(
        find.text(label),
        185,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 35,
      );
      expect(find.text(label), findsOneWidget);
    }
  });
}
