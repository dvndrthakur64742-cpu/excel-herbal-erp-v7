import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:excel_herbal_erp/screens/organization/employee_cashier_evidence_uat.dart';
import 'package:excel_herbal_erp/screens/organization/employee_finance_uat_api_loader.dart';

Map<String, dynamic> uatCashFixture() => {
  'read_only': true,
  'scope': 'disposable_v8_test_finance_review_only',
  'company_id': 1,
  'branch_id': 2,
  'employee_id': 42,
  'period': <String, dynamic>{'from': '2026-10-01', 'to': '2026-10-24'},
  'source_keys_independent': true,
  'same_sale_across_sources_not_proven': true,
  'combined_sale_total_paise': null,
  'combined_employee_cash_outstanding_paise': null,
  'physical_legacy_daily_cash_verified': false,
  'external_bank_deposit_verified': false,
  'source_pages': {
    'legacy_daily_orders': {
      'has_more': false,
      'rows': <Map<String, dynamic>>[
        {'source_type': 'daily_cycle', 'source_id': 55,
         'source_key': 'daily_cycle:55', 'cash_handover_verified': false},
      ],
    },
    'canonical_b2b_field_cash': {
      'has_more': false,
      'rows': <Map<String, dynamic>>[
        {
          'source_type': 'b2b_retailer_sale',
          'source_id': 77,
          'source_key': 'b2b_retailer_sale:77',
          'business_date': '2026-10-23',
          'posted_sale_paise': 20000,
          'field_cash_reported_paise': 20000,
          'upi_reported_paise': 0,
          'upi_bank_verified': false,
          'journal_consistent': true,
          'cash_custody_state': 'cashier_handover_reconciled_uat',
          'cash_handover_verified': true,
          'cashier_finance_evidence': {
            'evidence_scope': 'disposable_v8_test_verified_canonical_b2b_only',
            'source_key': 'b2b_retailer_sale:77',
            'cash_transit_reclassification_verified_uat': true,
            'physical_cash_confirmed_on_office_staging': false,
            'production_financial_status': 'not_certified',
            'cashier_receipt': {
              'receipt_id': 88,
              'reference': 'CI-CASHIER-REF-0001',
              'cashier_user_id': 2,
              'cashier_employee_id': 23,
              'amount_paise': 20000,
              'state': 'confirmed_uat',
            },
            'finance_check': {
              'remittance_id': 99,
              'journal_id': 101,
              'checker_user_id': 3,
              'checker_employee_id': 24,
              'amount_paise': 20000,
              'state': 'posted_uat',
            },
          },
        },
      ],
    },
  },
};

Map<String, dynamic> b2bRow(Map<String, dynamic> page) =>
    ((page['source_pages'] as Map)['canonical_b2b_field_cash'] as Map)['rows'][0];

Map<String, dynamic> receipt(Map<String, dynamic> page) =>
    (b2bRow(page)['cashier_finance_evidence'] as Map)['cashier_receipt'];

Map<String, dynamic> checker(Map<String, dynamic> page) =>
    (b2bRow(page)['cashier_finance_evidence'] as Map)['finance_check'];

CashierEvidenceUatPage parseUat(Map<String, dynamic> input) =>
    CashierEvidenceUatPage.fromResponse(
      response: input, companyId: 1, branchId: 2, employeeId: 42,
      from: '2026-10-01', to: '2026-10-24',
    );

