import 'package:excel_herbal_erp/core/search_request_scope.dart';
import 'package:flutter_test/flutter_test.dart';
void main() {
  test('search is invalid after branch authority or client replacement', () {
    final scope = SearchRequestScope<Object>();
    final state = Object(), client = Object();
    expect(scope.matches(state, client), isFalse);
    scope.capture(state, client);
    expect(scope.matches(state, client), isTrue);
    expect(scope.matches(Object(), client), isFalse);
    expect(scope.matches(state, Object()), isFalse);
    scope.clear();
    expect(scope.matches(state, client), isFalse);
  });
}
