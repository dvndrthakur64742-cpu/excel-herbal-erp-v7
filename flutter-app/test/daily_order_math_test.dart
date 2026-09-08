import 'package:excel_herbal_erp/core/daily_order_math.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('retail sold excludes returns and wholesale', () {
    expect(DailyOrderMath.retailSold(10, 2, 3), 5);
    expect(DailyOrderMath.retailSold(10, 2, 0), 8);
  });

  test('retail sold never becomes negative', () {
    expect(DailyOrderMath.retailSold(5, 4, 3), 0);
  });

  test('return plus wholesale cannot exceed issued', () {
    expect(DailyOrderMath.quantitiesFit(10, 2, 8), isTrue);
    expect(DailyOrderMath.quantitiesFit(10, 3, 8), isFalse);
  });

  test('wholesale rate validation', () {
    expect(DailyOrderMath.wholesaleRateValid(2, 90, 100), isTrue);
    expect(DailyOrderMath.wholesaleRateValid(2, 110, 100), isFalse);
    expect(DailyOrderMath.wholesaleRateValid(2, 0, 100), isFalse);
    expect(DailyOrderMath.wholesaleRateValid(0, 0, 100), isTrue);
  });

  test('retail plus wholesale amount is calculated', () {
    expect(DailyOrderMath.totalAmount(5, 100, 2, 80), 660);
  });

  test('deposit equality uses rounding tolerance', () {
    expect(DailyOrderMath.depositMatches(1000, 1000.004), isTrue);
    expect(DailyOrderMath.depositMatches(1000, 1000.01), isFalse);
  });
}
