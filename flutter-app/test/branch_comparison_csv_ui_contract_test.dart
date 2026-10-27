import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:excel_herbal_erp/core/api_paths.dart';
import 'package:excel_herbal_erp/screens/reports/reports_screen.dart';

void main() {
  test('Regional branch compare and XLS-ready safe CSV use authorized API', () {
    expect(ApiPaths.branchCompare, '/reports/branch-compare');
    expect(const ReportsScreen(), isA<ReportsScreen>());
    final code = File('lib/screens/reports/reports_screen.dart').readAsStringSync();
    expect(code, contains("'branch_compare_weekly', 'branch_compare_monthly'"));
    expect(code, contains("app.can('reports.view')"));
    expect(code, contains("_ReportOption('branch_compare_weekly', 'Compare Branches (Week)'"));
    expect(code, contains("_ReportOption('branch_compare_monthly', 'Compare Branches (Month)'"));
    expect(code, contains("path: ApiPaths.branchCompare"));
    expect(code, contains("comparisonReports.contains(activeType)"));
    expect(code, contains("'mode': activeType == 'branch_compare_weekly' ? 'week' : 'month'"));
    expect(code, contains("'date': toValue"));
    expect(code, contains("_BranchComparisonPanel(data: data, api: api, query: query)"));
    expect(code, contains("report['scope'] != 'single_authorized_branch_canonical_v7'"));
    expect(code, contains("result['scope'] != 'only_effective_authorized_branches'"));
    expect(code, contains("result['financial_visibility'] != 'no_gl_data_exported'"));
    expect(code, contains("coverage['cashier_handover_verified'] != false"));
    expect(code, contains("coverage['upi_bank_verified'] != false"));
    expect(code, contains("'export': 'csv'"));
    expect(code, contains("jsonEncode(response['branch_ids']) != jsonEncode(result['branch_ids'])"));
    expect(code, contains("Uint8List.fromList(utf8.encode(response['csv'] as String))"));
    expect(code, contains("Share.shareXFiles"));
    expect(code, contains("Export authorized CSV for Excel"));
    expect(code, contains("No employee Cash GL is exported."));
  });
}