void main() {
  test('Finance Review consumes no fake live cashier/PSP source', () {
    final review = File('lib/screens/organization/employee_finance_review_panel.dart')
        .readAsStringSync();
    final uat = File('lib/screens/organization/employee_cashier_evidence_uat.dart')
        .readAsStringSync();
    expect(review, contains('CashierEvidenceUatSection(page: cashierEvidenceUat!)'));
    expect(review, contains('final CashierEvidenceUatPage? cashierEvidenceUat;'));
    expect(review, contains('if (cashierEvidenceUat != null)'));
    expect(review, contains('ApiPaths.employee360CashControl(widget.employeeId)'));
    expect(review, contains('ApiPaths.employee360Register(widget.employeeId)'));
    expect(review, isNot(contains('uatCrossSourceResponse:')));
    expect(uat, contains('disposable_v8_test_finance_review_only'));
    expect(uat, contains('production_financial_status'));
    expect(uat, isNot(contains('api.post(')));
    expect(uat, isNot(contains('api.get(')));
  });

  test('Finance-only UAT payload preserves original source and two different actors', () {
    final result = parseUat(uatCashFixture());
    expect(result.records, hasLength(1));
    final chain = result.records.single;
    expect(chain.saleId, 77);
    expect(chain.amountPaise, 20000);
    expect(chain.receiptId, 88);
    expect(chain.reference, 'CI-CASHIER-REF-0001');
    expect(chain.cashierEmployeeId, 23);
    expect(chain.checkerEmployeeId, 24);
    expect(chain.remittanceId, 99);
    expect(chain.journalId, 101);
    expect(CashierEvidenceUatPage.inr(chain.amountPaise), '₹200.00');
  });

  test('Forged viewer scope, branch, period or full outstanding is rejected', () {
    final wrongBranch = uatCashFixture()..['branch_id'] = 3;
    expect(() => parseUat(wrongBranch), throwsFormatException);
    final wrongPeriod = uatCashFixture();
    (wrongPeriod['period'] as Map)['from'] = '2026-09-01';
    expect(() => parseUat(wrongPeriod), throwsFormatException);
    final fakeLive = uatCashFixture()..['scope'] = 'live_verified_receipts';
    expect(() => parseUat(fakeLive), throwsFormatException);
    final fakeDebt = uatCashFixture()
      ..['combined_employee_cash_outstanding_paise'] = 20000;
    expect(() => parseUat(fakeDebt), throwsFormatException);
    final fakeBank = uatCashFixture()..['external_bank_deposit_verified'] = true;
    expect(() => parseUat(fakeBank), throwsFormatException);
  });

  test('Cashier cannot be own checker, amounts and canonical IDs must match', () {
    final samePerson = uatCashFixture();
    checker(samePerson)['checker_employee_id'] = 23;
    expect(() => parseUat(samePerson), throwsFormatException);
    final sameUser = uatCashFixture();
    checker(sameUser)['checker_user_id'] = 2;
    expect(() => parseUat(sameUser), throwsFormatException);
    final forgedReceipt = uatCashFixture();
    receipt(forgedReceipt)['reference'] = 'X';
    expect(() => parseUat(forgedReceipt), throwsFormatException);
    final alteredAmount = uatCashFixture();
    receipt(alteredAmount)['amount_paise'] = 19999;
    expect(() => parseUat(alteredAmount), throwsFormatException);
    final fakeProof = uatCashFixture();
    (b2bRow(fakeProof)['cashier_finance_evidence'] as Map)
        ['physical_cash_confirmed_on_office_staging'] = true;
    expect(() => parseUat(fakeProof), throwsFormatException);
    final duplicate = uatCashFixture();
    ((duplicate['source_pages'] as Map)['canonical_b2b_field_cash'] as Map)
        ['rows'].add(Map<String, dynamic>.from(b2bRow(duplicate)));
    expect(() => parseUat(duplicate), throwsFormatException);
  });

  test('Unverified B2B and legacy Daily Orders are never receipt evidence', () {
    final unverified = uatCashFixture();
    b2bRow(unverified)['cash_handover_verified'] = false;
    b2bRow(unverified)['cash_custody_state'] = 'pending_cashier_handover';
    b2bRow(unverified)['cashier_finance_evidence'] = null;
    expect(parseUat(unverified).records, isEmpty);
    final forgedPending = uatCashFixture();
    b2bRow(forgedPending)['cash_handover_verified'] = false;
    expect(() => parseUat(forgedPending), throwsFormatException);
    final fakeDaily = uatCashFixture();
    (((fakeDaily['source_pages'] as Map)['legacy_daily_orders'] as Map)
        ['rows'][0] as Map)['cash_handover_verified'] = true;
    expect(() => parseUat(fakeDaily), throwsFormatException);
  });

  testWidgets('UAT-only authenticated GET adapter renders original receipt and checker',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: FinanceEvidenceUatApiLoader(
        getAuthenticatedUatPage: () async {
          calls++;
          return uatCashFixture();
        },
        companyId: 1, branchId: 2, employeeId: 42,
        from: '2026-10-01', to: '2026-10-24',
      )),
    ));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.text('Cashier → Finance Checker · UAT ONLY'), findsOneWidget);
    expect(find.textContaining('CI-CASHIER-REF-0001'), findsOneWidget);
    expect(find.textContaining('GL journal #101'), findsOneWidget);
  });

  testWidgets('Wrong-employee UAT response fails closed and displays no fake proof',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: FinanceEvidenceUatApiLoader(
        getAuthenticatedUatPage: () async => uatCashFixture(),
        companyId: 1, branchId: 2, employeeId: 43,
        from: '2026-10-01', to: '2026-10-24',
      )),
    ));
    await tester.pumpAndSettle();
    expect(find.text('UAT Cashier evidence unavailable'), findsOneWidget);
    expect(find.textContaining('No Cash receipt or Finance approval'), findsOneWidget);
    expect(find.textContaining('CI-CASHIER-REF-0001'), findsNothing);
  });

  testWidgets('Transport failures are not converted into verified Cash receipts',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: FinanceEvidenceUatApiLoader(
        getAuthenticatedUatPage: () async => throw StateError('Authorization denied'),
        companyId: 1, branchId: 2, employeeId: 42,
        from: '2026-10-01', to: '2026-10-24',
      )),
    ));
    await tester.pumpAndSettle();
    expect(find.text('UAT Cashier evidence unavailable'), findsOneWidget);
    expect(find.textContaining('Cashier → Finance Checker'), findsNothing);
  });

  testWidgets('Read-only Finance Review component shows genuine chain and UAT caveat',
      (tester) async {
    final page = parseUat(uatCashFixture());
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(
        child: CashierEvidenceUatSection(page: page),
      )),
    ));
    expect(find.text('Cashier → Finance Checker · UAT ONLY'), findsOneWidget);
    expect(find.text('B2B #77 · ₹200.00'), findsOneWidget);
    expect(find.textContaining('CI-CASHIER-REF-0001'), findsOneWidget);
    expect(find.textContaining('Finance checker #24'), findsOneWidget);
    expect(find.textContaining('GL journal #101'), findsOneWidget);
    expect(find.textContaining('NOT Office Cash proof'), findsOneWidget);
  });
}
