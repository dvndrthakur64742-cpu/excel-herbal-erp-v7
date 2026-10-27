import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:excel_herbal_erp/core/api_paths.dart';
import 'package:excel_herbal_erp/screens/reports/manager_notification_center_panel.dart';

void main() {
  test('Internal notification center is reviewer-only, draft-only, auditable and has no send action', () {
    expect(ApiPaths.reportReminderDrafts, '/reports/reminder-drafts');
    expect(ManagerNotificationCenterPanel, isNotNull);
    final root = File('lib/screens/reports/reports_screen.dart').readAsStringSync();
    final screen = File('lib/screens/reports/manager_notification_center_panel.dart').readAsStringSync();
    expect(root, contains("app.can('reports.view') && app.can('reports.review')"));
    expect(root, contains("_ReportOption('manager_notification_center'"));
    expect(root, contains("activeType == 'manager_notification_center'"));
    expect(root, contains("path: ApiPaths.reportReminderDrafts"));
    expect(root, contains("ManagerNotificationCenterPanel("));
    expect(screen, contains("widget.api.get(ApiPaths.reportReminderDrafts"));
    expect(screen, contains('reportReminderDrafts}/prepare'));
    expect(screen, contains('/\$id/dismiss'));
    expect(screen, contains("result['dispatch_enabled'] != false"));
    expect(screen, contains("data['dispatch_enabled'] != false"));
    expect(screen, contains("data['evidence'] != 'internal_followup_draft_only_no_delivery'"));
    expect(screen, contains("row['state'] != 'draft'"));
    expect(screen, contains('at least 12 characters'));
    expect(screen, contains('No notification was sent'));
    expect(screen, contains('No SMS, email, WhatsApp or push is sent'));
    expect(screen, contains('not queued, delivered or scheduled'));
  });
}
