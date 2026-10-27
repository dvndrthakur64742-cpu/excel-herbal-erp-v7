import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:excel_herbal_erp/shell/workspace_action_catalog.dart';

void main() {
  test('desktop and mobile use one owned list without duplicate destinations', () {
    final ids = WorkspaceActionCatalog.actions.map((action) => action.id).toList();
    expect(ids.toSet().length, ids.length);
    expect(ids, containsAll(['attendance', 'daily_create', 'evening',
      'stock_transfer', 'stock_adjustment', 'expense_entry', 'hr_lifecycle']));
    for (final action in WorkspaceActionCatalog.actions) {
      expect(action.label.trim(), isNotEmpty);
      expect(action.anyCapability, isNotEmpty);
    }
  });

  test('employee may open only their existing own workflows', () {
    const caps = {'workforce.attendance.self', 'daily_order.self'};
    final ids = WorkspaceActionCatalog.visible(caps.contains)
        .map((action) => action.id).toList();
    expect(ids, ['attendance', 'daily_create', 'evening']);
    expect(WorkspaceActionCatalog.allows('expense_entry', caps.contains), isFalse);
    expect(WorkspaceActionCatalog.allows('hr_lifecycle', caps.contains), isFalse);
    expect(WorkspaceActionCatalog.allows('some_stale_route', caps.contains), isFalse);
  });

  test('stock adjustment and HR lifecycle are distinct existing destinations', () {
    const caps = {'inventory.adjustment.create', 'organization.hr.view'};
    final ids = WorkspaceActionCatalog.visible(caps.contains)
        .map((action) => action.id).toList();
    expect(ids, ['stock_adjustment', 'hr_lifecycle']);
    expect(WorkspaceActionCatalog.allows('stock_transfer', caps.contains), isFalse);
  });

  test('revoke capability while sheet is open blocks old action on tap', () {
    var allowed = <String>{'finance.expense.create'};
    final staleActions = WorkspaceActionCatalog.visible(allowed.contains);
    expect(staleActions.single.id, 'expense_entry');
    allowed = {};
    expect(WorkspaceActionCatalog.visible(allowed.contains), isEmpty);
    expect(WorkspaceActionCatalog.allows(
        staleActions.single.id, allowed.contains), isFalse);
  });

  test('changed branch or logout cannot reuse an earlier authorized route', () {
    var branchAvailable = true;
    bool can(String cap) =>
        branchAvailable && cap == 'inventory.transfer.create';
    expect(WorkspaceActionCatalog.allows('stock_transfer', can), isTrue);
    branchAvailable = false;
    expect(WorkspaceActionCatalog.allows('stock_transfer', can), isFalse);
  });

  test('all action destinations route through the existing shell screens', () {
    final shell = File('lib/shell/app_shell.dart').readAsStringSync();
    for (final action in WorkspaceActionCatalog.actions) {
      expect(shell, contains("case '${action.id}':"),
          reason: 'No existing workflow route for ${action.id}');
    }
    expect(shell, contains("initialAction: 'adjustment'"));
    expect(shell, contains('screen = const HrLifecycleScreen();'));
    expect(shell, contains('if (!WorkspaceActionCatalog.allows('));
  });
}
