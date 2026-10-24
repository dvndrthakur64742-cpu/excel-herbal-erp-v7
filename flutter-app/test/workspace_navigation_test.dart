import 'package:flutter_test/flutter_test.dart';
import 'package:excel_herbal_erp/shell/app_shell.dart';
import 'package:excel_herbal_erp/shell/workspace_navigation.dart';

void main() {
  test('mobile rejects stale permissions duplicate and unsupported routes', () {
    final items = WorkspaceNavigation.mobileItems([
      {'id': 'home'}, {'id': 'home'}, {'id': 'approvals'},
      {'id': 'finance'}, {'id': 'unknown'}, {'id': 'profile'},
    ], allowed: (id) => id != 'approvals');
    expect(items.map((item) => item['id']), ['home', 'profile']);
  });
  test('empty or single mobile projection has safe usable fallback', () {
    for (final source in <List<Map<String, dynamic>>>[[], [{'id': 'home'}]]) {
      final items = WorkspaceNavigation.mobileItems(source, allowed: (_) => false);
      expect(items.map((item) => item['id']), ['home', 'profile']);
    }
  });
  test('shell compiles with shared navigation', () {
    expect(const AppShell(), isA<AppShell>());
  });
  test('each destination has exactly one primary owner', () {
    final groups = WorkspaceNavigation.groups(allowed: (_) => true);
    final ids = groups.values.expand((items) => items).map((d) => d.id).toList();
    expect(ids.toSet().length, ids.length);
    expect(groups.keys, ['Daily Work', 'Stock & Sales', 'Finance', 'People',
      'Reports & Administration']);
    expect(ids, containsAll(['administration', 'erp_tools', 'approvals']));
  });
  test('employee scope exposes no finance or administration destinations', () {
    final groups = WorkspaceNavigation.groups(
      allowed: (id) => {'home', 'my_work', 'tasks'}.contains(id));
    expect(groups.keys, ['Daily Work']);
    expect(groups.values.expand((v) => v).map((d) => d.id),
      ['home', 'my_work', 'tasks']);
  });
  test('mobile drawer excludes bottom routes and suppresses empty groups', () {
    final groups = WorkspaceNavigation.groups(
      allowed: (id) => {'home', 'my_work', 'finance', 'reports'}.contains(id),
      excluded: {'home', 'my_work'});
    expect(groups.keys, ['Finance', 'Reports & Administration']);
    expect(groups.values.expand((v) => v).map((d) => d.id), ['finance', 'reports']);
  });
  test('revoked access disappears when navigation is rebuilt', () {
    var financeAllowed = true;
    Map<String, List<WorkspaceDestination>> project() =>
      WorkspaceNavigation.groups(allowed: (id) => id == 'finance' && financeAllowed);
    expect(project().keys, ['Finance']);
    financeAllowed = false;
    expect(project(), isEmpty);
  });
  test('blocked scope retains overview only', () {
    final groups = WorkspaceNavigation.groups(allowed: (id) => id == 'home');
    expect(groups.values.single.single.id, 'home');
  });
}
