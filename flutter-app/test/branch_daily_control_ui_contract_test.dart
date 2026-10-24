import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:excel_herbal_erp/core/api_paths.dart';
import 'package:excel_herbal_erp/screens/reports/reports_screen.dart';

void main() {
  test('Branch Manager one-day control uses the existing authenticated reporting area', () {
    expect(ApiPaths.branchDailyControl, '/reports/branch-daily');
    expect(const ReportsScreen(), isA<ReportsScreen>());
    final code = File('lib/screens/reports/reports_screen.dart').readAsStringSync();
    expect(code, contains("_ReportOption('branch_daily', 'Branch Daily Control'"));
    expect(code, contains("app.can('reports.view')"));
    expect(code, contains("'branch_daily',"));
    expect(code, contains("if (dayReports.contains(activeType)) 'date': toValue"));
    expect(code, contains("needsBranch && app.currentBranchId == null"));
    expect(code, contains("path: ApiPaths.branchDailyControl"));
    expect(code, contains("_BranchDailyControlPanel(data: data)"));
    expect(code, contains("report['read_only'] != true"));
    expect(code, contains("report['scope'] != 'single_authorized_branch_canonical_v7'"));
    expect(code, contains("['cashier_handover_verified'] != false"));
    expect(code, contains("['upi_bank_verified'] != false"));
    expect(code, contains("Cash/UPI allocations are NOT"));
    expect(code, contains("Counter Sales (separate)"));
    expect(code, contains("Employee Daily Activity & Exceptions"));
    expect(code, contains("employee['exceptions']"));
  });
}
