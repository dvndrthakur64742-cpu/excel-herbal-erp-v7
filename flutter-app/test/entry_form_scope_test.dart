import 'package:excel_herbal_erp/core/entry_form_scope.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('entry cannot be reused after authority or session change', () {
    final state = Object(), client = Object();
    final scope = EntryFormScope(state, client);
    expect(scope.matches(state, client), isTrue);
    expect(scope.matches(Object(), client), isFalse);
    expect(scope.matches(state, Object()), isFalse);
  });
  test('product search matches name sku and batch case insensitively', () {
    final fields = ['Herbal Oil', 'HO-01', 'B-024', null];
    expect(EntryFormScope.matchesProduct(' oil ', fields), isTrue);
    expect(EntryFormScope.matchesProduct('ho-01', fields), isTrue);
    expect(EntryFormScope.matchesProduct('B-024', fields), isTrue);
    expect(EntryFormScope.matchesProduct('', fields), isTrue);
    expect(EntryFormScope.matchesProduct('missing', fields), isFalse);
  });
}
