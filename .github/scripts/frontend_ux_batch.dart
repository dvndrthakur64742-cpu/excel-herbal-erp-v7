import 'dart:io';

void replaceOnce(String path, String from, String to) {
  final file = File(path);
  var text = file.readAsStringSync();
  final count = from.allMatches(text).length;
  if (count != 1) {
    throw StateError('$path: expected 1 match, found $count');
  }
  text = text.replaceFirst(from, to);
  file.writeAsStringSync(text);
}

void replaceExpected(String path, String from, String to, int expected) {
  final file = File(path);
  var text = file.readAsStringSync();
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
    '''            const SizedBox(height: 14),
            Text(
              message,''',
    '''            const SizedBox(height: 14),
            Text(
              'No records yet',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,''',
  );
  replaceOnce(
    asyncPanel,
    "'Section load nahi ho paaya'",
    "'Unable to load this section'",
  );
  replaceOnce(asyncPanel, "const Text('Try Again')", "const Text('Retry')");

  const format = 'flutter-app/lib/core/business_format.dart';
  replaceOnce(
    format,
    "    'section': 'Section',\n",
    "    'section': 'Section',\n    'designation_code': 'Designation',\n    'reporting_category': 'Reporting Category',\n    'role_code': 'Role',\n    'login_enabled': 'Login Access',\n",
  );
  replaceOnce(
    format,
    "    if (k == 'status') return status(value);\n",
    "    if (k == 'status') return status(value);\n    if (k == 'login_enabled' || k.endsWith('_enabled')) {\n      return enabledLabel(value);\n    }\n    if (const {\n      'designation_code',\n      'reporting_category',\n      'role_code',\n    }.contains(k)) {\n      return codeLabel(value);\n    }\n",
  );
  replaceOnce(
    format,
    '''  static String displayName(String input) {''',
    '''  static const _acronyms = {
    'ASM',
    'SM',
    'BM',
    'RM',
    'RC',
    'ZI',
    'CM',
    'MD',
    'GM',
    'AGM',
    'HR',
    'ERP',
    'GPS',
    'GSTIN',
    'SKU',
    'UPI',
    'ID',
  };

  static String codeLabel(dynamic value) {
    final raw = '${value ?? ''}'.trim();
    if (raw.isEmpty) return '—';
    return raw
        .split(RegExp(r'[_\\s-]+'))
        .where((part) => part.isNotEmpty)
        .map((part) {
          final upper = part.toUpperCase();
          if (_acronyms.contains(upper)) return upper;
          final lower = part.toLowerCase();
          return '${lower[0].toUpperCase()}${lower.substring(1)}';
        })
        .join(' ');
  }

  static String enabledLabel(dynamic value) {
    final raw = '${value ?? ''}'.trim();
    if (raw.isEmpty) return '—';
    final lower = raw.toLowerCase();
    if (const {'1', 'true', 'yes', 'on', 'enabled'}.contains(lower)) {
      return 'Enabled';
    }
    if (const {'0', 'false', 'no', 'off', 'disabled'}.contains(lower)) {
      return 'Disabled';
    }
    return codeLabel(raw);
  }

  static String displayName(String input) {''',
  );

  const gps = 'flutter-app/lib/core/gps_tracking_service.dart';
  replaceOnce(
    gps,
    "      _lastError = 'Device location is off. Turn on Location for duty GPS.';",
    "      _lastError = kIsWeb\n          ? 'Location is unavailable. Turn on device Location, allow Location for this site in browser controls, then Retry.'\n          : 'Device Location is off. Turn on Location, then Retry.';",
  );
  replaceOnce(
    gps,
    '''      _lastError = permission == LocationPermission.deniedForever
          ? 'Location permission is blocked in device settings.'
          : 'Location permission is required for duty GPS.';''',
    '''      if (kIsWeb) {
        _lastError =
            'Location permission is blocked. Open the browser site controls/lock icon, set Location to Allow, then Retry.';
      } else if (permission == LocationPermission.deniedForever) {
        _lastError =
            'Location permission is blocked. Open this app in device App Permissions, allow Location, then Retry.';
      } else {
        _lastError =
            'Location permission is required for duty GPS. Allow Location when prompted, then Retry.';
      }''',
  );

  const tasks = 'flutter-app/lib/screens/communication/tasks_screen.dart';
  replaceOnce(
    tasks,
    '''    return Column(
      children: [
        if (message != null)''',
    '''    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('My Tasks', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 3),
                Text(
                  'Assigned work that still needs your action.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        if (message != null)''',
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
          'batch_no',
          'expires_on',
          'sku',
          'uom',
        ],''',
  );
  replaceOnce(
    records,
    '    return ordered.take(3).toList();',
    "    return ordered.take(widget.recordType == 'stock' ? 4 : 3).toList();",
  );
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

import 'package:excel_herbal_erp/core/business_format.dart';
import 'package:excel_herbal_erp/theme/excel_brand.dart';
import 'package:excel_herbal_erp/widgets/records_list.dart';

void main() {
  test('internal ERP codes are presented as readable labels', () {
    expect(BusinessFormat.label('designation_code'), 'Designation');
    expect(BusinessFormat.label('login_enabled'), 'Login Access');
    expect(BusinessFormat.value('login_enabled', 1), 'Enabled');
    expect(
      BusinessFormat.value('reporting_category', 'SENIOR_MANAGEMENT'),
      'Senior Management',
    );
    expect(BusinessFormat.value('designation_code', 'ASM'), 'ASM');
  });

  group('RecordsList responsive layout', () {
    Future<void> pumpStock(WidgetTester tester, double width) async {
      await tester.binding.setSurfaceSize(Size(width, 800));
      await tester.pumpWidget(
        MaterialApp(
          theme: ExcelBrand.lightTheme(),
          home: const Scaffold(
            body: RecordsList(
              recordType: 'stock',
              rows: [
                {
                  'product_name': 'Sample Product',
                  'quantity': 12,
                  'custodian_name': 'Head Office',
                  'batch_no': 'B-01',
                  'expires_on': '2027-12-31',
                  'sku': 'SKU-01',
                  'uom': 'PCS',
                },
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    for (final width in <double>[360, 390, 768]) {
      testWidgets('uses readable cards at ${width.toInt()}px', (tester) async {
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await pumpStock(tester, width);
        expect(find.byType(DataTable), findsNothing);
        expect(find.text('Sample Product'), findsOneWidget);
        expect(
          find.textContaining('Custodian: Head Office', findRichText: true),
          findsOneWidget,
        );
      });
    }

    testWidgets('uses a comparison table at 1366px', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpStock(tester, 1366);
      expect(find.byType(DataTable), findsOneWidget);
      expect(find.text('Sample Product'), findsOneWidget);
    });
  });
}
''');

  stdout.writeln('Frontend UX batch applied.');
}
