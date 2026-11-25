import 'dart:io';

import 'package:excel_herbal_erp/core/access_change_review.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('assignment review lists exact changes in stable order', () {
    final before = {'sales.view', 'sales.create', 'reports.view'};
    final after = {'sales.view', 'inventory.view', 'daily_order.self'};
    final change = AccessChangeReview<String>(before, after);
    expect(change.added, ['daily_order.self', 'inventory.view']);
    expect(change.removed, ['reports.view', 'sales.create']);
    expect(change.changed, isTrue);
    expect(before, contains('sales.create'));
    expect(after, contains('inventory.view'));
  });

  test('unchanged sets do not produce a change review', () {
    final review = AccessChangeReview<String>({'a', 'b'}, {'b', 'a'});
    expect(review.changed, isFalse);
    expect(review.added, isEmpty);
    expect(review.removed, isEmpty);
  });

  test('grant-to-deny change is represented as two assignment changes', () {
    const cap = 'finance.view';
    final grants = AccessChangeReview<String>({cap}, {});
    final denies = AccessChangeReview<String>({}, {cap});
    expect(grants.removed, [cap]);
    expect(denies.added, [cap]);
    expect(grants.added, isEmpty);
    expect(denies.removed, isEmpty);
  });

  test('admin screen requires review before role and employee writes', () {
    final source = File('lib/screens/administration/administration_screen.dart')
        .readAsStringSync();
    final role = source.substring(
      source.indexOf('Future<void> _editRoleCapabilities('),
      source.indexOf('Future<void> _assignEmployeeAccess('),
    );
    expect(role.indexOf('await _reviewAccessChanges('), greaterThanOrEqualTo(0));
    expect(role.indexOf('await _reviewAccessChanges('),
        lessThan(role.indexOf('await _post(')));
    expect(role, contains('if (!review.changed)'));
    final employee = source.substring(
      source.indexOf('Future<void> _assignEmployeeAccess('),
      source.indexOf('Future<bool> _reviewAccessChanges('),
    );
    expect(employee.indexOf('await _reviewAccessChanges('),
        greaterThanOrEqualTo(0));
    expect(employee.indexOf('await _reviewAccessChanges('),
        lessThan(employee.indexOf('await ref.read(apiClientProvider).post(')));
    expect(employee, contains('if (!confirmed || !mounted)'));
    expect(source, contains('Confirm access changes'));
    expect(source, contains('removing a deny may restore access'));
  });
}
