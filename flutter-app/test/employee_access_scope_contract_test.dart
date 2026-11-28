import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File('lib/screens/administration/administration_screen.dart')
      .readAsStringSync();
  final start = source.indexOf('  Future<void> _assignEmployeeAccess(');
  final end = source.indexOf('  Future<bool> _reviewAccessChanges(', start);
  final method = source.substring(start, end);

  test('employee access uses the captured API and rejects stale form authority', () {
    final capture = method.indexOf('final scope = EntryFormScope(app, api)');
    final read = method.indexOf('await api.get(ApiPaths.employeeAccess(id))');
    final check = method.indexOf('if (!current()) return;', read);
    final dialog = method.indexOf('await showModalBottomSheet');
    final review = method.indexOf('await _reviewAccessChanges');
    final post = method.indexOf('await api.post(');
    expect(capture, greaterThanOrEqualTo(0));
    expect(read, greaterThan(capture));
    expect(check, greaterThan(read));
    expect(dialog, greaterThan(check));
    expect(review, greaterThan(dialog));
    expect(post, greaterThan(review));
    expect(method.substring(review, post), contains('if (!current())'));
    expect(method, isNot(contains('await ref.read(apiClientProvider).post(')));
    expect(method, contains('if (!mounted || _employeeAccessOpen) return;'));
    expect(method, contains('_employeeAccessOpen = false;'));
  });

  test('search filters presentation, not submitted role or override sets', () {
    expect(method, contains('...visibleRoles.map'));
    expect(method, contains('final cap = visibleCaps[index - 1]'));
    expect(method, contains("'role_ids': selectedRoles.toList()..sort()"));
    expect(method, contains("'grants': grants.toList()..sort()"));
    expect(method, contains("'denies': denies.toList()..sort()"));
    expect(method, contains('originalRoles'));
    expect(method, contains('originalGrants'));
    expect(method, contains('originalDenies'));
  });
}
