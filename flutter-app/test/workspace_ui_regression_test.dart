import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {

  test('Organization uses the shared workspace shell', () {
    final source = File(
      'lib/screens/organization/organization_screen.dart',
    ).readAsStringSync();

    expect(source, contains('ModuleWorkspaceHeader('));
    expect(source, contains('ModuleMessageBanner(message: message!)'));
    expect(
      source,
      isNot(contains('ModuleSectionHeader(')),
      reason: 'Tabbed Organization content should not repeat a workspace header.',
    );
    expect(source, contains('contextLabel: app.currentBranchName'));
    expect(
      source.split('BranchSelector()').length - 1,
      1,
      reason: 'Organization should have one shared branch selector.',
    );
  });

  test('workspace section headers stack actions on narrow widths', () {
    final source = File('lib/widgets/module_workspace.dart').readAsStringSync();

    expect(source, contains('constraints.maxWidth < 520'));
    expect(source, contains('Align(alignment: Alignment.centerLeft, child: trailing!)'));
    expect(source, contains('Semantics('));
    expect(source, contains('liveRegion: true'));
  });

  test('My Work has one shared workspace shell for every entry point', () {
    final shell = File('lib/shell/app_shell.dart').readAsStringSync();
    final workspace = File(
      'lib/screens/my_work/my_work_workspace_screen.dart',
    ).readAsStringSync();

    expect(shell, contains("'my_work' => const MyWorkWorkspaceScreen()"));
    expect(shell, contains('screen is MyWorkWorkspaceScreen'));
    expect(workspace, contains('ModuleWorkspaceHeader('));
    expect(workspace, contains('app.currentBranchName.trim()'));
    expect(workspace, contains('MyWorkScreen('));
    expect(workspace, contains('ShellLayout.isDesktopWidth(constraints.maxWidth)'));
    expect(workspace, contains('constraints.maxWidth < 820'));
    expect(workspace, contains('_tabletCardWidth = 819'));
  });

  test('My Work attendance reflects server-scheduled duty without manual actions', () {
    final source = File(
      'lib/screens/my_work/my_work_attendance.dart',
    ).readAsStringSync();

    expect(source, contains("final checkedIn ="));
    expect(source, contains("final checkedOut ="));
    expect(
      source,
      contains("Duty automatically starts at 10:30 AM; no manual check-in is required."),
    );
    expect(source, contains("Duty is automatic · 10:30 AM–5:00 PM"));
    expect(source, contains("Attendance pending"));
    expect(source, contains("Check-Out: pending"));
    expect(source, isNot(contains("Future<void> _attendanceAction(")));
    expect(source, isNot(contains("ApiPaths.checkIn")));
    expect(source, isNot(contains("ApiPaths.checkOut")));
  });

  test('desktop shell avoids a second competing workspace header', () {
    final source = File('lib/shell/app_shell.dart').readAsStringSync();

    expect(source, isNot(contains('_desktopWorkspaceHeader')));
    expect(source, contains('SizedBox(width: 248'));
    expect(source, isNot(contains('ModuleWorkspaceHeader(')));
    expect(source, contains("_sectionLabel(context, 'WORK')"));
    expect(source, contains("_sectionLabel(context, 'CONTROL')"));
    expect(source, contains("_sectionLabel(context, 'MODULES')"));
  });

  test('business module page titles match shell navigation labels', () {
    final sales = File('lib/screens/sales/sales_screen.dart').readAsStringSync();
    final purchase =
        File('lib/screens/purchase/purchase_screen.dart').readAsStringSync();
    final finance =
        File('lib/screens/finance/finance_screen.dart').readAsStringSync();

    expect(sales, contains("Text('Sales & Collections')"));
    expect(purchase, contains("Text('Purchase & Suppliers')"));
    expect(finance, contains("Text('Finance & Accounts')"));
  });

  test('ERP modal surfaces use shared presentation styling', () {
    final source = File('lib/theme/excel_brand.dart').readAsStringSync();

    expect(source, contains('dataTableTheme: DataTableThemeData('));
    expect(source, contains('popupMenuTheme: PopupMenuThemeData('));
    expect(source, contains('bottomSheetTheme: const BottomSheetThemeData('));
    expect(source, contains('Radius.circular(24)'));
    expect(source, contains('insetPadding: const EdgeInsets.symmetric('));
  });

  test('payroll leave policy avoids fixed desktop dialogs', () {
    final source = File(
      'lib/screens/performance/payroll_policy_dialog.dart',
    ).readAsStringSync();

    expect(source, contains('showModalBottomSheet<String>('));
    expect(source, contains('isScrollControlled: true'));
    expect(source, contains('FractionallySizedBox('));
    expect(source, contains('MediaQuery.viewInsetsOf(addContext).bottom'));
    expect(source, isNot(contains('width: 640')));
    expect(source, isNot(contains('height: 500')));
    expect(source, isNot(contains('width: 420')));
  });

}
