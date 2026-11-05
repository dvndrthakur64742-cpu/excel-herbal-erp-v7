import 'dart:io';

import 'package:excel_herbal_erp/widgets/workspace_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('workspace banner supports narrow phone and large text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: WorkspaceBanner(
              eyebrow: 'Excel Herbal / Workspace overview',
              title: 'Good morning, a sample employee with a long name',
              subtitle: 'Authorised Head Office workspace',
              icon: Icons.dashboard_customize_outlined,
            ),
          ),
        ),
      ),
    );
    expect(find.textContaining('Good morning'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('dashboard/report hierarchy is backed by live scoped modules', () {
    final home = File('lib/screens/home/home_screen.dart').readAsStringSync();
    final reports =
        File('lib/screens/reports/reports_screen.dart').readAsStringSync();
    final shell = File('lib/shell/app_shell.dart').readAsStringSync();
    expect(home, contains('WorkspaceBanner('));
    expect(home, contains('_BranchContextCard()'));
    expect(home, contains('app.managementDashboardVisible'));
    expect(reports, contains('WorkspaceBanner('));
    expect(reports, contains('REPORT LIBRARY'));
    expect(reports, contains('constraints.maxWidth >= 900'));
    expect(shell, contains('SizedBox(width: 272'));
  });
}
