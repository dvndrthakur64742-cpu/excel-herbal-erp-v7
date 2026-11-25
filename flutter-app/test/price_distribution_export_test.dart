import 'dart:io';

import 'package:excel_herbal_erp/core/price_distribution_export.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('export contains only visible fields and preserves amounts and order', () {
    final source = <Map<String, dynamic>>[
      {
        'full_name': 'Synthetic Employee',
        'employee_code': 'TEST-01',
        'reporting_category': 'FIELD_EXECUTIVE',
        'sale_days': 2,
        'sale_price': '200.00',
        'ho_amount': '100.00',
        'bm_profit': '30.00',
        'salary_fund': '50.00',
        'expense': '20.00',
        'points': 0,
        'employee_id': 1,
        'internal_metadata': 'not for export',
      },
      {'full_name': 'Second Employee', 'sale_price': '0.00'},
    ];
    final exported = priceDistributionExportRows(source);
    expect(exported, hasLength(2));
    expect(exported.first, {
      'Employee': 'Synthetic Employee',
      'Employee Code': 'TEST-01',
      'Reporting': 'FIELD_EXECUTIVE',
      'Sale Days': 2,
      'Sale Price': '200.00',
      'HO Amount': '100.00',
      'BM Profit': '30.00',
      'Salary Fund': '50.00',
      'Expense': '20.00',
      'Points': 0,
    });
    expect(exported.last['Employee'], 'Second Employee');
    expect(exported.last['Sale Price'], '0.00');
    expect(source.first['internal_metadata'], 'not for export');
  });

  test('empty authorised report produces no export rows', () {
    expect(priceDistributionExportRows([]), isEmpty);
  });

  test('distribution screen uses current scoped rows and standard export controls', () {
    final source = File('lib/screens/reports/reports_screen.dart').readAsStringSync();
    expect(source, contains('scope: scopeLabel,'));
    final panel = source.substring(
      source.indexOf('class _PriceDistributionPanel'),
      source.indexOf('class _MetricCard'),
    );
    expect(panel, contains('_ReportExportActions('));
    expect(panel, contains('priceDistributionExportRows(rows)'));
    expect(panel, contains('All visible employees'));
    expect(panel, contains('BusinessFormat.status(reportingCategory)'));
  });
}
