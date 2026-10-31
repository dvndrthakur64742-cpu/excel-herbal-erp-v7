// Regression coverage for the certified responsive UX/accessibility batch.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:excel_herbal_erp/core/business_format.dart';
import 'package:excel_herbal_erp/widgets/records_list.dart';

void main() {
  testWidgets('business records stay readable at audited widths', (
    tester,
  ) async {
    final rows = [
      {
        'id': 1,
        'product_name': 'Long Herbal Product Name for Responsive Verification',
        'quantity': 12,
        'uom': 'pcs',
        'custodian_name': 'Head Office Store Custodian',
        'batch_no': 'BATCH-2026-LONG',
        'status': 'issue_pending',
      },
    ];
    for (final width in <double>[360, 390, 768, 900, 959]) {
      await tester.binding.setSurfaceSize(Size(width, 800));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RecordsList(rows: rows, recordType: 'stock'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Card), findsWidgets);
      expect(find.byType(DataTable), findsNothing);
      expect(
        find.textContaining('Head Office Store Custodian'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }

    for (final width in <double>[960, 1366]) {
      await tester.binding.setSurfaceSize(Size(width, 900));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RecordsList(rows: rows, recordType: 'stock'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DataTable), findsOneWidget);
      expect(tester.takeException(), isNull);
    }

    await tester.binding.setSurfaceSize(null);
  });

  test('internal values are readable business labels', () {
    expect(BusinessFormat.label('designation_code'), 'Designation');
    expect(BusinessFormat.label('reporting_category'), 'Reporting Group');
    expect(BusinessFormat.label('login_enabled'), 'Login Access');
    expect(BusinessFormat.value('login_enabled', true), 'Enabled');
    expect(BusinessFormat.value('login_enabled', 0), 'Disabled');
    expect(
      BusinessFormat.value('designation_code', 'BRANCH_MANAGER'),
      'Branch Manager',
    );
    expect(BusinessFormat.status('issue_pending'), 'Issue Pending');
  });
}
