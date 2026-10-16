import 'package:excel_herbal_erp/core/whole_pcs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Daily Order closing API quantities', () {
    test('normalizes MariaDB DECIMAL strings before building integer inputs', () {
      expect(WholePcs.apiQuantityText('0.0000'), '0');
      expect(WholePcs.apiQuantityText('3.00'), '3');
      expect(WholePcs.apiQuantityText(5), '5');
      expect(WholePcs.apiQuantityText(12.0), '12');
      expect(WholePcs.apiQuantityText(null), '0');
      expect(WholePcs.apiQuantityText(''), '0');
      expect(WholePcs.parseOrZero(WholePcs.apiQuantityText('2.000')), 2);
    });

    test('rejects invalid or fractional server quantities', () {
      for (final value in <Object>[
        '1.5',
        '-1',
        'abc',
        double.nan,
        double.infinity,
        '9007199254740992',
      ]) {
        expect(
          () => WholePcs.apiQuantityText(value),
          throwsFormatException,
          reason: 'Unsafe server quantity: $value',
        );
      }
    });

    test('still rejects decimal user entry after API normalization', () {
      expect(() => WholePcs.parseOrZero('3.00'), throwsFormatException);
      expect(WholePcs.parseOrZero('3'), 3);
    });
  });
}
