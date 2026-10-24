import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:excel_herbal_erp/core/api_paths.dart';
import 'package:excel_herbal_erp/screens/reports/branch_reporting_watch_panel.dart';

void main() {
  const good = {
    'read_only': true,
    'scope': 'authenticated_authorized_active_branches_only',
    'business_date': '2026-10-20',
    'timezone': 'Asia/Kolkata',
    'delivery_enabled': false,
    'automatic_notifications_sent': 0,
    'coverage': {
      'daily_status_from_original_v7_posted_evening': true,
      'weekly_monthly_product_salary_submission_evidence_integrated': true,
      'cashier_handover_verified': false,
      'upi_bank_verified': false,
    },
    'submission_registry_read_only': true,
    'reminder_outbox_dispatch_enabled': false,
    'submission_evidence_summary': {
      'submitted': 0, 'approved': 0, 'rejected': 0,
      'not_submitted': 1, 'hidden_salary_slots': 0,
    },
    'summary': {
      'branches': 1,
      'eligible_field_staff': 2,
      'posted_evening_closings': 1,
      'missing_daily_cycles': 1,
      'unposted_evening_closings': 0,
      'past_due_unposted_or_missing': 1,
      'branch_exceptions': 1,
    },
    'schedule': [
      {
        'id': 'evening_daily_closing',
        'label': 'Evening Daily Closing',
        'time': '19:30',
        'due_state': 'past_due',
        'submission_state': 'overdue_evidence',
      },
      {
        'id': 'tuesday_product_order',
        'label': 'Tuesday Product Order',
        'time': null,
        'due_state': 'due_today',
        'submission_state': 'not_submitted_all_branches',
      },
    ],
    'branches': [
      {
        'branch_id': 2,
        'branch_name': 'North Branch',
        'eligible_field_staff': 2,
        'posted_evening_closings': 1,
        'past_due_unposted_or_missing': 1,
        'pending_stock_requests': 1,
        'reporting_submissions': [
          {'branch_id': 2, 'report_type': 'product_order_tue',
           'submission_state': 'not_submitted', 'revision': null},
        ],
        'employees': [
          {
            'employee_id': 11,
            'employee_name': 'Field A',
            'closing_state': 'posted',
          },
          {
            'employee_id': 12,
            'employee_name': 'Field B',
            'closing_state': 'no_daily_cycle',
          },
        ],
      },
    ],
    'reminder_candidates': [
      {'employee_id': 12, 'delivery_state': 'not_dispatched'},
    ],
  };

  testWidgets('Manager watch shows read-only status and unsent candidates',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: BranchReportingWatchPanel(data: good)),
    ));
    expect(find.textContaining('Business day 2026-10-20'), findsOneWidget);
    expect(find.textContaining('no notifications have been sent'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Manager watch refuses fabricated payment verification',
      (tester) async {
    final tampered = Map<String, dynamic>.from(good);
    tampered['coverage'] = {
      ...Map<String, dynamic>.from(good['coverage'] as Map),
      'upi_bank_verified': true,
    };
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: BranchReportingWatchPanel(data: tampered)),
    ));
    expect(find.text('Manager reporting security/evidence contract mismatch.'),
        findsOneWidget);
  });

  test('Reports route is date-scoped and cannot pretend notification delivery', () {
    expect(ApiPaths.managerReportingWatch, '/reports/manager-watch');
    final screen = File('lib/screens/reports/reports_screen.dart').readAsStringSync();
    final view = File('lib/screens/reports/branch_reporting_watch_panel.dart')
        .readAsStringSync();
    expect(screen, contains("'branch_manager_watch'"));
    expect(screen, contains('path: ApiPaths.managerReportingWatch'));
    expect(screen, contains('BranchReportingWatchPanel(data: data)'));
    expect(screen, contains("if (dayReports.contains(activeType)) 'date': toValue"));
    expect(view, contains("report['delivery_enabled'] != false"));
    expect(view, contains('automatic_notifications_sent'));
    expect(view, contains('receipt states come from manager attestations')); // approval is not external verification
  });
}
