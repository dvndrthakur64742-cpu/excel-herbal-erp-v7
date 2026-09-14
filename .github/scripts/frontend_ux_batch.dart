import 'dart:io';

String _normalisedText(File file) =>
    file.readAsStringSync().replaceAll('\r\n', '\n').replaceAll('\r', '\n');

void replaceOnce(String path, String from, String to) {
  final file = File(path);
  var text = _normalisedText(file);
  final count = from.allMatches(text).length;
  if (count != 1) {
    throw StateError('$path: expected 1 match, found $count');
  }
  text = text.replaceFirst(from, to);
  file.writeAsStringSync(text);
}

void replaceExpected(String path, String from, String to, int expected) {
  final file = File(path);
  var text = _normalisedText(file);
  final count = from.allMatches(text).length;
  if (count != expected) {
    throw StateError('$path: expected $expected matches, found $count');
  }
  text = text.replaceAll(from, to);
  file.writeAsStringSync(text);
}

void main() {
  const theme = 'flutter-app/lib/theme/excel_brand.dart';
  replaceExpected(
    theme,
    'minimumSize: const Size(44, 44),',
    'minimumSize: const Size(48, 48),',
    2,
  );
  replaceOnce(
    theme,
    '''style: TextButton.styleFrom(
          foregroundColor: primaryDark,
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),''',
    '''style: TextButton.styleFrom(
          foregroundColor: primaryDark,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),''',
  );

  const asyncPanel = 'flutter-app/lib/widgets/async_panel.dart';
  replaceOnce(
    asyncPanel,
    "this.emptyMessage = 'Abhi koi data available nahi hai.',",
    "this.emptyMessage = 'This section has no records to show.',",
  );
  replaceOnce(
    asyncPanel,
    '''Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(32),
      child: SizedBox.square(
        dimension: 30,
        child: CircularProgressIndicator(strokeWidth: 2.6),
      ),
    ),
  );''',
    '''Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    label: 'Loading content',
    child: const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: SizedBox.square(
          dimension: 30,
          child: CircularProgressIndicator(strokeWidth: 2.6),
        ),
      ),
    ),
  );''',
  );
  replaceOnce(
    asyncPanel,
    '''            Text(
              message,
              textAlign: TextAlign.center,''',
    '''            Text(
              'No records yet',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 7),
            Text(
              message,
              textAlign: TextAlign.center,''',
  );
  replaceOnce(
    asyncPanel,
    "'Section load nahi ho paaya',",
    "'Unable to load this section',",
  );
  replaceOnce(asyncPanel, "label: const Text('Try Again'),", "label: const Text('Retry'),");

  const businessFormat = 'flutter-app/lib/core/business_format.dart';
  replaceOnce(
    businessFormat,
    "'designation_code': 'Designation Code',",
    "'designation_code': 'Designation',",
  );
  replaceOnce(
    businessFormat,
    "'reporting_category': 'Reporting Category',",
    "'reporting_category': 'Reporting Group',",
  );
  replaceOnce(
    businessFormat,
    "'role_code': 'Role Code',",
    "'role_code': 'Role',",
  );
  replaceOnce(
    businessFormat,
    "'login_enabled': 'Login Enabled',",
    "'login_enabled': 'Login Access',",
  );
  replaceOnce(
    businessFormat,
    "'''if (v is bool) return v ? 'Yes' : 'No';''',",
    "'''if (v is bool) return v ? 'Enabled' : 'Disabled';''',",
  );

  const gps = 'flutter-app/lib/core/gps_tracking_service.dart';
  replaceOnce(
    gps,
    "'Location permission blocked. Browser/device settings me permission allow karein.',",
    "'Location permission is blocked. Allow location for this site in your browser or device settings, then tap Retry.',",
  );
  replaceOnce(
    gps,
    "'Location permission deny ho gayi. Permission allow karke dobara try karein.',",
    "'Location permission was denied. Allow location when prompted, then tap Retry.',",
  );

  const tasks = 'flutter-app/lib/screens/communication/tasks_screen.dart';
  replaceOnce(
    tasks,
    '''    return Column(
      children: [''',
    '''    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('My Tasks', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 3),
                Text(
                  'Pending work assigned to you. Open a task to review its context.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),''',
  );
  replaceOnce(
    tasks,
    "return const Center(child: Text('Koi pending task nahi hai.'));",
    "return const Center(child: Text('No pending tasks.'));",
  );

  const records = 'flutter-app/lib/widgets/records_list.dart';
  replaceOnce(
    records,
    '''      'stock' => const [
        'quantity',
        'sku',
        'uom',
        'batch_no',
        'custodian_name',
        'expires_on',
      ],''',
    '''      'stock' => const [
        'quantity',
        'custodian_name',
        'sku',
        'uom',
        'batch_no',
        'expires_on',
      ],''',
  );
  replaceOnce(records, 'return ordered.take(3).toList();', '''final limit = widget.recordType == 'stock' ? 4 : 3;
    return ordered.take(limit).toList();''');
  replaceOnce(
    records,
    '''                  : SizedBox(
                      width: 34,
                      height: 34,''',
    '''                  : SizedBox(
                      width: 48,
                      height: 48,''',
  );

  final testFile = File('flutter-app/test/frontend_responsive_ux_test.dart');
  testFile.writeAsStringSync(r'''import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:excel_herbal_erp_v7/core/business_format.dart';
import 'package:excel_herbal_erp_v7/widgets/records_list.dart';

void main() {
  testWidgets('business records stay readable at audited widths', (tester) async {
    final rows = [
      {
        'id': 1,
        'product_name': 'Long Herbal Product Name for Responsive Verification',
        'quantity': 12,
        'uom': 'pcs',
        'custodian_name': 'Head Office Store Custodian',
        'batch_no': 'BATCH-2026-LONG',
        'status': 'issue_pending',
      }
    ];

    for (final width in <double>[360, 390, 768]) {
      await tester.binding.setSurfaceSize(Size(width, 800));
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: RecordsList(rows: rows, recordType: 'stock'))));
      await tester.pumpAndSettle();
      expect(find.byType(Card), findsWidgets);
      expect(find.textContaining('Head Office Store Custodian'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }

    await tester.binding.setSurfaceSize(const Size(1366, 900));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: RecordsList(rows: rows, recordType: 'stock'))));
    await tester.pumpAndSettle();
    expect(find.byType(DataTable), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.binding.setSurfaceSize(null);
  });

  test('internal values are presented as readable business labels', () {
    expect(BusinessFormat.label('designation_code'), 'Designation');
    expect(BusinessFormat.label('reporting_category'), 'Reporting Group');
    expect(BusinessFormat.label('login_enabled'), 'Login Access');
    expect(BusinessFormat.value('login_enabled', true), 'Enabled');
    expect(BusinessFormat.status('issue_pending'), 'Issue Pending');
  });
}
''');
}
