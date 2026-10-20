import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:excel_herbal_erp/core/api_paths.dart';
import 'package:excel_herbal_erp/screens/reports/reports_screen.dart';

void main() {
  test('Branch weekly/monthly reporting uses scoped read-only V7 endpoint and finance visibility', () {
    expect(ApiPaths.branchPeriodControl, '/reports/branch-period');
    expect(const ReportsScreen(), isA<ReportsScreen>());
    final src = File('lib/screens/reports/reports_screen.dart').readAsStringSync();
    expect(src, contains("_ReportOption('branch_weekly', 'Branch Weekly Performance'"));
    expect(src, contains("_ReportOption('branch_monthly', 'Branch Monthly Performance'"));
    expect(src, contains("app.can('reports.view')"));
    expect(src, contains("branchPeriodControl"));
    expect(src, contains("activeType == 'branch_weekly' ? 'week' : 'month'"));
    expect(src, contains("if (dayReports.contains(activeType)) 'date': toValue"));
    expect(src, contains("needsBranch && app.currentBranchId == null"));
    expect(src, contains("_BranchPeriodControlPanel(data: data)"));
    expect(src, contains("report['read_only'] != true"));
    expect(src, contains("report['scope'] != 'single_authorized_branch_canonical_v7'"));
    expect(src, contains("coverage['cashier_handover_verified'] != false"));
    expect(src, contains("coverage['upi_bank_verified'] != false"));
    expect(src, contains("'previous_period'"));
    expect(src, contains("employee['needs_attention']"));
    expect(src, contains("financeVisible && employee['tagged_cash_in_transit'] is Map"));
    expect(src, contains('Counter Sales (separate)'));
    expect(src, contains('NOT bank/cashier verified'));
  });
}
