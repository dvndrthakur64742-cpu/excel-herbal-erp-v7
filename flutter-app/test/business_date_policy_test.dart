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

  test('valid leap-day bootstrap metadata is startup ready', () {
    const state = AppState(
      bootstrap: {
        'business_date': '2028-02-29',
        'business_timezone': 'Asia/Kolkata',
        'server_timestamp': '2028-02-29T10:15:30+05:30',
        'api_contract': '7.4.0',
        'features': {'api_contract': '7.4.0'},
      },
    );

    expect(state.serverBusinessDate, '2028-02-29');
    expect(state.bootstrapCompatibilityError, isNull);
    expect(state.bootstrapReady, isTrue);
  });

  test('missing server date blocks startup safely', () {
    const state = AppState(
      bootstrap: {
        'business_timezone': 'Asia/Kolkata',
        'server_timestamp': '2026-09-23T13:50:00+05:30',
        'api_contract': '7.4.0',
        'features': {'api_contract': '7.4.0'},
      },
    );

    expect(state.bootstrapReady, isFalse);
    expect(
      state.bootstrapCompatibilityError,
      'ERP server business date is unavailable or invalid.',
    );
  });

  test('inconsistent API contract metadata blocks startup', () {
    const state = AppState(
      bootstrap: {
        'business_date': '2026-09-23',
        'business_timezone': 'Asia/Kolkata',
        'server_timestamp': '2026-09-23T13:50:00+05:30',
        'api_contract': '7.4.0',
        'features': {'api_contract': '7.3.5'},
      },
    );

    expect(state.bootstrapReady, isFalse);
    expect(
      state.bootstrapCompatibilityError,
      'ERP API contract metadata is unavailable or incompatible.',
    );
  });
}
