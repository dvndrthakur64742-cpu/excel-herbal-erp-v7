import 'package:excel_herbal_erp/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('valid server business date is authoritative', () {
    const state = AppState(
      bootstrap: {'business_date': '2026-09-18'},
    );

    expect(state.serverBusinessDate, '2026-09-18');
    expect(state.usingFallbackBusinessDate, isFalse);
    expect(state.businessDate, '2026-09-18');
    expect(state.businessMonthStart, '2026-09-01');
  });

  test('impossible calendar date is rejected', () {
    const state = AppState(
      bootstrap: {'business_date': '2026-02-31'},
    );

    expect(state.serverBusinessDate, isNull);
    expect(state.usingFallbackBusinessDate, isTrue);
  });

  test('malformed server business date is rejected', () {
    const state = AppState(
      bootstrap: {'business_date': '18-09-2026'},
    );

    expect(state.serverBusinessDate, isNull);
    expect(state.usingFallbackBusinessDate, isTrue);
  });
}
