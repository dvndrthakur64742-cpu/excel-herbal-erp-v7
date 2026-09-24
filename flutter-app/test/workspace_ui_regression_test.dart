import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {

  test('Organization uses the shared workspace shell', () {
    final source = File(
      'lib/screens/organization/organization_screen.dart',
    ).readAsStringSync();

    expect(source, contains('ModuleWorkspaceHeader('));
    expect(source, contains('ModuleMessageBanner(message: message!)'));
    expect(source, contains('ModuleSectionHeader('));
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

  test('My Work attendance shows only the valid next action', () {
    final source = File(
      'lib/screens/my_work/my_work_attendance.dart',
    ).readAsStringSync();

    expect(source, contains("final checkedIn ="));
    expect(source, contains("final checkedOut ="));
    expect(source, contains("if (!checkedIn)"));
    expect(source, contains("else if (!checkedOut)"));
    expect(source, contains("Attendance complete"));
    expect(source, contains("Check-Out: pending"));
  });

  test('ERP modal surfaces use shared presentation styling', () {
    final source = File('lib/theme/excel_brand.dart').readAsStringSync();

    expect(source, contains('dataTableTheme: DataTableThemeData('));
    expect(source, contains('popupMenuTheme: PopupMenuThemeData('));
    expect(source, contains('bottomSheetTheme: const BottomSheetThemeData('));
    expect(source, contains('Radius.circular(24)'));
    expect(source, contains('insetPadding: const EdgeInsets.symmetric('));
  });
}
