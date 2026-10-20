import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:excel_herbal_erp/core/api_paths.dart';
import 'package:excel_herbal_erp/screens/reports/report_submissions_panel.dart';

void main() {
  test('Reports submissions manager/reviewer capability UI and attestation evidence', () {
    expect(ApiPaths.reportSubmissions, '/reports/submissions');
    expect(ReportSubmissionsPanel, isNotNull);
    final parent = File('lib/screens/reports/reports_screen.dart').readAsStringSync();
    final panel = File('lib/screens/reports/report_submissions_panel.dart').readAsStringSync();
    expect(parent, contains("app.can('reports.submit') || app.can('reports.review')"));
    expect(parent, contains("_ReportOption('report_submissions'"));
    expect(parent, contains("path: ApiPaths.reportSubmissions"));
    expect(parent, contains("ReportSubmissionsPanel("));
    expect(parent, contains("canSubmit: app.can('reports.submit')"));
    expect(parent, contains("canReview: app.can('reports.review')"));
    expect(parent, contains("canViewSalary: app.can('payroll.salary.view')"));
    expect(panel, contains("if (!widget.canViewSalary)"));
    expect(panel, contains("report_type"));
    expect(panel, contains("summary_text"));
    expect(panel, contains("period_date"));
    expect(panel, contains("'/decision'"));
    expect(panel, contains("'/history'"));
    expect(panel, contains("canReview&&row['status']=='submitted'"));
    expect(panel, contains("'authorized_branch_report_submissions'"));
    expect(panel, contains("user_attestation_only_not_bank_payroll_or_stock_verification"));
    expect(panel, contains("Automatic WhatsApp/push/email is disabled."));
    expect(panel, contains("Immutable Submission History"));
  });
}
