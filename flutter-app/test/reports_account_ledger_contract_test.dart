import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Account Ledger bypasses the generic list loader until an account is selected', () {
    final screen = File('lib/screens/reports/reports_screen.dart').readAsStringSync();
    final ledgerBranch = screen.indexOf(
      "final reportView = activeType == 'account_ledger'",
    );
    final genericLoader = screen.indexOf(': AsyncPanel(', ledgerBranch);

    expect(ledgerBranch, greaterThanOrEqualTo(0));
    expect(genericLoader, greaterThan(ledgerBranch));
    expect(
      screen.substring(ledgerBranch, genericLoader),
      contains('_AccountLedgerPanel('),
    );
    expect(screen, contains("widget.api.get(ApiPaths.accountLedger,"));
    expect(screen, contains("'account_id': selectedId"));
  });

  test('Account Ledger API contract requires account and date range', () {
    final routes = File(
      '../backend/excel-herbal-erp-v7/src/Http/RouteRegistry.php',
    ).readAsStringSync();
    final contract = File(
      '../backend/excel-herbal-erp-v7/src/Http/ApiContract.php',
    ).readAsStringSync();

    expect(
      routes,
      contains("['GET','/reports/account-ledger','reports.ledger',true]"),
    );
    expect(
      contract,
      contains("'reports.ledger'=>['account_id','from','to']"),
    );
  });
}
