import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:excel_herbal_erp/core/api_paths.dart';
import 'package:excel_herbal_erp/screens/reports/branch_reporting_watch_panel.dart';

void main() {
  test('Manager Watch displays signed attestation statuses without marking payment verified or sending reminders', () {
    expect(ApiPaths.managerReportingWatch, '/reports/manager-watch');
    expect(ApiPaths.reportReminderDrafts, '/reports/reminder-drafts');
    expect(BranchReportingWatchPanel, isNotNull);
    final view = File('lib/screens/reports/branch_reporting_watch_panel.dart').readAsStringSync();
    expect(view, contains("coverage['weekly_monthly_product_salary_submission_evidence_integrated'] != true"));
    expect(view, contains("report['submission_registry_read_only'] != true"));
    expect(view, contains("report['reminder_outbox_dispatch_enabled'] != false"));
    expect(view, contains('Reports Submitted'));
    expect(view, contains('Reports Approved'));
    expect(view, contains('Reports Rejected'));
    expect(view, contains('Reports Not Submitted'));
    expect(view, contains("branch['reporting_submissions']"));
    expect(view, contains("obligation['submission_state']"));
    expect(view, contains('no exact time deadline'));
    expect(view, contains('no notifications have been sent'));
    expect(view, contains('NOT verified payment proof'));
  });
}
