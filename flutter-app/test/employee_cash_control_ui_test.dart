import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Employee finance Cash Control is read only and permission gated', () {
    final ui = File('lib/screens/organization/employee_360_screen.dart')
        .readAsStringSync();
    final paths = File('lib/core/api_paths.dart').readAsStringSync();
    expect(ui, contains("if (financeVisible) const Tab(text: 'Cash Control')"));
    expect(ui, contains('class _Employee360CashControl extends ConsumerStatefulWidget'));
    expect(ui, contains("app.can('finance.accounting.view')"));
    expect(ui, contains(".can('finance.accounting.view')"));
    expect(ui, contains("data['read_only'] != true"));
    expect(ui, contains("data['cash_remittance_status'] != 'not_available_in_legacy_v7'"));
    expect(ui, contains('Matching journal amounts do NOT prove'));
    expect(ui, contains('Cash handover:'));
    expect(ui, contains('page_size'));
    expect(paths, contains('employee360CashControl(int id)'));
  });
}
